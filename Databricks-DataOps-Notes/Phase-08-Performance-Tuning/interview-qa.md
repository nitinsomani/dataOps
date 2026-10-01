# Phase 8: Performance Tuning & Optimization — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ A Spark job that used to take 10 minutes now takes 2 hours. How do you approach debugging it?

**Answer:**
I'd start with the Spark UI's Stages tab to check for **skew** (a few tasks taking dramatically longer than the rest) and unusual **shuffle read/write volumes**. Next, the Executors tab to check for **spill to disk** (indicates memory pressure — data larger than available executor memory) and excessive GC time. I'd run `df.explain(True)` on the key transformations to confirm the join strategy hasn't silently changed (e.g., a broadcast join became a sort-merge join because a "small" table grew past the broadcast threshold) and check whether `PushedFilters`/predicate pushdown is still happening. I'd also check if underlying table statistics are stale (`ANALYZE TABLE`) — bad estimates can cause the optimizer to pick a poor plan — and check for the small-files problem if this reads from a frequently-appended Delta table (`DESCRIBE DETAIL`). Only after isolating the root cause would I apply a fix (repartitioning, forcing broadcast, running OPTIMIZE, tuning shuffle partitions).

---

## Q2. ⭐ What is Photon and how does it improve performance?

**Answer:**
Photon is Databricks' native, vectorized query execution engine written in C++ that replaces parts of Spark's default JVM-based Tungsten execution for SQL and DataFrame operations. Instead of processing rows one at a time in the JVM, Photon processes batches of rows using CPU vectorized (SIMD) instructions, giving large speedups on scans, filters, joins, and aggregations — especially over Parquet/Delta. It's enabled per cluster or SQL warehouse, increases the DBU rate, but frequently reduces total cost because the dramatic runtime reduction outweighs the higher per-hour rate. Photon transparently falls back to standard Spark execution for operations it doesn't yet support, so a single query can have mixed Photon/non-Photon execution.

---

## Q3. Explain data skipping and how Z-Order/Liquid Clustering improve it.

**Answer:**
Delta tracks min/max statistics per file for a subset of columns; when a query filters on those columns, Spark can skip reading entire files whose min/max range can't possibly match the filter — this is "data skipping" and it's essentially free once the stats exist. Z-Order physically reorganizes data within files so that rows with similar values in the Z-Ordered columns end up co-located in the same, fewer files — making data skipping dramatically more effective for filters on those columns, since instead of matching rows being scattered across every file, they cluster into a small subset. Liquid Clustering (`CLUSTER BY`) is the newer approach that maintains this clustering incrementally as data is written, without requiring full-table rewrites or being locked into a fixed partition scheme — generally preferred for new tables, especially when query patterns or clustering key cardinality may evolve over time.

---

## Q4. When would you NOT want to use traditional Hive-style partitioning on a Delta table?

**Answer:**
Avoid it when the partition column is high-cardinality (creates too many small partitions/files, hurting both write and read performance) or when it doesn't actually align with common query filter patterns (partitioning gives you pruning only if queries filter on the partition column — otherwise it's pure overhead with no benefit). It's also problematic when the natural partition key changes in relative importance over time, since repartitioning an existing large table requires a costly full rewrite. In most new designs I'd default to Liquid Clustering instead, reserving traditional partitioning for cases where you specifically need partition-level operational behavior — e.g., fast partition-level deletes for a retention/compliance policy.

---

## Q5. ⭐ What's the difference between `.cache()` and the Delta/Disk cache, and when would you use each?

**Answer:**
`.cache()`/`.persist()` materializes the *result of a specific DataFrame computation* in memory (or memory+disk), scoped to the current Spark session — useful when you know a particular derived DataFrame will be reused multiple times in the same job/session. The Delta Cache (a.k.a. Disk Cache) operates at a lower level — it transparently caches raw remote Parquet/Delta file bytes on the cluster's local SSD storage, persisting across different queries in the same cluster session without any code change, which is especially valuable for SQL Warehouses serving many repeated/similar BI queries against the same underlying tables. They solve different problems and can be used together; the key risk with `.cache()` specifically is over-caching causing memory pressure and eviction thrashing if you cache things that aren't actually reused.

---

## Q6. How would you decide whether a job's shuffle partition count needs tuning, given AQE is enabled?

**Answer:**
AQE's `coalescePartitions` feature already merges overly-small shuffle partitions at runtime, reducing (but not eliminating) the need for manual tuning of `spark.sql.shuffle.partitions`. I'd still check the Spark UI Stages tab for the shuffle stage: if there are thousands of tiny tasks completing in milliseconds, that indicates over-partitioning even after AQE coalescing (may need to lower the initial partition count or increase the coalescing target size); if there are very few, very large/slow tasks, that suggests under-partitioning or skew that AQE's skew-join handling isn't fully resolving. Generally I treat 200 (the default) as a starting point to validate against actual data volume and cluster core count, not a value to leave unquestioned for every workload size.

---

## Q7. What are Optimized Writes and Auto Compaction, and why would you enable them at the table level instead of relying only on scheduled `OPTIMIZE`?

**Answer:**
`delta.autoOptimize.optimizeWrite` adjusts the number of output files during the write itself to produce better-sized files (reducing an extra shuffle-like step at write time to target a healthier file size), and `delta.autoOptimize.autoCompact` runs a lightweight compaction pass automatically after writes that produced small files — both incur a small extra cost/latency on each write, in exchange for **not** accumulating a large small-files backlog between scheduled maintenance windows. This matters most for tables receiving frequent small writes (e.g., streaming ingestion, frequent MERGE operations) where waiting for a nightly scheduled `OPTIMIZE` job would mean queries suffer degraded performance for hours in between maintenance runs.

---

## Q8. How do you reason about the cost-performance tradeoff when recommending Photon or more powerful compute to a team?

**Answer:**
I'd frame it in terms of total cost, not just DBU rate: Photon and larger clusters cost more per hour, but if they cut job runtime significantly, the **total** dollar cost (hours × rate) can actually decrease, especially for compute-intensive SQL/DataFrame-heavy workloads where Photon's speedup is largest. I'd validate this empirically — run a representative workload with and without the change, compare total job cost (not just wall-clock time) using the cluster's DBU and cloud VM cost — rather than assuming a "faster = more expensive" default. For workloads that are already fast/small or dominated by non-Photon-accelerable operations (e.g., heavy Python UDF usage), the higher Photon DBU rate might not pay for itself, and the recommendation would differ.
