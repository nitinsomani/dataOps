# Databricks DataOps Engineer — Master Cheat Sheet & Roadmap

> **Goal**: Complete preparation for **DataOps Engineer / Data Platform Engineer (Databricks)** roles at product-based companies.
> **Structure**: Each phase has 4 files — `notes.md`, `cheat-sheet.md`, `interview-qa.md`, `lab-exercises.md`
> **Total**: 23 phases × 4 files = **92 files** (Phases 16-23 cover general interview rounds and adjacent tooling beyond Databricks itself: AWS system design, SQL, Python, data modeling, Airflow, Linux/Git, dbt, OpenTelemetry/observability)

---

## Progress Tracker

| # | Phase | Key Topics |
|---|-------|-----------|
| 01 | **Databricks & Lakehouse Fundamentals** | Lakehouse architecture, DBFS, Workspace, Control/Data plane, Clusters |
| 02 | **Apache Spark Core & PySpark** | RDD/DataFrame, Catalyst/Tungsten, Shuffle, Joins, Partitioning |
| 03 | **Delta Lake Deep Dive** | ACID, Transaction log, Time travel, MERGE, OPTIMIZE, Z-Order, Vacuum |
| 04 | **Ingestion & ETL/ELT** | Auto Loader, COPY INTO, Medallion architecture, Batch vs Streaming |
| 05 | **Orchestration** | Jobs, Multi-task workflows, DLT pipelines, Triggers, Retries |
| 06 | **Unity Catalog & Governance** | 3-level namespace, Data lineage, Access control, Sharing |
| 07 | **Security & Networking** | IAM, Secrets, VPC/VNet injection, PrivateLink, Encryption |
| 08 | **Performance Tuning** | AQE, Skew handling, Caching, File sizing, Photon |
| 09 | **Cluster Mgmt & Compute** | Cluster types, Autoscaling, Pools, Init scripts, SQL Warehouses |
| 10 | **CI/CD & DataOps Automation** | Repos, Databricks Asset Bundles, Terraform, GitHub Actions |
| 11 | **Data Quality & Observability** | Expectations, Great Expectations, System tables, Alerts |
| 12 | **Streaming & Real-Time** | Structured Streaming, Kafka, Checkpointing, Watermarking |
| 13 | **MLOps & MLflow** | Experiment tracking, Model registry, Feature Store, Serving |
| 14 | **Advanced Topics** | Multi-cloud, DR/BCP, Lakehouse Federation, Delta Sharing |
| 15 | **Interview Preparation** | Scenarios, System design, Mock interviews, Study plan |
| 16 | **System Design (AWS)** | S3, Glue, EMR, Kinesis, Redshift, Step Functions, Databricks-vs-native tradeoffs |
| 17 | **SQL for Interviews** | Window functions, CTEs, joins, gaps-and-islands, query optimization |
| 18 | **Python for Data Engineering** | OOP, decorators, generators, testing (pytest), common gotchas |
| 19 | **Data Modeling & Warehousing** | Star/snowflake schema, fact/dim design, grain, SCD Types 0-6, surrogate keys |
| 20 | **Airflow & External Orchestration** | DAGs, operators, sensors, XComs, Databricks operators, catchup/backfill |
| 21 | **Linux, Shell Scripting & Git** | bash scripting, cron, init scripts, merge vs rebase, reset vs revert |
| 22 | **dbt for Databricks** | Models, ref/source, materializations, schema tests, slim CI |
| 23 | **OpenTelemetry & Observability** | Traces/metrics/logs, OTel Collector, Prometheus/Grafana, Dynatrace, sampling |

---

## Quick Reference: The DataOps Lifecycle on Databricks

```
Source Systems → Ingestion (Auto Loader/COPY INTO) → Bronze (raw)
     → Transform (Spark/DLT) → Silver (cleansed) → Gold (aggregated/BI)
     → Orchestration (Jobs/Workflows) → Governance (Unity Catalog)
     → CI/CD (Bundles/Repos) → Monitoring (System Tables/Lakehouse Monitoring)
       Phase numbers: (4)         (2/3)         (3)        (5)         (6)          (10)             (11)
```

## Quick Reference: Medallion Architecture

```
BRONZE                  SILVER                    GOLD
─────────────────       ──────────────────       ──────────────────
Raw, as-is              Cleaned, deduped,        Aggregated, business-
Append-only              conformed schema          level, BI-ready
Full history            Validated/quality checks  Star schema/marts
Source of truth         Joined/enriched           Consumed by dashboards
```

## Quick Reference: Compute Options

