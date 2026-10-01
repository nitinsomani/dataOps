# Phase 22: dbt (data build tool) for Databricks — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ What is dbt, and what part of the data pipeline does it NOT handle?

**Answer:**
dbt is a transformation-only framework — it takes SQL `SELECT` statements organized as version-controlled "models," automatically infers their dependency graph via `ref()`/`source()` calls, and executes them against a warehouse (in this case, a Databricks SQL Warehouse via the `dbt-databricks` adapter) to build tables/views, alongside built-in testing and auto-generated documentation. It explicitly does **not** handle extraction or loading (that's Auto Loader, Fivetran, or a CDC tool's job), does not manage compute infrastructure itself (it just runs SQL against whatever warehouse/cluster you point it at), and does not handle orchestration timing on its own (a scheduler like Databricks Jobs or Airflow typically triggers `dbt run`/`dbt build` on a schedule).

---

## Q2. ⭐ How does dbt's dependency management compare to Delta Live Tables' dependency inference?

**Answer:**
Both tools derive an execution DAG automatically rather than requiring you to manually sequence steps: dbt infers dependencies from `{{ ref('model_name') }}` calls within SQL model files, while DLT infers dependencies from Python function calls (`dlt.read('table_name')`/`dlt.read_stream(...)`) within `@dlt.table`-decorated functions. Conceptually they solve the identical problem (build the dependency graph from code references rather than an explicit manually-maintained DAG definition), just in different syntaxes suited to their primary audiences — dbt targets SQL-first analytics engineers, DLT targets Python/PySpark-first data engineers, though DLT does also support a SQL-based syntax.

---

## Q3. Explain dbt's `incremental` materialization and how it compares to a Delta `MERGE` you'd write by hand.

**Answer:**
An `incremental` model is configured with a `unique_key` and, on subsequent runs (`is_incremental()` evaluates true after the first full build), only processes rows newer than what's already been materialized — typically via a `WHERE` clause comparing against `MAX(some_timestamp)` from the model's own existing table (`{{ this }}`). With `incremental_strategy='merge'` specifically on the Databricks adapter, dbt compiles this down to an actual Delta `MERGE INTO` statement under the hood — meaning it's not reinventing upsert logic, it's generating the same MERGE pattern you'd otherwise hand-write (Phase 3), just derived from a higher-level model configuration rather than raw SQL you maintain yourself.

---

## Q4. What are dbt schema tests, and how do they compare to Delta Live Tables expectations or Great Expectations?

**Answer:**
Schema tests are declared in YAML against specific model columns — built-in ones include `unique`, `not_null`, `accepted_values`, and `relationships` (a referential-integrity check against another model, analogous to a foreign key constraint), with the broader `dbt_utils`/`dbt_expectations` package ecosystem adding many more. Custom "singular" tests are just a SQL query in a `tests/` folder that must return **zero rows** to pass — any returned row represents a specific failing case. This serves the identical purpose as DLT's `@dlt.expect*` decorators or Great Expectations' `expect_column_values_to_*` methods (Phase 11) — asserting facts about the data itself as part of the pipeline — just expressed in dbt's YAML/SQL-test idiom rather than Python.

---

## Q5. If a company already uses both Databricks and dbt, how would you architect where DLT/Auto Loader responsibilities end and dbt responsibilities begin?

**Answer:**
A common, clean split: Auto Loader (or DLT for the ingestion/Bronze stage specifically) handles raw ingestion and any streaming-specific requirements, landing data into Bronze Delta tables — since dbt itself isn't built for continuous streaming ingestion. From Bronze onward, dbt takes over the Silver→Gold SQL transformation logic, since that's typically SQL-heavy, analytics-engineer-owned work that benefits from dbt's testing/documentation/version-control ergonomics designed specifically for that audience. Orchestration (Databricks Jobs or Airflow) then triggers both stages in the correct order — e.g., a Job task runs the Auto Loader/DLT ingestion pipeline, followed by a task that runs `dbt build` against the resulting Bronze tables. This avoids forcing either tool to do something it's not well-suited for.

---

## Q6. What is dbt's "slim CI" pattern (`state:modified+`), and why does it matter for a large dbt project?

**Answer:**
`dbt build --select state:modified+` compares the current project state against a previous state (typically the last successful production run's artifacts) and only builds/tests models that have actually changed, **plus** everything downstream of them that could be affected — rather than rebuilding the entire project (which could be hundreds of models) on every single PR. This dramatically speeds up CI feedback loops on large dbt projects, directly analogous to why you wouldn't want a CI pipeline to re-run every unit test in a massive codebase on every commit when only a small, localized change was made — it's the dbt-specific instantiation of "only test what could plausibly be affected," a general CI/CD efficiency principle from Phase 10.

---

## Q7. How does Unity Catalog governance interact with tables built by dbt?

**Answer:**
Since dbt's `dbt-databricks` adapter materializes models as standard Delta tables (or views) within whatever catalog/schema is configured in the dbt profile, those tables are fully subject to Unity Catalog governance exactly like any other Delta table — grants, row filters, column masks, and audit logging all apply without any dbt-specific configuration needed. The one nuance worth knowing: dbt's own auto-generated documentation/lineage (from `ref()`/`source()` calls) reflects the *transformation logic's* dependency graph, while Unity Catalog's lineage is derived from *actual query execution* and covers any query touching the table regardless of whether it went through dbt — so the two lineage views are complementary rather than identical, and in a mature setup you'd typically rely on Unity Catalog as the canonical, execution-based lineage source of truth while using dbt's docs site for developer-facing model documentation.
