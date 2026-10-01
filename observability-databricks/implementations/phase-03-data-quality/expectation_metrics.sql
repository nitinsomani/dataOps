-- ============================================================================
-- Phase 3 — DLT expectation metrics (from the pipeline event_log)
-- Shows per-table pass / fail / drop counts for data-quality expectations.
-- Point at the pipeline's event_log. Two ways to access it:
--   (a) system.lakeflow pipeline event log view (newer workspaces), or
--   (b) the pipeline's own event_log table:  event_log(TABLE(<pipeline_id>))
-- Adjust the source reference to match the workspace.
-- ============================================================================

-- Expectation results for the most recent update, per table + expectation.
WITH events AS (
  SELECT *
  FROM ${system_catalog}.lakeflow.pipeline_event_log   -- or: event_log(TABLE('<pipeline_id>'))
  WHERE event_type = 'flow_progress'
    AND timestamp >= CURRENT_DATE - INTERVAL 7 DAYS
),
exp AS (
  SELECT
    timestamp,
    origin.flow_name AS table_name,
    EXPLODE(FROM_JSON(
      details:flow_progress.data_quality.expectations,
      'array<struct<name:string,dataset:string,passed_records:bigint,failed_records:bigint>>'
    )) AS e
  FROM events
  WHERE details:flow_progress.data_quality IS NOT NULL
)
SELECT
  table_name,
  e.name                       AS expectation,
  SUM(e.passed_records)        AS passed,
  SUM(e.failed_records)        AS failed,
  ROUND(100.0 * SUM(e.failed_records)
        / NULLIF(SUM(e.passed_records + e.failed_records), 0), 2) AS fail_pct
FROM exp
GROUP BY table_name, e.name
ORDER BY fail_pct DESC, failed DESC;

-- Trend: daily failed-record count per expectation (for a line chart).
WITH events AS (
  SELECT *
  FROM ${system_catalog}.lakeflow.pipeline_event_log
  WHERE event_type = 'flow_progress'
    AND timestamp >= CURRENT_DATE - INTERVAL 30 DAYS
),
exp AS (
  SELECT
    CAST(timestamp AS DATE) AS day,
    EXPLODE(FROM_JSON(
      details:flow_progress.data_quality.expectations,
      'array<struct<name:string,failed_records:bigint>>'
    )) AS e
  FROM events
  WHERE details:flow_progress.data_quality IS NOT NULL
)
SELECT day, e.name AS expectation, SUM(e.failed_records) AS failed_records
FROM exp
GROUP BY day, e.name
ORDER BY day;
