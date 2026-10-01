# Databricks Observability Program (`observability-dbx`)

A phased, code-first program to make the Databricks lakehouse observable across
**cost, reliability, data quality, performance, security, lineage, and table
health** — for both the central platform repo (`osdu-ssw-central-dbx`) and the
data-engineering DAB repo (`ssw-dbx-idl2-de`).

Everything here is **Infrastructure/Config as Code** — no click-ops. Dashboards,
alerts, notifications, and monitors are all defined in Terraform / DAB YAML /
SQL so they are reviewable, versioned, and reproducible across `dev → uat → prod`
and both regions (`us-east-1`, `eu-west-1`).

---

## How this directory is organised

```
observability-dbx/
├── README.md                     ← you are here (index + roadmap)
├── docs/                         ← one design note per phase + cross-cutting guides
│   ├── 00-overview-and-architecture.md
│   ├── phase-00-dashboards-parity.md
│   ├── phase-01-notifications.md
│   ├── phase-02-job-health-and-archival.md
│   ├── phase-03-data-quality.md
│   ├── phase-04-query-performance.md
│   ├── phase-05-alerts-and-slo.md
│   ├── phase-06-aws-and-canary.md
│   ├── phase-07-opentelemetry.md
│   ├── phase-08-security-audit.md
│   ├── phase-09-data-lineage.md
│   ├── phase-10-delta-table-health.md
│   ├── roles-and-ownership.md    ← who owns what; where a data engineer is required
│   ├── best-practices.md         ← industry practices this program maps to
│   ├── concepts/                 ← learning deep-dives (read to understand the "why")
│   │   ├── README.md             (concepts index + reading path)
│   │   ├── relay-pattern-explained.md
│   │   ├── relay-pattern-deep-dive.md
│   │   ├── vpc-nat-networking-deep-dive.md
│   │   ├── databricks-webhook-payload-deep-dive.md
│   │   ├── iam-oidc-auth-deep-dive.md
│   │   ├── databricks-jobs-rest-api-deep-dive.md
│   │   ├── dlt-event-log-deep-dive.md
│   │   ├── unity-catalog-system-tables-deep-dive.md
│   │   └── lakeview-dashboard-json-deep-dive.md
│   └── dynatrace/                ← Dynatrace integration patterns (serverless-safe)
│       ├── 00-overview.md
│       ├── pattern-2-synthetic-monitor.md
│       ├── pattern-3-push-metrics.md
│       ├── pattern-4-webhook-events.md
│       └── pattern-4-implementation-osdu-ssw-central-dbx.md
└── implementations/              ← copy-ready code (Terraform, DAB YAML, SQL, Python)
    ├── phase-01-notifications/
    ├── phase-02-job-health/
    ├── phase-03-data-quality/
    ├── phase-04-query-performance/
    ├── phase-05-alerts/
    ├── phase-06-aws-canary/
    ├── phase-07-otel/
    ├── phase-08-security-audit/
    ├── phase-09-lineage/
    ├── phase-10-delta-health/
    └── dynatrace/                ← Dynatrace pattern code
        ├── pattern-2-synthetic/  (http_monitor.tf, monaco_http_monitor.json)
        ├── pattern-3-push-metrics/ (push_job_metrics.py, otlp_exporter.md)
        └── pattern-4-webhook-events/ (relay_lambda.py, post_dynatrace_event.py, dynatrace-relay.tf, dab-wiring.snippet.yml)
```

## Concepts — learn the "why" behind the infrastructure

If any of the underlying tech is unfamiliar, start in **`docs/concepts/`** — a
self-contained learning track (with Mermaid diagrams, grounded in this repo's real
files) that explains everything the program stands on:

| Doc | Explains | Backs |
|-----|----------|-------|
| `relay-pattern-explained.md` / `relay-pattern-deep-dive.md` | the relay pattern (email + webhook), from concept to packets | DuoCircle + Dynatrace Pattern 4 |
| `vpc-nat-networking-deep-dive.md` | VPC/subnets/NAT/EIP/SG/VPC-endpoints (tied to `vpc.tf`) | all AWS-side infra |
| `databricks-webhook-payload-deep-dive.md` | what Databricks webhooks send + the Dynatrace mapping | Phase 1, Pattern 4 |
| `iam-oidc-auth-deep-dive.md` | GitHub OIDC → AWS STS, SP OAuth, which token to use where | all CI/auth |
| `databricks-jobs-rest-api-deep-dive.md` | Jobs API + run-state model | Pattern 2 |
| `dlt-event-log-deep-dive.md` | DLT event_log, update/flow progress, expectations | Phases 2 & 3 |
| `unity-catalog-system-tables-deep-dive.md` | the `system.*` telemetry all dashboards read | Phases 0, 2, 4, 8, 9, 10 |
| `lakeview-dashboard-json-deep-dive.md` | the `databricks_dashboard` serialized JSON structure | every dashboard phase |

See `docs/concepts/README.md` for the recommended reading order.

