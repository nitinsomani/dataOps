# Phase 23: OpenTelemetry & Observability Integration (Dynatrace/Prometheus/Grafana) — Detailed Notes

> **Goal**: Databricks system tables (Phase 11) give you Databricks-native observability, but most product companies run a **unified, vendor-neutral observability stack** spanning every system, not just Databricks. This phase covers instrumenting Databricks/Spark workloads with OpenTelemetry and routing that telemetry into Prometheus/Grafana and/or Dynatrace.

---

## 1. Why OpenTelemetry Matters Here (Beyond Phase 11's System Tables)

- **System tables** (`system.lakeflow.*`, `system.query.history`) are Databricks-specific — great for Databricks-only questions, but they don't unify with the rest of a company's infrastructure (microservices, Kafka brokers, Airflow, Kubernetes).
- **OpenTelemetry (OTel)** is a vendor-neutral, CNCF standard for generating and exporting **traces, metrics, and logs** — the same instrumentation code works regardless of which backend (Prometheus, Grafana, Dynatrace, Datadog, Jaeger) ultimately receives the data. This avoids vendor lock-in and gives a **single pane of glass** across a heterogeneous stack, with Databricks pipelines showing up alongside every other service.
- As a DataOps engineer, you're often the one bridging "Databricks-native monitoring" with "the company's existing observability platform" — this phase is squarely that bridge.

---

## 2. The Three Signal Types

```
Traces   → a request/job's journey across components, as a tree of spans with timing
Metrics   → numeric measurements over time (counters, gauges, histograms)
Logs       → timestamped text/structured records, correlatable to traces via trace ID
```

- A **span** is a single unit of work within a trace (e.g., "read Bronze table," "run MERGE," "write Gold table") with a start/end time, attributes (key-value metadata), and a parent-child relationship to other spans.
- **Context propagation**: the mechanism (W3C Trace Context `traceparent` header) that lets a trace ID flow across process/service boundaries — e.g., from an Airflow task that triggers a Databricks job, through to the job's internal processing, so the whole chain appears as one connected trace instead of disconnected fragments.

---

## 3. OpenTelemetry Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────────────┐
│  Instrumented     │     │  OTel Collector    │     │      Backends            │
│  Application       │────►│  (receivers →      │────►│  Prometheus / Grafana     │
│  (OTel SDK)          │OTLP │   processors →      │OTLP/│  Dynatrace / Jaeger        │
│  Spark job, notebook,│     │   exporters)          │other │                             │
│  microservice          │     └──────────────────┘  proto  └─────────────────────────┘
└─────────────────┘
```

- **SDK**: instrumentation library added to your application code (Python, Java) that creates spans/metrics and exports them — either automatically (auto-instrumentation agents that patch common libraries) or manually (explicit `start_span()`/counter calls in your code).
- **OTLP (OpenTelemetry Protocol)**: the standard wire format/protocol for sending telemetry from SDK → Collector → backend.
- **Collector**: a standalone process that receives telemetry, processes it (batching, filtering, sampling, adding attributes), and exports it to one or more backends — this is the piece that decouples your instrumented application from any specific vendor. Two deployment modes:
  - **Agent mode**: one Collector per host/node (e.g., a DaemonSet in Kubernetes, or an init-script-installed process on a Databricks cluster node) — closer to the source, lower latency.
  - **Gateway mode**: a centralized Collector tier (fewer, larger instances) that agents forward to — centralizes processing, sampling, and fan-out to multiple backends.

---

## 4. OTel Collector Configuration (The Core Skill)

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch: {}
  resourcedetection:
    detectors: [env, system]
  attributes:
    actions:
      - key: databricks.job_id
        action: insert
        value: ${env:DATABRICKS_JOB_ID}

exporters:
  prometheusremotewrite:
    endpoint: "http://prometheus:9090/api/v1/write"
  otlphttp/dynatrace:
    endpoint: "https://<env-id>.live.dynatrace.com/api/v2/otlp"
    headers:
      Authorization: "Api-Token ${env:DYNATRACE_API_TOKEN}"
  logging: {}

service:
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [resourcedetection, attributes, batch]
      exporters: [prometheusremotewrite, otlphttp/dynatrace]
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlphttp/dynatrace, logging]
```

