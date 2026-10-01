-- ============================================================================
-- Phase 5 — SLO burn-rate query
-- SLI: fraction of days a critical pipeline completes by its target time.
-- SLO: e.g. 99% over rolling 30 days. Alert on multi-window burn rate.
-- Parameterise: ${system_catalog}, ${job_id}, target time, SLO target.
-- ============================================================================

-- Current 30-day SLO compliance for one job (did it finish by 06:00 each day?).
WITH runs AS (
  SELECT
    CAST(period_start_time AS DATE) AS run_date,
    MIN(period_end_time)            AS completed_at
  FROM ${system_catalog}.lakeflow.job_run_timeline
  WHERE job_id = ${job_id}
    AND result_state = 'SUCCEEDED'
    AND period_start_time >= CURRENT_DATE - INTERVAL 30 DAYS
  GROUP BY CAST(period_start_time AS DATE)
),
scored AS (
  SELECT
    run_date,
    completed_at,
    -- target: 06:00 local on run_date
    CASE WHEN completed_at <= run_date + INTERVAL 6 HOURS THEN 1 ELSE 0 END AS met_slo
  FROM runs
)
SELECT
  COUNT(*)                                            AS days_evaluated,
  SUM(met_slo)                                        AS days_met,
  ROUND(100.0 * SUM(met_slo) / NULLIF(COUNT(*),0), 2) AS slo_compliance_pct,
  99.0                                                AS slo_target_pct,
  ROUND(100.0 * SUM(met_slo) / NULLIF(COUNT(*),0), 2) - 99.0 AS headroom_pct
FROM scored;

-- ── Multi-window burn rate (fast-burn = page, slow-burn = ticket) ────────────
-- Fast window (1 day) and slow window (3 days); if the recent miss-rate is high
-- relative to the 1% error budget, you are burning too fast.
WITH runs AS (
  SELECT
    CAST(period_start_time AS DATE) AS run_date,
    MIN(period_end_time)            AS completed_at
  FROM ${system_catalog}.lakeflow.job_run_timeline
  WHERE job_id = ${job_id}
    AND result_state = 'SUCCEEDED'
    AND period_start_time >= CURRENT_DATE - INTERVAL 3 DAYS
  GROUP BY CAST(period_start_time AS DATE)
),
scored AS (
  SELECT run_date,
         CASE WHEN completed_at <= run_date + INTERVAL 6 HOURS THEN 0 ELSE 1 END AS missed
  FROM runs
)
SELECT
  SUM(CASE WHEN run_date >= CURRENT_DATE - INTERVAL 1 DAY  THEN missed ELSE 0 END) AS missed_fast_1d,
  SUM(missed)                                                                      AS missed_slow_3d,
  -- error budget for 99% SLO over 30d ~= 0.3 miss-days allowed / month
  0.3                                                                              AS monthly_budget_days
FROM scored;
-- Alert (Phase 5 databricks_alert): page if missed_fast_1d >= 1 (budget blown in a day).
