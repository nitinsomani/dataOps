# Phase 2: Apache Spark Core & PySpark — Cheat Sheet

---

## Execution Hierarchy

```
Application → Job (1 per action) → Stages (split at shuffle boundaries) → Tasks (1 per partition)
```

## Transformations vs Actions

```
TRANSFORMATIONS (lazy)        ACTIONS (trigger execution)
select, filter, withColumn    show, count, collect, take
groupBy, join, orderBy        write, save, toPandas
repartition, distinct         foreach, first
```

## Narrow vs Wide

```
NARROW (no shuffle)      WIDE (shuffle required)
map, filter, union        groupBy, join, distinct
                           repartition, orderBy
```

## Join Strategy Decision Table

| Left size | Right size | Strategy chosen |
|-----------|------------|-----------------|
| Large | Small (<10MB) | Broadcast Hash Join |
| Large | Large | Sort Merge Join |
| No equi-condition | — | Broadcast Nested Loop (slow) |

```python
from pyspark.sql.functions import broadcast
df.join(broadcast(small_df), "key")
```

## Caching Cheat Sheet

```python
df.cache()                                # MEMORY_AND_DISK
df.persist(StorageLevel.MEMORY_ONLY)
df.unpersist()
```

## AQE Configs

```python
spark.sql.adaptive.enabled = true                     # default on
spark.sql.adaptive.coalescePartitions.enabled = true
spark.sql.adaptive.skewJoin.enabled = true
spark.sql.shuffle.partitions = 200   # default, tune down for small clusters
```

## UDF Performance Ranking (fastest → slowest)

```
1. Built-in Spark SQL functions (Catalyst + Photon optimized)
2. Pandas UDF / vectorized UDF (Arrow-based batch processing)
3. Regular Python (row) UDF — slowest, opaque to optimizer
```

## Debugging Commands

```python
df.explain(True)              # Full plan: parsed/analyzed/optimized/physical
df.rdd.getNumPartitions()     # Check partition count
spark.sparkContext.uiWebUrl   # Spark UI link
df.printSchema()
```

## Spark UI Tabs Quick Reference

```
Jobs        → list of jobs, duration, status
Stages      → shuffle read/write, task duration, skew indicators
Storage     → cached RDDs/DataFrames, memory usage
Executors   → per-executor memory/CPU/GC time
SQL         → query plans for DataFrame/SQL operations
```
