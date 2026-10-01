# Phase 17: SQL for Interviews — Cheat Sheet

---

## Logical Execution Order

```
FROM/JOIN → WHERE → GROUP BY → HAVING → SELECT (+ window fns) → DISTINCT → ORDER BY → LIMIT
```

## Join Types Quick Reference

```
INNER        → matches only
LEFT/RIGHT   → all of one side + matches, NULL fill
FULL OUTER   → all of both sides
CROSS        → cartesian product
SELF         → table joined to itself (hierarchies)
SEMI (EXISTS)     → rows in A with a match in B, no duplication
ANTI (NOT EXISTS) → rows in A with NO match in B
```

**Gotcha**: `NOT IN` + NULL in subquery → returns zero rows. Always use `NOT EXISTS` for anti-joins.

## Window Functions Ranking Comparison

```
Data: [100, 100, 90, 80]
ROW_NUMBER: 1,2,3,4   (unique always)
RANK:       1,1,3,4   (ties share, skips after)
DENSE_RANK: 1,1,2,3   (ties share, no skip)
```

## Window Function Syntax

```sql
FUNC() OVER (PARTITION BY col ORDER BY col2 ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
```
```
LAG(col, n) / LEAD(col, n)   → prior/next row value
NTILE(n)                      → bucket into n groups
ROWS BETWEEN                  → physical row offset
RANGE BETWEEN                  → logical value offset
```
Cannot filter on a window function result in the same query's WHERE — wrap in CTE/subquery.

## CTE Skeleton

```sql
WITH cte_name AS (SELECT ...)
SELECT ... FROM cte_name;

WITH RECURSIVE cte AS (
  SELECT ... -- anchor
  UNION ALL
  SELECT ... FROM t JOIN cte ON ... -- recursive
)
SELECT * FROM cte;
```

## GROUP BY Extensions

```sql
GROUP BY ROLLUP(a, b)        -- hierarchical subtotals
GROUP BY CUBE(a, b)           -- all combinations
GROUP BY GROUPING SETS ((a),(b),())  -- custom combos
```

## Common Patterns Quick Recall

```sql
-- Top-N per group
ROW_NUMBER() OVER (PARTITION BY grp ORDER BY val DESC) AS rn ... WHERE rn <= N

-- Running total
SUM(x) OVER (ORDER BY date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)

-- Duplicates
GROUP BY key HAVING COUNT(*) > 1

-- Dedup keep latest
ROW_NUMBER() OVER (PARTITION BY key ORDER BY updated_at DESC) = 1

-- Gaps & islands
date - ROW_NUMBER() OVER (PARTITION BY key ORDER BY date) = constant for a streak

-- 2nd highest
SELECT DISTINCT val FROM t ORDER BY val DESC LIMIT 1 OFFSET 1
```

## NULL Rules

```
NULL = NULL          → NULL (not true) — use IS NULL
COUNT(*)             → counts all rows
COUNT(col)            → counts non-NULL only
NOT IN + NULL          → returns 0 rows (danger!)
COALESCE(a, default)    → NULL substitution
NULLIF(a, b)             → NULL if equal
```

## Databricks/Spark SQL Specifics

```sql
LATERAL VIEW EXPLODE(array_col) AS val    -- unnest arrays
TRANSFORM(array_col, x -> x*2)             -- higher-order array function
FILTER(array_col, x -> x > 0)
MERGE INTO ... WHEN MATCHED ... WHEN NOT MATCHED ...
```
No traditional indexes — rely on data skipping, Z-Order/Liquid Clustering, partitioning instead (Phase 3/8).

## Optimization Checklist

```
[ ] Use EXPLAIN / EXPLAIN ANALYZE before assuming
[ ] Filter early, on skippable/partition columns
[ ] Avoid SELECT *
[ ] Avoid functions wrapping filtered columns (breaks pruning)
[ ] No indexes in Spark SQL — think data skipping/clustering instead
```
