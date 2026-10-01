# Phase 5: Orchestration — Jobs, Workflows & DLT — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ What is a Databricks Job/Workflow and how does it differ from a single notebook run?

**Answer:**
A Job is a scheduled or triggered unit of orchestration composed of one or more **tasks**, each with its own compute, retry policy, and dependency relationships forming a DAG (a "multi-task Workflow"). Unlike manually running a single notebook, Jobs give you scheduling (cron/file-arrival triggers), automatic ephemeral job-cluster provisioning/teardown, retries with backoff, parameterization, conditional branching, task-to-task value passing, and failure notifications — the full operational scaffolding needed for production pipelines.

---

## Q2. ⭐ What is Delta Live Tables and how is it different from writing your own Spark job in a notebook?

**Answer:**
DLT is a declarative pipeline framework — you define the target tables and the transformation logic that produces them (`@dlt.table` decorated functions), and DLT automatically infers the dependency DAG between tables, manages cluster provisioning/scaling, handles retries, and tracks built-in data quality metrics via **expectations** (`@dlt.expect`, `@dlt.expect_or_drop`, `@dlt.expect_or_fail`). A hand-written notebook/Job requires you to manually sequence steps, handle checkpointing, build your own data quality checks, and manage cluster lifecycle — DLT abstracts all of that away for the common medallion ETL pattern, at the cost of less granular imperative control.

---

## Q3. Explain the three DLT expectation types and give a scenario for each.

**Answer:**
- `@dlt.expect("name", "condition")`: only tracks/reports violations as metrics but keeps all rows — use when you want visibility into data quality trends without blocking the pipeline (e.g., monitoring what % of rows have a null optional field).
- `@dlt.expect_or_drop("name", "condition")`: silently drops rows violating the condition — use for known-bad data you want to exclude from downstream layers without failing the whole run (e.g., dropping rows with negative amounts).
- `@dlt.expect_or_fail("name", "condition")`: fails the entire pipeline run if any row violates the condition — use for critical invariants where continuing to process would be worse than stopping (e.g., a primary key must never be null).

---

## Q4. ⭐ How would you implement SCD Type 2 (historical dimension tracking) using DLT?

**Answer:**
Use `dlt.apply_changes()` with `stored_as_scd_type="2"`, providing the target table, the CDC source table, the natural `keys` to match rows on, and a `sequence_by` column (typically an `updated_at`/event timestamp) to determine ordering of changes for out-of-order arrival. DLT automatically manages the "close out old record, insert new current record" pattern that SCD Type 2 requires — adding effective-dated/`__START_AT`/`__END_AT` tracking columns — without you having to hand-write the MERGE logic. `apply_as_deletes` handles source records flagged as deletes (soft-deleting/closing the corresponding target row rather than physically deleting history).

---

## Q5. When would you choose a native Databricks Workflow over an external orchestrator like Airflow, and vice versa?

**Answer:**
Native Workflows make sense when the entire pipeline lives within Databricks — you get tight integration (lineage, cost attribution per job, unified monitoring/alerting, no extra infrastructure to maintain) and simpler parameterization via job/task context variables. An external orchestrator like Airflow is preferable when Databricks is just one node in a broader enterprise DAG spanning multiple systems (e.g., triggering a Databricks job, then loading results into Snowflake, then kicking off a separate reporting system, with dependencies across all of them) — Airflow (via `DatabricksRunNowOperator`/`DatabricksSubmitRunOperator`) gives a single pane of glass across heterogeneous systems, at the cost of extra operational overhead of running/maintaining Airflow itself.

---

## Q6. How do you make a multi-task Workflow resilient to transient failures without wasting compute on full re-runs?

**Answer:**
Configure per-task retries with a backoff interval (`max_retries`, `min_retry_interval_millis`) to absorb transient issues (network blips, momentary throttling) automatically. Set task/job timeouts to bound worst-case runaway execution. For a Workflow with multiple tasks where only some fail, use **Repair Run** to re-execute just the failed tasks and their downstream dependents rather than restarting the entire DAG — saving significant compute time/cost, especially for long-running upstream tasks that already succeeded. Underpinning all of this, every task must be idempotent so retries/repairs never produce duplicate or corrupted data.

---

## Q7. How do you pass data between tasks in a Databricks Workflow, and what are the limitations?

**Answer:**
`dbutils.jobs.taskValues.set(key, value)` in an upstream task and `dbutils.jobs.taskValues.get(taskKey, key)` in a downstream task lets you pass small values (e.g., a row count, a computed flag, a file path) between tasks in the same job run. This is meant for lightweight coordination data, not for passing large datasets — actual data should flow through Delta tables/files, with task values only carrying metadata used for conditional logic (e.g., an "if row_count == 0, skip downstream task" branch) or parameterizing a subsequent task.

---

## Q8. What's the difference between DLT's "development" and "production" pipeline modes?

**Answer:**
Development mode reuses the same cluster across pipeline updates and disables automatic retries — optimized for fast iterative development where you're actively debugging and want quick feedback without waiting for fresh cluster spin-up each time. Production mode spins up fresh clusters for each run and enables full automatic retries on failure — optimized for reliability and isolation in a real production schedule, at the cost of slightly longer startup latency per run. You'd flip a pipeline from development to production mode as part of promoting it through your CI/CD environments (dev → staging → prod).
