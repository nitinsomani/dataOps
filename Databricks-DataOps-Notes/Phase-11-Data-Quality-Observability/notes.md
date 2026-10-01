# Phase 11: Data Quality, Testing & Observability — Detailed Notes

> **Goal**: Know how to detect, prevent, and get alerted about bad data and unhealthy pipelines — the "ops" half of DataOps in production.

---

## 1. Why Data Quality Is a First-Class DataOps Concern

Software can be "correct" (passes all unit tests) while still producing wrong business outcomes because the **data** itself is bad — a silently-changed upstream schema, a spike in nulls, a duplicate feed, a broken join key. Data quality tooling closes this gap by asserting things about the data itself as part of the pipeline, not just the code.

---

## 2. DLT Expectations (Built-in, Declarative)

Recap from Phase 5 — the simplest, most integrated way to enforce quality within a DLT pipeline:

```python
@dlt.expect("valid_id", "id IS NOT NULL")
@dlt.expect_or_drop("positive_amount", "amount > 0")
@dlt.expect_or_fail("no_dupes", "COUNT(*) OVER (PARTITION BY id) = 1")
def silver_table():
    ...
```

- Metrics on pass/fail rates per expectation are automatically tracked and visible in the pipeline's event log / UI — no custom dashboard needed for basic monitoring.
- Three severities (`expect`/`expect_or_drop`/`expect_or_fail`) map to "monitor only," "quarantine," and "stop the pipeline."

---

## 3. Great Expectations (External Framework)

For non-DLT pipelines (plain Jobs/notebooks) or more expressive rule sets than DLT's SQL-boolean expectations support, **Great Expectations (GX)** is a popular open-source framework:

```python
import great_expectations as gx

context = gx.get_context()
validator = context.sources.add_spark("spark_source").add_dataframe_asset("orders").get_validator(df=orders_df)

validator.expect_column_values_to_not_be_null("order_id")
validator.expect_column_values_to_be_between("amount", min_value=0, max_value=100000)
validator.expect_column_values_to_be_unique("order_id")
validator.expect_table_row_count_to_be_between(min_value=100)

results = validator.validate()
if not results.success:
    raise ValueError("Data quality checks failed!")
```

- GX supports a much richer expectation library (distribution checks, regex matching, referential integrity across tables, custom Python expectations) than DLT's boolean SQL expressions.
- Generates human-readable **Data Docs** (HTML reports) automatically from validation results — useful for sharing quality status with non-engineers.
- Can be inserted as a task/step in a Databricks Job or notebook, failing the pipeline (or just alerting) based on validation results.

---

## 4. Custom Data Quality Checks (Lightweight, DIY)

Not every team needs a full framework — many production checks are simple, hand-rolled SQL assertions run as a pipeline task:

```python
def assert_no_nulls(df, column):
    null_count = df.filter(df[column].isNull()).count()
    assert null_count == 0, f"{column} has {null_count} null values!"

def assert_row_count_within_range(df, min_rows, max_rows):
    count = df.count()
    assert min_rows <= count <= max_rows, f"Row count {count} out of expected range [{min_rows}, {max_rows}]"

def assert_no_duplicate_keys(df, key_cols):
    total = df.count()
    distinct = df.select(key_cols).distinct().count()
    assert total == distinct, "Duplicate keys found!"
```

- Low overhead to start, but doesn't scale as well as GX/DLT expectations for large rule sets or team-wide standardization.

---

## 5. Anomaly Detection & Volume Monitoring

- **Freshness checks**: alert if a table hasn't been updated within an expected window (e.g., "Bronze table should have new data every hour — alert if last write > 3 hours ago").
- **Volume checks**: alert if row counts for a given load deviate significantly from historical norms (e.g., today's batch is 50% smaller than the 7-day rolling average — possible upstream outage).
- **Distribution/statistical checks**: alert on significant shifts in a numeric column's mean/stddev or a categorical column's value distribution — can catch subtle upstream bugs that pass basic null/range checks.

```sql
-- Freshness check example
SELECT MAX(_ingest_ts) AS last_load, current_timestamp() AS now,
       datediff(minute, MAX(_ingest_ts), current_timestamp()) AS minutes_stale
FROM bronze_orders;
```

---

## 6. Lakehouse Monitoring (Databricks-native)

- **Lakehouse Monitoring** attaches automated statistical profiling and drift detection directly to a Unity Catalog table — tracks metrics like null rates, distinct counts, and distribution drift over time without custom code, generating dashboards and alerting automatically.
- Two monitor types: **Snapshot** (profile the whole table each run) and **Time Series** (track a specific timestamp column's trend over time, better for append-heavy fact tables).
- **Inference/drift monitoring** — specifically useful for ML feature/prediction tables, tracking input distribution drift vs a baseline.

---

## 7. System Tables for Pipeline Observability

```sql
-- Job run health over time
SELECT job_id, run_id, result_state, period_start_time, period_end_time
FROM system.lakeflow.job_run_timeline
WHERE result_state = 'FAILED'
ORDER BY period_start_time DESC;

-- Query-level performance (Databricks SQL)
SELECT statement_text, total_duration_ms, read_bytes
FROM system.query.history
WHERE total_duration_ms > 60000
ORDER BY total_duration_ms DESC;
```

- `system.lakeflow.*` — job/pipeline run metadata (durations, statuses, retries).
- `system.query.history` — query-level performance across the workspace, useful for spotting regressions or runaway queries.
- `system.billing.usage` — cost (Phase 9).
- `system.access.audit` — security/governance events (Phase 6/7).

All are just Delta tables — build your own monitoring dashboards/alerts on top with standard SQL, no separate observability tool strictly required (though many teams still integrate with Datadog/Grafana/PagerDuty for org-wide alerting consistency).

---

## 8. Alerting Channels

- **Job/DLT native notifications**: email, Slack/webhook on job start/success/failure/duration threshold.
- **Databricks SQL Alerts**: schedule a SQL query, define a threshold condition, get notified when triggered (e.g., "alert if row count in gold table = 0").
- **External integration**: piping system table data or alert webhooks into PagerDuty/Opsgenie for on-call rotation integration in mature production environments.

---

## 9. Data Contracts

- A **data contract** is an explicit agreement (often schema + semantic expectations, sometimes literally a JSON/YAML schema file checked into source control) between an upstream data producer and downstream consumers about the shape and meaning of data.
- Enforced via: schema validation at ingestion (Auto Loader `failOnNewColumns` in a canary/staging path), automated tests comparing actual vs contracted schema, and organizational process (producers must notify/version their contract before breaking changes).
- Growing practice in mature data organizations to reduce the "silent upstream change breaks my pipeline" failure mode — shifts some data quality responsibility upstream to the producer rather than only downstream detection.

---

## 10. Key Takeaways for DataOps

- Data quality lives on a spectrum: DLT expectations (lightweight, integrated) → hand-rolled assertions (flexible, DIY) → Great Expectations (rich, standardized) → Lakehouse Monitoring (automated statistical drift detection) — know when to reach for each.
- Freshness and volume checks catch a huge class of real-world incidents ("the pipeline succeeded but no new data arrived") that pure schema/row-level checks miss.
- System tables (`system.lakeflow.*`, `system.query.history`, `system.billing.usage`, `system.access.audit`) turn observability into a standard SQL/BI problem — a recurring theme across governance, cost, and quality phases.
- Data contracts shift quality left — preventing bad data at the source is cheaper than catching it downstream.
