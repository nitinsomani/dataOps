# Phase 5: Orchestration — Jobs, Workflows & DLT — Cheat Sheet

---

## Jobs / Workflows Building Blocks

```
Job → 1+ Tasks (DAG via depends_on) → each task: notebook/JAR/wheel/SQL/DLT pipeline
Triggers: cron | file arrival | continuous | manual/API (run-now)
Retries: per-task max_retries, min_retry_interval_millis
Task values: dbutils.jobs.taskValues.set()/get() — pass data between tasks
Repair Run: re-run only failed tasks, not the whole DAG
```

## DLT Skeleton

```python
import dlt
from pyspark.sql.functions import col

@dlt.table
def bronze_x():
    return spark.readStream.format("cloudFiles").option("cloudFiles.format","json").load("/path")

@dlt.table
@dlt.expect_or_drop("valid", "amount > 0")
def silver_x():
    return dlt.read_stream("bronze_x").dropDuplicates(["id"])

@dlt.table
def gold_x():
    return dlt.read("silver_x").groupBy("region").sum("amount")
```

## DLT Expectations

```
@dlt.expect("name","cond")            track only, keep row
@dlt.expect_or_drop("name","cond")    drop violating rows
@dlt.expect_or_fail("name","cond")    fail whole pipeline
```

## DLT `apply_changes` (CDC / SCD)

```python
dlt.apply_changes(
    target="silver_customers", source="cdc_customers",
    keys=["customer_id"], sequence_by="updated_at",
    apply_as_deletes="operation = 'DELETE'",
    stored_as_scd_type="2"   # or "1"
)
```

## Jobs vs DLT Decision Table

| Need | Use |
|------|-----|
| Heterogeneous multi-system DAG | Jobs/Workflows |
| Standard medallion ETL + quality checks | DLT |
| Fine-grained imperative cluster control | Jobs (notebook task) |
| Auto lineage + managed infra | DLT |

## DLT Pipeline Modes

```
Triggered   → run once on available data, then stop
Continuous  → always running, low latency
Development → shared cluster, no retries, fast iteration
Production  → fresh clusters, full retries, reliability first
```

## Reliability Checklist

```
[ ] Retries configured with backoff
[ ] Timeouts set per task/job
[ ] Alerts on failure/duration threshold
[ ] Idempotent tasks (safe to retry)
[ ] Repair Run used instead of full re-run on partial failure
```

## Monitoring Sources

```
Run history UI            → per-run/task status, logs, Spark UI link
system.lakeflow.* tables  → SQL-queryable job run metadata
REST API /api/2.1/jobs/*  → programmatic polling (external orchestrators)
```
