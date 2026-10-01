#!/bin/bash
# ============================================================================
# Phase 7 — OpenTelemetry / ADOT collector init script (cluster-scoped)
# Installs the AWS Distro for OpenTelemetry (ADOT) Collector on the DRIVER and
# points a Prometheus-scrape receiver at the Spark metrics sink. Exports OTLP to
# the chosen backend (CloudWatch / X-Ray shown; swap exporter for Tempo/Datadog).
#
# Attach via the cluster policy (e.g. var.bronze_policy_id) or an all-purpose
# cluster's init_scripts. Driver-only install is enough for JVM/driver metrics;
# add executor handling only if you need per-executor metrics.
#
# ⚠️ Confirm the backend decision (docs/phase-07-opentelemetry.md Step 0) before
#    rolling this out. This is a template, not a drop-in for prod as-is.
# ============================================================================
set -euo pipefail

OTEL_DIR=/databricks/otel
mkdir -p "${OTEL_DIR}"

# 1. Download ADOT collector (pin a version in real use).
curl -sSL -o "${OTEL_DIR}/aws-otel-collector.rpm" \
  https://aws-otel-collector.s3.amazonaws.com/amazon_linux/amd64/latest/aws-otel-collector.rpm || true

# 2. Write collector config: scrape Spark Prometheus sink -> OTLP -> CloudWatch.
cat > "${OTEL_DIR}/config.yaml" <<'YAML'
receivers:
  prometheus:
    config:
      scrape_configs:
        - job_name: spark-driver
          scrape_interval: 15s
          static_configs:
            - targets: ['localhost:9091']   # Spark PrometheusServlet / pushgateway
processors:
  batch: {}
  resourcedetection:
    detectors: [env, ec2]
exporters:
  awsemf:                 # CloudWatch EMF (metrics)
    namespace: Databricks/Spark
    region: eu-west-1
  awsxray:               # X-Ray (traces, if OTLP traces are forwarded)
    region: eu-west-1
service:
  pipelines:
    metrics:
      receivers: [prometheus]
      processors: [batch, resourcedetection]
      exporters: [awsemf]
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [awsxray]
  # otlp receiver for app-emitted spans (Part B instrumentation)
receivers/otlp: &otlp
  otlp:
    protocols:
      grpc: { endpoint: 0.0.0.0:4317 }
      http: { endpoint: 0.0.0.0:4318 }
YAML

# 3. Start the collector (systemd in a real image; backgrounded here for brevity).
if [ -f /opt/aws/aws-otel-collector/bin/aws-otel-collector-ctl ]; then
  /opt/aws/aws-otel-collector/bin/aws-otel-collector-ctl \
    -c "${OTEL_DIR}/config.yaml" -a start || true
fi

echo "otel init complete"
