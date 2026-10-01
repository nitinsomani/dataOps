# Phase 8: Performance Tuning & Optimization — Lab Exercises

> Use a small multi-node cluster (2-4 workers) so you can observe shuffle/parallelism effects.

---

## Lab 1: Photon On vs Off Benchmark

1. Create two SQL Warehouses (or clusters) — one with Photon enabled, one without, same size.
2. Run an aggregation-heavy query against a reasonably large table (or generate one):

```python
spark.range(0, 100_000_000).withColumn("bucket", (col("id") % 1000)) \
    .write.format("delta").mode("overwrite").saveAsTable("main.lab8_big_table")
```

```sql
SELECT bucket, COUNT(*), AVG(id) FROM main.lab8_big_table GROUP BY bucket ORDER BY bucket;
```

### Questions to Answer
- [ ] What was the query duration with Photon on vs off?
- [ ] Open Query Profile — which operators show as Photon-accelerated?

---

## Lab 2: Small Files Problem & OPTIMIZE Impact

```python
for i in range(30):
    spark.range(i*1000, i*1000+50).write.format("delta").mode("append").saveAsTable("main.lab8_small_files")
```

```sql
DESCRIBE DETAIL main.lab8_small_files;   -- note numFiles, sizeInBytes
SELECT COUNT(*) FROM main.lab8_small_files;  -- time this query
OPTIMIZE main.lab8_small_files;
DESCRIBE DETAIL main.lab8_small_files;   -- note numFiles after
SELECT COUNT(*) FROM main.lab8_small_files;  -- time this again
```

### Questions to Answer
- [ ] How many files existed before/after OPTIMIZE, and what was the average file size?
- [ ] Did the query duration change noticeably? Why might a `COUNT(*)` specifically show a smaller improvement than a full table scan with filters?

---

## Lab 3: Z-Order / Liquid Clustering Data Skipping

```python
import random
data = [(i, random.choice(['US','EU','APAC']), random.random()*1000) for i in range(2_000_000)]
df = spark.createDataFrame(data, ["id", "region", "amount"])
df.write.format("delta").mode("overwrite").saveAsTable("main.lab8_regions_unordered")
```

```sql
-- Baseline query time without Z-Order
SELECT * FROM main.lab8_regions_unordered WHERE region = 'US' AND amount > 900;

OPTIMIZE main.lab8_regions_unordered ZORDER BY (region);

-- Same query after Z-Order
SELECT * FROM main.lab8_regions_unordered WHERE region = 'US' AND amount > 900;
```

### Questions to Answer
- [ ] Compare query duration / files scanned before and after Z-Order (check Query Profile "files pruned" stat).
- [ ] Recreate the table using `CLUSTER BY (region)` instead — does Liquid Clustering achieve similar skipping with less manual maintenance?

---

## Lab 4: Broadcast Join Threshold Tuning

```python
large = spark.range(0, 10_000_000).withColumnRenamed("id", "key")
medium = spark.range(0, 50_000).withColumnRenamed("id", "key").withColumn("val", col("key")*2)

spark.conf.set("spark.sql.autoBroadcastJoinThreshold", "1048576")  # 1MB - too small
large.join(medium, "key").explain()

spark.conf.set("spark.sql.autoBroadcastJoinThreshold", "104857600")  # 100MB
large.join(medium, "key").explain()
```

### Questions to Answer
- [ ] Which join strategy was chosen at each threshold setting?
- [ ] At what approximate size does `medium` cross from broadcast-eligible to not, given its actual serialized size?

---

## Lab 5: Detecting Spill

```python
skewed = spark.range(0, 5_000_000).withColumn("key", when(rand() < 0.95, 1).otherwise(col("id") % 100))
skewed.groupBy("key").count().collect()
```

### Questions to Answer
- [ ] Check the Spark UI Executors tab — is there any "Spill (Memory)" or "Spill (Disk)" reported?
- [ ] What executor memory configuration change might reduce spill for this workload?

---

## Lab 6: Table Statistics and Query Planning

```sql
ANALYZE TABLE main.lab8_big_table COMPUTE STATISTICS FOR ALL COLUMNS;
DESCRIBE EXTENDED main.lab8_big_table bucket;
```

### Questions to Answer
- [ ] What statistics does `DESCRIBE EXTENDED` show for the `bucket` column after running ANALYZE?
- [ ] How might stale/missing statistics lead the optimizer to choose a suboptimal join strategy?
