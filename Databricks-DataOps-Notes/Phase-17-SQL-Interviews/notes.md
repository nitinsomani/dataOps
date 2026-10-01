# Phase 17: SQL for Interviews — Detailed Notes

> **Goal**: SQL rounds are near-universal for data roles at product companies, often as a standalone round separate from Databricks-specific technical questions. This phase covers interview-standard SQL plus Spark SQL-specific nuances relevant to Databricks.

---

## 1. Logical Query Execution Order (Know This Cold)

SQL is written in one order but **executed** in another — this trips up nearly everyone at some point and is a common conceptual interview question:

```
1. FROM        (+ JOINs)
2. WHERE
3. GROUP BY
4. HAVING
5. SELECT      (+ window functions evaluated here)
6. DISTINCT
7. ORDER BY
8. LIMIT / OFFSET
```

**Why it matters**: this explains why you can't reference a `SELECT`-aliased column in a `WHERE` clause (WHERE executes before SELECT), but you *can* reference it in `ORDER BY` (which executes after). It also explains why `HAVING` filters on aggregates but `WHERE` can't.

---

## 2. Joins Deep Dive

```sql
-- Inner: only matching rows both sides
SELECT * FROM a JOIN b ON a.id = b.id;

-- Left/Right: all rows from one side, NULLs where no match
SELECT * FROM a LEFT JOIN b ON a.id = b.id;

-- Full outer: all rows from both sides
SELECT * FROM a FULL OUTER JOIN b ON a.id = b.id;

-- Cross: cartesian product (every row × every row)
SELECT * FROM a CROSS JOIN b;

-- Self join: table joined to itself (e.g., employee-manager hierarchy)
SELECT e.name, m.name AS manager_name FROM employees e
  LEFT JOIN employees m ON e.manager_id = m.id;

-- Semi-join (rows in A that HAVE a match in B, without duplicating A's rows on multiple B matches)
SELECT * FROM a WHERE EXISTS (SELECT 1 FROM b WHERE b.id = a.id);

-- Anti-join (rows in A that have NO match in B)
SELECT * FROM a WHERE NOT EXISTS (SELECT 1 FROM b WHERE b.id = a.id);
```

- **`EXISTS`/`NOT EXISTS` vs `IN`/`NOT IN`**: `EXISTS` handles NULLs correctly and is generally the safer choice for anti-joins — `NOT IN` silently returns zero rows if the subquery result contains even one NULL, a classic interview gotcha.
- A **semi-join** is functionally what `EXISTS` gives you — unlike a regular JOIN, it never duplicates rows from the left table even if there are multiple matches on the right.

---

## 3. Window Functions — The Most-Tested SQL Topic

```sql
SELECT
  employee_id, department, salary,
  ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary DESC) AS row_num,
  RANK()       OVER (PARTITION BY department ORDER BY salary DESC) AS rank_val,
  DENSE_RANK() OVER (PARTITION BY department ORDER BY salary DESC) AS dense_rank_val,
  LAG(salary, 1)  OVER (PARTITION BY department ORDER BY salary DESC) AS prev_salary,
  LEAD(salary, 1) OVER (PARTITION BY department ORDER BY salary DESC) AS next_salary,
  SUM(salary)  OVER (PARTITION BY department) AS dept_total,
  AVG(salary)  OVER (PARTITION BY department ORDER BY salary
                      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_avg_3
FROM employees;
```

### `ROW_NUMBER` vs `RANK` vs `DENSE_RANK` (classic interview question)
```
Data: salaries [100, 100, 90, 80]
ROW_NUMBER: 1, 2, 3, 4       (always unique, arbitrary tiebreak)
RANK:       1, 1, 3, 4       (ties share rank, next rank skips)
DENSE_RANK: 1, 1, 2, 3       (ties share rank, next rank does NOT skip)
```

### Frame Clauses
```
ROWS BETWEEN 2 PRECEDING AND CURRENT ROW   -- physical row offset
RANGE BETWEEN INTERVAL 7 DAYS PRECEDING AND CURRENT ROW  -- logical value offset (needs ORDER BY on a comparable column)
```
- `ROWS` counts physical rows; `RANGE` groups by the actual value in the ORDER BY column (useful for time-based rolling windows where row counts per day vary).

### Window functions execute in the SELECT phase (Section 1) — **after** WHERE/GROUP BY but you cannot filter on a window function's result directly in the same query's WHERE; you must wrap it in a subquery or CTE.

```sql
-- WRONG: can't filter on ROW_NUMBER() in WHERE of the same SELECT
-- Correct pattern:
WITH ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary DESC) AS rn
  FROM employees
)
SELECT * FROM ranked WHERE rn = 1;   -- top earner per department
```

---

## 4. CTEs (Common Table Expressions)

```sql
WITH dept_avg AS (
  SELECT department, AVG(salary) AS avg_salary FROM employees GROUP BY department
)
SELECT e.name, e.salary, d.avg_salary
FROM employees e JOIN dept_avg d ON e.department = d.department
WHERE e.salary > d.avg_salary;
```

### Recursive CTEs (for hierarchical data)
```sql
WITH RECURSIVE org_chart AS (
  SELECT id, name, manager_id, 1 AS level FROM employees WHERE manager_id IS NULL
  UNION ALL
  SELECT e.id, e.name, e.manager_id, oc.level + 1
  FROM employees e JOIN org_chart oc ON e.manager_id = oc.id
)
SELECT * FROM org_chart ORDER BY level;
```
- CTEs improve readability over deeply nested subqueries but are **not automatically materialized/cached** in most engines (including Spark SQL) — each reference may re-execute the CTE's logic unless the engine's optimizer decides otherwise.

