# Phase 23: OpenTelemetry & Observability Integration — Cheat Sheet

---

## Three Signal Types

```
Traces  → request/job journey as spans (parent-child, timing, attributes)
Metrics → counters/gauges/histograms over time
Logs    → timestamped records, correlate to traces via trace ID
```

## Architecture

```
App (OTel SDK) --OTLP--> Collector (receivers→processors→exporters) --OTLP/other--> Backend(s)
                                                                        (Prometheus, Grafana, Dynatrace, Jaeger)
```

## Collector Deployment Modes

```
Agent mode    → one per host/node (DaemonSet, cluster init script) — low latency
Gateway mode  → centralized tier, agents forward to it — centralized sampling/processing/fan-out
```

## Collector Pipeline Skeleton

```yaml
receivers:
  otlp: {protocols: {grpc: {endpoint: 0.0.0.0:4317}, http: {endpoint: 0.0.0.0:4318}}}
processors:
  batch: {}
  attributes: {actions: [{key: databricks.job_id, action: insert, value: ${env:JOB_ID}}]}
exporters:
  prometheusremotewrite: {endpoint: "http://prometheus:9090/api/v1/write"}
  otlphttp/dynatrace: {endpoint: "https://<env>.live.dynatrace.com/api/v2/otlp", headers: {Authorization: "Api-Token ${env:DT_TOKEN}"}}
service:
  pipelines:
    metrics: {receivers: [otlp], processors: [batch], exporters: [prometheusremotewrite, otlphttp/dynatrace]}
    traces:  {receivers: [otlp], processors: [batch], exporters: [otlphttp/dynatrace]}
```

## Python Instrumentation Skeleton

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

provider = TracerProvider()
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint="http://otel-collector:4317", insecure=True)))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span("transform_stage") as span:
    span.set_attribute("rows_processed", count)
```

## JVM-Side (Spark Driver/Executor) via Init Script

```bash
wget -O /databricks/jars/otel-agent.jar <release-url>
# add to spark.driver.extraJavaOptions / spark.executor.extraJavaOptions:
# -javaagent:/databricks/jars/otel-agent.jar -Dotel.exporter.otlp.endpoint=...
```

## Pull vs Push Bridge (Prometheus)

```
prometheus exporter            → Collector exposes /metrics, Prometheus scrapes (pull) — simple
prometheusremotewrite exporter  → Collector actively pushes to Prometheus/Mimir/Cortex/Thanos — better at scale
```

## Prometheus/Grafana (OSS) vs Dynatrace (Commercial) 

| | Prometheus/Grafana(+Loki/Tempo) | Dynatrace |
|-|----------------------------------|-----------|
| Model | Self-hosted, OSS, pull-based metrics | SaaS, OneAgent auto-instrumentation |
| Alerting | Manual rules (Alertmanager/Grafana) | Davis AI (automated anomaly detection/RCA) |
| Cost | Infra + ops time | Licensing |
| OTLP support | Via Collector exporters | Native OTLP endpoint |

## Sampling Strategies

```
Head-based → decide at trace start (cheap, may drop rare failures)
Tail-based → decide after full trace seen (keeps errors/slow traces, needs gateway buffering)
```
For Spark: sample at job/stage-level spans, not per-task (too high volume).

## Migration Checklist

```
[ ] Stand up Collector (gateway mode)
[ ] Instrument ONE pipeline first, not everything at once
[ ] Dual-export to old + new backend during validation
[ ] Validate parity before cutover
[ ] Decommission old path only after confidence established
```

## Security Checklist

```
[ ] Collector endpoint reachable via private network path only (Phase 7)
[ ] API tokens/credentials in secret scopes, not hardcoded
[ ] TLS on OTLP in transit
```
