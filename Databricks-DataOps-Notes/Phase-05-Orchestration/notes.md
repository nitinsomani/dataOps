# Phase 5: Orchestration — Jobs, Workflows & Delta Live Tables — Detailed Notes

> **Goal**: Know how to reliably schedule, chain, and monitor production pipelines — the core "Ops" of DataOps.

---

## 1. Databricks Jobs — The Scheduling Primitive

A **Job** is the fundamental unit of scheduled/triggered execution on Databricks. A Job can run a notebook, a Python script/wheel, a JAR, a SQL file, or a **DLT pipeline**.

### Key Job Concepts
- **Tasks**: a Job is composed of one or more **tasks**, each with its own compute (job cluster or cluster pool), retry policy, and dependency (`depends_on`) relationships — forming a **DAG of tasks** (multi-task Workflows).
- **Triggers**: cron-based schedule, file arrival trigger, continuous, or manual/API-triggered (`run-now`).
- **Parameters/Widgets**: pass runtime parameters into notebooks via job parameters (`dbutils.widgets.get`).
- **Retries**: configurable per-task retry count and interval — critical for resilience against transient failures (e.g., a flaky upstream API).
- **Task values**: pass small values between tasks (`dbutils.jobs.taskValues.set/get`) — e.g., task A computes a row count, task B uses it for a conditional branch.
- **Conditional execution**: `If/else` condition tasks — run a task only if a condition (e.g., a task value) is met.
- **Job clusters vs shared clusters**: each task can use a dedicated ephemeral job cluster, or multiple tasks can share one cluster for efficiency (avoiding repeated cluster startup cost) — a trade-off between isolation and cost/speed.

```
Workflow DAG example:
  ingest_bronze → [validate_silver, enrich_reference_data] → build_gold → notify_success
                         (parallel tasks)                                  (on success/failure)
```

---

## 2. Delta Live Tables (DLT) — Declarative Pipelines

DLT is a **declarative framework** for building ETL pipelines: instead of imperatively writing "read this, write that," you declare the tables you want and the transformations that produce them, and DLT figures out execution order, manages infrastructure, and handles operational concerns automatically.

```python
import dlt
from pyspark.sql.functions import col

@dlt.table(comment="Raw bronze orders")
def bronze_orders():
    return (spark.readStream.format("cloudFiles")
            .option("cloudFiles.format", "json")
            .load("/mnt/raw/orders"))

@dlt.table(comment="Cleaned silver orders")
@dlt.expect_or_drop("valid_amount", "amount > 0")
@dlt.expect("has_customer", "customer_id IS NOT NULL")
def silver_orders():
    return (dlt.read_stream("bronze_orders")
            .dropDuplicates(["order_id"])
            .withColumn("amount", col("amount").cast("decimal(10,2)")))

@dlt.table(comment="Aggregated gold sales")
def gold_sales_by_region():
    return (dlt.read("silver_orders")
            .groupBy("region")
            .agg({"amount": "sum"}))
```

### DLT Expectations — Built-in Data Quality
```
@dlt.expect("name", "condition")            → track violations, keep the row (metrics only)
@dlt.expect_or_drop("name", "condition")     → drop rows violating the condition
@dlt.expect_or_fail("name", "condition")     → fail the entire pipeline run on violation
```
- Expectations are automatically tracked and surfaced in the pipeline's event log/metrics UI — no need to build custom quality-check plumbing.

### DLT Pipeline Modes
- **Triggered**: runs once, processes available data, then stops (like `availableNow`).
- **Continuous**: keeps running, processing new data as it arrives with low latency.
- **Development vs Production mode**: development mode reuses clusters across runs and disables retries for faster iteration; production mode enables full retries and creates fresh clusters for reliability.

### DLT and Auto-managed Infrastructure
- DLT automatically manages the underlying cluster, retries failed flows, orders table dependencies from the declared DAG, and tracks data quality/lineage — significantly less operational code than hand-rolled multi-task Jobs for classic medallion pipelines.
- Supports **SCD Type 1 and Type 2** natively via `dlt.apply_changes()` (a managed MERGE-equivalent for CDC application).

