# Phase 9 — Data Lineage (Table / Column)

**Pillar:** Impact analysis  ·  **Owner:** Platform  ·  **Effort:** Small  ·  **Repo:** `osdu-ssw-central-dbx`

## Objective

Answer *"if `silver_well` breaks or changes, what downstream gold tables, views, and
dashboards are affected?"* — and the reverse, *"where did this gold column come
from?"*. Critical given the medallion has **9 silver→gold dependency chains**.

## Data source

| Source | Gives |
|--------|-------|
| `${system_catalog}.access.table_lineage` | upstream/downstream table edges per read/write |
| `${system_catalog}.access.column_lineage` | column-level provenance |

These are populated automatically by Unity Catalog for jobs/queries that touch UC
tables — no instrumentation required.

## Panels

1. **Downstream impact** (table) — given a source table, list all downstream
   consumers (tables, notebooks, dashboards) seen in the last N days.
2. **Upstream provenance** (table) — given a gold table/column, trace it back to
   silver/bronze/source.
3. **Orphan detection** — tables with no downstream reads in 90d (candidates for
   deprecation / cost saving).
4. **Cross-schema dependency graph** — bronze→silver→gold edge counts, to visualise
   the medallion coupling.

SQL: `implementations/phase-09-lineage/lineage-queries.sql`.

## Best practice applied

- **Impact analysis before change** — run the downstream query before altering a
  silver table so you know the blast radius (ties into Phase 5 SLOs — which gold
  SLAs are at risk).
- **Orphan detection = cost hygiene** — unread tables still cost storage and
  `OPTIMIZE`/`VACUUM` compute (feeds Phase 10).
- **Lineage is free telemetry** — UC populates it automatically; not using it is
  leaving value on the table.

## Verification

- Picking `silver_well` returns its known gold consumers (gold_well, hierarchy, etc.).
- Column provenance for a gold column resolves back to a silver/bronze column.

## Ownership & DE involvement

**Platform-owned.** DE benefits from the impact analysis but no code change needed.
