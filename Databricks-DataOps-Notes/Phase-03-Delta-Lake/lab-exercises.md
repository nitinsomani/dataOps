# Phase 3: Delta Lake Deep Dive — Lab Exercises

> Run in a Databricks notebook. Use a scratch catalog/schema you can freely modify.

---

## Lab 1: Create a Delta Table and Inspect the Transaction Log

```python
spark.sql("CREATE SCHEMA IF NOT EXISTS main.lab3")

df = spark.createDataFrame([(1, "a", 100.0), (2, "b", 200.0)], ["id", "name", "amount"])
df.write.format("delta").mode("overwrite").saveAsTable("main.lab3.orders")
```

```python
%sh
ls -la /dbfs/user/hive/warehouse/lab3.db/orders/_delta_log/ 2>/dev/null || echo "Check via Catalog Explorer path instead for UC tables"
```

```python
spark.sql("DESCRIBE HISTORY main.lab3.orders").show(truncate=False)
```

### Questions to Answer
- [ ] How many commits (versions) exist after the initial create?
- [ ] What operation type does `DESCRIBE HISTORY` show for the write?

---

## Lab 2: Time Travel

```python
# Make more changes to create history
spark.sql("INSERT INTO main.lab3.orders VALUES (3, 'c', 300.0)")
spark.sql("UPDATE main.lab3.orders SET amount = 999.0 WHERE id = 1")

spark.sql("SELECT * FROM main.lab3.orders VERSION AS OF 0").show()
spark.sql("SELECT * FROM main.lab3.orders").show()
```

### Questions to Answer
- [ ] What did the table look like at version 0 vs the current version?
- [ ] Run `RESTORE TABLE main.lab3.orders TO VERSION AS OF 1` — what happens to the version history?

---

## Lab 3: MERGE INTO (Upsert)

```python
source_df = spark.createDataFrame(
    [(1, "a-updated", 150.0), (4, "d", 400.0)], ["id", "name", "amount"]
)
source_df.createOrReplaceTempView("source_updates")

spark.sql("""
MERGE INTO main.lab3.orders t
USING source_updates s
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
""")

spark.sql("SELECT * FROM main.lab3.orders ORDER BY id").show()
```

### Questions to Answer
- [ ] Which row was updated, and which was inserted?
- [ ] Modify the MERGE to also handle deletes when `s.amount < 0` — write the SQL.

---

## Lab 4: Small Files Problem, OPTIMIZE & Z-ORDER

```python
# Simulate many small writes (streaming-like behavior)
for i in range(20):
    spark.range(i*1000, i*1000 + 100).withColumnRenamed("id", "order_id") \
        .withColumn("customer_id", (spark_partition_id())) \
        .write.format("delta").mode("append").saveAsTable("main.lab3.small_files_demo")
```

```python
%sql
-- Count files before optimize
DESCRIBE DETAIL main.lab3.small_files_demo;
```

```sql
OPTIMIZE main.lab3.small_files_demo ZORDER BY (customer_id);
DESCRIBE DETAIL main.lab3.small_files_demo;
```

### Questions to Answer
- [ ] How many files existed before vs after `OPTIMIZE`?
- [ ] What's the average file size before/after (from `DESCRIBE DETAIL`)?

---

## Lab 5: VACUUM and Retention Safety

```sql
VACUUM main.lab3.orders RETAIN 168 HOURS;   -- dry-run friendly default
VACUUM main.lab3.orders RETAIN 168 HOURS DRY RUN;   -- shows files that WOULD be deleted
```

### Questions to Answer
- [ ] What did the dry run report — any files eligible for deletion yet?
- [ ] Why would `VACUUM ... RETAIN 0 HOURS` be dangerous on a table with an active streaming reader?

---

## Lab 6: Change Data Feed

```sql
ALTER TABLE main.lab3.orders SET TBLPROPERTIES (delta.enableChangeDataFeed = true);
UPDATE main.lab3.orders SET amount = amount * 1.1 WHERE id = 2;
SELECT * FROM table_changes('main.lab3.orders', 0, 100);
```

### Questions to Answer
- [ ] What columns does `table_changes` add beyond the normal table schema (hint: `_change_type`, `_commit_version`, `_commit_timestamp`)?
- [ ] How could you use this feed to propagate only changed rows to a Gold table?

---

## Lab 7: Schema Evolution & Constraints

```python
new_df = spark.createDataFrame([(5, "e", 500.0, "premium")], ["id", "name", "amount", "tier"])
new_df.write.format("delta").mode("append").option("mergeSchema", "true").saveAsTable("main.lab3.orders")
```

```sql
ALTER TABLE main.lab3.orders ADD CONSTRAINT positive_amount CHECK (amount >= 0);
-- Try to violate it:
INSERT INTO main.lab3.orders VALUES (6, 'f', -50.0, NULL);
```

### Questions to Answer
- [ ] Did the schema-evolved column (`tier`) appear as NULL for pre-existing rows?
- [ ] What error did the constraint violation produce?
