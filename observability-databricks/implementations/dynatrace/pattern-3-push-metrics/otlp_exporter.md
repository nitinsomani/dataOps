# Pattern 3 (OTLP variant) — Point the Phase 7 OpenTelemetry exporter at Dynatrace

Dynatrace ingests OTLP natively, so you do **not** need the Metrics API v2 sender if
you're already doing Phase 7. Just configure the OTel exporter to target Dynatrace.

## Endpoints

| Signal | Endpoint |
|--------|----------|
| Metrics | `https://<tenant>/api/v2/otlp/v1/metrics` |
| Traces  | `https://<tenant>/api/v2/otlp/v1/traces` |
| Logs    | `https://<tenant>/api/v2/otlp/v1/logs` |

## Auth

Header on every export:

```
Authorization: Api-Token dt0c01.XXXXXXXX
```

Token scopes: `metrics.ingest`, `openTelemetryTrace.ingest`, `logs.ingest`
(add only the ones you export).

## Collector config (replaces the awsemf/awsxray exporters in phase-07-otel/otel-init.sh)

```yaml
exporters:
  otlphttp/dynatrace:
    endpoint: https://<tenant>/api/v2/otlp
    headers:
      Authorization: "Api-Token ${DT_API_TOKEN}"

service:
  pipelines:
    metrics:
      receivers: [prometheus]
      processors: [batch, resourcedetection]
      exporters: [otlphttp/dynatrace]
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlphttp/dynatrace]
```

> `otlphttp` appends `/v1/metrics`, `/v1/traces`, `/v1/logs` to the base `endpoint`,
> which is why the base is `.../api/v2/otlp` (no trailing signal path).

## SDK exporter (Part B app spans → Dynatrace directly, no collector)

If you emit spans from the transformation code (Phase 7 Part B) and want them to go
straight to Dynatrace without a local collector:

```python
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

exporter = OTLPSpanExporter(
    endpoint="https://<tenant>/api/v2/otlp/v1/traces",
    headers={"Authorization": "Api-Token " + dbutils.secrets.get("dynatrace", "api-token")},
)
```

## Why prefer OTLP over Metrics API v2 here

- **One instrumentation, many backends** — the same OTel code can target CloudWatch,
  Dynatrace, Grafana, or Datadog by swapping the exporter. Metrics API v2 locks you to
  Dynatrace's proprietary line protocol.
- **Traces + logs, not just metrics** — Metrics API v2 is metrics-only; OTLP carries
  all three signals with correlation via `trace_id`.

## Gotchas

- Confirm your Dynatrace tenant has **OTLP ingest enabled** and the token has the
  matching `*.ingest` scopes.
- Serverless/private egress must reach the tenant host.
- Keep metric dimensions low-cardinality (same rule as the line-protocol variant).
