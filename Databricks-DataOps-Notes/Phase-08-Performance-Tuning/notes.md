# Phase 8: Performance Tuning & Optimization — Detailed Notes

> **Goal**: This is where "it works" becomes "it works fast and cheaply" — a core differentiator for senior DataOps roles.

---

## 1. Photon — Databricks' Native Execution Engine

- Photon is a **vectorized query engine written in C++** that replaces parts of Spark's JVM-based execution (Tungsten) for SQL and DataFrame operations — processes batches of rows using CPU SIMD instructions instead of row-at-a-time JVM execution.
- Speeds up: scans, filters, aggregations, joins, and writes — especially on Parquet/Delta.
- Enabled per-cluster/SQL warehouse (higher DBU rate, but often net cheaper due to dramatically reduced runtime).
- Falls back to standard Spark execution automatically for operations Photon doesn't yet support (e.g., some UDFs) — mixed execution within the same query is normal.

---

## 2. File Sizing & the Small Files Problem (recap + tuning specifics)

```sql
OPTIMIZE catalog.schema.table;
```
- Target file size default ~1GB (tunable via `delta.targetFileSize`).
- **Auto-compaction** and **Optimized Writes** (`delta.autoOptimize.autoCompact`, `delta.autoOptimize.optimizeWrite`) can be enabled per-table to automatically manage file sizes as data is written, reducing the need for scheduled manual `OPTIMIZE` runs — trades a small write-time overhead for consistently well-sized files.
- Too few large files hurts parallelism (not enough tasks to use the cluster); too many small files hurts overhead (task scheduling, file-open costs) — aim for files sized so that partition count ≈ available cores × small multiplier.

---

## 3. Data Skipping, Z-Order & Liquid Clustering

- Delta stores **min/max statistics** per file for the first N columns (default 32) — enabling data skipping: queries filtering on those columns can skip entire files without reading them.
- **Z-Order** improves data skipping effectiveness by physically co-locating rows with similar values across fewer files (only useful on the columns actually filtered).
- **Liquid Clustering** (`CLUSTER BY`) is the modern recommended replacement: incremental clustering maintained automatically as data is written/optimized, without needing full-table rewrites or a rigid partition + Z-Order combination — better for tables with evolving query patterns or clustering keys with high cardinality/skew.

```sql
CREATE TABLE t (id INT, region STRING, ts TIMESTAMP) CLUSTER BY (region, id);
OPTIMIZE t;   -- clustering maintenance still runs via OPTIMIZE
```

---

## 4. Partitioning — When (Not) to Use It

- Traditional Hive-style partitioning (`PARTITIONED BY (date)`) physically splits data into separate directories per partition value.
- Good for low-cardinality, coarse-grained filtering (e.g., date-based retention/deletion, partition-level compliance deletes).
- Bad when: high-cardinality partition columns (too many small partitions/files), or partitioning doesn't match actual query filter patterns (no pruning benefit, only overhead).
- **Rule of thumb**: for new tables, prefer **Liquid Clustering** over traditional partitioning unless you have a specific operational need for partition-level operations (e.g., fast partition-level deletes for retention policies).

---

## 5. Caching Strategies

```python
df.cache()                       # Spark in-memory cache, session-scoped
spark.sql("CACHE SELECT * FROM t")  # SQL cache
```
- **Delta Cache / Disk Cache** (cluster-local SSD cache of remote Parquet/Delta files): automatically caches recently-read data on local cluster storage — transparent, persists across queries in the same cluster session, especially valuable on SQL Warehouses for repeated BI queries.
- Difference from `.cache()`: Delta Cache operates at the file/byte level transparently; `.cache()` materializes a specific DataFrame's computed result in memory — different layers, can be used together.
- Cache only what's genuinely reused — over-caching causes memory pressure and eviction thrashing.

---

## 6. Join & Shuffle Tuning (ties back to Phase 2)

- Tune `spark.sql.autoBroadcastJoinThreshold` up/down based on cluster memory and typical small-table sizes.
- Tune `spark.sql.shuffle.partitions` — default 200 is often wrong for both very small and very large clusters; AQE's `coalescePartitions` reduces the need for hand-tuning but understanding the default still matters.
- Watch for **spill** (data too large for memory, spills to disk) in the Spark UI — indicates under-provisioned executor memory or a need to repartition/filter earlier.

---

## 7. Query & Code-Level Optimization

- **Predicate pushdown**: filter early, filter on columns that support data skipping — let Catalyst push filters as close to the data source as possible.
- **Column pruning**: `SELECT` only needed columns — Parquet's columnar format means unread columns cost nothing to skip, but only if the engine knows to skip them.
- **Avoid `collect()`** on large DataFrames — pulls all data to the driver, risking OOM; use `.write` or aggregate first.
- **Avoid wide transformations you don't need** — e.g., an unnecessary `distinct()` or `orderBy()` before a final aggregate forces an extra shuffle.
- **Repartition strategically before writes** — controlling output file count directly (`df.repartition(N).write...`) instead of relying purely on default parallelism, especially for partitioned writes.

---

## 8. Serverless SQL Warehouses & Auto-Scaling

- SQL Warehouses (Databricks SQL) autoscale clusters of executors based on concurrent query load, and **serverless** warehouses eliminate cold-start time almost entirely (sub-second warehouse "resume").
- **Query result caching**: Databricks SQL automatically caches identical repeated query results for a period — free performance win for dashboards with repeated refresh queries.

---

## 9. Monitoring for Performance Issues

- **Spark UI**: Stages (skew, shuffle read/write size), Executors (GC time, spill), SQL tab (query plan + actual vs estimated row counts — large mismatches indicate stale table statistics).
- **`ANALYZE TABLE ... COMPUTE STATISTICS`**: refresh table statistics used by the cost-based optimizer — stale stats can lead to poor join strategy selection.
- **Query Profile** (Databricks SQL): visual breakdown of time spent per operator in a SQL query, including whether Photon was used for each step.

```sql
ANALYZE TABLE catalog.schema.table COMPUTE STATISTICS FOR ALL COLUMNS;
```

---

## 10. Cost-Performance Tradeoffs

| Lever | Performance impact | Cost impact |
|-------|---------------------|-------------|
| Enable Photon | Faster (often 2-10x) | Higher DBU rate, usually net cheaper |
| More/larger workers | Faster (to a point) | Higher $/hour |
| Aggressive OPTIMIZE/Z-Order schedule | Faster reads | Extra compute for maintenance jobs |
| Spot/preemptible instances | No perf impact, risk of interruption | Much cheaper |
| Serverless SQL warehouse | Faster cold start, autoscale | Pay-per-use, can be cheaper for spiky workloads |

---

## 11. Key Takeaways for DataOps

- Most performance problems trace back to: **shuffles, small files, skew, or missing data-skipping** — diagnose in that order.
- Photon + Liquid Clustering + Optimized Writes are the "modern defaults" — reach for these before hand-tuning shuffle partition counts.
- Always validate optimization changes with **before/after Spark UI or Query Profile comparisons** — don't guess, measure.
- Performance tuning is inseparable from cost tuning on Databricks — always frame recommendations in terms of both.