- **Receivers**: how telemetry enters the Collector (`otlp` is the standard; others exist for scraping Prometheus endpoints, host metrics, etc.).
- **Processors**: transform/filter/enrich telemetry in-flight — `batch` (efficiency), `resourcedetection` (auto-tag with host/cloud metadata), `attributes` (add custom tags like a Databricks job ID for correlation), sampling processors for traces.
- **Exporters**: where telemetry goes — you can fan out to **multiple backends simultaneously** (e.g., Prometheus AND Dynatrace during a migration period).
- **Pipelines**: wire receivers → processors → exporters per signal type (metrics/traces/logs each have their own pipeline).

---

## 5. Instrumenting Databricks/Spark Workloads

### Python-side (driver code, notebooks, Jobs)
```python
from opentelemetry import trace, metrics
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource

resource = Resource.create({
    "service.name": "sales-etl-pipeline",
    "databricks.job.id": dbutils.widgets.get("job_id") if "dbutils" in dir() else "local",
})
provider = TracerProvider(resource=resource)
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint="http://otel-collector:4317", insecure=True)))
trace.set_tracer_provider(provider)

tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span("bronze_to_silver_transform") as span:
    row_count = silver_df.count()
    span.set_attribute("rows_processed", row_count)
    silver_df.write.format("delta").mode("overwrite").saveAsTable("silver.orders")
```
- Wrapping pipeline stages in spans gives you **per-stage timing** visible in a trace waterfall, correlated with custom attributes (row counts, table names) — much richer than a plain log line.
- Custom metrics (counters/histograms) can track things like "rows processed per run" or "MERGE duration" as time-series data queryable in Grafana/Dynatrace, independent of any single run's trace.

### JVM-side (Spark driver/executor internals)
- Spark's own Dropwizard-based metrics system can be bridged to OTel, or more commonly, the **OpenTelemetry Java agent** (a javaagent) is attached to the Spark driver/executor JVM processes to auto-instrument JVM metrics (GC, memory, thread pools) without code changes.
- On Databricks specifically, this is done via a **cluster init script** that downloads the OTel Java agent and injects it into the Spark JVM's startup flags (`spark.driver.extraJavaOptions`/`spark.executor.extraJavaOptions`), since you can't manually attach an agent to a running managed JVM the way you might on a self-hosted server.

```bash
#!/bin/bash
# init script: install and attach OTel Java agent
set -euo pipefail
wget -O /databricks/jars/opentelemetry-javaagent.jar \
  https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar

cat >> /databricks/driver/conf/spark-branch.conf << EOF
[driver] {
  "spark.driver.extraJavaOptions" = "-javaagent:/databricks/jars/opentelemetry-javaagent.jar -Dotel.exporter.otlp.endpoint=http://otel-collector:4317 -Dotel.service.name=databricks-spark-driver"
}
EOF
```

---

## 6. Routing to Prometheus + Grafana

- **Prometheus is pull-based** by default (it scrapes a `/metrics` endpoint), while OTel is fundamentally **push-based** (SDKs push to a Collector). Two ways to bridge this:
  1. Collector's **`prometheus` exporter**: exposes an in-memory `/metrics` endpoint that Prometheus scrapes as usual — Collector acts as the bridge, no Prometheus-side changes needed.
  2. Collector's **`prometheusremotewrite` exporter**: actively pushes metrics into Prometheus (or a remote-write-compatible store like Cortex/Mimir/Thanos) — better for high cardinality/volume and avoids Prometheus needing to discover/scrape every ephemeral Databricks job cluster.
- **Grafana** then visualizes Prometheus as a data source — dashboards, alerting rules (via Grafana Alerting or Prometheus Alertmanager). For traces/logs, the fuller "LGTM stack" (Loki for logs, Grafana Tempo for traces, Mimir/Prometheus for metrics) gives a complete, fully open-source OTel-native backend if a company wants to avoid a commercial APM vendor entirely.

---

## 7. Routing to Dynatrace

