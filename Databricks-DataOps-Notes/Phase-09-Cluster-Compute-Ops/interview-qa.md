# Phase 9: Cluster Management, Compute & Cost DevOps — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ Your team's Databricks bill has doubled month-over-month with no corresponding increase in data volume. How do you investigate?

**Answer:**
I'd start with `system.billing.usage` to break down DBU consumption by job/warehouse/cluster and tag (cost_center/team), looking for the specific workload(s) driving the increase rather than assuming it's uniform growth. Common root causes I'd check: all-purpose clusters left running without autotermination (or autotermination misconfigured), a job accidentally switched from a job cluster to an all-purpose cluster, a runaway/looping job retrying excessively, someone disabling spot instances or switching to larger instance types without a corresponding need, or a new SQL Warehouse left running continuously instead of using serverless auto-stop. I'd also check whether Photon was enabled somewhere without validating it actually reduced total cost for that specific workload.

---

## Q2. ⭐ What's the difference between an All-Purpose cluster and a Job cluster from a cost perspective, and why do production pipelines default to Job clusters?

**Answer:**
All-Purpose clusters are meant to stay up for interactive use and are billed at a higher DBU rate; if left running idle (no autotermination, or autotermination set too generously), they silently accumulate cost. Job clusters are provisioned fresh when a scheduled Job starts and automatically terminate when it finishes, at a lower DBU rate — you only pay for the exact duration of the actual work, with no risk of idle accumulation. Production pipelines default to Job clusters both for the cost savings and because ephemeral clusters provide workload isolation (one job's cluster issue can't affect another concurrently-running job sharing the same all-purpose cluster).

---

## Q3. Explain cluster policies and how they support both cost control and security governance simultaneously.

**Answer:**
Cluster policies are admin-authored JSON templates that constrain what configuration options are available when a user creates a cluster — they can **fix** values (hidden from the user entirely, e.g., always applying a `cost_center` tag or a 30-minute autotermination) or **restrict choices** to an allowlist (e.g., only certain instance types). This serves cost control (capping max workers, disallowing oversized/expensive instance types, enforcing autotermination) and security (disallowing "No Isolation Shared" access mode, forbidding public IPs, requiring specific network configurations) through the same mechanism — a single policy assignment enforces both concerns without relying on users remembering best practices manually.

---

## Q4. When would you use spot instances, and what's the risk/mitigation?

**Answer:**
Spot (AWS)/preemptible (GCP)/low-priority (Azure) instances offer significant discounts (often 60-90% cheaper) in exchange for the cloud provider being able to reclaim the instance with short notice when capacity is needed elsewhere. They're well-suited for worker nodes on fault-tolerant, restartable workloads — Spark naturally re-schedules lost tasks on remaining workers, so losing a spot worker mid-job is usually just a partial slowdown, not a failure, especially with checkpointed streaming jobs. The main mitigation is configuring **on-demand fallback** (Databricks automatically provisions on-demand instances if spot capacity isn't available or gets reclaimed) and generally avoiding spot for the **driver** node, since losing the driver kills the entire job regardless of task-level fault tolerance.

---

## Q5. What are Instance Pools and what specific problem do they solve?

**Answer:**
Instance Pools maintain a set of idle, pre-provisioned cloud VMs ready to be attached to a cluster on demand — when a cluster is created against a pool, it borrows already-running instances instead of waiting for the cloud provider to provision new VMs from scratch, cutting cluster startup time from several minutes down to seconds. This matters most for workloads with frequent short-lived job clusters (e.g., many small scheduled jobs throughout the day) where the fixed multi-minute VM provisioning overhead would otherwise dominate total runtime and cost for each run. Pools have their own idle-instance cost/configuration trade-offs (keeping some capacity warm costs money even when unused), so they're most valuable when startup latency reduction outweighs that idle cost.

---

## Q6. How would you structure environments (dev/staging/prod) for a Databricks-based data platform, and why does this matter operationally?

**Answer:**
I'd use separate workspaces (or at minimum separate Unity Catalog catalogs, ideally both) per environment, with distinct cluster policies, secret scopes, and network configurations for each — critically ensuring a dev-environment misconfiguration or runaway job cannot touch production compute, cost, or data (blast radius isolation). Consistency across environments would be maintained via Infrastructure as Code (Terraform/Databricks Asset Bundles) rather than manual configuration, so promoting a pipeline from staging to prod means deploying the same defined configuration rather than re-clicking settings and risking drift. This structure also makes cost attribution cleaner (tags/usage naturally segment by environment) and simplifies reasoning about access control (prod catalog access is a strict, small, audited group).

---

## Q7. What's the tradeoff between enabling autoscaling versus using a fixed-size cluster for a given job?

**Answer:**
Autoscaling adapts worker count to actual workload demand, avoiding over-provisioning for variable workloads — good for jobs with unpredictable or highly variable data volume. However, autoscaling has a ramp-up delay (it takes time to detect queued tasks and provision additional workers), so for very short-running or bursty jobs, a fixed-size (or pool-backed) cluster sized appropriately for the known workload can actually finish faster and end up cheaper overall, since the job completes before autoscaling would have reacted anyway. I'd choose fixed-size clusters for predictable, short jobs and autoscaling for longer-running or highly variable workloads where the ramp-up cost is amortized over a longer runtime.
