# Phase 2: Apache Spark Core & PySpark — Lab Exercises

> Run these in a Databricks notebook attached to a small cluster (2-4 workers is enough).

---

## Lab 1: Lazy Evaluation in Action

**Objective**: See the difference between transformations and actions.

```python
df = spark.read.csv("/databricks-datasets/samples/population-vs-price/data_geo.csv", header=True, inferSchema=True)

# Build a chain of transformations — notice NOTHING executes yet
step1 = df.filter(df["2014 Population estimate"] > 1000000)
step2 = step1.select("State", "2014 Population estimate")
step3 = step2.orderBy("2014 Population estimate", ascending=False)

print("Transformations built, nothing has run yet!")

# NOW trigger execution
step3.show(5)
```

### Questions to Answer
- [ ] Open the Spark UI (Jobs tab) — how many jobs were triggered? At which line?
- [ ] What would happen if you called `.show()` after each intermediate step instead?

---

## Lab 2: Narrow vs Wide Transformations — Observe Shuffles

```python
df = spark.range(0, 10_000_000).withColumnRenamed("id", "value")

# Narrow transformation - no shuffle
narrow = df.filter(df.value % 2 == 0)
narrow.explain()

# Wide transformation - shuffle required
wide = df.groupBy(df.value % 100).count()
wide.explain()
```

### Questions to Answer
- [ ] In the `.explain()` output for `wide`, find the `Exchange` operator — what does it indicate?
- [ ] Check the Spark UI Stages tab — how many stages did each job create?

---

## Lab 3: Broadcast Join vs Sort-Merge Join

```python
from pyspark.sql.functions import broadcast

large_df = spark.range(0, 5_000_000).withColumnRenamed("id", "key")
small_df = spark.range(0, 100).withColumnRenamed("id", "key").withColumn("label", (col("key")*2))

# Default join - let Spark decide
default_join = large_df.join(small_df, "key")
default_join.explain()

# Force broadcast
broadcast_join = large_df.join(broadcast(small_df), "key")
broadcast_join.explain()
```

### Questions to Answer
- [ ] Does the default join plan already show `BroadcastHashJoin`? Why or why not (check `autoBroadcastJoinThreshold`)?
- [ ] What's the size threshold (in bytes) for automatic broadcasting on your cluster?

---

## Lab 4: Simulate and Fix Data Skew

```python
from pyspark.sql.functions import when, col, rand

# Create heavily skewed data - 90% of rows have key=1
skewed_df = spark.range(0, 2_000_000).withColumn(
    "key", when(rand() < 0.9, 1).otherwise((col("id") % 1000))
)

result = skewed_df.groupBy("key").count()
result.explain()
result.count()  # trigger execution, then check Spark UI Stages tab for task duration skew
```

### Questions to Answer
- [ ] In the Stages tab, find the stage for this groupBy — is task duration highly uneven (one task much slower)?
- [ ] Enable `spark.sql.adaptive.skewJoin.enabled` (default true) — does behavior change for aggregation skew vs join skew?
- [ ] Research: what would "salting" the key look like in code for this scenario?

---

## Lab 5: Caching Impact

```python
import time

df = spark.range(0, 20_000_000).withColumn("value", col("id") * 2)

# Without cache — recomputed 3 times
start = time.time()
df.count()
df.filter(df.value > 100).count()
df.filter(df.value > 1000).count()
print("Without cache:", time.time() - start)

# With cache
df2 = df.cache()
start = time.time()
df2.count()               # materializes cache here
df2.filter(df2.value > 100).count()
df2.filter(df2.value > 1000).count()
print("With cache:", time.time() - start)
df2.unpersist()
```

### Questions to Answer
- [ ] Was the cached version faster on the 2nd and 3rd action? Was the 1st action (which materializes the cache) faster or slower than the non-cached equivalent?
- [ ] Check the Storage tab in Spark UI — how much memory did the cached DataFrame consume?

---

## Lab 6: Reading Physical Plans

```python
df1 = spark.read.csv("/databricks-datasets/samples/population-vs-price/data_geo.csv", header=True, inferSchema=True)
result = df1.filter(df1["2014 Population estimate"] > 500000).select("State", "2014 Population estimate")
result.explain(True)
```

### Questions to Answer
- [ ] Identify the 4 plan sections in the output (Parsed, Analyzed, Optimized, Physical).
- [ ] Did the filter get pushed down into the scan (look for `PushedFilters` in the physical plan)?
