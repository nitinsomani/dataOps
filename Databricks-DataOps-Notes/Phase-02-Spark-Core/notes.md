# Phase 2: Apache Spark Core & PySpark — Detailed Notes

> **Goal**: Understand Spark's execution model deeply enough to reason about performance, debug failures, and answer "why is my job slow" questions.

---

## 1. What is Apache Spark?

Spark is a **distributed, in-memory processing engine** for large-scale data processing. It generalizes the MapReduce model with a richer set of operations (map, filter, join, aggregate) and keeps intermediate data in memory instead of writing to disk between every step — this is why it's typically 10-100x faster than classic Hadoop MapReduce for iterative workloads.

### Core APIs
- **RDD (Resilient Distributed Dataset)** — the original low-level API: an immutable, partitioned collection of objects, with lineage-based fault tolerance. Rarely used directly today.
- **DataFrame** — a distributed table with named columns and a schema, built on top of RDDs, optimized via Catalyst. This is the primary API used today (`pyspark.sql.DataFrame`).
- **Dataset** — typed DataFrame (Scala/Java only, not available in Python).
- **Spark SQL** — write SQL directly against DataFrames registered as views/tables.

---

## 2. Spark Architecture — Driver, Executors, Cluster Manager

```
┌───────────────────────────────────────────────────────────┐
│                          DRIVER                             │
│  - Runs your main program / SparkContext                    │
│  - Builds the DAG (Directed Acyclic Graph) of transformations│
│  - Splits DAG into stages and tasks                          │
│  - Schedules tasks onto executors, collects results          │
└───────────────────────────────────────────────────────────┘
              │                     │                    │
              ▼                     ▼                    ▼
       ┌────────────┐        ┌────────────┐       ┌────────────┐
       │ Executor 1 │        │ Executor 2 │  ...  │ Executor N │
       │ (JVM proc) │        │ (JVM proc) │       │ (JVM proc) │
       │ - Tasks     │        │ - Tasks     │       │ - Tasks     │
       │ - Cache     │        │ - Cache     │       │ - Cache     │
       └────────────┘        └────────────┘       └────────────┘
```

