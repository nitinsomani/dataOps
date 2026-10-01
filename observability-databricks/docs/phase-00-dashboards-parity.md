# Phase 0 — eu-west-1 Dashboard Parity + Compute-Policy Compliance

**Pillar:** Cost & capacity  ·  **Owner:** Platform  ·  **Effort:** Small  ·  **Repo:** `osdu-ssw-central-dbx`

## Objective

1. Bring the three existing Lakeview dashboards (Compute Cost, User Usage, Active
   Users) to **eu-west-1**, which currently only has them in `us-east-1`.
2. Add a **compute-policy compliance** panel that flags the single most common cost
   leak: jobs running on all-purpose (interactive) clusters instead of job clusters.

## Why it's first

- Zero new patterns — it's a copy of a working, reviewed Terraform stack.
- Closes a real gap: the region you're actively building out (`eu-west-1`) has no
  cost visibility today.
- Compute-policy compliance typically finds 10–30% of avoidable spend in week one.

## Current state

```
terraform/{dev,uat,prod}/{public,private}/us-east-1/dashboards/
  ├── backend.tf                     # TFE workspace binding
  ├── providers.tf                   # databricks provider (host + token)
  ├── variables.tf                   # host, warehouse_id, groups, catalog, ...
  ├── commons.auto.tfvars            # per-env values
  ├── dashboard-compute-cost.tf      # databricks_dashboard + permissions
  ├── dashboard-user-usage.tf
  ├── dashboard-active-users.tf
  └── outputs.tf                     # dashboard URLs
```

There is **no** `eu-west-1/dashboards/` stack yet.

## Implementation steps

1. **Create the stack directory** for each env that has an eu-west-1 workspace:
   `terraform/{env}/public/eu-west-1/dashboards/`.
2. **Copy** `providers.tf`, `variables.tf`, `outputs.tf`, and the three
   `dashboard-*.tf` files verbatim from the us-east-1 equivalent.
3. **Create a new `backend.tf`** with an eu-west-1 TFE workspace name, following the
   naming convention already in use:
   `osdu-ssw-central-dbx-{env}-public-euw1-dashboards`.
4. **Create `commons.auto.tfvars`** with eu-west-1 values:
   - `short_region = "euw1"`
   - `databricks_host` = the EU workspace URL
   - `sql_warehouse_id` = an EU SQL warehouse id
   - `catalog_name` and the three AD groups for the EU workspace
   - Confirm the **system-catalog alias** used in `dashboard-compute-cost.tf`
     resolves in the EU workspace (it references `system_table_unitycatalog_prd`).
5. **Register the new TFE workspace** in `terraform/{env}/workspaces/commons.auto.tfvars`
   (the list that enumerates all dashboard workspaces).
6. **Add the compute-policy compliance dashboard** —
   `implementations/phase-02-job-health/` includes the SQL; the panel itself can live
   in a new `dashboard-compute-cost.tf` row or a dedicated
   `dashboard-policy-compliance.tf`.

## Compute-policy compliance query (the new bit)

```sql
-- Jobs whose runs used all-purpose (interactive) compute in the last 30 days.
-- Interactive compute for scheduled jobs is a cost anti-pattern — jobs should use
-- ephemeral job clusters or serverless.
WITH prices AS (
  SELECT sku_name, pricing.effective_list.default AS price_per_dbu
  FROM ${system_catalog}.billing.list_prices
  WHERE currency_code = 'USD' AND price_end_time IS NULL
)
SELECT
  u.usage_metadata.job_id            AS job_id,
  u.billing_origin_product,
  ROUND(SUM(u.usage_quantity * COALESCE(p.price_per_dbu, 0)), 2) AS cost_usd,
  SUM(u.usage_quantity)              AS dbus
FROM ${system_catalog}.billing.usage u
LEFT JOIN prices p ON u.sku_name = p.sku_name
WHERE u.usage_unit = 'DBU'
  AND u.billing_origin_product = 'ALL_PURPOSE'   -- interactive
  AND u.usage_metadata.job_id IS NOT NULL         -- but driven by a job
  AND u.usage_date >= CURRENT_DATE - INTERVAL 30 DAYS
GROUP BY u.usage_metadata.job_id, u.billing_origin_product
ORDER BY cost_usd DESC;
```

## Verification / acceptance

- `terraform plan` in the new eu-west-1 stack shows 3 dashboards + permissions to create.
- After apply, `outputs.tf` prints working dashboard URLs for the EU workspace.
- The compliance panel returns rows only where jobs genuinely ran on interactive
  compute (empty result = clean estate = good).

## Ownership & DE involvement

**Platform-only.** No data-engineering input needed — this is infra replication plus
a cost query.

## Rollout order

Do `prod/public/eu-west-1` first (highest value), then backfill `uat` and `dev` for
parity if those EU workspaces exist.
