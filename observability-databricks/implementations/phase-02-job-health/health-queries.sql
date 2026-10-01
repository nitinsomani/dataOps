-- ============================================================================
-- Phase 2 — Job / Pipeline Health dashboard queries
-- Source: Databricks system tables (lakeflow schema).
-- Replace ${system_catalog} with the workspace's system-catalog alias
--   (this estate: system_table_unitycatalog_prd). Vanilla Databricks: system.
-- Replace ${workspace_name} filter where you want to scope to one workspace.
-- ============================================================================

-- ── KPI: runs in last 24h ───────────────────────────────────────────────────
SELECT COUNT(*) AS runs_24h
FROM ${system_catalog}.lakeflow.job_run_timeline
WHERE period_start_time >= CURRENT_TIMESTAMP - INTERVAL 24 HOURS;

-- ── KPI: success rate last 7 days ───────────────────────────────────────────
SELECT
  ROUND(100.0 * SUM(CASE WHEN result_state = 'SUCCEEDED' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 1) AS success_rate_pct_7d
FROM ${system_catalog}.lakeflow.job_run_timeline
WHERE period_start_time >= CURRENT_DATE - INTERVAL 7 DAYS
  AND result_state IS NOT NULL;

-- ── KPI: currently running ──────────────────────────────────────────────────
SELECT COUNT(*) AS running_now
FROM ${system_catalog}.lakeflow.job_run_timeline
WHERE result_state IS NULL
  AND period_end_time IS NULL;

-- ── KPI: failed in last 24h ─────────────────────────────────────────────────
SELECT COUNT(*) AS failed_24h
FROM ${system_catalog}.lakeflow.job_run_timeline
WHERE result_state IN ('FAILED', 'ERROR', 'TIMEDOUT')
  AND period_start_time >= CURRENT_TIMESTAMP - INTERVAL 24 HOURS;

-- ── Success-rate trend (30d) ────────────────────────────────────────────────
SELECT
  CAST(period_start_time AS DATE) AS run_date,
  ROUND(100.0 * SUM(CASE WHEN result_state = 'SUCCEEDED' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 1) AS success_rate_pct
FROM ${system_catalog}.lakeflow.job_run_timeline
WHERE period_start_time >= CURRENT_DATE - INTERVAL 30 DAYS
  AND result_state IS NOT NULL
GROUP BY CAST(period_start_time AS DATE)
ORDER BY run_date;

-- ── Run-duration trend p50/p95 per job (30d) ────────────────────────────────
SELECT
  j.name AS job_name,
  CAST(t.period_start_time AS DATE) AS run_date,
  ROUND(PERCENTILE(
    (UNIX_TIMESTAMP(t.period_end_time) - UNIX_TIMESTAMP(t.period_start_time)), 0.5)/60.0, 1)
    AS p50_minutes,
  ROUND(PERCENTILE(
    (UNIX_TIMESTAMP(t.period_end_time) - UNIX_TIMESTAMP(t.period_start_time)), 0.95)/60.0, 1)
    AS p95_minutes
FROM ${system_catalog}.lakeflow.job_run_timeline t
JOIN ${system_catalog}.lakeflow.jobs j
  ON t.job_id = j.job_id
WHERE t.period_start_time >= CURRENT_DATE - INTERVAL 30 DAYS
  AND t.period_end_time IS NOT NULL
GROUP BY j.name, CAST(t.period_start_time AS DATE)
ORDER BY run_date, job_name;

-- ── Top failing tasks (30d) ─────────────────────────────────────────────────
SELECT
  job_id,
  task_key,
  COUNT(*) AS failures
FROM ${system_catalog}.lakeflow.job_task_run_timeline
WHERE result_state IN ('FAILED', 'ERROR', 'TIMEDOUT')
  AND period_start_time >= CURRENT_DATE - INTERVAL 30 DAYS
GROUP BY job_id, task_key
ORDER BY failures DESC
LIMIT 25;

-- ── Longest-running tasks p95 (30d) ─────────────────────────────────────────
SELECT
  job_id,
  task_key,
  ROUND(PERCENTILE(
    (UNIX_TIMESTAMP(period_end_time) - UNIX_TIMESTAMP(period_start_time)), 0.95)/60.0, 1)
    AS p95_minutes,
  COUNT(*) AS runs
FROM ${system_catalog}.lakeflow.job_task_run_timeline
WHERE period_end_time IS NOT NULL
  AND period_start_time >= CURRENT_DATE - INTERVAL 30 DAYS
GROUP BY job_id, task_key
ORDER BY p95_minutes DESC
LIMIT 25;
