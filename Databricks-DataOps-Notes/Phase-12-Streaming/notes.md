# Phase 12: Streaming & Real-Time Data Pipelines — Detailed Notes

> **Goal**: Understand Structured Streaming deeply enough to build and operate low-latency pipelines reliably.

---

## 1. Structured Streaming — The Mental Model

Spark Structured Streaming treats a stream as an **unbounded table** that keeps growing — you write the same DataFrame transformations you'd write for batch, and Spark executes them incrementally as new data arrives, in repeated **micro-batches** (or, for some sources, low-latency continuous processing).

```python
stream_df = (spark.readStream.format("delta").table("bronze_events"))
result_df = stream_df.groupBy("region").count()

query = (result_df.writeStream
         .format("delta")
         .outputMode("complete")
         .option("checkpointLocation", "/mnt/checkpoints/region_counts")
         .toTable("gold_region_counts"))
```

**Key insight for interviews**: "The same DataFrame code works for both batch and streaming — the difference is `spark.read` vs `spark.readStream`, and how the write is triggered." This unification is one of Structured Streaming's biggest selling points.

---

## 2. Output Modes

| Mode | Behavior | Use case |
|------|----------|----------|
| **Append** | Only new rows since last trigger are output | Default for simple transformations (filter, map, no aggregation) |
| **Complete** | Entire updated result table is output every trigger | Aggregations without windowing where you want the full current state |
| **Update** | Only rows that changed since last trigger are output | Aggregations where you only want deltas, not the whole table |

- Not all operations support all modes — e.g., `Append` mode with aggregations requires **watermarking** (see below) since Spark needs to know when it's safe to finalize/emit a given aggregation window.

---

## 3. Checkpointing

- Every streaming query needs a **checkpoint location** — stores the query's progress (which offsets/data have been processed) and state (for aggregations/joins), enabling exactly-once processing and safe restart after failure.
- **Never share a checkpoint location between two different streaming queries** — corrupts state and progress tracking.
- Changing the transformation logic significantly (e.g., changing an aggregation key) can invalidate the existing checkpoint, requiring a fresh checkpoint (and thus reprocessing, depending on the source's retention).

---

## 4. Watermarking — Handling Late Data

```python
from pyspark.sql.functions import window

windowed_counts = (stream_df
    .withWatermark("event_time", "10 minutes")
    .groupBy(window("event_time", "5 minutes"), "region")
    .count())
```

- A **watermark** tells Spark: "I don't expect data older than X behind the max event time I've seen so far — it's safe to finalize and drop state for windows older than that."
- Without a watermark, Spark would need to retain **unbounded state** for all historical windows, since a delayed event could theoretically still arrive for any past window — watermarking bounds memory usage by accepting that sufficiently late data will be dropped.
- Trade-off: too tight a watermark drops legitimately (if slightly) late data; too loose a watermark keeps more state in memory longer, increasing resource usage.

---

## 5. Windowing

```python
# Tumbling window (non-overlapping, fixed size)
.groupBy(window("event_time", "5 minutes"))

# Sliding window (overlapping)
.groupBy(window("event_time", "10 minutes", "5 minutes"))
```

- **Tumbling windows**: fixed, non-overlapping intervals (e.g., counts per 5-minute bucket).
- **Sliding windows**: overlapping intervals that advance by a smaller step than their size (e.g., a 10-minute window recomputed every 5 minutes) — used for smoothed/rolling metrics.
- **Session windows**: dynamic windows based on gaps of inactivity per key (e.g., group clickstream events into a "session" that ends after 30 minutes of no activity) — useful for user behavior analytics.

---

## 6. Stream-Stream and Stream-Static Joins

- **Stream-static join**: joining a streaming DataFrame with a static (batch) DataFrame — common for enriching events with reference/dimension data. The static side is re-read according to its own semantics (not incrementally tracked unless it's also a Delta table being read fresh each micro-batch).
- **Stream-stream join**: joining two streaming sources — requires watermarking on both sides so Spark knows how long to buffer unmatched rows waiting for a join partner before giving up.

```python
joined = (orders_stream
    .withWatermark("order_time", "1 hour")
    .join(shipments_stream.withWatermark("ship_time", "1 hour"),
          expr("order_id = shipment_order_id AND ship_time >= order_time"),
          "inner"))
```

---

## 7. Kafka Integration

```python
kafka_df = (spark.readStream.format("kafka")
    .option("kafka.bootstrap.servers", "broker1:9092,broker2:9092")
    .option("subscribe", "orders-topic")
    .option("startingOffsets", "latest")
    .load())

parsed_df = kafka_df.selectExpr("CAST(value AS STRING) as json_str") \
    .select(from_json(col("json_str"), schema).alias("data")).select("data.*")
```

- Kafka messages arrive as `key`/`value` binary columns — you parse `value` (commonly JSON or Avro with a schema registry) into structured columns.
- `startingOffsets`: `earliest` (reprocess full retention) vs `latest` (only new messages from now) — critical setting, especially for first-time deployment vs restart-after-failure semantics.
- Kafka + Structured Streaming + Delta is a very common real-time ingestion pattern: Kafka for the transport/buffer layer, Structured Streaming for processing, Delta for the durable, queryable sink.

---

## 8. Auto Loader as a Streaming Source (recap, ties to Phase 4)

- Auto Loader is itself a Structured Streaming source (`cloudFiles` format) — everything in this phase (output modes, checkpointing, watermarking, triggers) applies equally whether the source is Kafka or cloud file storage.

---

## 9. Trigger Types (recap + streaming-specific nuance)

```python
.trigger(processingTime="30 seconds")   # micro-batch every 30s
.trigger(availableNow=True)             # process all available, then stop (Phase 4 pattern)
.trigger(continuous="1 second")          # experimental low-latency continuous mode (limited operator support)
```

- **Continuous processing mode** offers millisecond-level latency (vs micro-batch's seconds) but supports a much smaller subset of operations and is less commonly used in production compared to micro-batch — most real-time Databricks pipelines use micro-batch with a short `processingTime` rather than true continuous mode.

---

## 10. Monitoring Streaming Queries

```python
query.status                 # {"message": "...", "isDataAvailable": True, "isTriggerActive": True}
query.lastProgress            # detailed metrics: input rate, processing rate, batch duration, state size
query.recentProgress          # history of recent micro-batches
```

- Watch **input rate vs processing rate** — if input consistently exceeds processing rate, the stream is falling behind (backlog growing) and needs more resources or code optimization.
- **State store size** (for streaming aggregations/joins) is visible in the Spark UI's Structured Streaming tab — growing unbounded state indicates a watermarking problem.

---

## 11. Key Takeaways for DataOps

- Structured Streaming's batch/stream code unification (`readStream`/`writeStream` mirroring `read`/`write`) is a key concept to articulate clearly in interviews.
- Watermarking is what makes streaming aggregations operationally feasible — know why it exists and its late-data trade-off.
- Checkpointing correctness (one checkpoint per query, careful with logic changes) is a common real-world operational gotcha.
- Auto Loader + `trigger(availableNow=True)` (Phase 4) blurs the batch/streaming line deliberately — a DataOps engineer should recognize when "streaming" tooling is actually being used for scheduled batch efficiency, vs true low-latency continuous processing (Kafka + short `processingTime` triggers).
