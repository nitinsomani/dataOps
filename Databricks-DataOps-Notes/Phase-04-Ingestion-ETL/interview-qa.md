# Phase 4: Ingestion, ETL/ELT & Auto Loader — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ Why does Databricks favor ELT over ETL?

**Answer:**
In ELT, raw data is loaded first (Bronze) and transformations happen afterward using Spark's elastic, scalable compute inside the Lakehouse — this avoids needing a separate transformation engine/tool, keeps a full copy of raw data for reprocessing/auditing, and lets you iterate on transformation logic without re-extracting from the source system each time. Traditional ETL (transform before load) made sense when target systems had limited/expensive compute (older warehouses) — that constraint doesn't apply to Databricks, where compute scales independently and cheaply.

---

## Q2. ⭐ What is Auto Loader and why would you use it over a plain batch read?

**Answer:**
Auto Loader (`cloudFiles` format) incrementally and efficiently discovers new files landing in cloud storage without re-listing/re-scanning the entire directory each run — it tracks which files have already been processed via its checkpoint. It supports schema inference and evolution, and scales to directories with millions of files using cloud-native file notification services (S3 SNS/SQS, ADLS Event Grid) instead of expensive directory listing. Compared to a plain batch read of the whole directory every time, Auto Loader avoids reprocessing old files and scales far better as data volume grows.

---

## Q3. ⭐ Explain `trigger(availableNow=True)` and why it's commonly used for "batch" jobs on Databricks.

**Answer:**
`trigger(availableNow=True)` tells a Structured Streaming query to process all data currently available in the source, then stop automatically — rather than running continuously or waiting on a fixed interval. This effectively converts an incremental streaming source (like Auto Loader) into a **scheduled batch job**: you run it via a Databricks Job on a schedule (e.g., hourly), it processes only new files since the last run (tracked via checkpoint), and then the cluster can terminate — giving you the efficiency/incrementality of streaming without paying for an always-on cluster.

---

## Q4. What's the difference between the schema evolution modes in Auto Loader, and when would you pick `rescue` over `failOnNewColumns`?

**Answer:**
- `addNewColumns` (default): a new column triggers the stream to stop and needs a restart before it picks up the new schema — safe default for most pipelines.
- `rescue`: unexpected/unmatched data is captured in a `_rescued_data` column rather than failing the job — you never lose data even if upstream schema drifts unexpectedly, at the cost of needing downstream logic to periodically inspect and reconcile that column.
- `failOnNewColumns`: hard-fails the pipeline on any schema drift — used when you have a strict data contract with upstream teams and want immediate visibility/alerting on any violation rather than silently absorbing it.

I'd choose `rescue` for ingestion from less-controlled/external sources (third-party APIs, partner feeds) where availability matters more than rejecting on drift, and `failOnNewColumns` for tightly-controlled internal sources where a contract violation indicates a real bug that should stop the pipeline immediately.

---

## Q5. ⭐ Describe the Medallion architecture and what specifically happens at each layer.

**Answer:**
Bronze is the raw landing zone — append-only, minimal transformation, typically enriched only with ingestion metadata (ingestion timestamp, source file name) and a rescued-data column for anything that didn't match the expected schema; this preserves a full, replayable audit trail. Silver applies cleansing: deduplication, type casting/conformance, joining reference/dimension data, and data quality checks — rows failing checks are either quarantined or dropped depending on policy. Gold aggregates and models data for consumption — dimensional/star schemas, pre-aggregated metrics, optimized for BI tool query patterns. The key benefit is that each layer is independently testable and reprocessable: if Silver logic has a bug, you can fix it and replay from immutable Bronze without re-ingesting from the source system.

---

## Q6. How do you handle CDC (Change Data Capture) from a relational database into Databricks?

**Answer:**
Typically a CDC tool (Debezium, native DB CDC connectors, or a managed ingestion tool like Fivetran/Airbyte, or Databricks' own LakeFlow Connect) captures row-level inserts/updates/deletes from the source database's transaction log and streams them (often via Kafka) into a Bronze Delta table, tagging each record with an operation type and a sequence/timestamp for ordering. From there, a scheduled or streaming `MERGE INTO` in Silver applies these changes to maintain a current-state table matching the source, using the operation type to decide between UPDATE/INSERT/DELETE within the MERGE's WHEN clauses.

---

## Q7. How do you ensure an ingestion pipeline is idempotent and safe to re-run after a failure?

**Answer:**
Use Auto Loader or COPY INTO, both of which track already-processed files internally (via checkpoint location or Delta's internal source-file tracking), so re-running after a failure doesn't reprocess/duplicate already-committed files. For the write side, ensure writes are wrapped in Delta's atomic commits (a failed micro-batch never partially commits). For upsert targets, use `MERGE INTO` keyed on a natural/business key rather than blind `INSERT`, so replaying the same batch twice doesn't create duplicate rows. Always test the "kill the job mid-run and restart it" scenario explicitly before considering a pipeline production-ready.

---

## Q8. What's the difference between directory listing mode and file notification mode in Auto Loader, and when does it matter?

**Answer:**
Directory listing mode incrementally lists the source directory tree on each trigger to discover new files — simple, no extra cloud infrastructure required, but its listing cost grows with the number of files/directories, making it inefficient at very large scale (millions of files, deeply nested paths). File notification mode instead subscribes to cloud-native storage event notifications (S3 event notifications via SNS/SQS, Azure Event Grid for ADLS, GCS Pub/Sub) so new file arrivals are pushed as events rather than discovered via repeated listing — this scales far better for high file-arrival-rate or very large existing directories, at the cost of needing the extra cloud messaging infrastructure (which Databricks can provision automatically in many cases).
