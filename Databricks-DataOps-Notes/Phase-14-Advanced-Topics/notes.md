# Phase 14: Advanced Topics — Multi-Cloud, DR, Lakehouse Federation & Delta Sharing — Detailed Notes

> **Goal**: Senior/staff-level topics — architecture decisions for resilience, cross-platform data access, and multi-cloud/region strategy.

---

## 1. Disaster Recovery (DR) & Business Continuity Planning (BCP)

- **RPO (Recovery Point Objective)**: maximum acceptable data loss, measured in time (e.g., "we can lose at most 15 minutes of data").
- **RTO (Recovery Time Objective)**: maximum acceptable downtime before service is restored.
- Databricks DR strategy typically involves:
  - **Cross-region storage replication**: replicate underlying Delta Lake data (S3 Cross-Region Replication, ADLS geo-redundant storage, GCS multi-region buckets) to a secondary region.
  - **Workspace redundancy**: maintain a standby workspace (and metastore, if using UC) in a secondary region, with Infrastructure as Code (Terraform/Asset Bundles) able to redeploy all jobs/pipelines/clusters quickly ("pets vs cattle" — workspaces should be reproducible from code, not hand-configured).
  - **Metadata backup**: Unity Catalog metadata, job definitions, and cluster policies should all be recoverable from version-controlled IaC rather than relying on manual workspace configuration.
- **Active-passive** (standby region idle until failover) vs **active-active** (both regions serving traffic, more complex, rarely needed for batch-oriented data platforms) — most data platforms use active-passive given batch/near-real-time tolerance for brief downtime.
- Delta Lake's transaction log and time travel help with **logical** disaster recovery (bad deployment/bad data) but not **physical** disaster recovery (region outage) — these require distinct strategies.

---

## 2. Lakehouse Federation — Querying External Systems Without Migration

```sql
CREATE CONNECTION postgres_conn TYPE postgresql
OPTIONS (host 'db.company.com', port '5432', user 'svc_user', password secret('scope','pg-pass'));

CREATE FOREIGN CATALOG postgres_catalog USING CONNECTION postgres_conn
OPTIONS (database 'salesdb');

SELECT * FROM postgres_catalog.public.orders;   -- query live, no data movement/copy needed
```

- **Lakehouse Federation** lets Unity Catalog register connections to external data systems (Postgres, MySQL, Snowflake, Redshift, BigQuery, SQL Server) and query them directly via a **foreign catalog**, without ETL-ing the data into Delta first.
- Use case: ad hoc joins between Lakehouse data and an operational database, without building/maintaining a dedicated ingestion pipeline just for occasional access.
- Trade-off: query performance depends on the source system's own capacity — not a substitute for proper ingestion when you need consistent, high-volume, governed access with Delta's performance characteristics.

---

## 3. Delta Sharing — Cross-Organization / Cross-Platform (recap + deeper)

- Already covered in Phase 6 for governance — architecturally, Delta Sharing is an **open protocol** (not Databricks-proprietary), meaning a recipient reading shared data doesn't need to be a Databricks customer at all.
- **Databricks-to-Databricks sharing**: simpler, uses Unity Catalog identities directly.
- **Open sharing**: uses bearer-token-based credential files (`.share` files) for recipients outside your Databricks account/organization entirely.
- Relevant to multi-cloud strategy: an organization on AWS Databricks can share data with a partner on Azure Databricks (or no Databricks at all) via Delta Sharing without any data replication pipeline.

---

## 4. Multi-Cloud & Multi-Region Considerations

- Databricks workspaces are cloud- and region-scoped; running truly multi-cloud means separate workspaces per cloud, with **Delta Sharing** or **cross-cloud object storage replication** as the bridge for shared data.
- Common reasons for multi-cloud: mergers/acquisitions (inherited infrastructure on different clouds), data residency requirements (certain data must stay in a specific cloud/region for regulatory reasons), or avoiding vendor lock-in at the infrastructure level.
- **Unity Catalog metastores are region-scoped** — a single metastore can span multiple workspaces within the same region/cloud, but cross-region/cross-cloud governance requires either multiple metastores (with Delta Sharing bridging them) or careful architecture around a primary region.

---

## 5. Data Mesh & Domain Ownership Patterns

- **Data Mesh** is an organizational/architectural pattern where data ownership is decentralized to domain teams (each owning their own data products), rather than centralized in one data engineering team — Databricks' catalog-per-domain Unity Catalog strategy (Phase 6) is a natural fit for implementing this.
- Domains publish governed "data products" (tables/views with clear ownership, SLAs, and documentation) that other domains consume via UC grants or Delta Sharing, rather than everyone pulling from a single monolithic warehouse team.
- A DataOps engineer in a data mesh org often works on the **platform/self-service tooling** (standardized CI/CD templates, cluster policies, monitoring dashboards) that domain teams use, rather than owning every domain's pipelines directly.

---

## 6. Lakehouse Monitoring at Scale / Multi-Workspace Governance

- Large organizations often run many workspaces (per business unit, region, or environment) attached to one or more metastores — requiring standardized cluster policies, secret scope naming, and CI/CD templates deployed consistently via Terraform across all of them.
- **Account-level API/Terraform** manages cross-workspace concerns (SSO config, network configuration, billing) that individual workspace admins can't control alone.

---

## 7. Cost & Governance at Enterprise Scale

- **Chargeback/showback**: using tags + `system.billing.usage` (Phase 9) to attribute cost per business unit/team, essential once dozens of teams share infrastructure.
- **Centralized policy-as-code**: cluster policies, UC grants, and network configurations defined once in Terraform and applied consistently across all workspaces — prevents "workspace sprawl" where each team configures things slightly differently, causing both security gaps and cost inefficiency.

---

## 8. Emerging/Advanced Patterns Worth Knowing

- **Databricks on Kubernetes / serverless GPU compute**: increasingly used for GenAI/LLM workloads alongside traditional Spark ETL — same governance (Unity Catalog) extends to vector search indexes and LLM endpoints.
- **Vector Search**: Unity Catalog-governed vector indexes for RAG (Retrieval-Augmented Generation) applications, built on the same Delta table change feed mechanism for incremental index updates.
- **Genie / natural language querying**: business users query governed data via natural language, backed by the same UC permission model — a DataOps engineer's governance work directly determines what Genie can/can't expose to a given user.

---

## 9. Key Takeaways for DataOps

- DR planning requires separating **logical recovery** (Delta time travel/restore) from **physical/regional recovery** (cross-region replication + IaC-based workspace rebuild) — interviewers often probe this distinction.
- Lakehouse Federation and Delta Sharing are both about **avoiding unnecessary data movement** — federation for querying external live systems, sharing for distributing your own governed data externally.
- Data Mesh is more an organizational/governance pattern than a specific technology — Unity Catalog's structure supports it, but the pattern itself is about ownership model, not tooling.
- At enterprise scale, "policy as code" (Terraform-managed cluster policies, grants, network config) is what keeps dozens of workspaces consistent — a natural extension of Phase 10's CI/CD principles to the platform level itself.
