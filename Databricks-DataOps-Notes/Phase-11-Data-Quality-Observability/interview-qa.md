# Phase 11: Data Quality, Testing & Observability — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ A pipeline succeeds every night, but the business reports the dashboard numbers "look wrong" intermittently. How do you approach diagnosing this?

**Answer:**
A "successful" job run only proves the code executed without throwing an exception — it says nothing about whether the data itself is correct, so I'd start by checking whether data-level quality gates even exist (row counts, null rates, freshness). I'd check `system.lakeflow.job_run_timeline` for run history/duration anomalies, check freshness of the source tables (did the upstream data actually arrive on time, or did the pipeline run "successfully" against stale/partial data?), and check volume trends (is the daily row count anomalously low/high vs a rolling baseline — indicating an upstream partial outage). I'd also use Unity Catalog lineage to trace the specific "wrong-looking" Gold metric backward through Silver to Bronze to isolate exactly where the numbers diverge from expectations, since job success/failure alone won't reveal a silent data-correctness bug.

---

## Q2. ⭐ What's the difference between DLT Expectations and a framework like Great Expectations, and when would you choose one over the other?

**Answer:**
DLT Expectations are lightweight, declarative, boolean SQL conditions built directly into a DLT pipeline (`@dlt.expect`/`expect_or_drop`/`expect_or_fail`), with pass/fail metrics automatically tracked in the pipeline UI — minimal setup, but limited to conditions expressible as a single SQL boolean per row. Great Expectations is a much richer, standalone framework supporting distribution checks, regex matching, cross-table referential integrity, and custom Python expectation logic, plus auto-generated human-readable Data Docs — but requires more setup and runs as an explicit step outside DLT's native execution model. I'd use DLT Expectations for straightforward row-level rules within a DLT pipeline, and reach for Great Expectations when I need more expressive checks, need to validate non-DLT (plain Job/notebook) pipelines, or want standardized, shareable quality reports across many pipelines/teams.

---

## Q3. What is a "freshness" check and why is it often more important than a simple row-count or null check?

**Answer:**
A freshness check verifies that a table has actually received new data within an expected time window (e.g., "this Bronze table should be updated every hour; alert if the max ingest timestamp is more than 3 hours old"). It's critical because a pipeline can complete "successfully" — zero errors, valid schema, no null violations — while processing **zero new rows** because an upstream source silently stopped sending data (e.g., an API outage, a broken CDC connector, a stuck upstream job). Row-count and null checks on the data that *did* arrive won't catch this "successful but stale" failure mode; only an explicit freshness/recency check will.

---

## Q4. How would you design volume anomaly detection for a daily batch ingestion pipeline, and what's a common pitfall?

**Answer:**
I'd compare each day's ingested row count against a rolling baseline (e.g., trailing 7 or 28-day average for that day-of-week, to account for weekly seasonality) and alert if the deviation exceeds a threshold (e.g., ±30%) in either direction — both an unexpected drop (partial upstream outage) and an unexpected spike (duplicate feed, replay bug, or a legitimate but unplanned business event) are worth investigating. A common pitfall is using a naive fixed threshold or day-over-day comparison without accounting for legitimate seasonality (e.g., weekday vs weekend volume differences) — this produces alert fatigue from false positives, which erodes trust in the alerting system and causes real issues to get ignored alongside the noise.

---

## Q5. What is Lakehouse Monitoring and how does it differ from writing your own custom SQL quality checks?

**Answer:**
Lakehouse Monitoring is a Databricks-native feature that attaches automated statistical profiling and drift detection directly to a Unity Catalog table — it tracks metrics like null rates, distinct value counts, and distribution shifts over time automatically, generating dashboards without hand-writing SQL for each metric, and supports specialized modes (Snapshot for point-in-time profiling, Time Series for trend tracking on append-heavy tables, Inference for ML feature/prediction drift). Custom SQL checks give full control and can express arbitrary business logic (e.g., "revenue by region shouldn't exceed X"), but require you to build, maintain, and dashboard each check yourself. In practice, I'd use Lakehouse Monitoring for broad, standardized statistical health monitoring across many tables with minimal setup, and custom checks for specific business-rule assertions that a generic profiling tool can't express.

---

## Q6. What is a data contract, and how does it shift data quality responsibility "left"?

**Answer:**
A data contract is an explicit, often version-controlled agreement between a data producer (upstream team/system) and downstream consumers defining the expected schema and semantics of the data being shared — going beyond an implicit "hope the schema doesn't change" arrangement. It shifts quality "left" by making the producer responsible for validating and versioning changes *before* publishing data, rather than leaving downstream consumers to discover breaking changes reactively when their pipeline fails or produces wrong numbers. In practice this might be enforced via a schema file checked into source control that both producer and consumer CI pipelines validate against, combined with a canary ingestion path using `failOnNewColumns` to immediately flag any unannounced drift.

---

## Q7. Where would you look first to build a dashboard showing overall data pipeline health across your organization's Databricks workspace?

**Answer:**
I'd start with the `system.lakeflow.*` system tables for job/pipeline run status, duration trends, and failure rates across all jobs — these are just Delta tables, so a standard Databricks SQL dashboard can be built directly on top without any external tooling. I'd layer in `system.query.history` for query-level performance regressions, and combine this with any DLT Expectations metrics and Lakehouse Monitoring outputs for data-level quality signals. For alerting, I'd configure Databricks SQL Alerts on key threshold conditions (e.g., failure rate > X% in the last 24 hours) and, for organizations with an existing on-call/observability stack, pipe critical alerts into PagerDuty/Opsgenie via webhook so pipeline health integrates with the broader incident response process rather than living in a Databricks-only silo.
