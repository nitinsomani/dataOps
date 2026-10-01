# Phase 17: SQL for Interviews — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ Explain the logical execution order of a SQL query and why you can't use a SELECT alias in a WHERE clause.

**Answer:**
SQL executes in this logical order: `FROM`/`JOIN` → `WHERE` → `GROUP BY` → `HAVING` → `SELECT` → `DISTINCT` → `ORDER BY` → `LIMIT`. Since `WHERE` executes before `SELECT`, any alias defined in the `SELECT` clause doesn't exist yet when `WHERE` is evaluated — that's why `SELECT amount * 1.1 AS adjusted WHERE adjusted > 100` fails in most engines, while it works fine in `ORDER BY` (which executes after `SELECT`). This also explains why `HAVING` (which runs after `GROUP BY`) can filter on aggregate results while `WHERE` (which runs before grouping) cannot.

---

## Q2. ⭐ What's the difference between `ROW_NUMBER()`, `RANK()`, and `DENSE_RANK()`?

**Answer:**
Given tied values, `ROW_NUMBER()` always assigns strictly increasing, unique numbers regardless of ties (arbitrary tiebreaking based on any additional ordering or physical row order). `RANK()` gives tied rows the same rank, but the next rank **skips** ahead by the number of tied rows (e.g., two rows tied for rank 1 means the next row gets rank 3). `DENSE_RANK()` also gives tied rows the same rank, but the next rank does **not** skip — it increments by exactly 1 regardless of how many rows were tied. I'd choose `ROW_NUMBER()` when I need a strict, unique ordering (e.g., picking exactly one "top" row per group), and `DENSE_RANK()`/`RANK()` when ties should genuinely share a position, choosing between the two based on whether subsequent ranks should reflect the "gap" left by ties.

---

## Q3. Why is `NOT IN` risky with subqueries, and what should you use instead?

**Answer:**
If the subquery in a `NOT IN (subquery)` produces even a single `NULL` value, the entire `NOT IN` condition evaluates to unknown/false for every row, causing the query to return zero rows — a very common, easy-to-miss bug, especially when the subquery selects a nullable foreign-key-style column. The safer, equivalent pattern is `WHERE NOT EXISTS (SELECT 1 FROM b WHERE b.id = a.id)`, which correctly handles NULLs in the correlated subquery and is also often better optimized by query engines. As a rule, I default to `EXISTS`/`NOT EXISTS` over `IN`/`NOT IN` whenever the subquery's result could contain NULLs, which is most of the time in real-world data.

---

## Q4. ⭐ Write a query to find the top 3 highest-paid employees in each department. Walk through your approach.

**Answer:**
```sql
WITH ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary DESC) AS rn
  FROM employees
)
SELECT * FROM ranked WHERE rn <= 3;
```
I'd use `ROW_NUMBER()` (not `RANK()`, unless the requirement explicitly wants tied 3rd-place salaries to *all* be included, in which case `RANK()` would be more appropriate) partitioned by department and ordered by salary descending, then wrap it in a CTE since window function results can't be filtered directly in the same query's `WHERE` clause — window functions are evaluated during the `SELECT` phase, which runs after `WHERE`.

---

## Q5. How would you write a query to detect consecutive login streaks per user (a "gaps and islands" problem)?

**Answer:**
```sql
WITH flagged AS (
  SELECT user_id, login_date,
    DATE_SUB(login_date, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_date)) AS grp
  FROM logins
)
SELECT user_id, MIN(login_date) AS streak_start, MAX(login_date) AS streak_end, COUNT(*) AS streak_length
FROM flagged GROUP BY user_id, grp;
```
The trick is that subtracting a strictly-increasing row number (partitioned per user, ordered by date) from each date produces a **constant value** for any run of consecutive dates — because both the date and the row number increase by exactly 1 per day within a genuine streak, their difference stays flat. Grouping by this constant "island group" value then lets you aggregate `MIN`/`MAX`/`COUNT` per streak. This same subtract-the-row-number pattern generalizes to any "find consecutive X" problem, not just dates.

---

## Q6. What's the difference between a CTE and a subquery, and does using a CTE improve performance?

**Answer:**
Functionally, a CTE (`WITH name AS (...)`) is largely equivalent to an inline subquery — it primarily improves **readability** by naming and separating logical steps, especially valuable when a query needs multiple sequential transformations or when the same derived result is referenced multiple times in the outer query. It does **not** automatically guarantee a performance improvement — most SQL engines, including Spark SQL, don't automatically materialize/cache a CTE's result by default; the CTE's underlying query may be re-executed each time it's referenced unless the query optimizer specifically decides to reuse a computed intermediate result. If a genuinely expensive computation needs to be materialized once and reused, an explicit temp table/view or `.cache()` (in a Spark context) is a more reliable guarantee than assuming a CTE alone provides caching.

---

## Q7. ⭐ Explain how you'd optimize a slow SQL query in a Databricks/Spark SQL environment, given there are no traditional indexes.

**Answer:**
I'd start with `EXPLAIN`/`EXPLAIN ANALYZE` (or Databricks SQL's Query Profile) to see the physical plan — checking whether filters are being pushed down and whether files are being pruned via data skipping. Since Spark SQL/Delta doesn't have traditional B-tree indexes, performance instead comes from: partitioning or **Liquid Clustering**/Z-Order on frequently-filtered columns (enabling file-level data skipping via min/max statistics), avoiding functions wrapped around filtered columns in the WHERE clause (e.g., `WHERE CAST(date_col AS DATE) = ...` defeats pruning — better to write a direct range comparison), ensuring join strategy is appropriate (broadcast vs sort-merge, Phase 2), and running `OPTIMIZE`/`ANALYZE TABLE` if file fragmentation or stale statistics are contributing factors. This is a good moment to explicitly connect SQL tuning back to the underlying Delta/Spark mechanics from Phases 2, 3, and 8 rather than treating it as generic RDBMS tuning.

---

## Q8. What does `LATERAL VIEW EXPLODE` do, and when would you need it?

**Answer:**
`LATERAL VIEW EXPLODE(array_column)` is a Spark SQL construct that "unnests" an array or map column into multiple rows — one row per element — joined back against the original row's other columns, similar to a cross join between each row and its own array's elements. This is common when working with semi-structured data (e.g., a JSON column parsed into an array of tags, or a nested list of line items within an order) where you need row-level analysis of individual array elements rather than treating the array as a single opaque value — a pattern that comes up frequently when working with raw/Bronze layer semi-structured ingested data before it's fully normalized into Silver.
