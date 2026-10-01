# Phase 4: Data Ingestion, ETL/ELT & Auto Loader — Detailed Notes

> **Goal**: Master the patterns for getting data *into* the Lakehouse reliably, incrementally, and at scale.

---

## 1. ETL vs ELT

- **ETL** (Extract, Transform, Load): transform data *before* loading into the target — common with traditional warehouses with limited compute.
- **ELT** (Extract, Load, Transform): load raw data first, transform *inside* the Lakehouse using Spark's scalable compute. This is the dominant pattern on Databricks — land raw data in Bronze, then transform in-place through Silver/Gold using the same elastic compute engine.

---

## 2. Batch Ingestion Methods

### COPY INTO
```sql
COPY INTO catalog.schema.orders
FROM '/mnt/raw/orders/'
FILEFORMAT = JSON
FORMAT_OPTIONS ('mergeSchema' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');
```
- Idempotent, SQL-based, incremental file loading — tracks which files have already been loaded so re-running is safe and only new files get picked up.
- Good for simpler, scheduled batch loads where you don't need continuous/streaming semantics.

### JDBC / Lakehouse Federation
```python
df = (spark.read.format("jdbc")
      .option("url", "jdbc:postgresql://host:5432/db")
      .option("dbtable", "public.orders")
      .option("user", "...").option("password", "...")
      .load())
```
- Use partitioned reads (`partitionColumn`, `lowerBound`, `upperBound`, `numPartitions`) to parallelize large table extracts instead of pulling through a single connection.
- **Lakehouse Federation** (Unity Catalog feature) lets you query external systems (Postgres, MySQL, Snowflake, Redshift, BigQuery) directly via UC-registered connections without a separate ETL hop, when read-through access is sufficient.

---

## 3. Auto Loader (`cloudFiles`) — The Preferred Incremental File Ingestion Tool

Auto Loader incrementally and efficiently processes new files landing in cloud storage, without re-scanning the entire directory on every run.

```python
df = (spark.readStream.format("cloudFiles")
      .option("cloudFiles.format", "json")
      .option("cloudFiles.schemaLocation", "/mnt/schema/orders")
      .option("cloudFiles.inferColumnTypes", "true")
      .option("cloudFiles.schemaEvolutionMode", "addNewColumns")
      .load("/mnt/raw/orders"))

(df.writeStream
   .format("delta")
   .option("checkpointLocation", "/mnt/checkpoints/orders")
   .trigger(availableNow=True)          # process all available data then stop (batch-like)
   .toTable("catalog.schema.bronze_orders"))
```

### How Auto Loader Discovers New Files
- **Directory listing mode**: lists cloud storage directories incrementally, tracking state — works well for lower file-arrival volumes.
- **File notification mode**: subscribes to cloud-native event notifications (S3 → SNS/SQS, ADLS → Event Grid, GCS → Pub/Sub) so new file arrival is detected via events instead of repeated listing — scales to very high file volumes/directories with millions of files, avoids expensive full listing operations.

### Schema Inference & Evolution
- Auto Loader samples files to infer schema, storing the inferred schema at `cloudFiles.schemaLocation` so it's consistent across restarts.
- `cloudFiles.schemaEvolutionMode`:
  - `addNewColumns` (default) — new columns trigger a stream restart, then the pipeline picks up with the new schema.
  - `rescue` — unexpected/mismatched data goes into a `_rescued_data` column instead of failing the pipeline — critical for **not losing data** when upstream schemas drift unexpectedly.
  - `failOnNewColumns` — hard fail on schema drift (used when strict contracts are required).
  - `none` — ignore new columns entirely.

### `trigger(availableNow=True)` vs continuous
- `trigger(availableNow=True)`: processes all data currently available then stops — effectively turns a streaming source into an efficient, incremental **batch** job. This is the most common pattern for scheduled DataOps pipelines (run every N hours via a Job) since it gets incremental-processing benefits without needing an always-on cluster.
- `trigger(processingTime="1 minute")`: micro-batch continuous streaming.
- Default (no trigger specified): process as fast as possible, continuously.

---

## 4. Medallion Architecture in Practice