- **Cluster Manager**: allocates resources (in Databricks this is handled internally — you don't manage YARN/Mesos/Kubernetes directly, though Databricks on K8s exists).
- **Executor**: a JVM process on a worker node running one or more **tasks** in parallel threads; holds cached data in memory.
- **Task**: the smallest unit of work — one task processes one partition of data.
- **Job → Stages → Tasks**: An **action** (e.g., `.count()`, `.write()`) triggers a **Job**. A job is split into **Stages** at shuffle boundaries. Each stage runs many **Tasks** in parallel (one per partition).

---

## 3. Transformations vs Actions (Lazy Evaluation)

- **Transformations** (`select`, `filter`, `join`, `groupBy`, `withColumn`) are **lazy** — they just build up a logical plan (DAG), nothing executes yet.
- **Actions** (`count`, `collect`, `show`, `write`, `take`) **trigger execution** of the whole accumulated DAG.

```python
df2 = df.filter(df.amount > 100).select("id", "amount")   # lazy, nothing runs
df2.show()                                                  # action → triggers execution
```

**Why this matters**: Spark can optimize the *entire* chain of transformations before running anything (predicate pushdown, column pruning, join reordering) — this is only possible because of laziness.

### Narrow vs Wide Transformations
- **Narrow**: each output partition depends on only one input partition (`map`, `filter`, `union`) — no shuffle needed, can be pipelined within a stage.
- **Wide**: output partitions depend on multiple input partitions (`groupBy`, `join`, `distinct`, `repartition`) — requires a **shuffle** (data movement across the network), which is the most expensive Spark operation and creates a new stage boundary.

---

## 4. Catalyst Optimizer & Tungsten Engine

- **Catalyst** is Spark SQL's query optimizer. It transforms your DataFrame/SQL code through 4 phases:
  1. **Analysis** — resolve column/table references against the catalog
  2. **Logical optimization** — rule-based rewrites (predicate pushdown, constant folding, column pruning)
  3. **Physical planning** — generate multiple physical plans, pick the cheapest using a cost model
  4. **Code generation** — generate Java bytecode directly (whole-stage code generation) for the physical plan
- **Tungsten** is the execution engine underneath — manages memory off-heap (avoiding JVM garbage collection overhead), uses cache-friendly binary data layout, and vectorized CPU operations.
- **Photon** (Databricks-specific) replaces parts of Tungsten's execution with a native C++ vectorized engine, giving large speedups especially for SQL and DataFrame aggregations/joins.

```python
df.explain(True)   # Shows: Parsed → Analyzed → Optimized Logical Plan → Physical Plan
```

---

## 5. Partitioning & Shuffles

- Data is split into **partitions** — the unit of parallelism. Default shuffle partition count: `spark.sql.shuffle.partitions` = **200** (often needs tuning down for smaller clusters, or dynamically handled by AQE).
- **Shuffle** = redistributing data across the cluster (e.g., for a `groupBy` or `join` on a key) — involves disk I/O, network I/O, and serialization. This is the #1 performance bottleneck in Spark jobs.
- **Skew**: when one partition/key has disproportionately more data than others, causing one task to take much longer than the rest (a straggler). Solutions: salting keys, AQE skew join optimization, broadcast joins for small tables.

```python
df.repartition(200)              # full shuffle to N partitions
df.repartition("customer_id")    # shuffle, partitioned by column
df.coalesce(10)                  # merge partitions WITHOUT full shuffle (reduce only)
```

---

## 6. Joins in Spark

| Join Strategy | When used | Notes |
|----------------|-----------|-------|
| **Broadcast Hash Join** | One side is small (< `spark.sql.autoBroadcastJoinThreshold`, default 10MB) | Fastest — small table copied to every executor, no shuffle of the large table |
| **Shuffle Hash Join** | Both sides larger, one side still fits in memory per partition | Shuffles both sides then builds hash table |
| **Sort Merge Join** | Default for large-large joins | Both sides shuffled and sorted by join key, then merged |
| **Broadcast Nested Loop Join** | No equi-join condition | Slow, avoid when possible |

```python
from pyspark.sql.functions import broadcast
result = large_df.join(broadcast(small_df), "customer_id")   # force broadcast join
```

---

## 7. Caching & Persistence

```python
df.cache()                                   # MEMORY_AND_DISK by default
df.persist(StorageLevel.MEMORY_ONLY)
df.unpersist()
```

- Use caching when a DataFrame is **reused multiple times** in the same session (e.g., referenced in 3 different downstream computations).
- Caching is **lazy** too — it only materializes on the first action after `.cache()` is called.
- Overusing cache can cause memory pressure/spills — only cache what's actually reused.

---

## 8. Adaptive Query Execution (AQE)

AQE (enabled by default in modern Spark/DBR) re-optimizes the query plan **at runtime** based on actual data statistics gathered after each stage, instead of relying purely on static estimates:
- **Dynamically coalesces shuffle partitions** — merges small partitions to avoid the "too many tiny tasks" problem.
- **Dynamically switches join strategies** — e.g., converts a sort-merge join to a broadcast join if runtime stats show one side is actually small.
- **Dynamically optimizes skew joins** — splits skewed partitions into smaller sub-partitions automatically.

```python
spark.conf.set("spark.sql.adaptive.enabled", "true")               # default true in DBR
spark.conf.set("spark.sql.adaptive.skewJoin.enabled", "true")
```

---

## 9. PySpark vs Pandas — Key Mental Model Shift

| Pandas | PySpark |
|--------|---------|
| Single-machine, eager execution | Distributed, lazy execution |
| Entire data in memory on one node | Data partitioned across cluster |
| `.apply()` runs in-process | UDFs serialize to executors (slower, avoid when built-ins exist) |
| Great for small/medium data | Built for data too big for one machine |

**Pandas API on Spark** (`pyspark.pandas`, formerly Koalas) lets you write pandas-like syntax that executes distributedly — useful for migrating pandas code without a full rewrite.

---

## 10. UDFs — Use Sparingly

```python
from pyspark.sql.functions import udf, pandas_udf
from pyspark.sql.types import IntegerType

@udf(returnType=IntegerType())
def add_one(x):
    return x + 1

# Pandas UDF (vectorized, much faster — uses Apache Arrow for serialization)
@pandas_udf(IntegerType())
def add_one_vectorized(s: pd.Series) -> pd.Series:
    return s + 1
```

- Regular Python UDFs serialize row-by-row between JVM and Python — slow, and **invisible to Catalyst** (can't be optimized/pushed down).
- **Pandas UDFs** (vectorized) use Apache Arrow for efficient batch serialization — much faster than row-at-a-time UDFs.
- **Always prefer built-in Spark SQL functions** (`pyspark.sql.functions`) over UDFs when possible — they run natively in the JVM/Photon and are Catalyst-optimizable.

---

## 11. Key Takeaways for DataOps

- Understand **lazy evaluation** — it explains why errors sometimes show up on `.show()`/`.write()` rather than where you "expect."
- **Shuffles are expensive** — most performance tuning is about minimizing/optimizing them (Phase 8 goes deeper).
- Prefer **DataFrame API + built-in functions** over RDDs and UDFs for performance and optimizer visibility.
- `.explain()` is your best friend for debugging performance issues — learn to read physical plans.
