# Phase 19: Data Modeling & Warehousing Fundamentals — Lab Exercises

> Mix of whiteboard-style design exercises and hands-on Delta implementation (ties back to Phase 3/5).

---

## Lab 1: Design a Star Schema from a Raw Requirements Statement

**Objective**: Practice grain definition and schema design under interview-like conditions.

**Prompt**: "We run a food delivery app. We need to analyze delivery times, order values, driver performance, and restaurant ratings over time."

1. Write down your chosen grain for the primary fact table.
2. List the fact table's foreign keys and measures.
3. List at least 4 dimension tables with 5+ descriptive columns each.
4. Identify which dimension(s) need SCD Type 2 and justify why.

### Questions to Answer
- [ ] What grain did you choose, and what question would you be UNABLE to answer if you'd chosen a coarser grain?
- [ ] Which dimension is most likely to need SCD Type 2 in this scenario (hint: driver status/rating changes over time)?

---

## Lab 2: Implement a Star Schema in Delta Lake

```python
spark.sql("CREATE SCHEMA IF NOT EXISTS main.lab19")

spark.sql("""
CREATE TABLE main.lab19.dim_customer (
  customer_key BIGINT, customer_id STRING, name STRING, segment STRING,
  effective_date DATE, end_date DATE, is_current BOOLEAN
) USING DELTA
""")

spark.sql("""
CREATE TABLE main.lab19.dim_product (
  product_key BIGINT, product_id STRING, name STRING, category STRING, brand STRING
) USING DELTA
""")

spark.sql("""
CREATE TABLE main.lab19.dim_date (
  date_key INT, full_date DATE, year INT, quarter INT, month INT, day_of_week STRING, is_holiday BOOLEAN
) USING DELTA
""")

spark.sql("""
CREATE TABLE main.lab19.fact_order_lines (
  order_line_id BIGINT, customer_key BIGINT, product_key BIGINT, date_key INT,
  quantity INT, unit_price DECIMAL(10,2), line_total DECIMAL(10,2)
) USING DELTA
CLUSTER BY (date_key, customer_key)
""")
```

### Questions to Answer
- [ ] Why does `fact_order_lines` cluster on `date_key`/`customer_key` rather than `order_line_id`?
- [ ] Insert sample rows and write a query joining fact to all three dimensions — confirm it returns sensible results.

---

## Lab 3: Implement SCD Type 2 with MERGE (ties to Phase 3)

```python
spark.sql("""
INSERT INTO main.lab19.dim_customer VALUES
  (1, 'CUST001', 'Alice', 'Standard', '2026-01-01', '9999-12-31', true)
""")

# Simulate a segment change - Alice upgrades to 'Premium'
spark.sql("""
MERGE INTO main.lab19.dim_customer t
USING (SELECT 'CUST001' AS customer_id, 'Premium' AS segment, current_date() AS change_date) s
ON t.customer_id = s.customer_id AND t.is_current = true
WHEN MATCHED AND t.segment != s.segment THEN
  UPDATE SET end_date = date_sub(s.change_date, 1), is_current = false
""")

spark.sql("""
INSERT INTO main.lab19.dim_customer
SELECT 2, 'CUST001', 'Alice', 'Premium', current_date(), '9999-12-31', true
""")

spark.sql("SELECT * FROM main.lab19.dim_customer ORDER BY customer_id").show()
```

### Questions to Answer
- [ ] How many rows now exist for CUST001, and what does each represent?
- [ ] Write a query that finds "what segment was CUST001 in on 2026-01-15" using the effective/end date range.

---

## Lab 4: Accumulating Snapshot Fact Table

```python
spark.sql("""
CREATE TABLE main.lab19.fact_order_process (
  order_id BIGINT PRIMARY KEY,
  placed_ts TIMESTAMP, paid_ts TIMESTAMP, shipped_ts TIMESTAMP, delivered_ts TIMESTAMP
) USING DELTA
""")

spark.sql("INSERT INTO main.lab19.fact_order_process VALUES (1, current_timestamp(), NULL, NULL, NULL)")

# Order gets paid - update in place
spark.sql("""
MERGE INTO main.lab19.fact_order_process t
USING (SELECT 1 AS order_id, current_timestamp() AS paid_ts) s
ON t.order_id = s.order_id
WHEN MATCHED THEN UPDATE SET paid_ts = s.paid_ts
""")
```

### Questions to Answer
- [ ] How does this write pattern (MERGE/update-in-place) differ from the append-only pattern typical of Bronze tables?
- [ ] Write a query calculating average time from `placed_ts` to `delivered_ts` across all completed orders.

---

## Lab 5: Critique a Bad Schema

**Objective**: Given a poorly designed schema, identify and fix the issues.

```sql
CREATE TABLE bad_fact_orders (
  order_id BIGINT,
  customer_name STRING,       -- denormalized directly into fact, no dimension
  customer_email STRING,
  product_name STRING,
  product_category STRING,
  order_date STRING,           -- stored as string, not date/date_key
  total_amount DECIMAL(10,2)
);
```

### Questions to Answer
- [ ] List at least 3 specific design problems with this table.
- [ ] Redesign it as a proper star schema with a stated grain.
