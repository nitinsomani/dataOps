# Phase 9: Cluster Management, Compute & Cost DevOps — Lab Exercises

---

## Lab 1: Autotermination and Cost Comparison

1. Create an all-purpose cluster with **no** autotermination set. Note the estimated DBU/hour.
2. Create a second identical cluster with autotermination = 15 minutes.
3. Leave both idle and check back in 30+ minutes.

### Questions to Answer
- [ ] What state is each cluster in after 30 minutes?
- [ ] Estimate the cost difference over a typical 8-hour idle overnight period between the two configurations.

---

## Lab 2: Build a Cluster Policy

1. Go to **Compute** → **Policies** → **Create Policy**.
2. Author a policy JSON that:
   - Fixes `autotermination_minutes` to 20 (hidden)
   - Allowlists 2-3 instance types
   - Requires a `cost_center` tag with no default (user must supply it)
   - Forbids `No Isolation Shared` access mode

```json
{
  "autotermination_minutes": {"type": "fixed", "value": 20, "hidden": true},
  "node_type_id": {"type": "allowlist", "values": ["Standard_DS3_v2", "Standard_DS4_v2"]},
  "custom_tags.cost_center": {"type": "required"},
  "data_security_mode": {"type": "allowlist", "values": ["SINGLE_USER", "USER_ISOLATION"]}
}
```

3. Assign the policy to a test user/group and have them create a cluster.

### Questions to Answer
- [ ] Which fields became locked/hidden vs. which required manual input in the creation UI?
- [ ] What error message appears if the user tries to create a cluster without the `cost_center` tag?

---

## Lab 3: Job Cluster vs All-Purpose Cost Comparison

1. Create a Job that runs a simple notebook (e.g., writes a small Delta table), using a **Job Cluster**.
2. Run the same notebook manually on an **All-Purpose cluster** attached interactively.
3. Compare the job run history's reported cost/DBU for each approach.

### Questions to Answer
- [ ] What DBU rate difference did you observe between job cluster and all-purpose execution for identical work?
- [ ] If this job ran hourly, estimate the monthly cost difference between the two approaches.

---

## Lab 4: Instance Pools

1. Create an Instance Pool with a minimum idle instance count of 1-2.
2. Create a Job cluster configuration that draws from this pool.
3. Run the job twice — once before the pool has warmed instances, once after.

### Questions to Answer
- [ ] What was the cluster startup time difference between the two runs?
- [ ] What's the idle cost implication of keeping 1-2 instances warm in the pool 24/7?

---

## Lab 5: Cost Attribution with System Tables

```sql
SELECT
  usage_metadata.cluster_id,
  usage_metadata.job_id,
  sku_name,
  SUM(usage_quantity) AS total_dbus
FROM system.billing.usage
WHERE usage_date >= current_date() - INTERVAL 7 DAYS
GROUP BY ALL
ORDER BY total_dbus DESC
LIMIT 20;
```

### Questions to Answer
- [ ] Which job/cluster consumed the most DBUs in the last 7 days in your workspace?
- [ ] Build a query that groups usage by a custom tag (e.g., `cost_center`) instead of cluster/job id — what does that require (tags must be applied consistently first)?

---

## Lab 6: Spot Instances with On-Demand Fallback

1. Configure a job cluster to use spot instances for workers with on-demand fallback enabled, and on-demand for the driver.
2. Run a moderately long job (a few minutes) and monitor the Event Log for any spot instance reclamation/fallback events.

### Questions to Answer
- [ ] Did any workers get reclaimed during the run? If so, how did the job recover?
- [ ] Why is it recommended to keep the driver on-demand even when workers use spot?
