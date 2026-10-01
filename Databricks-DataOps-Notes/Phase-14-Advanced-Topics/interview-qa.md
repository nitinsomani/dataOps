# Phase 14: Advanced Topics — Multi-Cloud, DR & Federation — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ How would you design a disaster recovery strategy for a Databricks-based data platform?

**Answer:**
I'd first define RPO/RTO requirements with the business — how much data loss and downtime is actually acceptable — since that drives the cost/complexity of the solution. I'd separate **logical** recovery (a bad deployment or corrupted data, recoverable via Delta time travel/`RESTORE TABLE` within the retention window) from **physical/regional** recovery (an entire cloud region outage, requiring cross-region storage replication of the underlying Delta/Parquet data plus the ability to quickly stand up a standby workspace). Critically, the workspace itself — cluster policies, job definitions, Unity Catalog grants — should be defined as code (Terraform/Asset Bundles) so a secondary region's workspace can be redeployed quickly rather than manually reconfigured during an actual incident. Most data platforms use an active-passive model (standby region idle until failover) given the batch/near-real-time tolerance typical of data workloads, rather than a more complex and costly active-active setup.

---

## Q2. ⭐ What is Lakehouse Federation and how does it differ from just building an ETL pipeline to copy the external data into Delta?

**Answer:**
Lakehouse Federation lets Unity Catalog register a connection to an external live system (Postgres, MySQL, Snowflake, BigQuery, etc.) and expose it as a **foreign catalog**, so you can query the external system's data directly through Databricks SQL syntax without first copying it into Delta tables. This is appropriate for ad hoc or infrequent cross-system joins where building and maintaining a dedicated ingestion pipeline isn't justified. It's not a substitute for proper ingestion when you need consistent, high-volume, governed, performant access — federated queries are ultimately bounded by the source system's own query capacity, and you lose Delta-specific performance benefits (data skipping, Z-Order, Photon acceleration on your own copy) since the actual computation partially happens on the source system.

---

## Q3. How is Delta Sharing different from simply granting an external partner access to your Databricks workspace?

**Answer:**
Delta Sharing is an **open, cross-platform protocol** — a recipient can read shared live Delta table data using any Delta Sharing-compatible client (Spark, pandas, PowerBI) without needing a Databricks account at all, authenticated via a bearer-token credential file for "open sharing," or directly via Unity Catalog identities for Databricks-to-Databricks sharing within the same organization's broader account. Granting workspace access instead requires the partner to become a Databricks user in your account, subject to your workspace's full authentication/authorization setup — much heavier-weight and creates platform lock-in for the recipient. Delta Sharing decouples "sharing governed data" from "requiring the recipient to run the same platform," which matters directly for multi-cloud and cross-organization scenarios.

---

## Q4. What does "Data Mesh" mean in the context of Unity Catalog, and what's the DataOps engineer's role in that model?

**Answer:**
Data Mesh is an organizational pattern where data ownership is decentralized to domain teams — each domain owns and publishes its own governed "data products" with clear SLAs, rather than a single central data engineering team owning all pipelines. Unity Catalog's catalog-per-domain structure naturally supports this: each domain can own a catalog, publish tables/views as data products, and grant cross-domain access via standard UC grants or Delta Sharing rather than requiring a central gatekeeper for every access request. In this model, a DataOps engineer typically shifts toward building **self-service platform tooling** — standardized CI/CD templates, cluster policies, monitoring dashboards, and governance guardrails — that domain teams use to operate their own pipelines independently, rather than the DataOps engineer directly owning every domain's pipeline logic.

---

## Q5. Why can't Unity Catalog governance span multiple clouds or regions natively, and how do organizations bridge this?

**Answer:**
A Unity Catalog metastore is scoped to a single region (and typically a single cloud), since it's tied to the underlying cloud infrastructure and workspaces attached to it. Organizations needing true multi-cloud or multi-region governance typically run separate metastores per region/cloud, bridging shared data between them via **Delta Sharing** (for point-to-point sharing of specific tables) or cross-cloud/cross-region object storage replication combined with separate table registrations in each metastore. This is a deliberate architectural trade-off — full unified cross-cloud governance isn't a single-click feature, and the design needs to account for which data genuinely needs to cross cloud/region boundaries versus what can stay region-local.

---

## Q6. How would you approach cost and policy consistency across dozens of Databricks workspaces in a large enterprise?

**Answer:**
I'd manage cluster policies, Unity Catalog grants, network configuration, and secret scope structure as Terraform code applied consistently across all workspaces — rather than each workspace admin configuring things independently, which inevitably drifts into inconsistent security postures and cost controls over time ("workspace sprawl"). For cost, I'd rely on consistent tagging (cost_center, team, environment) enforced via cluster policies, aggregated through `system.billing.usage` queries (or exported to the cloud provider's billing tools) to build chargeback/showback reporting per business unit. This "policy as code" approach at the platform level is really Phase 10's CI/CD discipline applied one level up — to the platform configuration itself, not just individual pipelines.

---

## Q7. How do newer capabilities like Vector Search and Genie change the governance responsibilities of a DataOps engineer?

**Answer:**
Vector Search indexes (used for RAG/GenAI applications) and Genie (natural language querying over governed data) both operate within the existing Unity Catalog permission model — a user's ability to query certain data via Genie, or retrieve certain documents via a vector search index, is still bounded by the same UC grants that govern direct SQL access. This means the governance work a DataOps engineer already does (row filters, column masks, careful grant scoping) directly determines what these newer AI-driven interfaces can expose, often to a less technical audience than would previously be querying SQL directly — raising the stakes on getting governance right, since a natural-language interface can make it easier for a user to stumble onto data they shouldn't see if the underlying grants are too permissive.
