-- ============================================================================
-- Phase 10 — Delta table / lakehouse health queries
-- Mix of information_schema (inventory) and per-table DESCRIBE DETAIL/HISTORY.
-- The DESCRIBE* commands run per table; the templates below show how to drive
-- them (loop in a notebook, or materialise into an owned health table).
-- ============================================================================

-- ── Table inventory (drives the per-table DESCRIBE loop) ────────────────────
SELECT
  table_catalog, table_schema, table_name
FROM ${system_catalog}.information_schema.tables
WHERE table_type != 'VIEW'
  AND table_schema IN ('bronze_edm', 'silver_edm', 'gold_edm')  -- scope to medallion
ORDER BY table_catalog, table_schema, table_name;

-- ── Per-table detail (run for each table from the inventory) ────────────────
-- DESCRIBE DETAIL returns: numFiles, sizeInBytes, partitionColumns, ...
-- Example (substitute the FQN):
--   DESCRIBE DETAIL subsurface_prd.silver_edm.silver_wellbore;
--
-- Small-file signal = sizeInBytes / numFiles << 128MB target.
-- Materialise for a dashboard by inserting DESCRIBE DETAIL output into a health
-- table via a notebook loop; example shape:
--
--   CREATE TABLE IF NOT EXISTS obs.health.table_detail (
--     table_name STRING, num_files BIGINT, size_bytes BIGINT,
--     avg_file_mb DOUBLE, captured_at TIMESTAMP
--   );

-- ── Small-file offenders (from the materialised health table) ───────────────
SELECT
  table_name,
  num_files,
  ROUND(size_bytes / (1024*1024*1024.0), 2)          AS size_gb,
  ROUND(size_bytes / NULLIF(num_files,0) / (1024*1024.0), 1) AS avg_file_mb
FROM obs.health.table_detail
WHERE captured_at = (SELECT MAX(captured_at) FROM obs.health.table_detail)
  AND size_bytes / NULLIF(num_files,0) < 64 * 1024 * 1024   -- avg file < 64MB
ORDER BY num_files DESC;

-- ── OPTIMIZE / VACUUM staleness (from DESCRIBE HISTORY, materialised) ────────
-- Capture last OPTIMIZE/VACUUM op per table into obs.health.maintenance, then:
SELECT
  table_name,
  last_optimize_at,
  DATEDIFF(CURRENT_DATE, CAST(last_optimize_at AS DATE)) AS days_since_optimize,
  last_vacuum_at,
  DATEDIFF(CURRENT_DATE, CAST(last_vacuum_at AS DATE))   AS days_since_vacuum
FROM obs.health.maintenance
WHERE captured_at = (SELECT MAX(captured_at) FROM obs.health.maintenance)
ORDER BY days_since_optimize DESC NULLS FIRST;

-- ── Largest tables (storage cost drivers) ───────────────────────────────────
SELECT
  table_name,
  ROUND(size_bytes / (1024*1024*1024.0), 2) AS size_gb
FROM obs.health.table_detail
WHERE captured_at = (SELECT MAX(captured_at) FROM obs.health.table_detail)
ORDER BY size_bytes DESC
LIMIT 25;

-- ── Growth trend (needs daily snapshots in obs.health.table_detail) ─────────
SELECT
  CAST(captured_at AS DATE) AS day,
  table_name,
  ROUND(size_bytes / (1024*1024*1024.0), 2) AS size_gb
FROM obs.health.table_detail
WHERE captured_at >= CURRENT_DATE - INTERVAL 30 DAYS
ORDER BY day, table_name;
