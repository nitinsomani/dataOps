# Phase 11: Data Quality, Testing & Observability — Cheat Sheet

---

## Data Quality Tooling Spectrum

```
DLT Expectations       → lightweight, declarative, built into DLT pipelines
Hand-rolled assertions  → DIY, flexible, no framework overhead
Great Expectations (GX) → rich expectation library, Data Docs, works outside DLT
Lakehouse Monitoring    → automated statistical profiling + drift detection on UC tables
```

## DLT Expectations Severity

```
@dlt.expect            → track metrics only, keep rows
@dlt.expect_or_drop     → quarantine (drop) violating rows
@dlt.expect_or_fail     → stop the whole pipeline
```

## Great Expectations Skeleton

```python
validator.expect_column_values_to_not_be_null("id")
validator.expect_column_values_to_be_unique("id")
validator.expect_column_values_to_be_between("amount", min_value=0)
validator.expect_table_row_count_to_be_between(min_value=100)
results = validator.validate()
```

## Freshness & Volume Check Pattern

```sql
SELECT datediff(minute, MAX(_ingest_ts), current_timestamp()) AS minutes_stale
FROM bronze_table;
-- Alert if minutes_stale > threshold
```

## Lakehouse Monitoring Types

```
Snapshot     → profile whole table each run (dimension/reference tables)
Time Series  → track trend over a timestamp column (append-heavy fact tables)
Inference    → drift detection for ML feature/prediction tables
```

## Key System Tables for Observability

```
system.lakeflow.job_run_timeline   → job/pipeline run status & duration
system.query.history               → query-level performance (Databricks SQL)
system.billing.usage               → cost (Phase 9)
system.access.audit                → security/governance events (Phase 6/7)
```

## Alerting Channels

```
Job/DLT native notifications  → email/Slack/webhook on start/success/fail
Databricks SQL Alerts          → scheduled query + threshold condition
External integration           → PagerDuty/Opsgenie via webhook
```

## Data Contract Enforcement Points

```
[ ] Schema validation at ingestion (failOnNewColumns canary)
[ ] Automated schema diff tests in CI
[ ] Explicit versioned schema file in source control
[ ] Producer notifies consumers before breaking changes
```
