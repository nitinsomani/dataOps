# Phase 9: Cluster Management, Compute & Cost DevOps — Detailed Notes

> **Goal**: This is the "infra ops" side of DataOps — treating compute as a managed, cost-aware resource rather than something manually clicked together.

---

## 1. Cluster Lifecycle Management

- **Autotermination**: every all-purpose cluster should have an idle timeout configured (e.g., 30-60 min) — the single highest-impact cost control for interactive clusters.
- **Autoscaling**: define min/max workers; Databricks scales workers up when tasks are queued and scales down when idle. Autoscaling has a ramp-up delay — for latency-sensitive jobs, a fixed-size cluster may outperform autoscaling despite the higher baseline cost.
- **Spot/preemptible instances**: use for worker nodes (not typically the driver) to cut compute cost significantly (up to 60-90%) — combined with **on-demand fallback** (Databricks can automatically fall back to on-demand instances if spot capacity is unavailable/reclaimed) to balance cost and reliability.
- **Instance Pools**: maintain a set of pre-warmed idle VMs so clusters attached to the pool skip the multi-minute cloud VM provisioning step — cuts cluster start latency from minutes to seconds, valuable for frequent short-lived job clusters.

---

## 2. Cluster Policies — Governance for Compute

```json
{
  "node_type_id": {"type": "allowlist", "values": ["Standard_DS3_v2", "Standard_DS4_v2"]},
  "autotermination_minutes": {"type": "fixed", "value": 30, "hidden": true},
  "custom_tags.cost_center": {"type": "fixed", "value": "data-eng", "hidden": true},
  "spark_conf.spark.databricks.cluster.profile": {"type": "forbidden"}
}
```
- Admin-defined constraints on what configurations users are allowed to select — enforce cost limits (max workers, disallow oversized instance types), security baselines (no public IP, required tags), and consistency (standard DBR version across the org).
- Policies can **fix** a value (hidden from the user, always applied) or **allowlist** a set of choices — different levels of control.

---

## 3. Choosing the Right Compute for the Workload

| Workload | Recommended compute |
|----------|----------------------|
| Interactive notebook development | All-purpose cluster, autotermination on, small pool |
| Scheduled production ETL job | Job cluster (ephemeral), spot workers where tolerable |
| BI/dashboard queries | SQL Warehouse (Serverless preferred for spiky usage) |
| DLT pipeline | DLT-managed cluster (auto-provisioned by the pipeline) |
| ML training | GPU cluster or ML runtime, often with dedicated pools |
| High-concurrency ad hoc SQL | Serverless SQL Warehouse with autoscaling |

---

## 4. Cost Monitoring & Attribution

- **Tags**: apply `cost_center`, `team`, `environment`, `project` tags to clusters/jobs/warehouses — flows through to cloud billing exports, enabling chargeback/showback reporting.
- **System tables for cost**: `system.billing.usage` gives DBU consumption joined with list prices, queryable with SQL — build cost dashboards natively instead of relying solely on cloud provider billing consoles.

```sql
SELECT usage_metadata.job_id, SUM(usage_quantity) AS dbus
FROM system.billing.usage
WHERE usage_date >= current_date() - INTERVAL 30 DAYS
GROUP BY usage_metadata.job_id
ORDER BY dbus DESC;
```

- **Budgets & alerts**: account-console budget policies can alert (and in some cases block) when spend crosses a threshold.

---

## 5. Databricks Runtime (DBR) Version Management

- Always default to the latest **LTS (Long Term Support)** version for production — gets security patches and bug fixes for an extended period without forcing frequent major upgrades.
- Track DBR **end-of-support dates** — running an unsupported DBR version is both a security risk and can block access to new features (e.g., certain UC capabilities require a minimum DBR version).
- Test DBR upgrades in a lower environment first — Spark/Photon behavior can subtly change between versions (e.g., default config changes, deprecated APIs).

---

## 6. Init Scripts & Custom Environments

```python
# Cluster-scoped init script (stored in a Volume/Workspace file)
%sh
pip install --index-url https://internal-pypi.company.com my-internal-lib==1.2.3
```
- **Init scripts** run at cluster startup to install custom libraries, configure OS-level settings, or set up monitoring agents.
- Prefer **cluster policies + library configuration** or **environment specs** (serverless compute environments) over ad hoc init scripts where possible — more auditable and reproducible.
- **Container services** (Databricks Container Services / custom Docker images) allow fully custom base images when standard DBR + init scripts aren't sufficient.

---

## 7. Multi-Workspace / Multi-Environment Strategy

- Typical setup: separate workspaces (or at least separate catalogs) for `dev`, `staging`, `prod` — sometimes separate workspaces per business unit/region for isolation and blast-radius control.
- **Workspace as a unit of blast radius**: a runaway job or misconfiguration in dev shouldn't be able to affect prod compute/cost/data — enforced by both workspace separation and Unity Catalog catalog isolation.
- Infrastructure as Code (Terraform — Phase 10) is the standard way to keep multiple workspaces consistently configured (same cluster policies, same secret scopes structure, same network setup) without manual drift.

---

## 8. Autoscaling Nuances

- **Enhanced Autoscaling** (available for DLT and some job clusters): more responsive scale-down, avoids over-provisioning at the end of a job when work is trailing off.
- Autoscaling doesn't help with **skewed** workloads — if one task is a straggler, adding more workers doesn't speed up that single task; skew must be fixed at the data/query level (Phase 2/8).
- For very short jobs, autoscaling ramp-up time can dominate — sometimes a small fixed-size cluster (or pool-backed cluster) finishes faster and cheaper than waiting for autoscaling to react.

---

## 9. Key Takeaways for DataOps

- Autotermination + job clusters + spot instances + pools are the four biggest cost levers — know each and when to (not) use them.
- Cluster policies are how governance and cost control get **enforced**, not just recommended — a DataOps engineer should be comfortable authoring these.
- `system.billing.usage` turns cost monitoring into a normal SQL/BI problem — no separate tooling required.
- Treat compute configuration as code (via Asset Bundles/Terraform, Phase 10) — manual cluster clicking doesn't scale across environments.
