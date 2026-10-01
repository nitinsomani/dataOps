# Phase 2 — Job/Pipeline Health Dashboard + System-Table Archival

**Pillar:** Reliability  ·  **Owner:** Platform  ·  **Effort:** Medium  ·  **Repo:** `osdu-ssw-central-dbx`

## Objective

1. A Lakeview dashboard answering: *Are jobs/pipelines succeeding? On time? Getting
   slower? Which task fails most?*
2. **Archive** key system-table data into owned Delta tables so trend/compliance
   analysis survives the system-table retention window (typically 365 days).

## Part A — Health dashboard

### Data sources

| Source | Gives |
|--------|-------|
| `${system_catalog}.lakeflow.job_run_timeline` | per-run status, start/end, trigger |
| `${system_catalog}.lakeflow.job_task_run_timeline` | per-task status & duration |
| `${system_catalog}.lakeflow.jobs` | job id → name lookup |
| DLT `event_log` (per pipeline, or the `system.lakeflow.pipelines` view) | flow progress, expectation results |

### Panels (KPIs → trends → detail)

1. **KPI counters** — runs (24h), success rate (7d), currently-running, failed (24h).
2. **Success-rate trend** (line, 30d) — % successful runs per day.
3. **Run-duration trend** (line, 30d) — p50/p95 duration per job; catches regressions.
4. **Top failing tasks** (bar) — `job_task_run_timeline` where `result_state='FAILED'`.
5. **Longest-running tasks** (table) — p95 duration ranked, to target optimisation.
6. **Schedule adherence** — actual start vs expected cron (feeds SLOs in Phase 5).

SQL for all panels: `implementations/phase-02-job-health/health-queries.sql`.

### Best practice applied

- **RED method for pipelines** — Rate (runs), Errors (failure %), Duration (p95).
- Trend, not just point-in-time — a single green tick hides a pipeline that's 3×
  slower than last week.

## Part B — System-table archival

### Why

System tables have bounded retention. For **year-over-year cost trends**,
**audit/compliance retention** (often 2–7 years), and **post-incident forensics**
beyond the window, snapshot the important tables into owned Delta tables.

### What to archive

| Source | Target (owned) | Cadence |
|--------|----------------|---------|
| `billing.usage` + `list_prices` | `obs.archive.billing_usage_daily` | daily |
| `access.audit` | `obs.archive.access_audit` | daily (append) |
| `lakeflow.job_run_timeline` | `obs.archive.job_runs` | daily |
| `access.table_lineage` | `obs.archive.table_lineage` | weekly |

### How

A small scheduled Databricks **job** (SQL task or notebook) that does incremental
`MERGE`/`INSERT` into the archive tables, watermarked on `usage_date` / `event_time`.
See `implementations/phase-02-job-health/archival-job.sql`.

### Best practice applied

- **Own your long-term telemetry** — never depend on a vendor's retention default
  for compliance-grade history.
- Incremental + idempotent (`MERGE` on natural keys) so re-runs are safe.

## Verification

- Dashboard renders with real run history for the medallion job + pipelines.
- Archive job runs green; `SELECT max(usage_date) FROM obs.archive.billing_usage_daily`
  advances each day.

## Ownership & DE involvement

**Platform-owned.** DE can advise which pipelines are "critical" (drives the SLO list
in Phase 5), but no transformation-code changes here.
