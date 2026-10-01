# Phase 22: dbt (data build tool) for Databricks — Lab Exercises

> Requires `pip install dbt-databricks` and a Databricks SQL Warehouse connection (host, HTTP path, access token/service principal OAuth).

---

## Lab 1: Initialize a dbt Project Connected to Databricks

```bash
pip install dbt-databricks
dbt init lab22_project
# When prompted, choose 'databricks' adapter and provide:
#   host, http_path (SQL Warehouse), token/OAuth creds, catalog, schema
```

```yaml
# ~/.dbt/profiles.yml (generated/edited)
lab22_project:
  target: dev
  outputs:
    dev:
      type: databricks
      catalog: main
      schema: lab22_dbt
      host: "<workspace-host>"
      http_path: "<sql-warehouse-http-path>"
      token: "{{ env_var('DATABRICKS_TOKEN') }}"
```

```bash
dbt debug   # validates the connection
```

### Questions to Answer
- [ ] Did `dbt debug` confirm a successful connection? What does it check specifically?
- [ ] Why is `token` referenced via `env_var()` rather than hardcoded in `profiles.yml` (ties to Phase 7 secrets hygiene)?

---

## Lab 2: Set Up a Source and a Staging Model

```sql
-- models/staging/sources.yml
version: 2
sources:
  - name: raw
    schema: lab22_raw
    tables:
      - name: orders
```

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
-- Create the raw source table first (in Databricks SQL or a notebook)
CREATE TABLE main.lab22_raw.orders (order_id BIGINT, customer_id BIGINT, order_date STRING, amount DOUBLE);
INSERT INTO main.lab22_raw.orders VALUES (1, 100, '2026-09-01', 50.0), (2, 100, '2026-09-02', -5.0), (3, 101, '2026-09-03', 75.0);
```

```bash
dbt run --select stg_orders
```

### Questions to Answer
- [ ] Query the resulting `stg_orders` table/view — did the negative-amount row get filtered out?
- [ ] What materialization did this model use by default (view or table), and where would you check/change that?

---

## Lab 3: Build a Downstream Model with `ref()`

```sql
-- models/staging/stg_customers.sql
SELECT customer_id, segment FROM {{ source('raw', 'customers') }}

-- models/marts/fct_orders.sql
SELECT o.order_id, o.customer_id, o.order_date, o.amount, c.segment
FROM {{ ref('stg_orders') }} o
JOIN {{ ref('stg_customers') }} c ON o.customer_id = c.customer_id
```

```bash
dbt run
dbt docs generate
dbt docs serve
```

### Questions to Answer
- [ ] In the generated docs site, does the DAG visualization correctly show `stg_orders`/`stg_customers` → `fct_orders`?
- [ ] Run `dbt run --select fct_orders+` vs `dbt run --select +fct_orders` — what's the difference in which models get selected?

---

## Lab 4: Add Schema Tests

```yaml
# models/staging/schema.yml
version: 2
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
```

```bash
dbt test --select stg_orders
```

### Questions to Answer
- [ ] Do all tests pass? Insert a duplicate `order_id` into the raw source and re-run — does the `unique` test correctly fail?
- [ ] Insert an order with a `customer_id` that doesn't exist in `stg_customers` — does the `relationships` test catch it?

---

## Lab 5: Incremental Model with Merge Strategy

```sql
-- models/marts/fct_orders_incremental.sql
{{ config(materialized='incremental', unique_key='order_id', incremental_strategy='merge') }}

SELECT order_id, customer_id, order_date, amount
FROM {{ source('raw', 'orders') }}
{% if is_incremental() %}
  WHERE order_date > (SELECT MAX(order_date) FROM {{ this }})
{% endif %}
```

```bash
dbt run --select fct_orders_incremental --full-refresh   # first build
# Insert new rows into main.lab22_raw.orders with a later order_date
dbt run --select fct_orders_incremental                    # incremental build
```

### Questions to Answer
- [ ] After the incremental run, did only the new rows get processed (check row counts before/after)?
- [ ] Inspect the compiled SQL (`target/compiled/.../fct_orders_incremental.sql`) — does it show an actual `MERGE INTO` statement?

---

## Lab 6: Slim CI Simulation

```bash
dbt run --select stg_orders   # simulate a "changed model"
dbt build --select state:modified+ --state ./previous_manifest/
```

### Questions to Answer
- [ ] What does the `--state` flag require (a prior `manifest.json` artifact) — where would this typically come from in a real CI pipeline (a scheduled prod run's artifacts)?
- [ ] Why would a large dbt project (100+ models) specifically benefit from this pattern in a GitHub Actions PR-check workflow (tying back to Phase 10)?
