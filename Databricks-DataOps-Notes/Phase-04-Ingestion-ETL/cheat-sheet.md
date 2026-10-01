# Phase 4: Ingestion, ETL/ELT & Auto Loader — Cheat Sheet

---

## ETL vs ELT

```
ETL: Extract → Transform (external tool) → Load    (legacy warehouse pattern)
ELT: Extract → Load (raw) → Transform (in Lakehouse via Spark)   (Databricks default)
```

## Auto Loader Skeleton

```python
df = (spark.readStream.format("cloudFiles")
      .option("cloudFiles.format", "json")
      .option("cloudFiles.schemaLocation", "/mnt/schema/x")
      .option("cloudFiles.schemaEvolutionMode", "rescue")
      .load("/mnt/raw/x"))

(df.writeStream.format("delta")
   .option("checkpointLocation", "/mnt/checkpoints/x")
   .trigger(availableNow=True)
   .toTable("cat.sch.bronze_x"))
```

## File Discovery Modes

| Mode | How it works | Best for |
|------|----------------|----------|
| Directory listing | Incremental listing of storage | Lower file volume |
| File notification | S3 SNS/SQS, ADLS Event Grid, GCS Pub/Sub | High volume / millions of files |

## Schema Evolution Modes

```
addNewColumns    → default; restarts stream to pick up new column
rescue           → unexpected data → _rescued_data column (no data loss)
failOnNewColumns → hard fail on drift (strict contract)
none             → ignore new columns
```

## Trigger Types

```
trigger(availableNow=True)        → process all available, then stop (scheduled batch pattern)
trigger(processingTime="1 min")   → micro-batch continuous
(no trigger)                       → run as fast as possible, continuously
```

## Medallion Layer Responsibilities

```
BRONZE  raw, append-only, + _ingest_ts, _source_file, _rescued_data
SILVER  dedup, validate, conform types, quarantine bad rows
GOLD    aggregate, dimensional model, BI-ready
```

## Malformed Data Handling Modes

```
PERMISSIVE (default)  → bad rows → _corrupt_record column
DROPMALFORMED          → silently drops (risk: invisible data loss)
FAILFAST               → fails entire job on any bad record
badRecordsPath          → quarantine path for bad records
```

## COPY INTO Skeleton

```sql
COPY INTO cat.sch.table
FROM '/mnt/raw/path/'
FILEFORMAT = JSON
FORMAT_OPTIONS ('mergeSchema' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');
```

## Idempotency Checklist

```
[ ] Checkpoint location set for streaming/Auto Loader jobs
[ ] COPY INTO / Auto Loader tracks already-processed files internally
[ ] MERGE (not blind INSERT) used for upsert targets
[ ] Job safely re-runnable without manual cleanup after failure
```
