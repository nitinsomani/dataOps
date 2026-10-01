# Phase 16: System Design — AWS Data Platform Architecture — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ Design a data platform on AWS + Databricks that ingests 50,000 clickstream events/sec, supporting both real-time fraud alerts (sub-second) and next-day BI reporting.

**Answer sketch:**
Two consumption paths off the same source: events publish to **Kinesis Data Streams** (or MSK). Path 1 (real-time): a Structured Streaming job with a short `processingTime` trigger reads directly from Kinesis, applies fraud-scoring logic (possibly invoking a Model Serving endpoint per micro-batch), and writes flagged events to an alerting table/downstream notification (SNS). Path 2 (batch/BI): the same Kinesis stream is also archived via **Kinesis Firehose** into S3 raw/Bronze, then a scheduled Auto Loader job (`trigger(availableNow=True)`) processes it into Silver/Gold Delta tables nightly for BI consumption via Databricks SQL. This dual-path design avoids forcing the low-latency path to also serve heavy BI aggregation queries, and avoids forcing the BI path to run on an expensive always-on streaming cluster. I'd call out cost (streaming cluster runs 24/7 — justified only because of the sub-second SLA) and governance (Unity Catalog grants restricting who can see raw clickstream PII).

---

## Q2. ⭐ Design a CDC pipeline replicating an on-prem Oracle database into the Lakehouse with under 5-minute latency.

**Answer sketch:**
Use a CDC tool (Debezium, AWS DMS, or a commercial connector) that reads Oracle's redo logs and publishes change events to **MSK/Kinesis**, since on-prem Oracle doesn't natively integrate with Databricks. Connectivity from on-prem to AWS goes through **Direct Connect or VPN** (ties to networking fundamentals). A Structured Streaming job (or DLT pipeline) consumes the CDC stream into Bronze with the operation type (insert/update/delete) and sequence timestamp preserved, then a `MERGE INTO` (or DLT `apply_changes`) applies changes into a current-state Silver table, satisfying the 5-minute latency requirement via a short `processingTime` trigger rather than `availableNow` batch scheduling. I'd flag the need for **initial full-load bootstrapping** (a one-time bulk extract before the CDC stream starts) and idempotency (replaying the same CDC event twice must not corrupt state — MERGE keyed on primary key handles this).

---

## Q3. When would you recommend Glue ETL over Databricks for a given workload, and how would you justify that to a team that's already invested in Databricks?

**Answer sketch:**
Glue makes sense for genuinely simple, infrequent, or low-volume transformations where the overhead of governance/Unity Catalog integration isn't needed, and where avoiding *any* cluster/session management (fully serverless, pay-per-job-second) matters more than Databricks' richer tooling — e.g., a small one-off data cleanup job run a few times a month. I'd justify recommending it (even to a Databricks-invested team) by being explicit about the tradeoff: Glue is cheaper and simpler for that narrow case, but you lose Unity Catalog governance, Delta Lake's ACID guarantees (unless explicitly using Glue with Delta support), and the unified lineage/audit story — so I'd only recommend it for genuinely isolated, low-stakes jobs, not as a general pattern, to avoid fragmenting governance across two platforms.

---

## Q4. How does Databricks' Unity Catalog interact with a company's existing AWS Glue Data Catalog?

**Answer sketch:**
Unity Catalog can be configured to read from (or migrate away from) an existing Glue Data Catalog, but the modern recommended pattern is for Unity Catalog to be the **single source of truth** for governance going forward, rather than running both catalogs in parallel indefinitely — dual catalogs create exactly the kind of governance fragmentation and drift risk that Unity Catalog was designed to eliminate. In a migration scenario, I'd plan an explicit cutover: register existing Glue-cataloged tables into Unity Catalog (often as external tables pointing at the same S3 locations), validate access patterns/grants are correctly re-established in UC, and then treat Glue Catalog as legacy/read-only rather than continuing to write new tables there.

---

## Q5. ⭐ How would you design network access so that Databricks clusters can reach S3 without traversing the public internet, and why does this matter?

**Answer sketch:**
Deploy Databricks with **VPC injection** into a customer-managed VPC, configure a **VPC Endpoint (Gateway type) for S3** so traffic from the cluster's private subnets reaches S3 over AWS's internal network rather than the public internet, and combine this with **No Public IP (NPIP)** cluster configuration so worker/driver nodes have no public IP addresses at all. This matters for both security (eliminating a public internet attack surface for data-plane-to-storage traffic) and often for compliance requirements that mandate no regulated data traverse the public internet even in encrypted form. I'd also mention PrivateLink for the separate concern of control-plane connectivity (Phase 7), since S3 VPC endpoints and PrivateLink solve different parts of the "keep traffic off the public internet" requirement.

---

## Q6. Design a cost-optimized architecture for a company whose daily batch ETL workload varies dramatically — some days 10GB, other days 500GB (e.g., month-end reporting spikes).

**Answer sketch:**
I'd avoid fixed-size clusters sized for the worst case (wasteful on normal days) and instead use **job clusters with autoscaling** (min/max workers) so compute scales with actual daily volume, combined with **spot instances with on-demand fallback** for the fault-tolerant batch workers. For the underlying storage, I'd apply **S3 lifecycle policies** (Intelligent-Tiering or transition to Infrequent Access/Glacier for older Bronze data rarely re-queried) to control storage cost independent of compute. I'd also evaluate whether the month-end spike workload could be decoupled into its own separate job (rather than baked into the daily job's cluster sizing logic), so the daily job stays lean and the monthly spike gets its own appropriately-sized ephemeral cluster only when it actually runs.

---

## Q7. How would you design a multi-tenant data platform for multiple business units needing isolated compute but the ability to share specific governed datasets?

**Answer sketch:**
I'd use a **catalog-per-business-unit** Unity Catalog structure (ties to Phase 6/14's Data Mesh discussion), each with its own cluster policies enforcing tenant-specific cost/security constraints, and separate job/cluster ownership per unit to isolate compute blast radius (one tenant's runaway job shouldn't starve another's). Cross-unit data sharing happens via explicit Unity Catalog **GRANTs** on specific tables/views (within the same metastore) rather than broad cross-catalog access, or via **Delta Sharing** if the business units are on genuinely separate metastores/accounts (e.g., post-acquisition subsidiaries). I'd also enforce network isolation via separate VPCs or subnets per tenant if compute isolation needs to extend to the network layer, not just the governance layer.
