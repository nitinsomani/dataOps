-- ============================================================================
-- Phase 4 — Query / Warehouse performance dashboard queries
-- Source: ${system_catalog}.query.history and compute.warehouse_events
-- ============================================================================

-- ── KPI: p95 query duration last 7d (ms) ────────────────────────────────────
SELECT ROUND(PERCENTILE(total_duration_ms, 0.95), 0) AS p95_duration_ms_7d
FROM ${system_catalog}.query.history
WHERE start_time >= CURRENT_DATE - INTERVAL 7 DAYS;

-- ── KPI: queries last 24h ───────────────────────────────────────────────────
SELECT COUNT(*) AS queries_24h
FROM ${system_catalog}.query.history
WHERE start_time >= CURRENT_TIMESTAMP - INTERVAL 24 HOURS;

-- ── KPI: failed queries last 24h ────────────────────────────────────────────
SELECT COUNT(*) AS failed_24h
FROM ${system_catalog}.query.history
WHERE start_time >= CURRENT_TIMESTAMP - INTERVAL 24 HOURS
  AND execution_status = 'FAILED';

-- ── Slowest queries (7d) ────────────────────────────────────────────────────
SELECT
  statement_id,
  executed_by            AS user,
  compute.warehouse_id   AS warehouse_id,
  ROUND(total_duration_ms / 1000.0, 1) AS duration_s,
  read_rows,
  read_bytes,
  LEFT(statement_text, 200) AS sql_preview
FROM ${system_catalog}.query.history
WHERE start_time >= CURRENT_DATE - INTERVAL 7 DAYS
ORDER BY total_duration_ms DESC
LIMIT 50;

-- ── Queue-time trend (rising = under-provisioned warehouse) ──────────────────
SELECT
  CAST(start_time AS DATE) AS day,
  ROUND(PERCENTILE(waiting_for_compute_duration_ms, 0.95), 0) AS p95_queue_ms
FROM ${system_catalog}.query.history
WHERE start_time >= CURRENT_DATE - INTERVAL 30 DAYS
GROUP BY CAST(start_time AS DATE)
ORDER BY day;

-- ── Spill detection (needs bigger warehouse or query rewrite) ────────────────
SELECT
  statement_id,
  executed_by AS user,
  ROUND(spilled_local_bytes  / (1024*1024*1024.0), 2) AS spill_local_gb,
  ROUND(total_duration_ms / 1000.0, 1)                AS duration_s,
  LEFT(statement_text, 200) AS sql_preview
FROM ${system_catalog}.query.history
WHERE start_time >= CURRENT_DATE - INTERVAL 7 DAYS
  AND spilled_local_bytes > 0
ORDER BY spilled_local_bytes DESC
LIMIT 50;

-- ── Warehouse scaling events (utilisation / auto-stop tuning) ────────────────
SELECT
  warehouse_id,
  event_type,
  cluster_count,
  event_time
FROM ${system_catalog}.compute.warehouse_events
WHERE event_time >= CURRENT_DATE - INTERVAL 7 DAYS
ORDER BY event_time DESC
LIMIT 200;

-- ── Query volume by user (bar) ──────────────────────────────────────────────
SELECT executed_by AS user, COUNT(*) AS queries
FROM ${system_catalog}.query.history
WHERE start_time >= CURRENT_DATE - INTERVAL 7 DAYS
GROUP BY executed_by
ORDER BY queries DESC
LIMIT 25;

-- NOTE: column names (total_duration_ms, waiting_for_compute_duration_ms,
-- spilled_local_bytes, execution_status) follow the current system.query.history
-- schema — confirm against the workspace and adjust if a release differs.
