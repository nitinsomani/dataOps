# Phase 11: Data Quality, Testing & Observability — Lab Exercises

---

## Lab 1: DLT Expectations End-to-End

```python
import dlt
from pyspark.sql.functions import col

@dlt.table
def raw_events():
    return spark.createDataFrame([
        (1, 100.0, "US"), (2, -50.0, "EU"), (3, None, "US"), (4, 200.0, None), (5, 300.0, "APAC")
    ], ["id", "amount", "region"])

@dlt.table
@dlt.expect("valid_region", "region IS NOT NULL")
@dlt.expect_or_drop("positive_amount", "amount > 0")
@dlt.expect_or_fail("valid_id", "id IS NOT NULL")
def clean_events():
    return dlt.read("raw_events")
```

Run this as a DLT pipeline.

### Questions to Answer
- [ ] How many rows survived into `clean_events`, and which ones were dropped vs merely flagged?
- [ ] Open the pipeline's Data Quality tab — what pass/fail percentage does each expectation show?

---

## Lab 2: Great Expectations on a Spark DataFrame

```python
%pip install great_expectations
```

```python
import great_expectations as gx

df = spark.createDataFrame(
    [(1, 100.0, "a@x.com"), (2, None, "b@x.com"), (3, -10.0, None)],
    ["id", "amount", "email"]
)

context = gx.get_context()
validator = context.sources.add_spark("spark_src").add_dataframe_asset("orders").get_validator(df=df)

validator.expect_column_values_to_not_be_null("id")
validator.expect_column_values_to_be_between("amount", min_value=0)
validator.expect_column_values_to_not_be_null("email")

results = validator.validate()
print(results.success)
print(results)
```

### Questions to Answer
- [ ] Which expectations failed, and for how many rows?
- [ ] Generate Data Docs (`context.build_data_docs()`) — what does the HTML report show?

---

## Lab 3: Freshness Check

```python
from pyspark.sql.functions import current_timestamp, col

spark.sql("""
CREATE TABLE IF NOT EXISTS main.lab11_bronze (id INT, _ingest_ts TIMESTAMP)
""")
spark.sql("INSERT INTO main.lab11_bronze VALUES (1, current_timestamp())")

result = spark.sql("""
SELECT MAX(_ingest_ts) AS last_load,
       datediff(minute, MAX(_ingest_ts), current_timestamp()) AS minutes_stale
FROM main.lab11_bronze
""").collect()[0]

print(result)
assert result["minutes_stale"] < 60, "Data is stale!"
```

### Questions to Answer
- [ ] What happens to `minutes_stale` if you don't insert new data for a while and re-run the check?
- [ ] Wire this assertion into a Databricks Job task that fails/alerts if the table is stale — what task type would you use?

---

## Lab 4: Volume Anomaly Detection

```python
import random
from pyspark.sql.functions import lit

# Simulate 14 days of "normal" load counts, then one anomalous day
history = [(f"2026-09-{i:02d}", random.randint(950, 1050)) for i in range(1, 15)]
history.append(("2026-09-15", 200))  # anomaly: much lower than usual

hist_df = spark.createDataFrame(history, ["load_date", "row_count"])
hist_df.createOrReplaceTempView("load_history")

spark.sql("""
SELECT load_date, row_count,
       AVG(row_count) OVER (ORDER BY load_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING) AS rolling_avg,
       row_count / AVG(row_count) OVER (ORDER BY load_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING) AS ratio
FROM load_history
ORDER BY load_date
""").show()
```

### Questions to Answer
- [ ] What ratio value does the anomalous day show relative to its rolling average?
- [ ] What threshold would you set to reliably flag this anomaly without generating too many false positives on normal daily variance?

---

## Lab 5: Set Up a Databricks SQL Alert

1. In Databricks SQL, write a query: `SELECT COUNT(*) AS row_count FROM main.lab11_bronze WHERE _ingest_ts > current_timestamp() - INTERVAL 1 DAY`.
2. Save it, then create an **Alert** on this query with a condition: `row_count < 1`.
3. Configure a notification destination (email).

### Questions to Answer
- [ ] What schedule options are available for how often the alert query re-runs?
- [ ] What's the difference between this SQL Alert approach and a DLT expectation for catching the same kind of issue?

---

## Lab 6: Explore System Tables for Observability

```sql
SELECT * FROM system.lakeflow.job_run_timeline ORDER BY period_start_time DESC LIMIT 10;
SELECT * FROM system.query.history WHERE total_duration_ms > 30000 ORDER BY total_duration_ms DESC LIMIT 10;
```

### Questions to Answer
- [ ] What's the longest-running query in your workspace in the last query history window?
- [ ] Design a query that computes job failure rate (%) per job over the last 7 days using `system.lakeflow.job_run_timeline`.