- Dynatrace has a **native OTLP ingestion endpoint** (`https://<env-id>.live.dynatrace.com/api/v2/otlp`), authenticated via an API token — the Collector's `otlphttp` exporter points directly there, no separate Dynatrace-specific exporter plugin needed since Dynatrace speaks standard OTLP.
- Dynatrace's value proposition over self-hosted Prometheus/Grafana: **Davis AI** (automated root-cause analysis and anomaly detection without manually authoring alert rules), **OneAgent** (a single auto-instrumentation agent that can attach to a host/process with minimal configuration, versus manually configuring OTel SDKs everywhere), and a unified commercial SaaS platform (traces+metrics+logs+infra all correlated automatically) — at the cost of licensing spend versus the "free but you operate it yourself" nature of Prometheus/Grafana/Loki/Tempo.
- Many enterprises run **both**: Dynatrace for infrastructure/APM-wide, AI-driven monitoring across the whole company, with Databricks-specific pipelines optionally also feeding Prometheus/Grafana for data-engineering-team-specific dashboards that don't need Dynatrace's full feature set.

---

## 8. Migration Strategy: Moving to a Unified OTel-Based Stack

```
1. Stand up an OTel Collector (start with Gateway mode, centrally managed)
2. Instrument one pipeline first (not everything at once) — add OTel SDK spans/metrics
3. Configure the Collector to fan out to BOTH the old monitoring approach AND the new backend(s)
   simultaneously during validation — never cut over blind
4. Validate parity: do dashboards/alerts show consistent data between old and new?
5. Cut traffic/alerting responsibility to the new backend
6. Decommission the old exporter/pipeline once confidence is established
7. Repeat pipeline-by-pipeline rather than a big-bang company-wide switch
```
- This mirrors the same incremental migration discipline from Phase 15/Phase 19's schema migration advice — dual-running before cutover is the safe pattern for any observability migration too.

---

## 9. Sampling — Critical for High-Volume Spark Workloads

- **Head-based sampling**: decide whether to keep a trace at its *start* (e.g., keep 10% of all traces) — simple, cheap, but risks discarding exactly the rare failed/slow traces you'd want to investigate.
- **Tail-based sampling**: decide *after* seeing the full trace (e.g., always keep traces that errored or exceeded a latency threshold, sample the rest at a low rate) — much more useful for debugging, but requires the Collector to buffer complete traces before deciding, which costs more memory/complexity (usually requires a gateway-mode Collector tier).
- For a Spark ETL pipeline with thousands of tasks per job, tail-based sampling on the **job/stage-level spans** (not per-task) is usually the practical granularity — per-task span volume would overwhelm most backends.

---

## 10. Security & Network Considerations (ties to Phase 7)

- The OTel Collector endpoint must be reachable from the Databricks Data Plane (VPC) — typically a private endpoint/internal load balancer, never a public endpoint for internal telemetry.
- Dynatrace API tokens and any Collector-side credentials should be stored in Databricks secret scopes (Phase 7), injected as environment variables into cluster init scripts or job configuration — never hardcoded.
- Use `otlphttp`/`otlpgrpc` with TLS in transit; for cross-VPC/cross-account telemetry shipping, apply the same PrivateLink/VPC-peering considerations as any other cross-network traffic (Phase 7/16).

---

## 11. Key Takeaways for DataOps

- OTel's core value is **vendor neutrality** — instrument once, route anywhere (Prometheus, Grafana/Tempo/Loki, Dynatrace, or all simultaneously) — a strong signal in interviews that you think about observability architecture, not just "which dashboard tool."
- The **Collector** is the piece that matters most operationally — receivers/processors/exporters pipeline design is the actual skill being tested, not just "install an SDK."
- Know the **pull vs push** mismatch between OTel (push) and classic Prometheus (pull), and the two ways the Collector bridges it (`prometheus` exporter vs `prometheusremotewrite`).
- For Databricks specifically: Python-side instrumentation is straightforward (standard OTel SDK), JVM-side requires an init-script-installed Java agent since you can't manually attach to a managed cluster's JVM.
- Always frame a migration as incremental dual-export + validation, never a blind cutover.
