# Phase 1: Databricks & Lakehouse Fundamentals — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ What is a Lakehouse and how is it different from a Data Lake or Data Warehouse?

**Answer:**
A **Data Lake** stores raw files cheaply (S3/ADLS) but has no ACID guarantees, no schema enforcement — prone to becoming a "data swamp." A **Data Warehouse** (Snowflake/Redshift) gives strong SQL/BI performance and governance but is expensive, proprietary-format, and weak for ML/unstructured data.

A **Lakehouse** (Databricks' approach via Delta Lake) combines both: data lives once as open Parquet/Delta files in cheap object storage, but gets ACID transactions, schema enforcement/evolution, time travel, and fine-grained governance layered on top — so the same copy of data serves BI, streaming, and ML workloads without duplicating pipelines.

---

## Q2. ⭐ Explain Databricks' Control Plane vs Data Plane architecture. Why does this matter for security?

**Answer:**
The **Control Plane** is hosted and managed by Databricks — it contains the web UI, REST APIs, job scheduler, cluster manager, and (for Unity Catalog) the metadata store. The **Data Plane** runs inside the customer's own cloud account/subscription — this is where clusters (VMs) actually spin up and where the data physically resides.

This separation matters because with classic (non-serverless) compute, **customer data never leaves the customer's cloud account** — Databricks orchestrates compute remotely but doesn't ingest or store the actual data on its own infrastructure. This is a major selling point for regulated industries (finance, healthcare) doing security reviews. Serverless compute changes this slightly — compute runs in a Databricks-managed serverless layer, though data still resides in customer storage.

---

## Q3. What is DBFS and why is Databricks moving away from it?

**Answer:**
DBFS (Databricks File System) is an abstraction layer over cloud object storage, historically used for storing files, mounting external storage (`/dbfs/mnt`), and notebook-adjacent files (`/dbfs/FileStore`). Problems: mounts are workspace-wide (no fine-grained per-user/group access control), the DBFS root isn't easily covered by customer-managed encryption keys, and it bypasses Unity Catalog governance. Databricks now recommends **Unity Catalog Volumes** and **external locations** for file-based access — these provide the same functionality but with proper access control, audit logging, and lineage.

---

## Q4. ⭐ What's the difference between an All-Purpose Cluster, a Job Cluster, and a SQL Warehouse?

**Answer:**
- **All-Purpose Cluster**: long-running, shared, used for interactive notebook development. Most expensive if left idle — should always have autotermination configured.
- **Job Cluster**: ephemeral — created automatically when a scheduled Job starts, terminated when it finishes. Cheaper DBU rate than all-purpose, and provides workload isolation (one job's cluster failure doesn't affect others).
- **SQL Warehouse**: purpose-built compute for Databricks SQL/BI workloads, leverages Photon, available in Classic/Pro/Serverless flavors with auto-stop and fast auto-resume.

As a DataOps engineer, production pipelines should almost always run on **Job Clusters**, not all-purpose clusters — cheaper and isolates blast radius.

---

## Q5. What is a DBU and how does Databricks pricing work?

**Answer:**
A DBU (Databricks Unit) is a normalized unit of processing capacity billed per hour on top of the underlying cloud infrastructure cost. Total spend = cloud VM/storage cost + DBU cost, and the DBU rate itself varies by workload type (Jobs cheaper than All-Purpose), tier (Standard/Premium/Enterprise), and whether Photon is enabled (higher DBU rate but often net-cheaper due to speed). Cost control levers include job clusters, autoscaling, autotermination, spot instances, and pools.

---

## Q6. ⭐ Walk me through the Medallion Architecture and why you'd use it.

**Answer:**
Medallion architecture organizes data into three progressively refined layers within the Lakehouse:
- **Bronze**: raw, ingested as-is (append-only), preserves full history/audit trail, minimal transformation.
- **Silver**: cleansed, deduplicated, conformed schema, validated, joined/enriched — closer to "business entity" shape.
- **Gold**: aggregated, denormalized, business-level tables (often star schema) optimized for BI/reporting consumption.

This gives incremental, testable, replayable transformations — if a bug is found in Silver logic, you can reprocess from immutable Bronze without re-ingesting from source. It also lets different consumers plug in at the layer appropriate for their need (data scientists might want Silver, analysts want Gold).

---

## Q7. Who are the primary personas that use Databricks, and how does a DataOps Engineer's role differ from a Data Engineer's?

**Answer:**
Personas: Data Engineers (build pipelines), Data Analysts (SQL/BI via Databricks SQL & Genie), Data Scientists/ML Engineers (MLflow, Feature Store, notebooks), and Platform Admins (account/workspace administration). A **DataOps Engineer** overlaps heavily with Data Engineering but applies a DevOps lens specifically: CI/CD for pipelines (Asset Bundles, Repos), infrastructure as code (Terraform), automated testing/data quality gates, observability (system tables, alerting), and reliable, repeatable deployment of jobs/DLT pipelines across dev/staging/prod — treating data pipelines with the same rigor as software releases.

---

## Q8. How does Databricks differ from running Apache Spark yourself on EMR or bare VMs?

**Answer:**
Databricks provides a managed, optimized runtime (DBR) with performance improvements like Photon and Adaptive Query Execution tuned beyond open-source Spark defaults, collaborative notebooks, built-in job scheduling/orchestration, Unity Catalog governance, and automated cluster lifecycle management (autoscaling, autotermination, pools). Self-managed Spark (EMR/bare VMs) gives full control and potentially lower raw infra cost, but shifts all operational burden — cluster tuning, upgrades, security patching, and building your own orchestration/governance layers — onto your team.
