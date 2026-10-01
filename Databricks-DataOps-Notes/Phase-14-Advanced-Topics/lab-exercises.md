# Phase 14: Advanced Topics — Multi-Cloud, DR & Federation — Lab Exercises

> Some labs are conceptual/design exercises since full multi-cloud/DR setups require infrastructure beyond a single trial workspace.

---

## Lab 1: Design a DR Runbook (Conceptual)

**Objective**: Write a concrete DR runbook for a hypothetical Databricks platform.

1. Define RPO/RTO targets for a hypothetical e-commerce analytics platform (e.g., RPO = 1 hour, RTO = 4 hours).
2. List the specific steps required to fail over to a secondary region:
   - Which Terraform/Asset Bundle commands would redeploy workspace resources?
   - Which storage replication mechanism handles the underlying Delta files?
   - What manual steps (if any) remain, and how would you eliminate them over time?

### Questions to Answer
- [ ] What's your answer if asked "how much data would you lose in a regional failure" given your chosen replication mechanism's typical lag?
- [ ] Which parts of this runbook could be tested without an actual regional outage (e.g., periodic DR drills)?

---

## Lab 2: Set Up Lakehouse Federation (if you have a reachable external database)

```sql
CREATE CONNECTION lab14_pg_conn TYPE postgresql
OPTIONS (
  host '<your-postgres-host>',
  port '5432',
  user 'svc_user',
  password secret('lab7-scope', 'api-key')  -- reuse a secret scope from Phase 7
);

CREATE FOREIGN CATALOG lab14_pg_catalog USING CONNECTION lab14_pg_conn
OPTIONS (database 'testdb');

SELECT * FROM lab14_pg_catalog.public.some_table LIMIT 10;
```

### Questions to Answer
- [ ] Run `EXPLAIN` on a federated query — does any of the filtering/aggregation get pushed down to Postgres, or is all data pulled into Spark first?
- [ ] What UC grants would you need to give an analyst read access to this foreign catalog?

---

## Lab 3: Delta Sharing — Create and Consume a Share

```sql
CREATE SHARE lab14_share;
ALTER SHARE lab14_share ADD TABLE main.lab3.orders;   -- reuse table from Phase 3

CREATE RECIPIENT lab14_recipient;
GRANT SELECT ON SHARE lab14_share TO RECIPIENT lab14_recipient;

DESCRIBE RECIPIENT lab14_recipient;  -- shows activation link / token info for open sharing
```

```python
# Consuming from a non-Databricks client (conceptual — requires delta-sharing python package)
import delta_sharing
client = delta_sharing.SharingClient("<path-to-downloaded-profile-file>.share")
client.list_all_tables()
df = delta_sharing.load_as_pandas("<profile-file>.share#lab14_share.default.orders")
```

### Questions to Answer
- [ ] What information is contained in the `.share` credential file, and why must it be handled as a secret?
- [ ] How would you revoke access for `lab14_recipient` if the partnership ended?

---

## Lab 4: Cost Chargeback Across Simulated "Teams" via Tags

```sql
-- Assume clusters/jobs already tagged with cost_center in Phase 9
SELECT
  custom_tags.cost_center AS team,
  SUM(usage_quantity) AS total_dbus
FROM system.billing.usage
LEFT JOIN LATERAL (SELECT * FROM json_each(tags)) AS custom_tags ON true  -- adjust based on actual schema
WHERE usage_date >= current_date() - INTERVAL 30 DAYS
GROUP BY team
ORDER BY total_dbus DESC;
```

### Questions to Answer
- [ ] Adjust this query to match the actual structure of `system.billing.usage` in your workspace (check `DESCRIBE system.billing.usage`) — what are the real tag-related columns?
- [ ] How would you present this as a monthly chargeback report to engineering leadership?

---

## Lab 5: Data Mesh Catalog Design Exercise (Conceptual)

**Objective**: Design a Unity Catalog structure for a company with 4 domains: Sales, Marketing, Finance, and Product Analytics.

1. Sketch out a catalog/schema naming convention supporting both domain ownership and dev/staging/prod environments.
2. Decide: catalog-per-domain-per-environment, or catalog-per-environment with schema-per-domain? Justify your choice.
3. Define which cross-domain data products would need to be shared, and via what mechanism (UC grants within the same metastore vs Delta Sharing if domains span different metastores/clouds).

### Questions to Answer
- [ ] What naming convention did you land on, and how does it scale if a 5th domain is added later?
- [ ] Which domain(s) would need the most cross-domain grants, and how would you avoid an unmanageable grant sprawl?
