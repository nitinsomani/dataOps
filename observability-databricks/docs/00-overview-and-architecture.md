# 00 — Overview & Architecture

## Why

A Databricks lakehouse fails silently in ways a monolith never did: a DLT pipeline
can drop 30% of rows to a quarantine table and still report "success"; a job can
run for 6 hours on an interactive cluster and quietly triple the bill; a stale
`OPTIMIZE` schedule can degrade query latency for weeks. Observability is how we
see these before a stakeholder does.

This program is organised around **seven observability pillars**, each mapped to a
concrete data source that already exists in the platform (no new backend required
for pillars 1–6).

## The seven pillars

| # | Pillar | Question it answers | Primary source |
|---|--------|---------------------|----------------|
| 1 | **Cost & capacity** | What are we spending, on what, trending how? | `system.billing.usage` / `list_prices`, `system.compute.clusters`/`warehouses` |
| 2 | **Job & pipeline health** | Are pipelines succeeding, on time, without regressions? | `system.lakeflow.job_run_timeline`, `job_task_run_timeline`, DLT `event_log` |
| 3 | **Data quality** | Is the data correct, complete, and non-drifting? | DLT expectations (`event_log`), Lakehouse Monitoring metric tables |
| 4 | **Query & warehouse performance** | Are queries fast? Are warehouses right-sized? | `system.query.history`, `system.compute.warehouse_events` |
| 5 | **Security & audit** | Who did what? Any anomalous access or grants? | `system.access.audit` |
| 6 | **Lineage & impact** | If X breaks, what downstream is affected? | `system.access.table_lineage`, `column_lineage` |
| 7 | **Deep telemetry (opt-in)** | JVM/executor internals, custom business spans | OpenTelemetry → CloudWatch/X-Ray (or Grafana/Datadog) |

## High-level architecture

```
                         ┌─────────────────────────────────────────────┐
                         │          Databricks workspace(s)             │
                         │   (dev / uat / prod  ×  us-east-1 / eu-west-1)│
                         └───────────────┬─────────────────────────────┘
                                         │ emits
        ┌────────────────────────────────┼─────────────────────────────────┐
        ▼                                ▼                                   ▼
┌───────────────┐              ┌────────────────────┐              ┌──────────────────┐
│ system.*       │              │ DLT event_log       │              │ OpenTelemetry    │
│ (billing,      │              │ (per-pipeline flow, │              │ Collector         │
│  lakeflow,     │              │  expectations)      │              │ (init script)     │
│  query, access,│              └─────────┬──────────┘              └────────┬─────────┘
│  compute)      │                        │                                  │
└───────┬────────┘                        │                                  │
        │                                 │                    OTLP          ▼
        │  SQL (Lakeview dashboards,       │              ┌────────────────────────────┐
        │  SQL alerts) — Terraform          │              │ CloudWatch / X-Ray          │
        ▼                                  ▼              │ (or Grafana Tempo/Datadog)  │
┌──────────────────────────────────────────────┐        └────────────────────────────┘
│   Lakeview dashboards + SQL alerts            │
│   (databricks_dashboard / databricks_alert)   │────► Teams webhook (existing destination)
│   defined in terraform/.../dashboards/        │────► email (on_failure)
└──────────────────────────────────────────────┘
```

Pillars 1–6 are pure SQL over telemetry that Databricks already produces — they
reuse the **existing `databricks_dashboard` Terraform pattern** in
`terraform/{env}/.../dashboards/`. Only pillar 7 (OTel) introduces new moving parts.

## What already exists (baseline)

- **Cost/Usage, User Usage, Active Users** Lakeview dashboards in
  `terraform/{env}/{public,private}/us-east-1/dashboards/` (Terraform, system tables).
- **Job-level notifications** on `resources/edm_medallion.job.yml` in the DAB repo
  (`email_notifications.on_failure` + `webhook_notifications.on_failure`).
- **AWS budgets** (`terraform/.../budget.tf`) at the account level.

## What this program adds

- Region parity (eu-west-1) for the dashboards that exist only in us-east-1.
- Notification coverage on **every** pipeline, not just the orchestration job.
- New dashboards for pillars 2, 4, 5, 6 and table-health (10).
- Proactive SQL alerts and SLO burn-rate alerting.
- Security/audit visibility (pillar 5).
- Optional deep telemetry via OpenTelemetry (pillar 7).

## Environment / region matrix

| Env | Region | Catalog | System catalog alias |
|-----|--------|---------|----------------------|
| dev | us-east-1 | `subsurface_dev` | `system_table_unitycatalog_prd` |
| uat | us-east-1 | `subsurface_pre` | `system_table_unitycatalog_prd` |
| prod | us-east-1 | `subsurface_prd` | `system_table_unitycatalog_prd` |
| prod | eu-west-1 | `subsurface_prd` (EU) | *confirm per workspace* |

> Always confirm the system-catalog alias per workspace. In this estate it is
> `system_table_unitycatalog_prd`, not the vanilla `system`. All SQL in
> `implementations/` uses a `${system_catalog}` placeholder you substitute at deploy.

See the per-phase docs for the concrete design and `implementations/` for the code.