```python
dlt.apply_changes(
    target="silver_customers",
    source="cdc_customers",
    keys=["customer_id"],
    sequence_by="updated_at",
    apply_as_deletes="operation = 'DELETE'",
    stored_as_scd_type="2"
)
```

---

## 3. Jobs vs DLT — When to Use Which

| Scenario | Prefer |
|----------|--------|
| Simple medallion ETL with quality checks, clear DAG of transformations | **DLT** |
| Orchestrating heterogeneous tasks (notebook → dbt run → ML training → notification) | **Jobs/Workflows** |
| Need fine-grained imperative control over cluster/session behavior | **Jobs** with notebook tasks |
| Want built-in data quality, lineage, and auto-managed infra with minimal code | **DLT** |
| Mixing DLT pipelines with other steps (e.g., run DLT pipeline, then trigger ML retraining) | **Workflows orchestrating a DLT task alongside other task types** |

In practice, production systems often **combine both**: a Workflow with a DLT pipeline task for the medallion transformation, plus surrounding tasks for validation, notification, and downstream triggers.

---

## 4. Workflow Reliability Patterns

- **Retries with backoff**: configure `min_retry_interval_millis` and `max_retries` per task to handle transient failures (network blips, throttling).
- **Timeouts**: set task/job-level timeouts to prevent runaway jobs from consuming compute indefinitely.
- **Alerts/Notifications**: configure email/webhook/Slack notifications on job start, success, failure, or duration threshold exceeded.
- **Idempotent design** (see Phase 4): retries must be safe — a retried task shouldn't double-process data.
- **Repair Run**: Databricks Jobs supports re-running only the *failed* tasks in a multi-task Workflow rather than the entire DAG from scratch — saves time/cost on partial failures.

---

## 5. Parameterization & Environments

```python
# In a notebook
run_date = dbutils.widgets.get("run_date")
```
```json
// Job task parameters (JSON)
{"run_date": "{{job.start_time.iso_date}}"}
```
- Use **dynamic value references** (job/task context variables like `{{job.start_time}}`, `{{job.id}}`) to avoid hardcoding.
- Separate **dev/staging/prod** job definitions via parameters and target workspaces — this ties directly into CI/CD with Databricks Asset Bundles (Phase 10).

---

## 6. Monitoring Job Runs

- **Run history UI**: per-run status, duration, task-level drill-down, logs, and Spark UI links.
- **System tables** (`system.lakeflow.job_run_timeline`, `system.lakeflow.jobs`, etc.) — SQL-queryable job run metadata for building custom dashboards/alerting (deep dive in Phase 11).
- **REST API** (`/api/2.1/jobs/runs/get`) — programmatic status checks, useful for external orchestrators (Airflow) triggering Databricks Jobs and polling completion.

---

## 7. External Orchestration (Airflow, ADF, Dagster)

Many organizations orchestrate Databricks Jobs from an external tool rather than using native Workflows alone:
- **Apache Airflow**: `DatabricksSubmitRunOperator` / `DatabricksRunNowOperator` trigger and poll Databricks Jobs, useful when Databricks is one piece of a broader multi-system pipeline (e.g., also touching Snowflake, S3 events, other services).
- **Azure Data Factory (ADF)**: native Databricks activity types (notebook, jar, python).
- Trade-off: native Databricks Workflows are simpler and tightly integrated (lineage, cost visibility) for Databricks-only pipelines; external orchestrators make sense when Databricks is one node in a larger enterprise DAG spanning many systems.

---

## 8. Key Takeaways for DataOps

- Multi-task Workflows give you DAG-based orchestration, retries, conditional branching, and parameterization natively — no separate orchestrator required for Databricks-only pipelines.
- DLT trades some imperative control for **automatic dependency resolution, built-in data quality (expectations), and managed infrastructure** — huge productivity win for standard medallion pipelines.
- `apply_changes()` (DLT) is the declarative equivalent of hand-written CDC MERGE logic — know when to reach for it.
- Idempotency + retries + repair-run + alerting = the operational reliability toolkit expected of a DataOps engineer.
