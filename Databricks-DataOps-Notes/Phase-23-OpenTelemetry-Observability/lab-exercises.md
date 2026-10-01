# Phase 23: OpenTelemetry & Observability Integration — Lab Exercises

> Requires Docker/Docker Compose locally. Simulates the full pipeline: instrumented app → Collector → Prometheus/Grafana, with a Dynatrace export step you can adapt if you have a trial tenant.

---

## Lab 1: Stand Up an OTel Collector + Prometheus + Grafana Stack

```yaml
# docker-compose.yml
version: "3.8"
services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    volumes:
      - ./otel-collector-config.yaml:/etc/otelcol-contrib/config.yaml
    ports: ["4317:4317", "4318:4318"]

  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports: ["9090:9090"]

  grafana:
    image: grafana/grafana:latest
    ports: ["3000:3000"]
```

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc: {endpoint: 0.0.0.0:4317}
      http: {endpoint: 0.0.0.0:4318}
processors:
  batch: {}
exporters:
  prometheus:
    endpoint: 0.0.0.0:8889
  logging: {}
service:
  pipelines:
    metrics: {receivers: [otlp], processors: [batch], exporters: [prometheus, logging]}
    traces: {receivers: [otlp], processors: [batch], exporters: [logging]}
```

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'otel-collector'
    static_configs:
      - targets: ['otel-collector:8889']
```

```bash
docker compose up -d
```

### Questions to Answer
- [ ] Visit `http://localhost:9090/targets` — is the `otel-collector` target showing as UP?
- [ ] Visit `http://localhost:3000` (Grafana) and add Prometheus (`http://prometheus:9090`) as a data source — does it connect successfully?

---

## Lab 2: Instrument a Simulated PySpark Job with OTel Python SDK

```bash
pip install opentelemetry-sdk opentelemetry-exporter-otlp
```

```python
# simulated_pipeline.py
import time, random
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.resources import Resource

resource = Resource.create({"service.name": "lab23-sales-etl"})

trace.set_tracer_provider(TracerProvider(resource=resource))
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter(endpoint="localhost:4317", insecure=True))
)
tracer = trace.get_tracer(__name__)

metrics.set_meter_provider(MeterProvider(
    resource=resource,
    metric_readers=[PeriodicExportingMetricReader(OTLPMetricExporter(endpoint="localhost:4317", insecure=True))]
))
meter = metrics.get_meter(__name__)
rows_processed_counter = meter.create_counter("rows_processed")

def bronze_to_silver():
    with tracer.start_as_current_span("bronze_to_silver") as span:
        time.sleep(random.uniform(0.5, 1.5))
        rows = random.randint(1000, 5000)
        span.set_attribute("rows_processed", rows)
        rows_processed_counter.add(rows, {"stage": "silver"})

def silver_to_gold():
    with tracer.start_as_current_span("silver_to_gold") as span:
        time.sleep(random.uniform(0.3, 0.8))
        rows = random.randint(500, 2000)
        span.set_attribute("rows_processed", rows)
        rows_processed_counter.add(rows, {"stage": "gold"})

with tracer.start_as_current_span("full_pipeline_run"):
    bronze_to_silver()
    silver_to_gold()

print("Pipeline run complete, telemetry exported.")
time.sleep(3)   # give the batch exporter time to flush
```

```bash
python simulated_pipeline.py
```

### Questions to Answer
- [ ] Check the OTel Collector's logs (`docker compose logs otel-collector`) — do you see the trace spans and metric data points logged?
- [ ] In Grafana, build a simple panel querying `rows_processed_total` from Prometheus — does it show the counter incrementing across runs?

---

## Lab 3: Build a Grafana Dashboard and Alert Rule

1. In Grafana, create a new dashboard with a panel showing `rate(rows_processed_total[5m])`.
2. Add a second panel showing pipeline run count over time.
3. Create an alert rule: fire if `rows_processed_total` for the `gold` stage is 0 over a 10-minute window (simulating a "pipeline ran but processed nothing" freshness-style alert, tying back to Phase 11).

### Questions to Answer
- [ ] Trigger the alert condition (stop running the simulated pipeline for 10+ minutes) — does the alert fire?
- [ ] What Phase 11 concept does this alert rule directly parallel (hint: freshness/volume checks)?

---

## Lab 4: Simulate Dual-Export During a Migration

```yaml
# updated otel-collector-config.yaml exporters section
exporters:
  prometheus:
    endpoint: 0.0.0.0:8889
  otlphttp/mock_dynatrace:
    endpoint: "http://mock-dynatrace-receiver:4318"   # or use a real trial tenant endpoint
    headers:
      Authorization: "Api-Token FAKE_TOKEN_FOR_LAB"
  logging: {}

service:
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheus, otlphttp/mock_dynatrace, logging]   # fan-out to BOTH
```

### Questions to Answer
- [ ] Re-run the simulated pipeline — do metrics now appear both in Prometheus AND get attempted-sent to the second exporter (check Collector logs for errors if using a fake endpoint)?
- [ ] Why is this dual-export pattern the safer approach compared to switching the exporter list outright in one step?

---

## Lab 5: Add Resource Attributes for Databricks Correlation

```yaml
processors:
  batch: {}
  attributes:
    actions:
      - key: databricks.job_id
        action: insert
        value: "123456"
      - key: databricks.run_id
        action: insert
        value: "789"
```

### Questions to Answer
- [ ] After adding this processor, do the exported spans/metrics now carry `databricks.job_id`/`databricks.run_id` attributes (check Collector's `logging` exporter output)?
- [ ] How would you use these attributes to cross-reference a trace in Grafana/Dynatrace with the corresponding row in `system.lakeflow.job_run_timeline` (Phase 11)?

---

## Lab 6: Write a Databricks Init Script for JVM Auto-Instrumentation (Design Exercise)

**Objective**: Without necessarily running this on a real cluster, write and review the init script.

```bash
#!/bin/bash
set -euo pipefail

AGENT_URL="https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar"
AGENT_PATH="/databricks/jars/opentelemetry-javaagent.jar"

echo "Downloading OTel Java agent..."
curl -sSL -o "$AGENT_PATH" "$AGENT_URL"

echo "Configuring Spark driver/executor JVM options..."
cat >> /databricks/driver/conf/otel-javaagent.conf << EOF
[driver] {
  "spark.driver.extraJavaOptions" = "-javaagent:$AGENT_PATH -Dotel.exporter.otlp.endpoint=http://otel-collector.internal:4317 -Dotel.service.name=databricks-driver"
}
[executor] {
  "spark.executor.extraJavaOptions" = "-javaagent:$AGENT_PATH -Dotel.exporter.otlp.endpoint=http://otel-collector.internal:4317 -Dotel.service.name=databricks-executor"
}
EOF

echo "Init script completed successfully."
```

### Questions to Answer
- [ ] What would happen if `AGENT_URL` were unreachable due to the Databricks Data Plane having no internet egress (tying to Phase 7's network isolation) — how would you fix this (hint: host the jar in an internal artifact repo/S3 bucket instead)?
- [ ] Why does this script use `set -euo pipefail` (Phase 21) and explicit `echo` logging at each step?
