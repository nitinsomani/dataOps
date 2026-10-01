# Phase 3: Delta Lake Deep Dive — Detailed Notes

> **Goal**: Delta Lake is the storage foundation of everything on Databricks. This is arguably the single most important phase for a DataOps Engineer interview.

---

## 1. What is Delta Lake?

Delta Lake is an **open-source storage layer** that brings ACID transactions, schema enforcement, and time travel to data lakes built on Parquet files. A Delta table is physically just a directory of **Parquet data files** plus a **transaction log** (`_delta_log/`) that records every change ever made to the table.

```
my_table/
├── _delta_log/
│   ├── 00000000000000000000.json
│   ├── 00000000000000000001.json
│   ├── 00000000000000000010.checkpoint.parquet
│   └── _last_checkpoint
├── part-00000-xxxx.snappy.parquet
├── part-00001-xxxx.snappy.parquet
└── ...
```

---

## 2. The Transaction Log (`_delta_log`)

Every write to a Delta table produces a new **JSON commit file** (e.g., `000...001.json`) describing the atomic set of changes: which files were added (`add`), which were logically removed (`remove`), metadata changes, etc. Readers reconstruct the current table state by replaying these JSON files in order.

- **Checkpoints**: every 10 commits (configurable), Delta writes a **Parquet checkpoint** summarizing the full state up to that point, so readers don't need to replay thousands of tiny JSON files from scratch.
- **Atomicity**: a write either fully commits (new JSON file appears) or fails entirely — no partial/corrupt reads, even with concurrent writers.
- **Optimistic concurrency control**: multiple writers can attempt commits concurrently; Delta detects conflicts (e.g., two writers touching overlapping files) at commit time and retries/fails as appropriate rather than locking the whole table.

### ACID guarantees Delta adds over plain Parquet
| Guarantee | What it means |
|-----------|----------------|
| **Atomicity** | A transaction (e.g., a MERGE touching 1000 files) either fully applies or not at all |
| **Consistency** | Schema is enforced on write; readers never see a partially-written state |
| **Isolation** | Concurrent readers/writers don't interfere — readers see a consistent snapshot |
| **Durability** | Once committed, the change is permanently recorded in the log |

---

## 3. Schema Enforcement & Schema Evolution

- **Schema enforcement (schema-on-write)**: by default, Delta rejects writes that don't match the target table's schema (wrong types, extra/missing columns) — prevents silently corrupting a table with malformed data.
- **Schema evolution**: explicitly allow schema changes when they're desired.

```python
# Allow new columns to be added automatically
df.write.format("delta").mode("append").option("mergeSchema", "true").save(path)

# Or at the session level
spark.conf.set("spark.databricks.delta.schema.autoMerge.enabled", "true")
```

```sql
-- Explicit schema changes
ALTER TABLE my_table ADD COLUMN new_col STRING;
ALTER TABLE my_table ALTER COLUMN amount TYPE DOUBLE;
```

---

## 4. Time Travel

Because the transaction log preserves the full history of changes, you can query a table **as of a previous version or timestamp**:

```sql
SELECT * FROM my_table VERSION AS OF 12;
SELECT * FROM my_table TIMESTAMP AS OF '2026-09-01T00:00:00Z';
```

```python
df = spark.read.format("delta").option("versionAsOf", 12).load(path)
```

Use cases: auditing, reproducing a report from a specific point in time, recovering from accidental bad writes (`RESTORE TABLE my_table TO VERSION AS OF 12;`).

**Important**: Time travel is limited by **retention** — old data files eligible for time travel get physically deleted by `VACUUM` after the retention window (default 7 days / 168 hours). Once vacuumed, you can't time-travel past that point even though the log entries might still reference it logically.

---

## 5. MERGE INTO (Upserts) — the Workhorse Operation

```sql
MERGE INTO target t
USING source s
ON t.id = s.id
WHEN MATCHED AND s.is_deleted = true THEN DELETE
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
```

- This is how you implement **upserts**, **CDC application**, and **SCD Type 1/2** dimension updates.
- Under the hood, MERGE reads only the affected files (using data skipping/partition pruning), rewrites them with the changes applied, and commits atomically — it does **not** rewrite the entire table.
- **SCD Type 2** (tracking history) typically requires a more advanced MERGE that closes out the old record (`WHEN MATCHED THEN UPDATE SET end_date = current_date, is_current = false`) and inserts a new current row.

