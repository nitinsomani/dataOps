# Phase 12: Streaming & Real-Time Data Pipelines — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ Explain Spark Structured Streaming's core mental model.

**Answer:**
Structured Streaming treats an incoming data stream as an **unbounded table** that continuously grows as new data arrives — you write the same DataFrame transformation code you would for batch processing, and Spark executes it incrementally in repeated micro-batches (or, for a limited operator set, true continuous processing). The key practical difference from batch is using `spark.readStream`/`.writeStream` instead of `spark.read`/`.write`, plus specifying an output mode, a checkpoint location, and a trigger — the transformation logic itself (filters, joins, aggregations) is written identically to batch DataFrame code.

---

## Q2. ⭐ What is watermarking and why is it necessary for streaming aggregations?

**Answer:**
A watermark tells Spark how much delay to tolerate for late-arriving data relative to the maximum event-time seen so far (e.g., `withWatermark("event_time", "10 minutes")` means "don't expect data more than 10 minutes behind the latest event time"). It's necessary because streaming aggregations (especially windowed ones) would otherwise need to retain **unbounded state** in memory forever — any past window could theoretically still receive a late-arriving event, so without a cutoff, memory usage grows without bound. The watermark lets Spark safely finalize and evict state for windows older than the watermark threshold, at the cost of dropping data that arrives even later than that threshold — a deliberate trade-off between memory bounds and completeness.

---

## Q3. What's the difference between Append, Complete, and Update output modes?

**Answer:**
Append mode outputs only new rows added since the last trigger and is the default for simple row-level transformations without aggregation. Complete mode outputs the entire current result table on every trigger — appropriate for aggregations where you want the full up-to-date state each time (works best with bounded/small result cardinality, since the whole table is rewritten every batch). Update mode outputs only the rows that changed since the last trigger, useful for aggregations where you want incremental deltas rather than the whole table repeatedly. Note that Append mode with aggregations specifically requires watermarking, since Spark needs a way to know when a given aggregation result is "final" and safe to emit exactly once rather than being updated again later.

---

## Q4. ⭐ Why must every streaming query have its own dedicated checkpoint location, and what happens if you get this wrong?

**Answer:**
The checkpoint location stores the query's processing progress (which source offsets have been consumed) and any stateful operator state (aggregation/join state) — this is what enables exactly-once processing semantics and safe recovery/restart after a failure or planned restart. If two different streaming queries share the same checkpoint location, their progress tracking and state get corrupted/intermingled, leading to incorrect results, duplicate processing, or the queries failing outright. It's also important to know that significantly changing a query's logic (e.g., changing an aggregation's grouping key) can invalidate compatibility with an existing checkpoint, effectively requiring a fresh checkpoint (and therefore reprocessing behavior determined by the source's retention/replay capability).

---

## Q5. When would you use a stream-stream join versus a stream-static join, and what extra consideration does a stream-stream join require?

**Answer:**
A stream-static join enriches streaming event data with relatively slow-changing reference/dimension data (e.g., joining a stream of orders with a static customer dimension table) — the static side doesn't need its own watermark since it's not itself an unbounded stream. A stream-stream join combines two genuinely unbounded streams (e.g., matching an `orders` stream with a `shipments` stream on order ID) — this requires a watermark on **both** sides, because Spark needs to know how long to buffer rows from each side waiting for a matching partner before giving up and treating them as unmatched, otherwise it would need to buffer every unmatched row from both streams indefinitely.

---

## Q6. What's the practical difference between using `trigger(processingTime="30 seconds")` and `trigger(availableNow=True)`, and when would you pick each?

**Answer:**
`processingTime` runs the query continuously, processing a new micro-batch of whatever data has arrived every N seconds/minutes, for as long as the query/cluster stays running — appropriate for genuinely low-latency, always-on streaming use cases (e.g., real-time dashboards, fraud detection). `availableNow` processes all currently available data and then stops the query automatically — appropriate for scheduled, incremental "batch" jobs (e.g., an hourly Databricks Job using Auto Loader) where you want the efficiency of incremental processing (via checkpointing) without paying for an always-on cluster between runs. The choice generally comes down to whether the business requirement is true real-time processing versus periodic, incremental batch processing.

---

## Q7. How would you monitor a production streaming job to detect if it's falling behind?

**Answer:**
I'd inspect `query.lastProgress`/`query.recentProgress`, specifically comparing the **input rate** (rate at which new data is arriving) against the **processing rate** (rate at which the query is actually consuming/processing it) — if input consistently exceeds processing rate over time, a backlog is building and the stream is falling behind, requiring either more compute resources, code-level optimization (e.g., reducing shuffle in the streaming aggregation), or reducing the batch interval. I'd also monitor state store size in the Structured Streaming tab of the Spark UI for stateful operators (aggregations, stream-stream joins) — an unexpectedly growing state size often points to a watermarking misconfiguration (too loose, or missing entirely) rather than genuine data volume growth.

---

## Q8. How does Kafka integration typically work with Structured Streaming on Databricks, and what does `startingOffsets` control?

**Answer:**
Kafka messages arrive as a DataFrame with binary `key`/`value` columns (plus metadata like topic/partition/offset); typical practice is to cast/parse the `value` column (commonly JSON or Avro, often with a schema registry) into structured columns using `from_json` with an explicit schema. `startingOffsets` controls where a *new* streaming query starts reading from within the topic's retained data: `earliest` reprocesses the full retained history in the topic (useful for a first backfill), while `latest` starts from only new messages published after the query starts (typical for a fresh real-time pipeline that doesn't need historical replay). Once a checkpoint exists, `startingOffsets` is only consulted for a completely new query — restarts use the checkpointed offset instead, which is an important operational distinction to know when debugging "why did my restarted stream reprocess/skip data."