---

## 5. GROUP BY Extensions

```sql
-- ROLLUP: hierarchical subtotals (region -> region+city -> grand total)
SELECT region, city, SUM(sales) FROM sales GROUP BY ROLLUP(region, city);

-- CUBE: all possible combinations of subtotals
SELECT region, city, SUM(sales) FROM sales GROUP BY CUBE(region, city);

-- GROUPING SETS: explicit custom combination of groupings
SELECT region, city, SUM(sales) FROM sales GROUP BY GROUPING SETS ((region), (city), ());
```

---

## 6. Common Interview Query Patterns

### Top-N per group
```sql
WITH ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary DESC) AS rn
  FROM employees
)
SELECT * FROM ranked WHERE rn <= 3;   -- top 3 earners per department
```

### Running total
```sql
SELECT order_date, amount,
  SUM(amount) OVER (ORDER BY order_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
FROM orders;
```

### Find duplicates
```sql
SELECT email, COUNT(*) FROM users GROUP BY email HAVING COUNT(*) > 1;
```

### Deduplicate (keep latest per key)
```sql
WITH ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY updated_at DESC) AS rn
  FROM users
)
SELECT * FROM ranked WHERE rn = 1;
```

### Gaps and islands (find consecutive date ranges)
```sql
WITH flagged AS (
  SELECT user_id, login_date,
    DATE_DIFF(login_date, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_date), 'day') AS grp
  FROM logins
)
SELECT user_id, MIN(login_date) AS streak_start, MAX(login_date) AS streak_end, COUNT(*) AS streak_len
FROM flagged GROUP BY user_id, grp;
```
- The trick: subtracting a strictly increasing row number from a date produces a constant value for consecutive dates — a classic "islands" detection pattern.

### Second-highest value (without LIMIT/OFFSET, portable pattern)
```sql
SELECT MAX(salary) FROM employees WHERE salary < (SELECT MAX(salary) FROM employees);
-- Or, handles ties better:
SELECT DISTINCT salary FROM employees ORDER BY salary DESC LIMIT 1 OFFSET 1;
```

### Pivot (rows to columns)
```sql
SELECT * FROM sales
PIVOT (SUM(amount) FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4'));
```

---

## 7. NULL Handling Gotchas

- `NULL = NULL` evaluates to `NULL` (not `TRUE`) — always use `IS NULL`/`IS NOT NULL`.
- Aggregate functions (`COUNT`, `SUM`, `AVG`) ignore NULLs by default — `COUNT(*)` counts all rows including NULLs in any column, `COUNT(col)` counts only non-NULL values of `col`.
- `NOT IN (subquery)` returns **no rows** if the subquery contains any NULL — always prefer `NOT EXISTS` for anti-joins.
- `COALESCE(col, default)` and `NULLIF(a, b)` are the standard tools for NULL substitution/comparison.

---

## 8. Query Optimization Fundamentals

- **`EXPLAIN` / `EXPLAIN ANALYZE`**: read the execution plan to see join strategy, scan type (full scan vs index/data-skipping), and estimated vs actual row counts.
- **Predicate pushdown**: filter as early as possible, ideally on columns the storage layer can use for pruning (partition columns, Z-Ordered columns in Delta).
- **Avoid `SELECT *`**: especially in columnar storage (Parquet/Delta), unread columns cost nothing — but only if you actually select just what's needed.
- **Avoid functions on indexed/filtered columns** in the WHERE clause (e.g., `WHERE YEAR(order_date) = 2026` prevents partition/index pruning vs `WHERE order_date >= '2026-01-01' AND order_date < '2027-01-01'`).
- **Traditional indexes don't exist in Spark SQL/Delta** — instead, performance relies on **data skipping** (file-level min/max stats), **Z-Order/Liquid Clustering**, and **partitioning** (Phase 3/8). This is a key Databricks-specific SQL nuance to mention if asked.

---

## 9. Spark SQL / Databricks-Specific SQL Nuances

```sql
-- LATERAL VIEW EXPLODE - unnesting arrays (Spark SQL specific)
SELECT id, exploded_val
FROM table LATERAL VIEW EXPLODE(array_col) AS exploded_val;

-- MERGE INTO - not standard ANSI SQL in most RDBMS interview contexts, but core to Delta (Phase 3)
MERGE INTO target USING source ON target.id = source.id
  WHEN MATCHED THEN UPDATE SET *
  WHEN NOT MATCHED THEN INSERT *;

-- Higher-order functions on arrays (Spark SQL specific)
SELECT TRANSFORM(array_col, x -> x * 2) FROM table;
SELECT FILTER(array_col, x -> x > 0) FROM table;
```
- Spark SQL supports semi-structured data operations (arrays, structs, maps, JSON functions) more natively than traditional RDBMS SQL — worth mentioning you're comfortable with both flavors.

---

## 10. Key Takeaways for DataOps

- Execution order + window functions are the two topics most likely to appear regardless of interviewer — know them cold.
- Always default to `NOT EXISTS` over `NOT IN` for anti-joins — the NULL gotcha is a very common trick question.
- Be ready to explain that Spark SQL/Delta has **no traditional indexes** — performance comes from data skipping/clustering instead, tying this phase directly back to Phase 3/8.
- Practice writing gaps-and-islands, top-N-per-group, and running-total patterns until they're automatic — these three patterns cover a huge fraction of asked SQL problems.
