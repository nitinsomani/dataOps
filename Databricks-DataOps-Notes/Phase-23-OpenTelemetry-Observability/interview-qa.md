# Phase 23: OpenTelemetry & Observability Integration — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ Why would a team adopt OpenTelemetry for Databricks pipelines instead of just relying on Databricks system tables or a vendor-specific SDK?

**Answer:**
Databricks system tables (Phase 11) are excellent for Databricks-native questions (job run history, query performance) but don't extend to the rest of a company's infrastructure — microservices, Kafka, Airflow, Kubernetes. OpenTelemetry is a vendor-neutral standard: the same instrumentation code exports traces/metrics/logs that can be routed to Prometheus, Grafana, Dynatrace, or any other OTLP-compatible backend, without rewriting instrumentation if the company later switches observability vendors. Using a vendor-specific SDK directly (e.g., Dynatrace's proprietary API) would work but locks the instrumentation to that vendor — OTel decouples "how you instrument" from "where the data ends up," which matters a lot for a platform team supporting many pipelines across a long time horizon.

---

## Q2. ⭐ Explain the role of the OpenTelemetry Collector and why you wouldn't just have applications export directly to a backend.

**Answer:**
The Collector sits between instrumented applications and the eventual backend(s), receiving telemetry (via OTLP), processing it (batching for efficiency, sampling to control volume, enriching with resource attributes like a Databricks job ID), and exporting it to one or more destinations. Without a Collector, every application would need to know the specific backend's API/auth details directly, and switching backends would require redeploying every instrumented application. With a Collector, applications only need to know one thing — the Collector's OTLP endpoint — and all backend-specific configuration, credential management, and even fan-out to multiple backends simultaneously (e.g., during a migration) lives centrally in the Collector's config, not scattered across every pipeline's code.

---

## Q3. How do you reconcile OpenTelemetry's push-based model with Prometheus's traditionally pull-based scraping model?

**Answer:**
The OTel Collector bridges this in one of two ways: the **`prometheus` exporter** makes the Collector expose an in-memory `/metrics` HTTP endpoint that Prometheus scrapes exactly as it would scrape any traditional application — no changes needed on the Prometheus side, but this still requires Prometheus to know how to discover/scrape the Collector. The **`prometheusremotewrite` exporter** instead has the Collector actively push metrics into Prometheus (or a remote-write-compatible long-term store like Mimir/Cortex/Thanos) — this scales better for high-cardinality or rapidly-changing infrastructure (like ephemeral Databricks job clusters that spin up and down constantly, which would be awkward for Prometheus to reliably discover and scrape via traditional service discovery).

---

## Q4. How would you instrument a PySpark job running as a Databricks Job to emit custom traces, and what would you actually capture?

**Answer:**
I'd add the OpenTelemetry Python SDK to the job's dependencies (via a wheel library or requirements, Phase 18's packaging practices), configure a `TracerProvider` with a resource identifying the pipeline (`service.name`, plus custom attributes like the Databricks `job_id`/`run_id` pulled from job parameters for correlation with system tables), and wrap each meaningful pipeline stage — Bronze ingestion, Silver transformation, Gold aggregation — in a span using `tracer.start_as_current_span()`. I'd capture attributes like row counts processed, table names read/written, and any data quality check results as span attributes, and export via `OTLPSpanExporter` pointed at the Collector's endpoint. This gives a trace waterfall view showing exactly how long each stage took and lets me correlate a specific failed or slow pipeline run with the exact stage responsible, rather than just knowing "the job failed" from the Databricks Jobs UI alone.

---

## Q5. How do you instrument the JVM-level internals of Spark (driver/executor) on a managed Databricks cluster, given you can't manually attach a Java agent the way you would on a self-hosted server?

**Answer:**
Since Databricks manages the cluster lifecycle, you can't SSH in and attach a `-javaagent` flag interactively — instead, this is done via a **cluster-scoped init script** that runs at cluster startup: it downloads the OpenTelemetry Java auto-instrumentation agent jar to a known path on the node, then modifies the Spark configuration (`spark.driver.extraJavaOptions`/`spark.executor.extraJavaOptions`, typically via a `spark-branch.conf` file the init script writes) to include the `-javaagent` flag pointing at that jar, along with OTel exporter endpoint configuration. This auto-instruments JVM-level metrics (garbage collection, memory, thread pools) without modifying any Spark application code, complementing the manual Python-side span instrumentation for business-logic-level tracing.

---

## Q6. What's the difference between head-based and tail-based sampling for traces, and which would you choose for a high-volume Spark ETL pipeline?

**Answer:**
Head-based sampling makes the keep/discard decision at the very start of a trace (e.g., "keep 10% of all traces, decided randomly at the first span") — simple and cheap, but it can just as easily discard the rare failed or abnormally slow trace you'd actually want to investigate as it can discard a routine successful one. Tail-based sampling defers the decision until the entire trace has completed, allowing rules like "always keep traces that errored or exceeded a latency threshold, sample the rest at a low rate" — much more useful for debugging, at the cost of requiring the Collector (typically in gateway mode) to buffer complete traces in memory before deciding, which is more resource-intensive. For a high-volume Spark ETL pipeline, I'd use tail-based sampling, but at the **job/stage span granularity** rather than per-task — with potentially thousands of tasks per job, per-task trace volume would overwhelm most backends and isn't the useful level of granularity for pipeline-level debugging anyway.

---

## Q7. If a company wants to migrate from ad hoc logging/print-statement debugging to a unified OpenTelemetry-based observability stack feeding Dynatrace, how would you approach the migration without disrupting existing operations?

**Answer:**
I'd never do a big-bang, all-pipelines-at-once cutover. I'd start by standing up an OTel Collector (gateway mode) as shared infrastructure, then instrument **one representative pipeline first** — adding OTel SDK spans/metrics without removing the existing logging — and configure the Collector to export to Dynatrace. I'd run this in parallel with the existing approach for a validation period, comparing what the new traces/metrics show against what the team already knows about that pipeline's behavior (are durations, failure points, and volumes consistent with expectations?), before treating Dynatrace as the source of truth for that pipeline and only then removing the redundant ad hoc logging. I'd repeat this pipeline-by-pipeline, prioritizing the most business-critical or hardest-to-debug pipelines first, rather than attempting a company-wide switch in one step — the same incremental, validate-before-cutover discipline as any other production migration (Phase 10's deployment philosophy, applied to observability tooling itself).

---

## Q8. Why might an organization run both Dynatrace and a self-hosted Prometheus/Grafana stack simultaneously, rather than choosing just one?

**Answer:**
Dynatrace's value is broad, AI-driven (Davis AI), auto-instrumented (OneAgent) observability across the *entire* infrastructure estate with minimal manual configuration and automated root-cause analysis — valuable for company-wide APM and incident response, but it's a licensed commercial product with real per-host/per-data-volume cost. A self-hosted Prometheus/Grafana(+Loki/Tempo) stack is fully open-source and free to run (aside from operating it yourselves), and data engineering teams often want lightweight, fully-customizable dashboards specific to their own pipelines (e.g., custom business metrics like "rows processed per pipeline run") without needing to involve or pay for the broader company APM platform for every small team-specific dashboard. In practice: Dynatrace handles company-wide infra/APM monitoring and alerting, while Prometheus/Grafana (fed by the same OTel Collector, fanned out to both) serves as a lighter-weight, team-owned layer for pipeline-specific operational dashboards — both sourced from the same underlying OTel instrumentation, avoiding duplicated instrumentation effort.
