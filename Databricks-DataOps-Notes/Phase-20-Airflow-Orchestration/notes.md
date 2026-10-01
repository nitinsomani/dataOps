# Phase 20: Apache Airflow & External Orchestration — Detailed Notes

> **Goal**: Many product companies orchestrate Databricks *from* Airflow rather than relying solely on native Databricks Workflows, especially when Databricks is one piece of a larger multi-system pipeline. This phase covers Airflow deeply enough to be functional in that environment.

---

## 1. Why Airflow Coexists with Databricks Workflows

Recap from Phase 5: native Workflows are simpler for Databricks-only pipelines. Airflow becomes the better choice when a pipeline needs to coordinate **many heterogeneous systems** — e.g., trigger a Databricks job, then load results into Snowflake, then call a REST API, then send a Slack notification, with complex cross-system dependencies — under one unified scheduling/monitoring plane. Many product companies standardize on Airflow as their company-wide orchestrator regardless of which specific compute engines (Databricks, EMR, Snowflake, dbt) sit underneath.

---

## 2. Core Airflow Concepts

```python
from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime, timedelta

default_args = {
    "owner": "data-eng",
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    dag_id="sales_pipeline",
    schedule="0 2 * * *",          # cron: daily at 2 AM
    start_date=datetime(2026, 1, 1),
    catchup=False,
    default_args=default_args,
) as dag:

    def extract():
        print("extracting...")

    extract_task = PythonOperator(task_id="extract", python_callable=extract)
```

