-- ============================================================================
-- Phase 2 — System-table archival job (incremental, idempotent)
-- Run as a scheduled Databricks SQL / job task (daily).
-- Snapshots system tables into owned Delta tables so trend + compliance history
-- survives the system-table retention window.
-- Replace ${system_catalog} and ${archive_catalog}/${archive_schema} as needed.
-- ============================================================================

-- One-time: create the archive schema (run once, or manage via Terraform/DAB).
-- CREATE SCHEMA IF NOT EXISTS ${archive_catalog}.${archive_schema};

-- ── Billing usage (daily incremental MERGE) ─────────────────────────────────
CREATE TABLE IF NOT EXISTS ${archive_catalog}.${archive_schema}.billing_usage_daily
AS SELECT * FROM ${system_catalog}.billing.usage WHERE 1 = 0;

MERGE INTO ${archive_catalog}.${archive_schema}.billing_usage_daily AS tgt
USING (
  SELECT * FROM ${system_catalog}.billing.usage
  WHERE usage_date >= (
    SELECT COALESCE(MAX(usage_date), DATE'2020-01-01')
    FROM ${archive_catalog}.${archive_schema}.billing_usage_daily
  )
) AS src
ON  tgt.record_id = src.record_id
WHEN NOT MATCHED THEN INSERT *;

-- ── Access audit (append-only incremental) ──────────────────────────────────
CREATE TABLE IF NOT EXISTS ${archive_catalog}.${archive_schema}.access_audit
AS SELECT * FROM ${system_catalog}.access.audit WHERE 1 = 0;

INSERT INTO ${archive_catalog}.${archive_schema}.access_audit
SELECT * FROM ${system_catalog}.access.audit a
WHERE a.event_time > (
  SELECT COALESCE(MAX(event_time), TIMESTAMP'2020-01-01')
  FROM ${archive_catalog}.${archive_schema}.access_audit
);

-- ── Job run timeline (daily incremental) ────────────────────────────────────
CREATE TABLE IF NOT EXISTS ${archive_catalog}.${archive_schema}.job_runs
AS SELECT * FROM ${system_catalog}.lakeflow.job_run_timeline WHERE 1 = 0;

MERGE INTO ${archive_catalog}.${archive_schema}.job_runs AS tgt
USING (
  SELECT * FROM ${system_catalog}.lakeflow.job_run_timeline
  WHERE period_start_time >= (
    SELECT COALESCE(MAX(period_start_time), TIMESTAMP'2020-01-01')
    FROM ${archive_catalog}.${archive_schema}.job_runs
  )
) AS src
ON  tgt.job_id = src.job_id AND tgt.run_id = src.run_id
    AND tgt.period_start_time = src.period_start_time
WHEN NOT MATCHED THEN INSERT *;

-- ── Table lineage (weekly incremental) ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS ${archive_catalog}.${archive_schema}.table_lineage
AS SELECT * FROM ${system_catalog}.access.table_lineage WHERE 1 = 0;

INSERT INTO ${archive_catalog}.${archive_schema}.table_lineage
SELECT * FROM ${system_catalog}.access.table_lineage l
WHERE l.event_time > (
  SELECT COALESCE(MAX(event_time), TIMESTAMP'2020-01-01')
  FROM ${archive_catalog}.${archive_schema}.table_lineage
);

-- NOTE: exact column names (record_id, run_id, event_time) can vary slightly by
-- Databricks release — confirm against the workspace's system schema and adjust
-- the MERGE keys accordingly before scheduling.
