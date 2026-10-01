# Phase 7 — OpenTelemetry (Cluster Metrics + Custom Pipeline Tracing)

**Pillar:** Deep telemetry  ·  **Owner:** Platform + ⚠️ **Data Engineering**  ·  **Effort:** Large  ·  **Repo:** both

## Objective

Go beyond what system tables can see: **JVM/executor internals** (GC, memory,
shuffle, disk spill) and **custom business spans** inside transformations
(e.g. *"dedup wellbore records took 4.2s"*). Export to an OTLP backend.

> Nothing OTel-related exists in either repo today — this phase is net-new and is the
> heaviest lift. Do the system-table phases (2, 4) first; only reach for OTel when
> you need internals they can't provide.

## Step 0 — Decide the backend (blocking)

| Option | Pros | Cons |
|--------|------|------|
| **AWS ADOT → CloudWatch / X-Ray** | No infra to run; fits the AWS-centric estate; IAM-native | AWS-only; X-Ray trace UX is basic |
| Grafana Tempo + Prometheus | Best trace/metric UX; open source | You run/operate it |
| Datadog / Honeycomb (SaaS) | Turnkey, great UX | Cost; data leaves AWS |

**Recommendation for this estate:** ADOT → CloudWatch/X-Ray (least new infra, aligns
with existing AWS budgets/flow-logs work in Phase 6).

## Part A — Cluster & JVM metrics (platform)

Cluster-scoped **init script** that:

1. Installs the OpenTelemetry Collector (or ADOT Collector) on the driver.
2. Configures Spark to emit metrics (`spark.metrics.conf` / `metrics.properties`) to a
   Prometheus/StatsD sink the collector scrapes.
3. Collector exports OTLP → chosen backend.

Example init script + Spark metrics config:
`implementations/phase-07-otel/otel-init.sh` and `metrics.properties`.

Attach via the cluster policy used by the bronze DLT cluster
(`var.bronze_policy_id`) / all-purpose clusters.

### What this gives you beyond system tables

GC pauses, executor memory pressure, shuffle read/write, disk spill bytes,
task-level skew — none of which `system.compute.*` exposes.

## Part B — Custom pipeline tracing (⚠️ needs Data Eng)

Add `opentelemetry-sdk` + OTLP exporter to the PySpark transformation code and wrap
**meaningful business steps** in spans:

```python
from opentelemetry import trace
tracer = trace.get_tracer("silver_wellbore")

with tracer.start_as_current_span("dedup_wellbore_records") as span:
    span.set_attribute("input_rows", input_count)
    df = deduplicate(df)
    span.set_attribute("output_rows", df.count())
```

Pattern: `implementations/phase-07-otel/instrumentation_example.py`.

### ⚠️ Why Data Eng is needed here

Platform can install the collector and export plumbing solo. But **choosing what's
worth a span** — which functions, which attributes, what "step" means in the wells
domain — requires whoever owns the transformation logic. This is best done as a
pairing session, not generated blind. Instrumenting the wrong points produces noise
and overhead with no insight.

## Part C — Log correlation (optional)

`cluster_log_conf` → S3, collector tails driver/executor logs, forwards as OTLP logs
tagged with `trace_id` so a slow trace links straight to its logs.

## Best practice applied

- **System tables first, OTel for the gaps** — don't re-instrument what
  `system.*` already gives you.
- **Semantic spans, not blanket auto-instrumentation** — a few meaningful business
  spans beat thousands of framework spans nobody reads.
- **Correlate the three signals** — metrics ↔ traces ↔ logs via `trace_id`.

## Verification

- Driver metrics appear in the backend (GC/memory dashboards).
- A traced pipeline run produces a span waterfall with the custom business spans.

## Ownership & DE involvement

**Split.** Parts A & C: platform. Part B: **requires data engineering** for
instrumentation-point selection. Backend choice (Step 0) is a joint decision.
