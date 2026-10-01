# Phase 4: Ingestion, ETL/ELT & Auto Loader — Lab Exercises

> Run in a Databricks notebook. Create a scratch volume/path for raw files first.

---

## Lab 1: Set Up a Landing Zone and Simulate File Arrival

```python
dbutils.fs.mkdirs("/tmp/lab4/raw_orders")

import json, random
def write_batch(batch_num, n=50):
    rows = [{"order_id": batch_num*1000 + i, "amount": round(random.uniform(10, 500), 2),
             "customer_id": random.randint(1, 20)} for i in range(n)]
    path = f"/tmp/lab4/raw_orders/batch_{batch_num}.json"
    dbutils.fs.put(path, "\n".join(json.dumps(r) for r in rows), overwrite=True)

write_batch(1)
```

### Questions to Answer
- [ ] List the files under `/tmp/lab4/raw_orders` — what format are they in?

---

## Lab 2: Auto Loader Batch-Style Ingestion with `availableNow`

```python
bronze_stream = (spark.readStream.format("cloudFiles")
    .option("cloudFiles.format", "json")
    .option("cloudFiles.schemaLocation", "/tmp/lab4/schema/orders")
    .option("cloudFiles.schemaEvolutionMode", "rescue")
    .load("/tmp/lab4/raw_orders"))

(bronze_stream
    .withColumn("_ingest_ts", current_timestamp())
    .writeStream.format("delta")
    .option("checkpointLocation", "/tmp/lab4/checkpoints/orders")
    .trigger(availableNow=True)
    .toTable("main.lab4_bronze_orders"))
```

```python
spark.sql("SELECT * FROM main.lab4_bronze_orders").show()
```

### Questions to Answer
- [ ] How many rows landed in the Bronze table after the first run?
- [ ] Add a second batch (`write_batch(2)`), re-run the same streaming write — did it reprocess batch 1, or only pick up batch 2?

---

## Lab 3: Schema Drift Simulation — `rescue` mode

```python
# Introduce an unexpected field
import json
rows = [{"order_id": 9001, "amount": 42.0, "customer_id": 5, "unexpected_field": "surprise!"}]
dbutils.fs.put("/tmp/lab4/raw_orders/batch_drift.json", "\n".join(json.dumps(r) for r in rows), overwrite=True)

(spark.readStream.format("cloudFiles")
    .option("cloudFiles.format", "json")
    .option("cloudFiles.schemaLocation", "/tmp/lab4/schema/orders")
    .option("cloudFiles.schemaEvolutionMode", "rescue")
    .load("/tmp/lab4/raw_orders")
    .writeStream.format("delta")
    .option("checkpointLocation", "/tmp/lab4/checkpoints/orders")
    .trigger(availableNow=True)
    .toTable("main.lab4_bronze_orders"))

spark.sql("SELECT * FROM main.lab4_bronze_orders WHERE _rescued_data IS NOT NULL").show(truncate=False)
```

### Questions to Answer
- [ ] What does the `_rescued_data` column contain for the drifted row?
- [ ] Re-run with `cloudFiles.schemaEvolutionMode` set to `failOnNewColumns` on a fresh checkpoint — what error occurs?

---

## Lab 4: Building the Silver Layer with Deduplication and Validation

```python
from pyspark.sql.functions import col

bronze_df = spark.table("main.lab4_bronze_orders")

silver_df = (bronze_df
    .dropDuplicates(["order_id"])
    .filter(col("amount") > 0)
    .withColumn("amount", col("amount").cast("decimal(10,2)")))

silver_df.write.format("delta").mode("overwrite").saveAsTable("main.lab4_silver_orders")
spark.sql("SELECT COUNT(*) FROM main.lab4_silver_orders").show()
```

### Questions to Answer
- [ ] How many rows were dropped between Bronze and Silver, and why?
- [ ] What additional validation would you add for a production pipeline (e.g., customer_id must exist in a dimension table)?

---

## Lab 5: MERGE-based Upsert into a Gold/Current-State Table

```python
spark.sql("""
CREATE TABLE IF NOT EXISTS main.lab4_gold_customer_totals (
  customer_id INT, total_amount DECIMAL(12,2), last_updated TIMESTAMP
)
""")

spark.sql("""
MERGE INTO main.lab4_gold_customer_totals t
USING (
  SELECT customer_id, SUM(amount) AS total_amount, current_timestamp() AS last_updated
  FROM main.lab4_silver_orders GROUP BY customer_id
) s
ON t.customer_id = s.customer_id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
""")

spark.sql("SELECT * FROM main.lab4_gold_customer_totals ORDER BY total_amount DESC").show()
```

### Questions to Answer
- [ ] Re-run this MERGE a second time without new data — does the result change (idempotency check)?
- [ ] What would happen if you used `INSERT INTO` instead of `MERGE` and ran it twice?

---

## Lab 6: COPY INTO as an Alternative Pattern

```sql
CREATE TABLE IF NOT EXISTS main.lab4_copyinto_orders (
  order_id BIGINT, amount DOUBLE, customer_id INT
);

COPY INTO main.lab4_copyinto_orders
FROM '/tmp/lab4/raw_orders/'
FILEFORMAT = JSON
FORMAT_OPTIONS ('mergeSchema' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');
```

### Questions to Answer
- [ ] Run the `COPY INTO` statement twice in a row — does it reprocess files it already loaded?
- [ ] When would you pick `COPY INTO` over Auto Loader for a given use case?
