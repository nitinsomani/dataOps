# Phase 2: Apache Spark Core & PySpark — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ Explain Spark's architecture — Driver, Executors, Jobs/Stages/Tasks.

**Answer:**
The **Driver** runs the main program, builds a logical DAG of transformations, and splits it into a physical execution plan. Each **action** (like `.count()` or `.write()`) triggers a **Job**. Spark splits a job into **Stages** at shuffle boundaries — operations that don't require moving data across the network (narrow transformations) get pipelined into the same stage. Each stage runs many **Tasks** in parallel, one task per data partition, executed by **Executors** (JVM processes on worker nodes) that hold cached data and run tasks in threads.

---

## Q2. ⭐ What's the difference between transformations and actions? Why does laziness matter?

**Answer:**
Transformations (`filter`, `select`, `join`, `groupBy`) build up a logical plan but don't execute anything — they're lazy. Actions (`show`, `count`, `write`, `collect`) trigger execution of the accumulated plan. This laziness lets Catalyst see the *entire* chain of operations before running anything, enabling optimizations like predicate pushdown (filtering as early as possible, even before reading unnecessary data) and column pruning — optimizations that wouldn't be possible if each line executed immediately like in pandas.

---

## Q3. ⭐ What is a shuffle, and why is it expensive? How do you minimize it?

**Answer:**
A shuffle is the redistribution of data across the cluster — required whenever a wide transformation (`groupBy`, `join`, `repartition`, `distinct`) needs data with the same key to end up on the same partition/executor. It involves writing intermediate data to disk, transferring it over the network, and re-reading it — making it by far the most expensive operation in Spark.

To minimize shuffles: use broadcast joins for small tables (avoids shuffling the large side), filter/aggregate data before joining to reduce volume, avoid unnecessary `repartition()` calls, tune `spark.sql.shuffle.partitions` to match data volume/cluster size, and rely on AQE to dynamically coalesce small shuffle partitions.

---

## Q4. What is data skew and how do you handle it?

**Answer:**
Data skew occurs when one or a few partition keys have disproportionately more rows than others (e.g., one `customer_id` accounts for 40% of all rows). This causes one task to take dramatically longer than its peers — a "straggler" — while other executors sit idle, hurting overall job time.

Solutions: **salting** the skewed key (append a random suffix to spread it across more partitions, then aggregate in two phases), enabling **AQE skew join optimization** (Spark automatically detects and splits skewed partitions at runtime), using **broadcast joins** if the skew is on a join where one side is small enough to broadcast, or isolating and processing the skewed keys separately from the rest.

---

## Q5. ⭐ Explain the Catalyst optimizer and Tungsten execution engine.

**Answer:**
Catalyst is Spark SQL's rule- and cost-based query optimizer. It processes a query through four phases: **Analysis** (resolve column/table references), **Logical Optimization** (rule-based rewrites like predicate pushdown and constant folding), **Physical Planning** (generate candidate physical plans and pick the cheapest via a cost model — e.g., deciding broadcast vs sort-merge join), and **Code Generation** (compile the chosen plan into JVM bytecode directly — "whole-stage codegen").

Tungsten is the underlying execution engine that manages memory off-heap to avoid JVM garbage-collection pauses, uses a compact binary row format for cache efficiency, and supports vectorized processing. On Databricks, **Photon** further replaces parts of this execution path with a native, vectorized C++ engine for large speedups on SQL/DataFrame workloads.

---

## Q6. When would you choose a broadcast join over a sort-merge join, and how do you force one?

**Answer:**
Broadcast join is ideal when one side of the join is small enough to fit comfortably in executor memory (default threshold 10MB, configurable via `spark.sql.autoBroadcastJoinThreshold`) — it avoids shuffling the large table entirely by copying the small table to every executor. Sort-merge join is the fallback for large-large joins where neither side can be broadcast — both sides get shuffled and sorted by the join key, then merged, which is more expensive but scales to arbitrarily large data on both sides.

You can force it explicitly: `large_df.join(broadcast(small_df), "key")`. AQE can also *automatically* convert a planned sort-merge join into a broadcast join at runtime if actual statistics show one side is small.

---

## Q7. What is Adaptive Query Execution (AQE) and what problems does it solve?

**Answer:**
AQE re-optimizes the query plan mid-execution using actual runtime statistics rather than relying solely on the optimizer's pre-execution estimates (which can be badly wrong, especially after complex filters/joins). It solves three main problems: (1) **too many small shuffle partitions** — AQE dynamically coalesces them to reduce task overhead; (2) **suboptimal join strategy** — AQE can switch a sort-merge join to a broadcast join at runtime if actual data turns out smaller than estimated; (3) **skewed joins** — AQE detects disproportionately large partitions and splits them into smaller sub-tasks automatically. It's enabled by default in modern Spark/DBR.

---

## Q8. Why should you avoid Python UDFs when built-in functions exist?

**Answer:**
Regular (row-at-a-time) Python UDFs require serializing data from the JVM to a separate Python process and back for every row — this serialization overhead, combined with the fact that Catalyst treats UDFs as an opaque black box (it can't push down predicates through them or otherwise optimize around them), makes them dramatically slower than native Spark SQL functions. When a UDF is unavoidable, prefer **Pandas UDFs** (vectorized, using Apache Arrow for efficient batch serialization) over standard row UDFs — but the first choice should always be checking if `pyspark.sql.functions` already has a built-in equivalent.

---

## Q9. How would you debug a Spark job that's running much slower than expected?

**Answer:**
Start with the **Spark UI**: check the Stages tab for tasks with unusually long duration (skew indicator), check shuffle read/write sizes for unexpectedly large data movement, and check the Executors tab for GC time or memory spill indicators. Use `df.explain(True)` to inspect the physical plan and confirm the join strategy/predicate pushdown is happening as expected. Common root causes: data skew, missing broadcast join opportunities, too many/few shuffle partitions, unnecessary caching causing memory pressure, or small-file problems on the storage layer causing excessive task overhead.
