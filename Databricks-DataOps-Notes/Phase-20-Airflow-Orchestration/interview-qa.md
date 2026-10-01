# Phase 20: Apache Airflow & External Orchestration — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ When would you recommend orchestrating Databricks pipelines with Airflow instead of native Databricks Workflows?

**Answer:**
When the pipeline needs to coordinate multiple heterogeneous systems beyond Databricks itself — e.g., triggering a Databricks job, then loading results into Snowflake, calling a third-party API, and sending notifications, all with cross-system dependencies — a single orchestrator with visibility across all of them is valuable, and Airflow (or a similar general-purpose orchestrator) fills that role better than a Databricks-specific tool. It's also the right choice when an organization has already standardized on Airflow as its company-wide orchestration platform, since introducing a second, Databricks-only orchestrator fragments operational visibility and on-call tooling. For pipelines that are entirely Databricks-centric with no external system dependencies, native Workflows are simpler and avoid the operational overhead of running/maintaining Airflow infrastructure.

---

## Q2. ⭐ What's the difference between `DatabricksSubmitRunOperator` and `DatabricksRunNowOperator`, and which do you prefer for production pipelines?

**Answer:**
`DatabricksSubmitRunOperator` submits a fully ad hoc run — the cluster spec and task definition live entirely in the Airflow DAG code itself, with no persistent Databricks Job object created beforehand. `DatabricksRunNowOperator` instead triggers an *existing* Databricks Job (identified by job ID) that was already defined separately — via the UI, Terraform, or a Databricks Asset Bundle. I prefer `DatabricksRunNowOperator` for production: it keeps the job definition (cluster config, task DAG, retries) version-controlled and deployed through the normal Databricks CI/CD pipeline (Phase 10), while Airflow's responsibility narrows to just *scheduling and cross-system dependency management* — a cleaner separation of concerns than embedding Databricks-specific infrastructure details inside Airflow DAG code.

---

## Q3. What is a Sensor in Airflow, and what's the operational risk of using too many of them without deferrable mode?

**Answer:**
A Sensor is a special task that polls for an external condition (a file's arrival, an S3 key's existence, an API returning a certain status) at a configured interval, blocking downstream tasks until the condition is met or a timeout is reached. The operational risk with traditional (non-deferrable) sensors is that each one occupies a worker slot for its *entire* waiting duration, even though it's mostly idle between polls — with many long-running sensors across many DAGs, this can exhaust the executor's available worker capacity and starve other, genuinely ready-to-run tasks. Newer Airflow versions address this with **deferrable/smart sensors**, which release the worker slot while waiting and only reclaim one when the condition is actually met — a significant efficiency improvement worth mentioning if asked about scaling Airflow to many pipelines.

---

## Q4. ⭐ Explain XComs and how they compare to Databricks' task values.

**Answer:**
XComs (cross-communications) let one Airflow task push a small piece of data (`xcom_push`) that a downstream task can retrieve (`xcom_pull`) — conceptually identical to Databricks Workflows' `dbutils.jobs.taskValues.set()`/`get()` (Phase 5). Both are meant for small metadata — row counts, computed flags, file paths used for conditional branching — not for passing actual datasets between tasks, since XComs are persisted in Airflow's metadata database and large payloads degrade scheduler/database performance. If a downstream task genuinely needs the *data* itself (not just metadata about it), the correct pattern in both systems is to write the data to durable storage (a Delta table, S3 path) and pass just the *reference* to that location via XCom/taskValues.

---

## Q5. What does `catchup=False` do, and why is it almost always set for production DAGs?

**Answer:**
By default, when a DAG is first deployed (or unpaused after being paused) with a `start_date` in the past, Airflow's scheduler will automatically create and run a DAG run for **every** missed scheduling interval between `start_date` and the current time — this is "catchup" behavior, and for a daily DAG with a `start_date` six months ago, that means six months' worth of backfill runs firing immediately, likely overwhelming downstream systems and producing surprising, unintended reprocessing. Setting `catchup=False` disables this — the DAG only runs from the next scheduled interval going forward. Intentional historical reprocessing should instead be done explicitly via `airflow dags backfill` for specific date ranges, as a deliberate operation rather than an automatic side effect of deployment.

---

## Q6. How do idempotency requirements for Airflow-orchestrated tasks compare to what we discussed for Databricks Jobs in Phase 10?

**Answer:**
The requirement is identical in principle: any task must be safely re-runnable without duplicating or corrupting data, because Airflow will retry failed tasks automatically (per `retries`/`retry_delay` in `default_args`) and because backfills intentionally re-execute tasks for past dates that may have already been processed. In practice this means the same patterns apply regardless of orchestrator — MERGE-based upserts keyed on natural/business keys rather than blind inserts, checkpoint-based incremental processing (Auto Loader tracks its own progress independent of Airflow re-triggering it), and avoiding side effects that aren't safe to repeat (e.g., sending a duplicate notification email on every retry). The orchestrator changes; the underlying idempotency discipline from Phase 4/10 doesn't.

---

## Q7. A DAG's tasks are all succeeding, but the pipeline consistently takes 3 hours longer than expected. How would you diagnose this using Airflow's tooling specifically?

**Answer:**
I'd start with the Airflow Grid/Graph view for the DAG run to visually identify which specific task(s) are consuming the most wall-clock time, rather than assuming it's evenly distributed. If a Sensor task is involved, I'd check whether it's spending most of its time actually waiting for the external condition (legitimate, expected delay from an upstream system) versus polling inefficiently — and whether it's a traditional (worker-slot-holding) sensor potentially being delayed further by resource contention from other DAGs. I'd also check for **SLA misses** if configured, and review whether `DatabricksRunNowOperator`/`DatabricksSubmitRunOperator` tasks are spending time in Databricks cluster startup (job cluster provisioning) rather than actual computation — in which case the fix might belong on the Databricks side (Instance Pools, Phase 9) rather than in Airflow itself.
