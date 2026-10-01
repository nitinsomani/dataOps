# Phase 4 — Query / Warehouse Performance Dashboard

**Pillar:** Performance  ·  **Owner:** Platform  ·  **Effort:** Medium  ·  **Repo:** `osdu-ssw-central-dbx`

## Objective

See *why* SQL is slow and whether warehouses are right-sized: slow queries,
queue/spill, and warehouse utilisation.

## Data sources

| Source | Gives |
|--------|-------|
| `${system_catalog}.query.history` | per-statement duration, rows, bytes, user, warehouse |
| `${system_catalog}.compute.warehouse_events` | scale-up/down, STARTING/RUNNING/STOPPED events |
| `${system_catalog}.compute.warehouses` | warehouse inventory & config |

## Panels

1. **KPI** — p95 query duration (7d), queries (24h), failed queries (24h), avg queue time.
2. **Slowest queries** (table, 7d) — duration, user, warehouse, rows/bytes read;
   the drill-down list for optimisation.
3. **Queue-time trend** (line) — rising queue time ⇒ warehouse under-provisioned.
4. **Spill detection** (table) — statements with disk/memory spill ⇒ needs bigger
   warehouse or query rewrite.
5. **Warehouse utilisation** (line) — running vs idle time; idle time = wasted auto-stop
   window to tune.
6. **Query volume by user/source** (bar) — who/what drives load.

SQL: `implementations/phase-04-query-performance/` (add alongside as a new
`dashboard-query-performance.tf` using the same `databricks_dashboard` pattern).

## Best practice applied

- **p95, not average** — averages hide the tail that users actually feel.
- **Queue time is the leading indicator** — it rises before users complain; alert on
  it in Phase 5.
- **Right-size from evidence** — idle-time and spill panels turn "the warehouse feels
  slow" into a concrete Small→Medium decision.

## Verification

- Dashboard shows real query history for the target warehouse.
- Slowest-queries panel matches what you see in the Query History UI.

## Ownership & DE involvement

**Platform-owned.** DE may use the slow-query output to optimise specific
transformations, but no code change is required to build the dashboard.