```
All-Purpose Cluster   → Interactive dev/notebooks (shared, expensive if idle)
Job Cluster           → Ephemeral, spun up per job run, cheaper, isolated
SQL Warehouse         → Serverless/classic/pro, for BI & SQL queries (Photon)
Pools                 → Pre-warmed VMs to cut cluster startup latency
Serverless Compute    → Fully managed, no infra to tune, pay-per-use
```

## Quick Reference: Delta Lake Transaction Log

```
_delta_log/
  00000000000000000000.json   ← commit 0 (CREATE TABLE)
  00000000000000000001.json   ← commit 1 (INSERT)
  00000000000000000002.json   ← commit 2 (UPDATE/MERGE)
  ...
  00000000000000000010.checkpoint.parquet  ← every 10 commits by default
```

---

## Essential Commands & Snippets

```python
# === SPARK SESSION (implicit `spark` in notebooks) ===
df = spark.read.format("delta").load("/mnt/bronze/orders")
df.write.format("delta").mode("overwrite").saveAsTable("catalog.schema.table")

# === AUTO LOADER (incremental file ingestion) ===
df = (spark.readStream.format("cloudFiles")
      .option("cloudFiles.format", "json")
      .option("cloudFiles.schemaLocation", "/mnt/schema/orders")
      .load("/mnt/raw/orders"))

# === DELTA MERGE (upsert) ===
# MERGE INTO target USING source ON target.id = source.id
#   WHEN MATCHED THEN UPDATE SET *
#   WHEN NOT MATCHED THEN INSERT *

# === OPTIMIZE & Z-ORDER ===
# OPTIMIZE catalog.schema.table ZORDER BY (customer_id)
# VACUUM catalog.schema.table RETAIN 168 HOURS

# === TIME TRAVEL ===
# SELECT * FROM table VERSION AS OF 5
# SELECT * FROM table TIMESTAMP AS OF '2026-09-01'
```

```bash
# === DATABRICKS CLI ===
databricks configure --token
databricks workspace ls /Users/me@company.com
databricks jobs run-now --job-id 123
databricks fs cp local.csv dbfs:/mnt/raw/

# === DATABRICKS ASSET BUNDLES (DAB) ===
databricks bundle init
databricks bundle deploy -t dev
databricks bundle run my_job -t prod

# === UNITY CATALOG SQL ===
# GRANT SELECT ON TABLE catalog.schema.table TO `data-analysts`;
# CREATE CATALOG sales MANAGED LOCATION 's3://bucket/sales';
# SHOW GRANTS ON TABLE catalog.schema.table;
```

---

## System Design Quick Reference: Batch Pipeline

```
Source (DB/API/Files)
   ↓ Auto Loader / COPY INTO (schema inference + evolution)
Bronze (Delta, append-only, raw)
   ↓ DLT / Spark job (dedupe, cast types, quality checks)
Silver (Delta, cleansed, SCD handling via MERGE)
   ↓ Aggregations, joins, business logic
Gold (Delta, star schema, partitioned)
   ↓ Databricks SQL / Genie / BI tools (Power BI, Tableau)
Consumption
```

---

## Must-Know Terms Glossary

```
DBU     Databricks Unit — compute pricing unit
DBFS    Databricks File System — abstraction over cloud storage
UC      Unity Catalog — unified governance layer
DLT     Delta Live Tables — declarative pipeline framework
CDF     Change Data Feed — row-level change tracking on Delta tables
CDC     Change Data Capture — capturing upstream DB changes
AQE     Adaptive Query Execution — runtime Spark query optimization
Photon  Databricks' native vectorized query engine (C++)
DAB     Databricks Asset Bundles — IaC for Databricks projects
SCD     Slowly Changing Dimension
```

---

## Study Plan (Suggested Pace)

| Week | Phases | Focus |
|------|--------|-------|
| 1 | 01–02 | Fundamentals + Spark internals |
| 2 | 03–04 | Delta Lake + Ingestion patterns |
| 3 | 05–06 | Orchestration + Governance |
| 4 | 07–08 | Security + Performance tuning |
| 5 | 09–10 | Compute ops + CI/CD |
| 6 | 11–12 | Quality/Observability + Streaming |
| 7 | 13–14 | MLOps + Advanced/multi-cloud |
| 8 | 16–17 | AWS system design + SQL drills |
| 9 | 18–19 | Python fundamentals + Data modeling |
| 10 | 20–21 | Airflow + Linux/Git fundamentals |
| 11 | 22–23 | dbt + OpenTelemetry/observability (if the target role/JD mentions them) |
| 12 | 15 | Mock interviews + revision (revisit after all other phases) |

---

## Related Notes

- [Networking for DevOps notes](../master-cheat-sheet.md) — for platform/network-adjacent questions (VPC, PrivateLink, DNS) that intersect with Databricks deployments.
