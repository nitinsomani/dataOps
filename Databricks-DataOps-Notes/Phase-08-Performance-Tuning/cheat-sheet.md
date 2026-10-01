# Phase 8: Performance Tuning & Optimization — Cheat Sheet

---

## Diagnostic Order (When Something Is Slow)

```
1. Check for shuffle/skew   (Spark UI → Stages: uneven task duration?)
2. Check for small files    (DESCRIBE DETAIL → numFiles, avg size)
3. Check for spill           (Spark UI → Executors: spill to disk?)
4. Check data skipping       (df.explain → PushedFilters, file pruning)
5. Check stats freshness     (ANALYZE TABLE ... COMPUTE STATISTICS)
```

## Photon

```
Vectorized C++ engine, replaces Tungsten for SQL/DataFrame ops
Enable per cluster/warehouse → higher DBU rate, usually net cheaper due to speed
Falls back to standard Spark for unsupported ops (mixed execution normal)
```

## File & Clustering Maintenance

```sql
OPTIMIZE t;                          -- bin-pack small files (~1GB target)
OPTIMIZE t ZORDER BY (col);          -- legacy data-skipping colocation
CREATE TABLE t (...) CLUSTER BY (col);  -- Liquid Clustering (modern default)
ALTER TABLE t SET TBLPROPERTIES (delta.autoOptimize.optimizeWrite = true, delta.autoOptimize.autoCompact = true);
```

## Caching Layers

```
.cache() / persist()   → Spark in-memory materialization, session-scoped
Delta/Disk Cache        → cluster-local SSD cache of remote files, transparent
Databricks SQL result cache → caches identical repeated query results
```

## Key Spark Configs

```python
spark.sql.autoBroadcastJoinThreshold   # default 10MB
spark.sql.shuffle.partitions           # default 200
spark.sql.adaptive.enabled             # default true (AQE)
spark.sql.adaptive.coalescePartitions.enabled
spark.sql.adaptive.skewJoin.enabled
```

## Query-Level Best Practices

```
[ ] Filter early (predicate pushdown)
[ ] SELECT only needed columns (column pruning)
[ ] Avoid collect() on large data
[ ] Avoid unnecessary distinct()/orderBy() before aggregation
[ ] Repartition before writes to control output file count
[ ] Broadcast small dimension tables explicitly when in doubt
```

## Stats Refresh

```sql
ANALYZE TABLE t COMPUTE STATISTICS FOR ALL COLUMNS;
```

## Cost-Performance Cheat Table

| Lever | Perf | Cost |
|-------|------|------|
| Photon | ↑↑ | usually ↓ net |
| More workers | ↑ (to a point) | ↑ |
| Spot instances | = | ↓↓ |
| Serverless SQL warehouse | ↑ cold start | pay-per-use |