## Dynatrace integration (optional backend)

Dynatrace is **not a separate phase** — it's a backend choice for Phases 6 (canary) and
7 (OpenTelemetry) and a failure-routing target for Phases 1/5. Because most of this
estate is **serverless** (no OneAgent/init scripts), the viable patterns are the three
push/pull integrations documented in `docs/dynatrace/`:

| Pattern | Direction | Role | Doc |
|--------:|-----------|------|-----|
| 2 — Synthetic monitor → Jobs REST API | Dynatrace pulls | external watchdog / uptime SLA | `docs/dynatrace/pattern-2-synthetic-monitor.md` |
| 3 — Push metrics (Metrics API v2 / OTLP) | Databricks pushes | rich metrics, dashboards, SLOs | `docs/dynatrace/pattern-3-push-metrics.md` |
| 4 — Webhook → Dynatrace events | Databricks pushes on failure | instant paging / problems | `docs/dynatrace/pattern-4-webhook-events.md` |

Combine as: **4 = paging, 3 = observability, 2 = watchdog-of-the-watchdog.**
Pattern 1 (OneAgent) is omitted — it can't run on serverless (see `docs/dynatrace/00-overview.md`).

> The SQL in `implementations/` is written against Databricks **system tables**
> (`system.billing`, `system.lakeflow`, `system.access`, `system.query`,
> `system.compute`) and `information_schema`. In this estate the system catalog
> is surfaced as **`system_table_unitycatalog_prd`** (Shell internal) — see the
> existing `dashboards/dashboard-compute-cost.tf` for the precedent. Swap the
> catalog name to match the target workspace.

---

## Roadmap at a glance

| Phase | Title | Primary pillar | Owner | Effort |
|------:|-------|----------------|-------|--------|
| 0 | eu-west-1 dashboard parity + compute-policy compliance | Cost / capacity | Platform | S |
| 1 | Job & DLT pipeline notifications | Reliability | Platform | S |
| 2 | Job/pipeline health dashboard + system-table archival | Reliability | Platform | M |
| 3 | Data quality (DLT expectations + Lakehouse Monitoring) | Data quality | **Data Eng** | M |
| 4 | Query / warehouse performance dashboard | Performance | Platform | M |
| 5 | SQL alerts + SLA/SLO burn-rate alerting | Reliability | Platform (+DE for SLOs) | M |
| 6 | AWS observability + synthetic canary checks | Infra | Platform | M |
| 7 | OpenTelemetry (cluster metrics + custom tracing) | Deep telemetry | Platform + **Data Eng** | L |
| 8 | Security & audit observability | Security | Platform / Security | M |
| 9 | Data lineage (table/column) | Impact analysis | Platform | S |
| 10 | Delta table / lakehouse health | Cost / performance | Platform (+DE) | M |

Effort: S = small (hours), M = medium (days), L = large (week+).

**Recommended sequence:** 0 → 1 → 2 → 4 → 9 → 10 → 8 → 5 → 6 → 3 → 7.
Start with the copy-paste wins (0, 1) and the system-table dashboards (2, 4, 8, 9, 10)
because they reuse the existing `databricks_dashboard` Terraform pattern. Save the
two phases that need data-engineering domain input (3, 7) for when a DE is available.

---

## Where each phase is implemented

| Phase | Repo | Location |
|------:|------|----------|
| 0 | `osdu-ssw-central-dbx` | `terraform/{env}/{public,private}/eu-west-1/dashboards/` |
| 1 | `ssw-dbx-idl2-de` | `resources/*.pipeline.yml`, `resources/edm_medallion.job.yml` |
| 2, 4, 8, 9, 10 | `osdu-ssw-central-dbx` | `terraform/{env}/.../dashboards/` (new `.tf` dashboards) |
| 3 | `ssw-dbx-idl2-de` | pipeline `transformations/*.py` + new `resources/monitors.yml` |
| 5 | `osdu-ssw-central-dbx` | `terraform/.../dashboards/` (new `alerts.tf`) |
| 6 | `osdu-ssw-central-dbx` | `terraform/{env}/.../eu-west-1/scops-core/` |
| 7 | both | init scripts in central repo; instrumentation in DAB transforms |

---

## Guiding principles

1. **Everything as code** — reviewable in PRs, promoted through environments.
2. **System tables first** — prefer built-in `system.*` telemetry before bolting on
   external tooling; only reach for OTel/external APM where system tables can't reach
   (JVM internals, custom business spans).
3. **Alert on symptoms, page on impact** — route failures/SLO burn to the existing
   Teams webhook; keep dashboards for exploration, alerts for action.
4. **Least privilege** — dashboards/alerts inherit the existing admin/owner/user AD
   group permission pattern already used in the `dashboards` stack.
5. **Don't invent business rules** — data-quality expectations and trace points are
   owned by data engineering; platform provides the plumbing.

See `docs/roles-and-ownership.md` for the full RACI and `docs/best-practices.md`
for the mapping to the Databricks Well-Architected Framework.
