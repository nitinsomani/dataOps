# Phase 3 — Data Quality (DLT Expectations + Lakehouse Monitoring)

**Pillar:** Data quality  ·  **Owner:** ⚠️ **Data Engineering** (platform assists)  ·  **Effort:** Medium  ·  **Repo:** `ssw-dbx-idl2-de`

## Objective

Catch *bad data*, not just *failed runs*. A pipeline can succeed while silently
dropping or corrupting records. This phase adds:

1. **DLT expectations** on silver/gold tables (row-level rules).
2. **Lakehouse Monitoring** on key gold tables (profile/drift over time).
3. An expectations dashboard reading the DLT `event_log`.

## ⚠️ Why this needs a data engineer

Expectation rules encode **business truth** — e.g. *"a wellbore must have a non-null
UWI"*, *"measured depth must be ≥ 0"*, *"a well can't have two active statuses"*.
Only the owner of `silver_well_pipeline/transformations/*.py`,
`gold_wellbore_pipeline/...` etc. knows these. The platform can wire the plumbing,
dashboards, and monitors, **but cannot invent the rules.** Generating rules blind
would create false confidence.

**Division of labour:**
- *Data engineer:* defines the `@dlt.expect_*` rules per table; picks which gold
  tables get Lakehouse Monitoring and the metrics that matter.
- *Platform (me):* provides the expectation patterns/examples, the
  `databricks_quality_monitor` Terraform/DAB config, and the expectations dashboard.

## Part A — DLT expectations

Three enforcement levels (choose per rule):

| Decorator | Behaviour on violation | Use when |
|-----------|------------------------|----------|
| `@dlt.expect` | log only, keep row | soft/advisory metric |
| `@dlt.expect_or_drop` | drop the row, continue | bad rows shouldn't reach downstream |
| `@dlt.expect_or_fail` | fail the update | a violation means the source is broken |

Example patterns in `implementations/phase-03-data-quality/expectations_examples.py`.

### Best practice applied

- **Quarantine, don't discard silently** — pair `expect_or_drop` with a side table
  capturing dropped rows so data quality issues are auditable, not invisible.
- **Fail fast on structural violations** — use `expect_or_fail` for invariants
  (e.g. primary-key non-null) so a schema break stops the pipeline instead of
  propagating corruption to gold.

## Part B — Lakehouse Monitoring

For key gold tables, enable a monitor to track profile metrics (null %, distinct
counts, min/max) and detect **drift** vs a baseline over time. Two monitor types fit
this estate:

- **Snapshot** — for dimension-style gold tables (well, wellbore master).
- **TimeSeries** — for event/fact tables with a timestamp (DDR, trajectory).

Terraform/DAB config: `implementations/phase-03-data-quality/quality_monitor.tf`.

### Best practice applied

- **Drift detection catches the slow leak** — a source system quietly changing a
  code list won't fail an expectation but *will* shift a distribution; monitoring
  surfaces it.

## Part C — Expectations dashboard

Read the DLT `event_log` (`details:flow_progress.data_quality.expectations`) to show
per-table pass/fail/drop counts and trends. SQL:
`implementations/phase-03-data-quality/expectation_metrics.sql`.

## Verification

- A deliberately bad test row is dropped/failed per the configured rule and appears
  in the quarantine table + expectations dashboard.
- Lakehouse Monitoring produces a profile + drift metric table on schedule.

## Ownership & DE involvement

**Blocked on data engineering** for rule definitions and monitor scope. Platform
delivers everything around that once the rules are provided.
