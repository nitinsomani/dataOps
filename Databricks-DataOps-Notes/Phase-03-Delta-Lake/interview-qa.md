# Phase 3: Delta Lake Deep Dive — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ What is Delta Lake and how does it add ACID transactions on top of Parquet?

**Answer:**
Delta Lake is an open storage format consisting of Parquet data files plus a **transaction log** (`_delta_log/`) — a sequence of JSON commit files that atomically record every add/remove of data files. Every write produces one new commit file; readers reconstruct table state by reading the log (with periodic Parquet checkpoints to avoid replaying the entire history). Because a commit either fully appears in the log or doesn't, writes are atomic — there's no possibility of a reader seeing a half-written state, and concurrent writers are coordinated via optimistic concurrency control that detects conflicting commits.

---

## Q2. ⭐ Explain how Time Travel works and its limitations.

**Answer:**
Every commit in the transaction log is versioned, so you can query `VERSION AS OF n` or `TIMESTAMP AS OF <ts>` and Delta will reconstruct the table as it existed at that point by replaying the log up to that commit. This is useful for auditing, reproducing historical reports, and recovering from bad writes via `RESTORE TABLE`.

The limitation: time travel depends on the underlying **data files still existing**. `VACUUM` physically deletes files no longer referenced by the current version once they're older than the retention window (default 7 days) — once vacuumed, you lose the ability to time-travel to versions that depended on those files, even though the log entries may still reference them.

---

## Q3. ⭐ Walk me through how you'd implement an upsert/CDC pipeline using MERGE INTO.

**Answer:**
`MERGE INTO target USING source ON <join condition> WHEN MATCHED THEN UPDATE ... WHEN NOT MATCHED THEN INSERT ...` — this reads the incoming change set (source), matches it against existing rows in the target by key, updates matched rows, inserts new ones, and can delete matched rows flagged as deleted (`WHEN MATCHED AND s.op='D' THEN DELETE`). Internally, Delta only rewrites the specific files containing matched rows (using file-level statistics to skip irrelevant files) rather than rewriting the whole table, making it efficient even on large tables. For SCD Type 2, the MATCHED clause typically closes out the old row (`end_date`, `is_current=false`) while the NOT MATCHED clause inserts the new current version.

---

## Q4. What is OPTIMIZE and Z-ORDER, and when would you use Liquid Clustering instead?

**Answer:**
`OPTIMIZE` compacts many small Parquet files into fewer, larger ones (bin-packing, target ~1GB), which reduces file-open overhead and improves scan performance — critical after frequent small writes (e.g., streaming). `ZORDER BY (col)` additionally co-locates rows with similar values in the specified columns across the same files, enabling data skipping (file-level min/max stats let Spark skip entire files that can't match a filter) — best on high-cardinality columns commonly used in WHERE clauses.

**Liquid Clustering** (`CLUSTER BY`) is the newer, generally recommended replacement — it clusters data incrementally as it's written, without requiring a full table rewrite each time and without the rigid physical partitioning + Z-Order combination, adapting more gracefully to changing query patterns and data skew over time.

---

## Q5. What's the difference between schema enforcement and schema evolution, and how do you enable the latter?

**Answer:**
Schema enforcement (schema-on-write) is Delta's default behavior: writes that don't match the target table's schema (wrong column types, unexpected extra columns) are rejected — this prevents silent data corruption. Schema evolution is the explicit opt-in to allow certain schema changes, most commonly adding new columns: `df.write.option("mergeSchema", "true")` or setting `spark.databricks.delta.schema.autoMerge.enabled = true` at the session level. You can also make explicit DDL changes via `ALTER TABLE ... ADD COLUMN`. As a best practice, schema evolution should be intentional/controlled in production pipelines rather than blanket-enabled, to avoid silently absorbing unexpected upstream schema drift.

---

## Q6. What is Change Data Feed (CDF) and how does it differ from just re-querying the whole table?

**Answer:**
CDF (`delta.enableChangeDataFeed = true`) makes Delta record row-level change events (insert, update_preimage/postimage, delete) alongside each commit, queryable via `table_changes('table', startVersion, endVersion)` or as a streaming source. This lets downstream consumers process only what actually changed since they last read, instead of diffing or reprocessing the entire table — essential for efficient incremental Bronze→Silver→Gold propagation and for building CDC-style consumers off a Delta table without external tools like Debezium.

---

## Q7. Explain VACUUM and why reducing retention below 7 days is risky.

**Answer:**
`VACUUM` physically deletes data files that are no longer part of the current table version and are older than the retention threshold (default 168 hours / 7 days). It's necessary maintenance because operations like MERGE/UPDATE/DELETE/OPTIMIZE leave old file versions on disk (needed for time travel and to let concurrent readers finish). Reducing retention below the default risks deleting files that a long-running query, a streaming job, or another concurrent reader is still actively referencing — causing "file not found" failures mid-read. Databricks requires explicitly disabling a safety check to VACUUM below the default retention for this reason.

---

## Q8. What are Deletion Vectors and why were they introduced?

**Answer:**
Before deletion vectors, any `DELETE`, `UPDATE`, or `MERGE` operation had to rewrite entire Parquet files even to remove/modify a small number of rows within them — expensive "write amplification," especially for large files or frequent row-level operations (e.g., GDPR right-to-be-forgotten deletes). Deletion vectors let Delta instead record which rows are logically deleted/updated in a small auxiliary file, without touching the original Parquet file — readers merge this vector at query time to skip those rows. The physical files get compacted later during `OPTIMIZE`, batching the rewrite cost instead of paying it on every single operation.

---

## Q9. What's the difference between a managed and an external Delta table?

**Answer:**
A **managed table** stores its data in Databricks/Unity-Catalog-managed default storage; dropping the table (`DROP TABLE`) deletes both the metadata *and* the underlying data files. An **external table** is created with an explicit `LOCATION` pointing to storage you control; dropping it only removes the catalog metadata entry — the data files remain untouched. External tables are common when data needs to be shared/accessed outside Databricks or must persist independently of the catalog entry's lifecycle.