- **DAG (Directed Acyclic Graph)**: the pipeline definition itself — a Python file describing tasks and their dependencies. No cycles allowed (a task can't depend on itself, directly or transitively).
- **Operator**: a template for a single task's work (`PythonOperator`, `BashOperator`, `DatabricksSubmitRunOperator`, etc.) — Airflow ships many pre-built operators for common integrations.
- **Task**: an instantiated operator within a specific DAG — the actual unit of execution.
- **Task Instance**: one specific run of a task for a specific `execution_date`/DAG run.
- **Scheduler**: the Airflow component that parses DAGs and decides when tasks should run based on schedule and dependency state.
- **Executor**: determines *how* tasks actually run (LocalExecutor, CeleryExecutor, KubernetesExecutor) — a scaling/infrastructure concern separate from DAG authoring.

---

## 3. Task Dependencies

```python
extract_task >> transform_task >> load_task     # sequential
extract_task >> [transform_a, transform_b] >> load_task   # fan-out then fan-in

# Alternative explicit syntax
transform_task.set_upstream(extract_task)
load_task.set_downstream(transform_task)
```
- `>>` and `<<` define dependency direction — the DAG's actual execution graph, distinct from the order tasks are written in the Python file.
- Airflow DAG files are **parsed repeatedly** by the scheduler (not run top-to-bottom like a script) — this is why DAG-defining Python code should be fast and side-effect-free; slow imports/API calls at DAG-definition time slow down the entire scheduler.

---

## 4. Databricks-Specific Airflow Operators

```python
from airflow.providers.databricks.operators.databricks import (
    DatabricksSubmitRunOperator, DatabricksRunNowOperator
)

# Submit a new, one-off cluster + job spec
submit_task = DatabricksSubmitRunOperator(
    task_id="run_databricks_job",
    databricks_conn_id="databricks_default",
    new_cluster={"spark_version": "15.4.x-scala2.12", "num_workers": 2, "node_type_id": "i3.xlarge"},
    notebook_task={"notebook_path": "/Repos/prod/pipeline/etl_notebook"},
)

# Trigger an EXISTING Databricks Job (defined via Asset Bundle/UI) by job ID
run_now_task = DatabricksRunNowOperator(
    task_id="trigger_existing_job",
    databricks_conn_id="databricks_default",
    job_id=123456,
)
```

- **`DatabricksSubmitRunOperator`**: submits an ad hoc run with a fully-specified cluster + task — Airflow owns the job definition entirely.
- **`DatabricksRunNowOperator`**: triggers a job that already exists in Databricks (created via UI, Asset Bundle, or Terraform) by ID — Airflow just triggers/monitors, Databricks owns the job definition. **This is generally the preferred pattern** for DataOps: job definitions live in version-controlled Asset Bundles (Phase 10), Airflow just orchestrates *when* they run relative to other systems.
- Both operators **poll** the Databricks Jobs API for run completion status, surfacing failure/success back into the Airflow DAG's dependency graph.
- **`databricks_conn_id`**: an Airflow Connection storing the Databricks workspace host + auth (ideally a service principal token, tying back to Phase 7) — managed via Airflow's Connections UI or environment variables, not hardcoded in the DAG.

---

## 5. Sensors — Waiting for External Conditions

```python
from airflow.sensors.filesystem import FileSensor
from airflow.providers.amazon.aws.sensors.s3 import S3KeySensor

wait_for_file = FileSensor(task_id="wait_for_file", filepath="/data/incoming/orders.csv", poke_interval=60)

wait_for_s3 = S3KeySensor(
    task_id="wait_for_s3_file",
    bucket_name="my-bucket",
    bucket_key="raw/orders/{{ ds }}/data.parquet",
    poke_interval=300, timeout=3600,
)
```
- A **Sensor** is a special task type that waits/polls for a condition (file arrival, S3 key existence, external API status) before allowing downstream tasks to proceed — critical for pipelines that depend on upstream systems with unpredictable/variable delivery timing.
- **Deferrable/smart sensors**: newer Airflow versions support "deferred" mode where a sensor releases its worker slot while waiting (instead of holding a slot for the entire poll duration) — a significant efficiency improvement for pipelines with many long-waiting sensors.

---

## 6. XComs — Passing Data Between Tasks

```python
def extract(**context):
    row_count = 1500
    context["ti"].xcom_push(key="row_count", value=row_count)

def validate(**context):
    row_count = context["ti"].xcom_pull(task_ids="extract", key="row_count")
    assert row_count > 0
```
- **XCom (cross-communication)** lets tasks pass small pieces of data to each other — conceptually similar to Databricks' `taskValues` (Phase 5). Meant for small metadata (counts, flags, file paths), **not** large datasets — XComs are stored in Airflow's metadata database, and large payloads will degrade scheduler performance.

---

## 7. Templating with Jinja

```python
notebook_task={"notebook_path": "/Repos/prod/pipeline/etl_notebook",
               "base_parameters": {"run_date": "{{ ds }}"}}
```
- Airflow uses **Jinja templating** for dynamic values — `{{ ds }}` (execution date as `YYYY-MM-DD`), `{{ ts }}` (full timestamp), `{{ dag_run.conf }}` (manually triggered run parameters) — allowing the same DAG definition to parameterize each run correctly without hardcoding dates.

---

## 8. Idempotency & Backfills

- **`catchup=False`**: prevents Airflow from automatically running every missed scheduled interval between `start_date` and now when a DAG is first deployed/paused-then-unpaused — almost always what you want for production DAGs to avoid an unexpected backfill storm.
- **Backfilling**: intentionally re-running a DAG for past dates (`airflow dags backfill`) — requires the DAG's tasks to be **idempotent** (ties directly to Phase 4/10 principles) since backfilled runs will re-execute logic for dates already processed.
- **`execution_date` semantics**: historically confusing — a DAG scheduled to run "daily" has its `execution_date` set to the *start* of the interval being processed, not the actual run time (e.g., the DAG run that executes on Jan 2nd has `execution_date` of Jan 1st, representing "processing Jan 1st's data"). Newer Airflow versions use `logical_date` terminology to reduce this confusion.

---

## 9. Monitoring & Alerting

```python
default_args = {
    "on_failure_callback": lambda context: send_slack_alert(context),
    "sla": timedelta(hours=2),
}
```
- **SLA misses**: Airflow can alert if a task/DAG takes longer than an expected SLA, independent of outright failure.
- **`on_failure_callback`/`on_success_callback`**: hook custom alerting (Slack, PagerDuty) directly into task lifecycle events.
- Airflow's web UI (Grid view, Graph view) is the primary operational dashboard — analogous to Databricks' Workflow run history UI, but spanning all orchestrated systems, not just Databricks.

---

## 10. Airflow vs Databricks Workflows — Decision Recap (from Phase 5, expanded)

| Factor | Favor Airflow | Favor Databricks Workflows |
|--------|----------------|------------------------------|
| Scope | Multi-system (Databricks + Snowflake + APIs + …) | Databricks-only pipeline |
| Team ownership | Central platform team owns one orchestrator for the whole company | Data engineering team wants full self-service without a separate system |
| Existing investment | Company already standardized on Airflow | Greenfield, Databricks-first org |
| Failure/backfill tooling | Mature backfill/catchup semantics | Simpler Repair Run, less granular backfill tooling |

---

## 11. Key Takeaways for DataOps

- `DatabricksRunNowOperator` triggering Asset-Bundle-defined jobs is the cleanest separation of concerns: Airflow orchestrates timing/cross-system dependencies, Databricks Asset Bundles own the actual job definition (Phase 10).
- Sensors + XComs are Airflow's equivalents to Auto Loader's file-notification triggering and Databricks' taskValues, respectively — good bridge concepts to mention in interviews.
- `catchup=False` and idempotent task design are non-negotiable production defaults — the same discipline as Phase 4/10, just in a different orchestrator.
- Know when to recommend Airflow vs native Workflows — it's a judgment/tradeoff question, not a "which is objectively better" question.
