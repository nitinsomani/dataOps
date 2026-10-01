# Phase 5 — SQL Alerts + SLA/SLO Burn-Rate Alerting

**Pillar:** Reliability  ·  **Owner:** Platform (SLO targets with Data Eng)  ·  **Effort:** Medium  ·  **Repo:** `osdu-ssw-central-dbx`

## Objective

Move from *dashboards you have to look at* to *alerts that come to you*. Two layers:

1. **Threshold alerts** — simple "value crossed a line" (cost spike, failure rate).
2. **SLO burn-rate alerts** — formal objective per critical pipeline (e.g. *gold_well
   lands by 06:00, 99% of days*), alerting on the rate at which you're burning the
   error budget.

## Part A — Threshold SQL alerts

Use `databricks_alert` (Terraform) — a scheduled query + condition + notification to
the existing Teams webhook destination. Candidate alerts:

| Alert | Condition | Source |
|-------|-----------|--------|
| Daily cost spike | today's USD > 1.5 × trailing-7d average | `billing.usage` |
| Job failure rate | >10% of runs failed in last 24h | `lakeflow.job_run_timeline` |
| Pipeline fatal failure | any `on-update-fatal-failure` in 1h | DLT `event_log` |
| Warehouse queue time | p95 queue > 10s over 1h | `query.history` |
| Interactive-cluster job | any job cost on `ALL_PURPOSE` today | `billing.usage` |

Terraform: `implementations/phase-05-alerts/alerts.tf`.

## Part B — SLO burn-rate alerting

For each **critical** pipeline (DE nominates the list), define:

- **SLI** — e.g. *fraction of days gold_well completes by target time*.
- **SLO** — e.g. *99% over a rolling 30 days*.
- **Error budget** — 1% ⇒ ~0.3 late days / month.
- **Burn-rate alert** — page when you'll exhaust the month's budget fast
  (e.g. 2 late days in 24h), warn on slow burn.

Modelled as a SQL query over `job_run_timeline` comparing actual completion vs the
target window, with multi-window burn-rate conditions. Pattern:
`implementations/phase-05-alerts/slo_burn_rate.sql`.

### Best practice applied

- **Alert on symptoms/impact, not causes** — "gold_well is late" (impact) beats
  "CPU high" (cause) for paging.
- **Multi-window burn rate** (Google SRE workbook) — fast-burn (page) + slow-burn
  (ticket) avoids both alert fatigue and missed slow degradations.
- **Error budgets gate change** — when budget is spent, freeze risky deploys; when
  healthy, ship freely. Ties observability to release policy.

## ⚠️ Where Data Eng is needed

Only to **nominate the critical pipelines and their target times** (the SLO targets).
Everything else — the SQL, the alert resources, the burn-rate math — is platform.

## Verification

- Trip a threshold in dev (e.g. lower the cost multiplier) and confirm the Teams
  alert fires.
- SLO query returns a sensible current-compliance % for a known pipeline.
