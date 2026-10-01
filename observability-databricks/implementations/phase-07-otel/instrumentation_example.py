"""
Phase 7 — Custom pipeline tracing PATTERN (example only).

⚠️  WHICH functions to trace and WHAT attributes to record is a Data-Engineering
    decision (see docs/phase-07-opentelemetry.md Part B). This shows the mechanics.

Install on the cluster (init script or %pip):
    pip install opentelemetry-sdk opentelemetry-exporter-otlp

The collector (otel-init.sh) listens on localhost:4317 (OTLP gRPC).
"""

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter


def init_tracing(service_name: str) -> trace.Tracer:
    """Wire the OTLP exporter once per driver session."""
    provider = TracerProvider(resource=Resource.create({"service.name": service_name}))
    provider.add_span_processor(
        BatchSpanProcessor(OTLPSpanExporter(endpoint="http://localhost:4317", insecure=True))
    )
    trace.set_tracer_provider(provider)
    return trace.get_tracer(service_name)


# --- Example usage inside a transformation (DE chooses the real span points) ---
def run_silver_wellbore(spark):
    tracer = init_tracing("silver_wellbore")

    with tracer.start_as_current_span("read_bronze") as span:
        df = spark.read.table("bronze_edm.wellbore")
        span.set_attribute("input_rows", df.count())

    with tracer.start_as_current_span("dedup_wellbore_records") as span:
        before = df.count()
        df = df.dropDuplicates(["uwi"])
        after = df.count()
        span.set_attribute("input_rows", before)
        span.set_attribute("output_rows", after)
        span.set_attribute("dropped_rows", before - after)

    with tracer.start_as_current_span("write_silver") as span:
        df.write.mode("overwrite").saveAsTable("silver_edm.wellbore")
        span.set_attribute("written_rows", df.count())

    return df