```
Bronze  → Raw ingest, minimal/no transformation, append-only, preserves _rescued_data,
           source metadata columns (ingest timestamp, source file name)
Silver  → Deduplicated, validated, conformed types/schema, joined reference data,
           quality-checked (rows failing checks quarantined or dropped)
Gold    → Aggregated, dimensional model (facts/dimensions), partitioned for BI,
           often materialized as smaller, highly-optimized tables
```

```python
# Bronze: land raw with lineage metadata
bronze_df = (raw_stream_df
    .withColumn("_ingest_ts", current_timestamp())
    .withColumn("_source_file", col("_metadata.file_path")))

# Silver: clean & validate
silver_df = (bronze_df
    .dropDuplicates(["order_id"])
    .filter(col("amount").isNotNull())
    .withColumn("amount", col("amount").cast("decimal(10,2)")))

# Gold: aggregate
gold_df = (silver_df
    .groupBy("region", "order_date")
    .agg(sum("amount").alias("total_sales"), count("*").alias("order_count")))
```

---

## 5. CDC (Change Data Capture) Patterns

| Source | Common CDC mechanism |
|--------|------------------------|
| Relational DB (Postgres/MySQL/SQL Server) | Debezium / native CDC connectors → Kafka → Auto Loader, or Databricks LakeFlow Connect |
| SaaS APIs | Fivetran/Airbyte connectors landing raw JSON, or custom incremental pulls using `updated_at` watermarks |
| Files | Auto Loader tracks new/changed files; combined with MERGE for upsert semantics |

- Once CDC events land in Bronze (as insert/update/delete records with an operation type column), a `MERGE INTO` in Silver applies them to maintain a current-state table.
- **LakeFlow Connect** (Databricks-native ingestion connectors) offers managed connectors for common databases and SaaS sources, reducing the need to stand up separate ingestion tooling (Fivetran-style) for common systems.

---

## 6. Idempotency & Exactly-Once Semantics

- Auto Loader + Delta checkpoints give **exactly-once** processing guarantees for the write path — if a job fails mid-batch and retries, already-committed data isn't duplicated (checkpoint tracks processed file offsets, Delta's atomic commits ensure no partial writes).
- For **COPY INTO**, idempotency comes from tracking already-loaded file names/paths internally.
- Design ingestion jobs to be **safely re-runnable** — critical for production reliability (a failed job should be re-triggerable without manual cleanup or risk of duplicate data).

---

## 7. Handling Bad/Malformed Data

```python
df = (spark.readStream.format("cloudFiles")
      .option("cloudFiles.format", "json")
      .option("cloudFiles.schemaLocation", schema_loc)
      .option("badRecordsPath", "/mnt/bad_records/orders")   # quarantine malformed rows
      .load(path))
```
- `PERMISSIVE` mode (default): malformed records go into a `_corrupt_record` column instead of failing the job.
- `DROPMALFORMED`: silently drops bad rows (risky — invisible data loss unless monitored).
- `FAILFAST`: fails the whole job on any malformed record (used when strict correctness > availability).
- `_rescued_data` column (Auto Loader specific): catches columns/values that don't match the inferred schema, preserving them without breaking the pipeline.

---

## 8. Partitioning Strategy for Ingested Tables

- Partition by a **low-cardinality, frequently-filtered column** — commonly a date column (`ingest_date`, `order_date`).
- Avoid over-partitioning (too many small partitions → small files problem); avoid under-partitioning (can't prune effectively).
- With **Liquid Clustering** available, many new tables skip traditional partitioning entirely in favor of `CLUSTER BY`, which adapts automatically without rigid directory structure.

---

## 9. Key Takeaways for DataOps

- **Auto Loader with `trigger(availableNow=True)`** is the default modern pattern for scheduled incremental batch ingestion — know this pattern cold, it comes up constantly.
- Medallion architecture isn't just a diagram — know concretely what transformation/validation happens at each layer.
- Idempotency and safe re-run behavior are non-negotiable production requirements — always design ingestion so a retried job doesn't duplicate or corrupt data.
- Schema evolution mode (`rescue` vs `addNewColumns` vs `failOnNewColumns`) is a real design decision with real trade-offs — be ready to justify your choice.
