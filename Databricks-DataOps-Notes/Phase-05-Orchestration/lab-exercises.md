# Phase 5: Orchestration — Jobs, Workflows & DLT — Lab Exercises

> Use the Databricks Workflows UI and a DLT pipeline for these labs.

---

## Lab 1: Build a Multi-Task Workflow

**Objective**: Create a 3-task DAG with dependencies.

1. Create three notebooks:
   - `task_ingest`: writes a small DataFrame to a Delta table `main.lab5_raw`
   - `task_validate`: reads `main.lab5_raw`, checks row count > 0, raises an exception if not
   - `task_aggregate`: reads `main.lab5_raw`, writes an aggregated table `main.lab5_agg`
2. In **Workflows** → **Create Job**, add all three as tasks: `task_ingest` → `task_validate` → `task_aggregate` (set `depends_on`).
3. Run the job (`Run now`).

### Questions to Answer
- [ ] What happens in the DAG view if `task_validate` fails — does `task_aggregate` still run?
- [ ] Use **Repair Run** after intentionally failing `task_validate` (e.g., write 0 rows) — which tasks actually re-execute?

---

## Lab 2: Parameters and Task Values

```python
# task_ingest notebook
dbutils.widgets.text("run_date", "2026-01-01")
run_date = dbutils.widgets.get("run_date")
row_count = 42  # pretend this came from an actual write
dbutils.jobs.taskValues.set(key="row_count", value=row_count)
```

```python
# task_validate notebook
prior_count = dbutils.jobs.taskValues.get(taskKey="task_ingest", key="row_count", default=0)
print(f"Row count from ingest task: {prior_count}")
assert prior_count > 0, "No rows ingested!"
```

### Questions to Answer
- [ ] Set the job parameter `run_date` using a dynamic value reference (`{{job.start_time.iso_date}}`) — what value gets substituted at runtime?
- [ ] What happens if `task_validate` requests a `taskValues.get` key that was never set?

---

## Lab 3: Build a Simple DLT Pipeline

**Objective**: Create a declarative Bronze → Silver → Gold pipeline.

```python
# dlt_pipeline notebook
import dlt
from pyspark.sql.functions import col, current_timestamp

@dlt.table(comment="Bronze raw events")
def bronze_events():
    return spark.range(0, 1000).withColumn("amount", (col("id") % 100).cast("double")) \
        .withColumn("customer_id", (col("id") % 10)) \
        .withColumn("_ingest_ts", current_timestamp())

@dlt.table(comment="Silver cleaned events")
@dlt.expect_or_drop("valid_amount", "amount >= 0")
@dlt.expect("has_customer", "customer_id IS NOT NULL")
def silver_events():
    return dlt.read("bronze_events").dropDuplicates(["id"])

@dlt.table(comment="Gold aggregated totals")
def gold_customer_totals():
    return dlt.read("silver_events").groupBy("customer_id").sum("amount")
```

Create a **DLT Pipeline** referencing this notebook, run it, and inspect the pipeline graph UI.

### Questions to Answer
- [ ] What does the pipeline DAG visualization show for table dependencies?
- [ ] Open the "Data Quality" metrics for `silver_events` — how many rows passed/failed each expectation?
- [ ] Switch the pipeline to Development mode and re-run — is the run noticeably faster on the second execution?

---

## Lab 4: Simulate CDC with `apply_changes`

```python
import dlt

@dlt.view
def cdc_customers():
    return spark.createDataFrame([
        (1, "Alice", "alice@x.com", "UPSERT", "2026-01-01T00:00:00"),
        (1, "Alice", "alice@newdomain.com", "UPSERT", "2026-02-01T00:00:00"),
        (2, "Bob", "bob@x.com", "UPSERT", "2026-01-15T00:00:00"),
    ], ["customer_id", "name", "email", "operation", "updated_at"])

dlt.create_streaming_table("silver_customers")

dlt.apply_changes(
    target="silver_customers",
    source="cdc_customers",
    keys=["customer_id"],
    sequence_by="updated_at",
    apply_as_deletes="operation = 'DELETE'",
    stored_as_scd_type="2"
)
```

### Questions to Answer
- [ ] After running the pipeline, query `silver_customers` — how many historical rows exist for `customer_id = 1`?
- [ ] What columns did DLT add to track the SCD Type 2 validity window?

---

## Lab 5: Alerts and Monitoring

1. In the Job you built in Lab 1, go to **Notifications** and add an email/webhook alert on failure.
2. Query the system tables (if enabled in your workspace):

```sql
SELECT * FROM system.lakeflow.job_run_timeline
WHERE job_id = <your_job_id>
ORDER BY period_start_time DESC
LIMIT 20;
```

### Questions to Answer
- [ ] What fields does the system table expose that aren't visible in the run history UI at a glance?
- [ ] How would you build a dashboard alerting on jobs whose duration exceeds a threshold, using this table?
