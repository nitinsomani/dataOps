# Phase 20: Apache Airflow & External Orchestration — Cheat Sheet

---

## Core Concepts

```
DAG        → pipeline definition (Python file, tasks + dependencies, no cycles)
Operator   → template for a task's work (PythonOperator, BashOperator, DatabricksRunNowOperator)
Task        → instantiated operator within a DAG
Task Instance → one run of a task for a specific execution date
Scheduler    → parses DAGs, decides when tasks run
Executor      → HOW tasks run (Local/Celery/KubernetesExecutor)
```

## Dependency Syntax

```python
a >> b >> c                  # sequential
a >> [b, c] >> d              # fan-out then fan-in
b.set_upstream(a)              # explicit alternative
```

## Databricks Operators

```python
DatabricksSubmitRunOperator   # ad hoc cluster + job spec, Airflow owns definition
DatabricksRunNowOperator      # triggers EXISTING job by ID — PREFERRED (job lives in Asset Bundle)
```

## Sensors

```python
FileSensor(filepath=..., poke_interval=60)
S3KeySensor(bucket_name=..., bucket_key=..., poke_interval=300, timeout=3600)
```
Deferrable sensors release worker slot while waiting — use for long-waiting sensors.

## XComs (task-to-task small data)

```python
context["ti"].xcom_push(key="k", value=v)
context["ti"].xcom_pull(task_ids="upstream_task", key="k")
```
Small metadata only — NOT large datasets (stored in metadata DB).

## Jinja Templating

```
{{ ds }}          → execution date YYYY-MM-DD
{{ ts }}           → full timestamp
{{ dag_run.conf }}  → manually-triggered run parameters
```

## Idempotency & Backfill

```
catchup=False          → don't auto-run every missed interval on deploy (almost always wanted)
airflow dags backfill    → intentional re-run for past dates — requires idempotent tasks
execution_date/logical_date → represents START of interval being processed, not actual run time
```

## Monitoring

```python
default_args = {
  "on_failure_callback": alert_fn,
  "sla": timedelta(hours=2),
}
```

## Airflow vs Databricks Workflows

| Favor Airflow | Favor Workflows |
|----------------|-------------------|
| Multi-system pipeline | Databricks-only |
| Company-wide orchestrator standard | Greenfield Databricks-first |
| Mature backfill tooling needed | Simpler Repair Run sufficient |
