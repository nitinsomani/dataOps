# Phase 12: Streaming & Real-Time Data Pipelines — Cheat Sheet

---

## Batch vs Streaming Code Mirror

```
Batch:      spark.read...                  df.write...
Streaming:  spark.readStream...            df.writeStream...
```

## Output Modes

```
Append    → only new rows (default; simple transforms, no aggregation without watermark)
Complete  → full result table every trigger (aggregations, small cardinality)
Update    → only changed rows since last trigger
```

## Checkpointing Rules

```
[ ] One checkpoint location per streaming query — never share
[ ] Checkpoint stores offsets + state → enables exactly-once + safe restart
[ ] Major logic changes (e.g., new agg key) may invalidate checkpoint
```

## Watermarking

```python
.withWatermark("event_time", "10 minutes")
```
```
Bounds state memory by allowing late data beyond threshold to be dropped
Tighter watermark → less state, more dropped late data
Looser watermark  → more state, fewer dropped events
```

## Windowing Types

```
Tumbling  → window("event_time", "5 minutes")               fixed, non-overlapping
Sliding   → window("event_time", "10 minutes", "5 minutes")  overlapping
Session   → gap-based, dynamic per-key (e.g., 30 min inactivity)
```

## Joins

```
Stream-static  → enrich stream with reference/dimension data
Stream-stream  → requires watermark on BOTH sides (bounds buffering for unmatched rows)
```

## Kafka Source Skeleton

```python
spark.readStream.format("kafka")
  .option("kafka.bootstrap.servers", "...")
  .option("subscribe", "topic")
  .option("startingOffsets", "latest")  # or "earliest"
  .load()
```

## Trigger Types

```
processingTime="30 seconds"  → micro-batch every N
availableNow=True             → process all available, then stop (batch-like, Phase 4)
continuous="1 second"          → experimental low-latency, limited operator support
```

## Monitoring

```python
query.lastProgress     # input/processing rate, batch duration, state size
query.recentProgress   # history of recent batches
```
Watch: input rate > processing rate → falling behind → scale up or optimize.