---

## 6. OPTIMIZE & Z-ORDER — File Compaction and Data Skipping

### The Small Files Problem
Frequent small writes (e.g., streaming micro-batches) create many small Parquet files. Small files hurt performance — more file-open overhead, more task scheduling overhead, worse compression ratio.

```sql
OPTIMIZE my_table;                                  -- compacts small files into larger ones (bin-packing)
OPTIMIZE my_table WHERE date >= '2026-09-01';        -- scoped optimize
OPTIMIZE my_table ZORDER BY (customer_id, region);   -- + colocate related data for faster filtering
```

- **OPTIMIZE (bin-packing)**: merges small files into fewer, larger files (target ~1GB by default) to reduce file count and improve scan efficiency.
- **Z-Ordering**: co-locates related data in the same set of files based on the specified columns, so queries filtering on those columns can skip reading irrelevant files (data skipping via file-level min/max statistics). Best for high-cardinality columns frequently used in `WHERE` clauses.
- **Liquid Clustering** (newer alternative to Z-Order + partitioning): `CLUSTER BY (col1, col2)` — adapts clustering incrementally without needing full table rewrites, recommended for new tables over traditional partitioning + Z-Order.

---

## 7. VACUUM — Cleaning Up Old Files

```sql
VACUUM my_table RETAIN 168 HOURS;   -- default retention: 7 days
VACUUM my_table RETAIN 0 HOURS;     -- dangerous: removes ALL old files, breaks time travel & concurrent readers
```

- Physically deletes data files that are no longer referenced by the current table version **and** older than the retention threshold.
- Deleting below the default 7-day retention risks breaking long-running readers or streaming jobs that reference "removed" files still mid-read — Databricks warns/blocks this unless you explicitly override safety checks.

---

## 8. Change Data Feed (CDF)

```sql
ALTER TABLE my_table SET TBLPROPERTIES (delta.enableChangeDataFeed = true);

SELECT * FROM table_changes('my_table', 2, 5);   -- changes between version 2 and 5
```

- Records **row-level changes** (`insert`, `update_preimage`, `update_postimage`, `delete`) with each commit, exposed as a queryable feed.
- Enables efficient **incremental** downstream processing (e.g., propagating only what changed from Silver to Gold) instead of reprocessing full tables.

---

## 9. Constraints & Generated Columns

```sql
ALTER TABLE my_table ADD CONSTRAINT valid_amount CHECK (amount >= 0);

CREATE TABLE events (
  event_time TIMESTAMP,
  event_date DATE GENERATED ALWAYS AS (CAST(event_time AS DATE))
);
```

- **CHECK constraints** enforce data quality rules at write time — writes violating the constraint fail.
- **Generated columns** are automatically computed from other columns — commonly used to derive a partition column from a timestamp.

---

## 10. Deletion Vectors & Row-Level Concurrency

- **Deletion Vectors**: instead of rewriting entire Parquet files on every `DELETE`/`UPDATE`/`MERGE`, Delta can mark specific rows as deleted in a lightweight auxiliary file — dramatically speeding up write-heavy workloads (especially GDPR-style targeted deletes). Files get physically compacted later during OPTIMIZE.
- This reduces write amplification significantly for row-level operations on large tables.

---

## 11. Delta Lake Table Formats: Managed vs External

| Type | Storage location | Behavior on `DROP TABLE` |
|------|-------------------|---------------------------|
| **Managed table** | Databricks-managed default location (Unity Catalog managed storage) | Drops metadata **and** deletes underlying data files |
| **External table** | User-specified path (`LOCATION 's3://...'`) | Drops only metadata, data files remain |

```sql
-- Managed
CREATE TABLE catalog.schema.orders (id INT, amount DOUBLE) USING DELTA;

-- External
CREATE TABLE catalog.schema.orders (id INT, amount DOUBLE)
USING DELTA LOCATION 's3://my-bucket/orders/';
```

---

## 12. Key Takeaways for DataOps

- The transaction log is the source of truth — understanding it explains time travel, concurrency, and why MERGE is efficient.
- **OPTIMIZE + Z-ORDER/Liquid Clustering + VACUUM** is the standard maintenance trio every production Delta table needs on a schedule.
- MERGE INTO is the backbone of upsert/CDC/SCD patterns — know the syntax cold.
- Schema enforcement is a feature, not a bug — it's what keeps Bronze→Silver→Gold pipelines trustworthy.
