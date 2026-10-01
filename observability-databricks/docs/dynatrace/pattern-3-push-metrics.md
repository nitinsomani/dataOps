# Pattern 3 — Push Job Status / Metrics into Dynatrace

**Direction:** Databricks **pushes** · **Serverless-safe:** ✅ · **Effort:** Medium
**What it gives you:** rich, per-run metrics (duration, row counts, success flag,
per-pipeline trends) inside Dynatrace for dashboards, SLOs, and anomaly detection —
plus optional distributed **traces** via OTLP.

---

## 1. Concept

Instead of Dynatrace reaching in (Pattern 2), the job reaches out: at the end of a run
(and/or per pipeline step) a small piece of code **pushes metrics** to Dynatrace. Two
ingest surfaces, pick per need:

| Surface | Endpoint | Use when |
|---------|----------|----------|
| **Metrics API v2** | `POST /api/v2/metrics/ingest` (line protocol) | simple numeric metrics: duration, rows, success=1/0 |
| **OTLP ingest** | `POST /api/v2/otlp/v1/{metrics,traces,logs}` | you already emit OpenTelemetry (ties into Phase 7) and want traces/spans too |

```
Databricks job (final task or per-step)
   │  builds metric lines / OTLP payload
   │  POST  https://<tenant>/api/v2/metrics/ingest
   │  Authorization: Api-Token dt0c01.XXXX   (scope: metrics.ingest)
   ▼
Dynatrace  ──►  custom metrics  ──►  dashboards / SLOs / Davis anomaly detection
```

## 2. Metrics API v2 — the line protocol (simplest)

Dynatrace metric ingest uses a compact line format:

```
<metric.key>,<dim1>=<v1>,<dim2>=<v2> <value> <timestamp_ms>
```

Example payload for a finished pipeline run:

```
databricks.job.duration_seconds,job=silver_wellbore,env=prod 412 1730419200000
databricks.job.rows_written,job=silver_wellbore,env=prod 1543221 1730419200000
databricks.job.success,job=silver_wellbore,env=prod 1 1730419200000
```

Key rules:
- Metric keys are dot-namespaced; register/auto-create on first ingest.
- Dimensions are low-cardinality labels (job name, env, region) — **not** run_id
  (high cardinality blows up metric series).
- Value is numeric; timestamp is epoch **milliseconds** (optional — defaults to now).

Full sender: `implementations/dynatrace/pattern-3-push-metrics/push_job_metrics.py`.

## 3. Where to put the push (two placements)

### Placement A — a final "report" task on the job (recommended start)
Add a small task to the orchestration job that runs **after** the pipelines, reads the
run outcome from the Jobs API / DLT event log, and pushes summary metrics. One place,
covers the whole medallion. Wire into `edm_medallion.job.yml` as a trailing task with
`depends_on` all gold tasks and `run_if: ALL_DONE` so it fires even on partial failure.

### Placement B — inside each transformation (richer, needs DE)
Emit metrics/spans from within the PySpark transforms (row counts before/after dedup,
per-step duration). This is the same instrumentation-point decision as Phase 7 Part B —
**requires data engineering** to choose what's worth measuring. Best via OTLP so it
reuses the Phase 7 SDK setup.

## 4. OTLP variant (ties into Phase 7)

Dynatrace ingests OTLP natively, so the Phase 7 OpenTelemetry collector/exporter can
target Dynatrace with just endpoint + token config — no CloudWatch needed:

```
exporter endpoint: https://<tenant>/api/v2/otlp/v1/metrics   (and /traces, /logs)
header:            Authorization: Api-Token dt0c01.XXXX
scopes:            metrics.ingest, openTelemetryTrace.ingest, logs.ingest
```

So: **Pattern 3 via OTLP == Phase 7 with a Dynatrace backend.** If you're doing Phase 7
anyway, do the metrics push through the same OTLP path rather than the Metrics API v2.
Config: `implementations/dynatrace/pattern-3-push-metrics/otlp_exporter.md`.

## 5. Prerequisites

- Dynatrace API token with `metrics.ingest` (+ `openTelemetryTrace.ingest`,
  `logs.ingest` for OTLP traces/logs).
- Token stored in a **Databricks secret scope** (e.g. `dynatrace/api-token`), read at
  runtime with `dbutils.secrets.get`. Never hardcode.
- Outbound network path from the job compute to the Dynatrace tenant (egress via NAT
  / proxy). On serverless, confirm egress is allowed to the tenant host.
- The tenant/environment URL.

## 6. Step-by-step (Metrics API v2, Placement A)

1. Create a Dynatrace API token with `metrics.ingest`; store it:
   `databricks secrets put --scope dynatrace --key api-token`.
2. Add `push_job_metrics.py` as a task script in the DAB repo (e.g. `ops/`).
3. Add a trailing task to `edm_medallion.job.yml`:
   ```yaml
   - task_key: report_metrics_to_dynatrace
     depends_on: [ { task_key: gold_well }, { task_key: gold_wellbore }, ... ]
     run_if: ALL_DONE            # fire even if an upstream task failed
     spark_python_task:
       python_file: ../ops/push_job_metrics.py
   ```
4. In the script, read outcome (success/duration/rows) from the run context / Jobs API
   / DLT event log, build metric lines, POST to `/api/v2/metrics/ingest`.
5. Build a Dynatrace dashboard + SLO on `databricks.job.*` metrics.

## 7. Verification

- After a run, `databricks.job.duration_seconds` and `…success` appear in Dynatrace
  Metrics (Data Explorer) with the right dimensions.
- A failed run pushes `success=0`; a Dynatrace metric-event/SLO on that flips.

## 8. Pros / cons / gotchas

**Pros**
- Richest data — real per-run numbers for dashboards, SLOs, Davis anomaly detection.
- Serverless-safe (app-level push, no agent).
- OTLP variant reuses Phase 7 — one instrumentation, choice of backend.

**Cons / gotchas**
- **Cardinality** — never put `run_id` / timestamps as dimensions; use job/env/region
  only or you'll explode metric series (and cost).
- **Push can't report its own outage** — if the job dies before the report task, no
  metric is sent (that's exactly why you *also* want Pattern 2 as the external
  watchdog, and Pattern 4 for the failure event).
- **Egress** — serverless/private networking must allow outbound HTTPS to the tenant.
- **Token scope/rotation** — least-privilege token in a secret scope; rotate on a
  schedule.
- **Timestamp units** — epoch **milliseconds**; a seconds value lands the metric in
  1970.
