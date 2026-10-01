# Phase 9: Cluster Management, Compute & Cost DevOps — Cheat Sheet

---

## Top 4 Cost Levers

```
1. Autotermination        — kill idle all-purpose clusters (biggest lever)
2. Job clusters            — ephemeral, cheaper than all-purpose for scheduled work
3. Spot/preemptible workers — up to 60-90% cheaper, use on-demand fallback
4. Instance Pools           — pre-warmed VMs, faster + cheaper frequent job starts
```

## Compute Selection Table

| Workload | Compute |
|----------|---------|
| Interactive dev | All-purpose + autotermination |
| Scheduled ETL | Job cluster (ephemeral) |
| BI/dashboards | SQL Warehouse (Serverless preferred) |
| DLT pipeline | DLT-managed cluster |
| ML training | GPU / ML runtime + pools |
| Ad hoc high concurrency SQL | Serverless SQL Warehouse, autoscale |

## Cluster Policy Skeleton

```json
{
  "node_type_id": {"type": "allowlist", "values": ["Standard_DS3_v2"]},
  "autotermination_minutes": {"type": "fixed", "value": 30, "hidden": true},
  "custom_tags.cost_center": {"type": "fixed", "value": "data-eng"}
}
```

## Cost Monitoring Query

```sql
SELECT usage_metadata.job_id, SUM(usage_quantity) AS dbus
FROM system.billing.usage
WHERE usage_date >= current_date() - INTERVAL 30 DAYS
GROUP BY usage_metadata.job_id ORDER BY dbus DESC;
```

## DBR Version Guidance

```
Production → latest LTS version
Track end-of-support dates
Test upgrades in dev/staging first
```

## Autoscaling Gotchas

```
- Ramp-up delay: bad for very short/bursty jobs
- Doesn't fix skew: adding workers ≠ speeding up a straggler task
- Enhanced Autoscaling (DLT) scales down more responsively
```

## Environment Isolation

```
Separate workspaces/catalogs: dev | staging | prod
Blast radius: dev misconfig should never touch prod compute/data
IaC (Terraform/Asset Bundles) keeps environments consistent, no manual drift
```
