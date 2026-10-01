# Phase 15: Interview Preparation — Scenario-Based Interview Q&A

> Full end-to-end scenario questions synthesizing all prior phases. Practice answering out loud, timed.

---

## Q1. ⭐ Design an end-to-end pipeline that ingests daily sales data from a partner's S3 bucket, cleans and aggregates it, and serves it to a BI dashboard with strong governance and cost control.

**Answer sketch:**
**Requirements**: daily batch (not real-time), moderate volume, consumed by BI/Databricks SQL dashboards, needs governance since it may contain partner PII/pricing data.

**Architecture**: Auto Loader (`cloudFiles`, file notification mode) reading from the partner's S3 path with `trigger(availableNow=True)` scheduled via a daily Databricks Job — gets incremental efficiency without an always-on cluster. Bronze layer lands raw with ingestion metadata and `_rescued_data` for schema drift tolerance (since it's an external partner feed, I'd favor `rescue` mode over hard failure). Silver deduplicates, validates via DLT expectations (or Great Expectations if not using DLT), and joins any internal reference/dimension data. Gold aggregates into a star-schema-like structure optimized for the BI tool's query patterns, using Liquid Clustering on commonly-filtered columns.

**Governance**: dedicated Unity Catalog catalog/schema for this domain, row filters if different partner regions need row-level restriction, column masks if PII is present, grants scoped to a BI-analyst group.

**Reliability**: job cluster (not all-purpose) with retries and repair-run capability, checkpointed Auto Loader for idempotency, freshness/volume checks alerting if the partner feed doesn't arrive on schedule.

**CI/CD**: pipeline defined as a Databricks Asset Bundle, deployed through dev→staging→prod with a manual approval gate before prod, tested with unit tests on transformation logic and integration tests against a scratch catalog.

**Cost**: job cluster with autotermination, spot workers (batch job tolerates interruption), Photon enabled for the aggregation-heavy Gold step given likely net cost benefit.

---

## Q2. A critical nightly job has been failing intermittently for the past week — sometimes it succeeds, sometimes it times out. How do you investigate and fix this long-term?

**Answer sketch:**
Start with `system.lakeflow.job_run_timeline` to look at the pattern of failures — is it always the same task, a particular time of day, or correlated with specific upstream data volume spikes? Check the Spark UI for failed runs for skew/spill/shuffle anomalies, and check whether cluster provisioning itself is sometimes slow (e.g., spot instance unavailability if using spot workers without proper fallback). I'd check if the job's timeout setting is simply too tight for legitimate variance in data volume, versus a genuine performance regression. Long-term fixes might include: adding retries with backoff for transient issues, switching from spot to on-demand for this specific critical job if interruption is the root cause, adding autoscaling or resizing the cluster if data volume has genuinely grown, and adding a freshness/volume check upstream to catch a root-cause data issue rather than just treating symptoms. I'd also ensure Repair Run is available so a partial failure doesn't require reprocessing already-completed upstream tasks.

---

## Q3. How would you migrate a legacy on-premises ETL pipeline (SSIS/Informatica jobs writing to a SQL Server warehouse) to Databricks?

**Answer sketch:**
I'd start by inventorying the existing pipeline's sources, transformation logic, and downstream consumers, then map this onto a medallion architecture: source extraction becomes an ingestion pattern (Auto Loader for file-based sources, Lakehouse Federation or a CDC tool for direct database sources), the SSIS/Informatica transformation logic gets reimplemented as PySpark/SQL in Silver, and the final warehouse tables map to Gold. I'd migrate incrementally, domain-by-domain or pipeline-by-pipeline rather than a big-bang cutover, running the new Databricks pipeline in parallel with the legacy system and comparing outputs (a form of data contract/reconciliation testing) before cutting over consumers. Unity Catalog would be set up from day one (not retrofitted later) with a clear catalog/schema strategy, and the new pipelines would be built with CI/CD (Asset Bundles) and data quality gates from the start rather than replicating the legacy system's likely lack of automated testing.

---

## Q4. Your organization wants to reduce Databricks costs by 30% without impacting SLAs. Walk me through your approach.

**Answer sketch:**
I'd start with `system.billing.usage` broken down by job/cluster/team to identify the biggest cost drivers rather than applying blanket cuts. Common high-impact, low-risk levers: enforce autotermination on all-purpose clusters via cluster policy (often the single biggest quick win), convert any production jobs still running on all-purpose clusters to job clusters, introduce/expand spot instance usage with on-demand fallback for fault-tolerant batch workloads, right-size over-provisioned clusters (check if autoscaling max is unnecessarily high, or if a fixed cluster is oversized for actual workload), and evaluate serverless SQL Warehouses with auto-stop for spiky BI workloads instead of always-on classic warehouses. I'd validate SLA impact before/after each change with actual measurements (not assumptions), and consider Photon specifically where its speedup would let a smaller/cheaper cluster meet the same SLA.

---

## Q5. A data scientist reports their model's production accuracy has silently degraded over the past month, even though nothing in the model code changed. How do you help diagnose this?

**Answer sketch:**
This is a classic drift scenario. I'd check whether Lakehouse Monitoring (or equivalent) shows a shift in the production inference input feature distributions compared to the training baseline — if the real-world data has drifted from what the model was trained on, degraded accuracy without any code change is expected. I'd also check the Feature Store pipeline (if used) for any recent upstream schema or logic changes that might have subtly altered feature computation, causing training/serving skew even without a direct model code change. I'd verify the feature computation logic used in the original training set matches what's currently being computed for live inference (point-in-time correctness and consistency), and check Unity Catalog lineage to see if any upstream source tables feeding the features changed structurally or in data quality recently. The fix is typically either retraining on more recent representative data, or fixing an upstream feature pipeline bug if one is found.

---

## Q6. How would you convince a skeptical stakeholder that investing in CI/CD and automated testing for data pipelines (rather than "just shipping fast") is worth the upfront time cost?

**Answer sketch:**
I'd frame it in terms of total cost/risk rather than abstract engineering best practice: manual, untested deployments have a real (often underestimated) failure rate that translates into incident response time, bad business decisions made on wrong data, and erosion of stakeholder trust in the data platform — all of which cost more than the upfront investment in CI/CD once you account for even a handful of incidents per year. I'd propose starting small and incrementally — e.g., adding automated tests and a staging deployment step for just the highest-business-impact pipeline first, measuring the reduction in production incidents/rollbacks over a quarter, and using that concrete evidence to justify expanding the practice further, rather than trying to mandate a full CI/CD overhaul across every pipeline immediately.
