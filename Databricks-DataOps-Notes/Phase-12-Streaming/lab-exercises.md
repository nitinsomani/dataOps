# Phase 12: Streaming & Real-Time Data Pipelines — Lab Exercises

> Run in a Databricks notebook. Simulate streaming sources using rate/file sources to avoid needing a real Kafka cluster.

---

## Lab 1: Your First Streaming Query (Rate Source)

```python
rate_df = spark.readStream.format("rate").option("rowsPerSecond", 5).load()

query = (rate_df.writeStream
    .format("memory")
    .queryName("rate_test")
    .outputMode("append")
    .start())

import time
time.sleep(10)
spark.sql("SELECT * FROM rate_test ORDER BY timestamp DESC LIMIT 5").show()
query.stop()
```

### Questions to Answer
- [ ] What columns does the `rate` source produce by default?
- [ ] Inspect `query.lastProgress` — what's reported as the input rows per second?

---

## Lab 2: Output Modes Comparison

```python
rate_df = spark.readStream.format("rate").option("rowsPerSecond", 10).load()
counts = rate_df.groupBy((col("value") % 5).alias("bucket")).count()

q_complete = (counts.writeStream.format("memory").queryName("complete_test")
    .outputMode("complete").start())

import time
time.sleep(8)
spark.sql("SELECT * FROM complete_test ORDER BY bucket").show()
q_complete.stop()
```

### Questions to Answer
- [ ] Try switching `outputMode` to `"update"` — how does the output differ from `"complete"`?
- [ ] Try `"append"` on this aggregation without a watermark — what error occurs?

---

## Lab 3: Watermarking and Windowed Aggregation

```python
from pyspark.sql.functions import expr, window

events = (spark.readStream.format("rate").option("rowsPerSecond", 20).load()
    .withColumn("event_time", col("timestamp"))
    .withColumn("category", (col("value") % 3).cast("string")))

windowed = (events
    .withWatermark("event_time", "30 seconds")
    .groupBy(window("event_time", "10 seconds"), "category")
    .count())

query = (windowed.writeStream.format("memory").queryName("windowed_test")
    .outputMode("append").start())

import time
time.sleep(30)
spark.sql("SELECT * FROM windowed_test ORDER BY window DESC").show(truncate=False)
query.stop()
```

### Questions to Answer
- [ ] Why does `outputMode("append")` work here but not in Lab 2 without a watermark?
- [ ] What happens to the state store size over time — check via the Spark UI's Structured Streaming tab while this runs longer.

---

## Lab 4: Auto Loader as a Streaming Source (ties to Phase 4)

```python
dbutils.fs.mkdirs("/tmp/lab12/stream_input")

def write_event_batch(n):
    import json
    rows = [{"id": i, "value": i * 2} for i in range(n)]
    dbutils.fs.put(f"/tmp/lab12/stream_input/batch_{n}.json",
                    "\n".join(json.dumps(r) for r in rows), overwrite=True)

write_event_batch(1)

stream = (spark.readStream.format("cloudFiles")
    .option("cloudFiles.format", "json")
    .option("cloudFiles.schemaLocation", "/tmp/lab12/schema")
    .load("/tmp/lab12/stream_input"))

query = (stream.writeStream.format("delta")
    .option("checkpointLocation", "/tmp/lab12/checkpoint")
    .trigger(processingTime="5 seconds")
    .toTable("main.lab12_stream_output"))

import time
time.sleep(10)
write_event_batch(2)
time.sleep(10)
spark.sql("SELECT COUNT(*) FROM main.lab12_stream_output").show()
query.stop()
```

### Questions to Answer
- [ ] Did the table pick up the second batch automatically without restarting the query?
- [ ] Change the trigger to `availableNow=True` and re-run as a fresh query with a new checkpoint — how does the execution behavior differ (does it stay running or stop)?

---

## Lab 5: Stream-Static Join

```python
dim_df = spark.createDataFrame([(0, "Category A"), (1, "Category B"), (2, "Category C")], ["cat_id", "cat_name"])

stream_df = (spark.readStream.format("rate").option("rowsPerSecond", 5).load()
    .withColumn("cat_id", (col("value") % 3)))

joined = stream_df.join(dim_df, "cat_id")

query = (joined.writeStream.format("memory").queryName("joined_test").outputMode("append").start())
import time
time.sleep(8)
spark.sql("SELECT * FROM joined_test LIMIT 10").show()
query.stop()
```

### Questions to Answer
- [ ] Did the join correctly enrich the streaming rows with the static dimension names?
- [ ] What would change if `dim_df` were itself read via `readStream` from a Delta table instead of a static DataFrame?

---

## Lab 6: Checkpoint Recovery Simulation

1. Start the Lab 4 streaming query, let it process batch 1, then stop it (simulate a failure by not calling `.stop()` gracefully — just interrupt the cell).
2. Restart the exact same streaming query code (same checkpoint location).
3. Add a new batch of data and confirm the query resumes correctly.

### Questions to Answer
- [ ] Did the restarted query reprocess batch 1, or correctly skip straight to new data?
- [ ] What would happen if you pointed a *different* streaming query definition at the same checkpoint location — is this safe?
