# Dynatrace ↔ Databricks Integration (Patterns 2, 3, 4)

> Learning + implementation reference for integrating Databricks **job/pipeline
> health** with Dynatrace, focused on the patterns that work on this estate's
> **serverless** compute. Pattern 1 (OneAgent) is documented only as a caveat
> because it does **not** work on serverless.

## Why this exists (the core mismatch)

Dynatrace was built to monitor **long-running services** that expose an HTTP
endpoint and run on a host where OneAgent can be installed. Databricks **jobs and
DLT pipelines are batch/scheduled** — they:

- do **not** expose a `/healthz` HTTP endpoint,
- run on **ephemeral** compute (a job cluster or serverless that appears, runs, and
  disappears),
- are **serverless** in most of this estate (`serverless: true` on the DLT pipelines).

So "health-check endpoint for a job" has to be *synthesised*. There are three ways
to do that without OneAgent — the three patterns below.

## The serverless constraint (read this first)

| Pattern | Mechanism | Serverless? | Why |
|--------:|-----------|:-----------:|-----|
| 1 — OneAgent (init script) | Agent on driver/executor host | ❌ **No** | Serverless forbids init scripts / host access |
| **2 — Synthetic monitor → Jobs REST API** | Dynatrace polls Databricks API | ✅ Yes | Fully external to Databricks compute |
| **3 — Push job status → Dynatrace** | Databricks posts metrics/traces (OTLP or Metrics API v2) | ✅ Yes | App-level push, no host agent |
| **4 — Webhook → Dynatrace events** | Job failure webhook → Dynatrace event ingest | ✅ Yes | Config-only on the Databricks side |

**On this estate, use Patterns 2–4.** Pattern 1 could only ever cover the single
classic **bronze** cluster (which has `serverless: false`), so it is not a general
solution here.

## The three patterns at a glance

```
                    ┌─────────────────────────────────────────────┐
                    │                 Dynatrace                    │
                    │  Synthetic │ Metrics API v2 │ Events API v2  │
                    │   monitors │  / OTLP ingest │   (problems)   │
                    └─────▲────────────▲─────────────────▲─────────┘
        Pattern 2 (pull)  │ Pattern 3  │ (push)  Pattern 4│ (push on failure)
          Dynatrace polls │ Databricks │ pushes  Databricks│ webhook/relay
                          │            │                   │
                   ┌──────┴─────┐ ┌────┴───────┐   ┌───────┴────────┐
                   │ Databricks │ │ Databricks │   │ Databricks job │
                   │ Jobs REST  │ │ job task   │   │ webhook_notif. │
                   │ API 2.1    │ │ (py: OTLP/ │   │ on_failure     │
                   │            │ │  Metrics)  │   │                │
                   └────────────┘ └────────────┘   └────────────────┘
```

| | Pattern 2 — Synthetic | Pattern 3 — Push metrics | Pattern 4 — Webhook events |
|--|----------------------|--------------------------|----------------------------|
| **Direction** | Dynatrace pulls | Databricks pushes | Databricks pushes (on failure) |
| **Best for** | "is the last run healthy" SLA/uptime | rich per-run metrics, dashboards, trends | turning a failure into a Dynatrace problem/alert |
| **Latency** | poll interval (e.g. 5–15 min) | end-of-run (seconds) | on failure (seconds) |
| **Databricks change** | none (external) | a small task in the job | notification config (+ maybe a relay) |
| **Effort** | Low | Medium | Low–Medium |
| **Doc** | `pattern-2-synthetic-monitor.md` | `pattern-3-push-metrics.md` | `pattern-4-webhook-events.md` |

> **Implementing Pattern 4 in this repo?** See the tailored runbook
> `pattern-4-implementation-osdu-ssw-central-dbx.md` — it mirrors the existing
> **DuoCircle relay** (VPC Lambda + HTTP API Gateway) already running in
> `terraform/.../scops-core/`, so the relay is a copy with a different payload map.

## How they combine (recommended end state)

They are complementary, not either/or:

- **Pattern 4** gives you the *immediate alert* — a failed run becomes a Dynatrace
  problem in seconds.
- **Pattern 3** gives you the *rich metrics* — duration, row counts, per-pipeline
  trends — for dashboards and SLO/burn-rate analysis in Dynatrace.
- **Pattern 2** gives you the *independent black-box check* — even if Databricks
  can't push (auth broken, workspace down), Dynatrace still detects "the job's last
  run is stale/failed" from the outside.

Think of it as: **4 = paging, 3 = observability, 2 = watchdog-of-the-watchdog.**

## Prerequisites common to all three

1. A **Dynatrace tenant** URL, e.g. `https://<env-id>.live.dynatrace.com` (SaaS) or a
   Managed/ActiveGate environment URL.
2. A **Dynatrace API token** (`dt0c01.…`) with the right scopes per pattern:
   - Pattern 2: token to create synthetic monitors (or use Dynatrace Terraform/Monaco).
   - Pattern 3: `metrics.ingest` (and `openTelemetryTrace.ingest` if using OTLP traces).
   - Pattern 4: `events.ingest`.
3. A **Databricks PAT or service-principal OAuth** for Pattern 2 (Dynatrace calls the
   Databricks API) — least-privilege, read-only jobs scope.
4. Secrets stored properly — **never** hardcode tokens:
   - Databricks side: Databricks **secret scope** (this repo already uses
     `cds_secret_scope`; add a `dynatrace` scope with `api-token`).
   - Dynatrace side: store the Databricks PAT as a Dynatrace credential vault entry.

## How this maps to the main roadmap

Dynatrace is **not a new phase** — it's a *backend choice* for phases already in the
plan:

- **Phase 6 (canary)** → Pattern 2 is the Dynatrace-native form of the synthetic
  heartbeat.
- **Phase 7 (OpenTelemetry)** → Pattern 3 via OTLP: Dynatrace ingests OTLP natively,
  so the Phase 7 collector/exporter can target Dynatrace instead of CloudWatch.
- **Phase 1/5 (notifications/alerts)** → Pattern 4 routes failures to Dynatrace
  problems in addition to (or instead of) the Teams webhook.

Read the three pattern docs in order; each has full step-by-step notes + code in
`implementations/dynatrace/`.
