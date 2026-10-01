# Phase 10 — Delta Table / Lakehouse Health

**Pillar:** Cost & performance  ·  **Owner:** Platform (maintenance schedule with Data Eng)  ·  **Effort:** Medium  ·  **Repo:** `osdu-ssw-central-dbx` (+ optional maintenance job in DAB)

## Objective

Catch the #1 silent cost-and-performance killer in every Databricks estate:
un-maintained Delta tables — small-file explosion, missing `OPTIMIZE`/`VACUUM`,
stale statistics, and unconstrained table growth.

## Data sources

| Source | Gives |
|--------|-------|
| `${system_catalog}.information_schema.tables` | table inventory, type, owner |
| `DESCRIBE DETAIL <table>` | numFiles, sizeInBytes, partition count |
| `DESCRIBE HISTORY <table>` | last OPTIMIZE/VACUUM operation + time |
| `${system_catalog}.access.table_lineage` (Phase 9) | last-read (orphan) signal |

## Panels

1. **Small-file offenders** (table) — tables with high `numFiles` relative to
   `sizeInBytes` (avg file << 128MB target) ⇒ need `OPTIMIZE`.
2. **OPTIMIZE/VACUUM staleness** — days since last maintenance op per table.
3. **Table growth** (line) — size trend; flags runaway/unconstrained growth.
4. **Largest tables** (bar) — storage cost drivers.
5. **Orphan + large** — big tables with no recent reads (Phase 9 join) ⇒ drop/archive
   candidates.

SQL: `implementations/phase-10-delta-health/table-health-queries.sql`.

## Optional — automated maintenance job

A scheduled Databricks job that runs `OPTIMIZE` (with `ZORDER` where appropriate) and
`VACUUM` on the medallion tables on a cadence (e.g. nightly), with failure alerting.
For DLT/managed tables, predictive optimization may already handle some of this —
confirm per table before scheduling manual maintenance to avoid double work.

Config: `implementations/phase-10-delta-health/maintenance-job.sql`.

### ⚠️ Where Data Eng advises

The **ZORDER columns** and **VACUUM retention** per table depend on query patterns
and time-travel requirements the DE owns. Platform can schedule and monitor; the
per-table tuning parameters need DE sign-off (wrong VACUUM retention can break
time-travel/GDPR requirements).

## Best practice applied

- **Small files are the silent tax** — every query pays for excess file-open
  overhead; `OPTIMIZE` compaction is the highest-ROI maintenance.
- **Don't VACUUM blind** — retention must respect time-travel/compliance needs; make
  it a reviewed parameter, not a default.
- **Prefer predictive optimization where available** — let the platform auto-maintain
  managed tables; only hand-schedule where it doesn't apply.

## Verification

- Small-file panel flags a known unoptimised table; after `OPTIMIZE`, its file count
  drops and it clears the panel.
- Staleness panel advances after the maintenance job runs.

## Ownership & DE involvement

**Platform-owned dashboards + scheduling; DE owns per-table tuning params**
(ZORDER cols, VACUUM retention).
