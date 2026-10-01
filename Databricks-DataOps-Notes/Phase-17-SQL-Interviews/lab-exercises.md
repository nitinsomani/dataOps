# Phase 17: SQL for Interviews — Lab Exercises

> Run these in Databricks SQL or a notebook `%sql` cell. Create sample tables first.

---

## Lab 0: Set Up Sample Data

```sql
CREATE TABLE IF NOT EXISTS main.lab17_employees (
  id INT, name STRING, department STRING, salary DOUBLE, manager_id INT
);
INSERT INTO main.lab17_employees VALUES
  (1, 'Alice', 'Engineering', 120000, NULL),
  (2, 'Bob', 'Engineering', 110000, 1),
  (3, 'Carol', 'Engineering', 110000, 1),
  (4, 'Dave', 'Sales', 95000, NULL),
  (5, 'Eve', 'Sales', 90000, 4),
  (6, 'Frank', 'Sales', 90000, 4);

CREATE TABLE IF NOT EXISTS main.lab17_logins (user_id INT, login_date DATE);
INSERT INTO main.lab17_logins VALUES
  (1, '2026-09-01'), (1, '2026-09-02'), (1, '2026-09-03'),
  (1, '2026-09-05'), (1, '2026-09-06'),
  (2, '2026-09-01'), (2, '2026-09-03');
```

---

## Lab 1: Execution Order Debugging

```sql
-- This will fail - figure out why, then fix it
SELECT department, AVG(salary) AS avg_salary
FROM main.lab17_employees
WHERE avg_salary > 100000
GROUP BY department;
```

### Questions to Answer
- [ ] Why does this fail? Rewrite it using `HAVING` correctly.
- [ ] Rewrite using a CTE instead of `HAVING` — which do you prefer and why?

---

## Lab 2: Window Functions Ranking Comparison

```sql
SELECT name, department, salary,
  ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary DESC) AS rn,
  RANK()       OVER (PARTITION BY department ORDER BY salary DESC) AS rnk,
  DENSE_RANK() OVER (PARTITION BY department ORDER BY salary DESC) AS drnk
FROM main.lab17_employees
ORDER BY department, salary DESC;
```

### Questions to Answer
- [ ] For the Sales department (Eve and Frank tied at 90000), what values do `rn`, `rnk`, and `drnk` show for each?
- [ ] Modify the query to return only the top-earner per department using `rn`.

---

## Lab 3: Anti-Join NULL Gotcha

```sql
-- Add a NULL manager_id scenario and observe NOT IN behavior
SELECT * FROM main.lab17_employees
WHERE manager_id NOT IN (SELECT manager_id FROM main.lab17_employees WHERE manager_id IS NOT NULL);

-- Now deliberately include the NULL row in the subquery
SELECT * FROM main.lab17_employees
WHERE manager_id NOT IN (SELECT manager_id FROM main.lab17_employees);
```

### Questions to Answer
- [ ] What result did the second query return, and why (hint: `manager_id` for Alice/Dave is NULL)?
- [ ] Rewrite using `NOT EXISTS` — confirm it returns the expected rows regardless of NULLs.

---

## Lab 4: Gaps and Islands — Login Streaks

```sql
WITH flagged AS (
  SELECT user_id, login_date,
    date_sub(login_date, CAST(ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_date) AS INT)) AS grp
  FROM main.lab17_logins
)
SELECT user_id, MIN(login_date) AS streak_start, MAX(login_date) AS streak_end, COUNT(*) AS streak_len
FROM flagged
GROUP BY user_id, grp
ORDER BY user_id, streak_start;
```

### Questions to Answer
- [ ] For user_id=1, how many separate streaks does this identify, and what are their lengths?
- [ ] Modify the query to only return streaks of length >= 3.

---

## Lab 5: Recursive CTE — Org Chart

```sql
WITH RECURSIVE org_chart AS (
  SELECT id, name, manager_id, 1 AS level FROM main.lab17_employees WHERE manager_id IS NULL
  UNION ALL
  SELECT e.id, e.name, e.manager_id, oc.level + 1
  FROM main.lab17_employees e JOIN org_chart oc ON e.manager_id = oc.id
)
SELECT * FROM org_chart ORDER BY level;
```

### Questions to Answer
- [ ] Does Databricks SQL support `WITH RECURSIVE` natively? If not, what alternative approach would you use (iterative joins, or Python-side recursion)?
- [ ] What would happen with a circular management reference — how would you guard against infinite recursion?

---

## Lab 6: Running Totals and Rolling Averages

```sql
CREATE TABLE IF NOT EXISTS main.lab17_orders (order_date DATE, amount DOUBLE);
INSERT INTO main.lab17_orders VALUES
  ('2026-09-01', 100), ('2026-09-02', 150), ('2026-09-03', 90),
  ('2026-09-04', 200), ('2026-09-05', 120);

SELECT order_date, amount,
  SUM(amount) OVER (ORDER BY order_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total,
  AVG(amount) OVER (ORDER BY order_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_avg_3day
FROM main.lab17_orders
ORDER BY order_date;
```

### Questions to Answer
- [ ] What's the `running_total` value on 2026-09-03, and does it match manual addition?
- [ ] Change the frame to `RANGE BETWEEN INTERVAL 2 DAYS PRECEDING AND CURRENT ROW` — does the result differ from `ROWS`, and under what data conditions would it?

---

## Lab 7: Pivot Practice

```sql
CREATE TABLE IF NOT EXISTS main.lab17_sales (region STRING, quarter STRING, amount DOUBLE);
INSERT INTO main.lab17_sales VALUES
  ('US', 'Q1', 100), ('US', 'Q2', 150), ('EU', 'Q1', 80), ('EU', 'Q2', 90);

SELECT * FROM main.lab17_sales
PIVOT (SUM(amount) FOR quarter IN ('Q1', 'Q2'));
```

### Questions to Answer
- [ ] What does the output table look like compared to the input?
- [ ] Write the equivalent using conditional aggregation (`SUM(CASE WHEN quarter = 'Q1' THEN amount END)`) instead of `PIVOT` — which is more portable across SQL engines?
