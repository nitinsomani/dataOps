# Phase 22: dbt (data build tool) for Databricks — Cheat Sheet

---

## What dbt Owns vs Doesn't

```
dbt owns:      Transformation (T in ELT) — SQL models, tests, docs, lineage
dbt does NOT:  Extract/Load (Auto Loader/Fivetran), compute mgmt (Databricks cluster/warehouse), orchestration timing (Airflow/Databricks Jobs trigger dbt runs)
```

## dbt vs DLT Decision Table

| | dbt | DLT |
|-|-----|-----|
| Language | SQL + Jinja | Python/SQL decorators |
| Quality checks | schema tests + custom SQL tests | `@dlt.expect*` |
| Streaming | mostly batch | native streaming |
| Best fit | SQL-heavy analytics engineers, multi-warehouse | Databricks-native, streaming+batch unified |

## Core Building Blocks

```sql
{{ ref('other_model') }}         -- reference another dbt model, builds the DAG
{{ source('raw', 'orders') }}     -- reference a non-dbt-managed raw table
```

## Materializations

```
view        → recomputed every query, cheap to build
table        → full rebuild every run
incremental   → only new/changed rows (dbt's MERGE-equivalent)
ephemeral      → not materialized, inlined as CTE
```

```sql
{{ config(materialized='incremental', unique_key='order_id', incremental_strategy='merge') }}
SELECT * FROM {{ source('raw','orders') }}
{% if is_incremental() %} WHERE order_date > (SELECT MAX(order_date) FROM {{ this }}) {% endif %}
```

## Testing

```yaml
tests: [unique, not_null]
tests:
  - relationships: {to: ref('stg_customers'), field: customer_id}
  - dbt_utils.accepted_range: {min_value: 0}
```
Custom test = SQL file in `tests/` that must return ZERO rows to pass.

## CLI Commands

```bash
dbt run                          # build models
dbt test                          # run tests
dbt build                          # run + test in dependency order (recommended)
dbt run --select stg_orders+       # model + everything downstream
dbt build --select state:modified+  # slim CI — only changed models + downstream
dbt docs generate && dbt docs serve  # lineage + docs site
```

## Macros

```sql
{% macro cents_to_dollars(col) %}({{ col }} / 100.0){% endmacro %}
-- usage: {{ cents_to_dollars('amount_cents') }}
```
`dbt-utils` package = library of common macros (surrogate keys, date spines, pivots).

## Databricks-Specific Notes

```
[ ] dbt-databricks adapter connects to a SQL Warehouse (billed like any DBSQL usage)
[ ] Models materialize as standard Delta tables — fully Unity Catalog governed
[ ] incremental_strategy='merge' uses Delta MERGE INTO under the hood
```
