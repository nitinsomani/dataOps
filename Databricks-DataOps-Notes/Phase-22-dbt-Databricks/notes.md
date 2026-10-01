# Phase 22: dbt (data build tool) for Databricks — Detailed Notes

> **Goal**: dbt has become a common transformation-layer choice at many product companies, sometimes alongside Databricks (via the `dbt-databricks` adapter) instead of or in addition to DLT. Enough depth here to be conversational and productive if a team uses it.

---

## 1. What is dbt and Why Does It Exist Alongside Databricks?

dbt is a **transformation-only** framework — it doesn't extract or load data (that's Auto Loader/Fivetran/ingestion tools' job), it doesn't manage compute (that's the Databricks cluster/SQL Warehouse underneath). dbt's entire focus is the **T** in ELT: turning raw tables into clean, tested, documented, version-controlled SQL models — bringing software engineering practices (modularity, testing, version control, documentation) to what was traditionally a pile of ad hoc SQL scripts or stored procedures.

- **dbt Core**: open-source CLI tool.
- **dbt Cloud**: managed service (scheduling, IDE, CI, hosted docs) on top of dbt Core.
- **`dbt-databricks` adapter**: lets dbt compile and run its SQL models against a Databricks SQL Warehouse or cluster, using Delta Lake as the underlying table format.

---

## 2. dbt vs Delta Live Tables — The Question You'll Actually Be Asked

| | dbt | DLT |
|---|-----|-----|
| Primary language | SQL (with Jinja templating), some Python models | Python or SQL (declarative decorators) |
| Execution model | Compiles to SQL, runs via a SQL Warehouse/cluster | Databricks-managed pipeline execution, auto-manages infra |
| Data quality | `tests` (schema tests + custom SQL tests) | Expectations (`@dlt.expect*`) |
| Lineage | Auto-generated DAG from `ref()` calls, documented in dbt Docs | Automatic via Unity Catalog |
| Streaming support | Primarily batch/SQL-oriented | Native streaming support (Structured Streaming under the hood) |
| Best fit | SQL-heavy analytics engineering teams, multi-warehouse orgs (some tables in Snowflake, some in Databricks) | Databricks-native teams, streaming + batch unified, needing DLT's managed infra |

- Many orgs actually run **both**: DLT/Auto Loader handles Bronze ingestion and streaming, while dbt owns the Silver→Gold SQL transformation layer where analysts/analytics engineers are the primary contributors (SQL is a lower barrier to entry than PySpark for that audience).

---

## 3. Core dbt Concepts

```sql
-- models/staging/stg_orders.sql
SELECT
  order_id,
  customer_id,
  CAST(order_date AS DATE) AS order_date,
  amount
FROM {{ source('raw', 'orders') }}
WHERE amount IS NOT NULL
```

```sql
-- models/marts/fct_orders.sql
SELECT
  o.order_id, o.customer_id, o.order_date, o.amount,
  c.segment
FROM {{ ref('stg_orders') }} o
JOIN {{ ref('stg_customers') }} c ON o.customer_id = c.customer_id
```

- **`ref()`**: references another dbt model by name — dbt automatically infers the dependency graph (a DAG, like Airflow's) from these `ref()` calls, so execution order is derived, not manually specified.
- **`source()`**: references a raw table not managed by dbt (e.g., a Bronze Delta table populated by Auto Loader) — declared in a `sources.yml` file with metadata (freshness expectations, description).
- **Materializations**: how a model gets physically built —
  - `view` (default): a SQL view, recomputed on every query — cheap to build, more expensive to query repeatedly.
  - `table`: a full physical table, rebuilt entirely on every `dbt run`.
  - `incremental`: only processes new/changed rows since the last run — the dbt equivalent of a `MERGE`-based upsert pattern.
  - `ephemeral`: not materialized at all, inlined as a CTE into whatever references it.

```sql
-- models/marts/fct_orders_incremental.sql
{{ config(materialized='incremental', unique_key='order_id') }}

SELECT * FROM {{ source('raw', 'orders') }}
{% if is_incremental() %}
  WHERE order_date > (SELECT MAX(order_date) FROM {{ this }})
{% endif %}
```
- `is_incremental()`: a Jinja conditional true only on incremental runs (not the first/full-refresh run) — lets the same model definition handle both full builds and incremental updates.
- `{{ this }}`: refers to the model's own already-materialized table — used to look up "what's already been processed."

---

## 4. Testing in dbt

```yaml
# models/schema.yml
models:
  - name: stg_orders
    columns:
      - name: order_id
        tests: [unique, not_null]
      - name: customer_id
        tests:
          - relationships:
              to: ref('stg_customers')
              field: customer_id
      - name: amount
        tests:
          - dbt_utils.accepted_range:
              min_value: 0
```
- **Schema tests** (built-in): `unique`, `not_null`, `accepted_values`, `relationships` (referential integrity — analogous to a foreign key check) — declared in YAML, no SQL needed.
- **Custom/singular tests**: a SQL query in a `tests/` folder that should return **zero rows** if the test passes (any returned row represents a failure).
- Conceptually parallels DLT Expectations (Phase 5/11) and Great Expectations (Phase 11) — same underlying goal (assert things about the data, not just the code), different tool/ecosystem.

```bash
dbt run           # build all models
dbt test           # run all tests
dbt build           # run + test in dependency order (recommended over running separately)
dbt run --select stg_orders+     # run this model and everything downstream of it
```

---

## 5. Documentation & Lineage

```bash
dbt docs generate
dbt docs serve
```
- Auto-generates a browsable documentation site including the full **DAG visualization** (derived from `ref()`/`source()` calls) and column-level descriptions defined in `schema.yml` — a lighter-weight, dbt-native parallel to Unity Catalog's lineage graph (Phase 6). When both dbt and Unity Catalog are in play, they provide overlapping but not identical lineage views (dbt's is transformation-logic-based; UC's is execution-based and covers non-dbt-orchestrated queries too).

---

## 6. Jinja & Macros — Reusable SQL Logic

```sql
-- macros/cents_to_dollars.sql
{% macro cents_to_dollars(column_name) %}
  ({{ column_name }} / 100.0)
{% endmacro %}

-- usage in a model
SELECT {{ cents_to_dollars('amount_cents') }} AS amount_dollars FROM {{ ref('stg_orders') }}
```
- Macros are reusable Jinja+SQL snippets — the dbt equivalent of a Python function, letting you avoid copy-pasting the same SQL logic (unit conversions, standard date-bucketing expressions) across many models.
- **`dbt-utils`** and other public packages provide a large library of common macros (surrogate key generation, date spine generation, pivot helpers) so teams don't reinvent common patterns.

---

## 7. dbt + Databricks-Specific Considerations

- The `dbt-databricks` adapter connects to a **SQL Warehouse** (or all-purpose cluster, less commonly for production) — meaning dbt's compute cost is billed exactly like any other Databricks SQL Warehouse usage (Phase 8/9 cost considerations apply directly).
- dbt models materialize as standard **Delta tables**, fully visible and governable in **Unity Catalog** — grants, lineage, and row filters/column masks (Phase 6) apply to dbt-built tables exactly as they would to any other Delta table.
- dbt's `incremental` materialization can be configured to use Delta's `merge` strategy under the hood (`incremental_strategy='merge'`) — directly leveraging the `MERGE INTO` mechanics from Phase 3 rather than reinventing upsert logic.

---

## 8. CI/CD for dbt (Ties to Phase 10)

- dbt projects are Git-versioned like any other codebase — the same PR → CI test → staged deploy → prod promotion pattern from Phase 10 applies.
- `dbt build --select state:modified+` (dbt's "slim CI" pattern): only run/test models that changed (plus their downstream dependents) compared to a previous state, rather than rebuilding the entire project on every PR — significantly faster CI feedback loops on large projects.
- Common to run `dbt build` as a step inside a GitHub Actions job, similar in spirit to the `databricks bundle deploy` step from Phase 10.

---

## 9. Key Takeaways for DataOps

- dbt owns **transformation** SQL specifically; ingestion (Auto Loader) and orchestration (Jobs/Airflow) remain separate concerns it doesn't replace.
- `ref()`/`source()` auto-derive the DAG — conceptually identical to how DLT infers table dependencies, just SQL-first instead of Python-decorator-first.
- Materializations (view/table/incremental/ephemeral) are the key architectural decision per model — know `incremental` + `merge` strategy cold, since it's the dbt equivalent of Phase 3's MERGE-based upsert pattern.
- Schema tests (`unique`, `not_null`, `relationships`) are dbt's answer to Phase 11's data quality gates — same goal, YAML-based syntax instead of Python decorators.
