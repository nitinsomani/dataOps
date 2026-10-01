-- ============================================================================
-- Phase 9 — Data lineage queries
-- Source: ${system_catalog}.access.table_lineage / column_lineage
-- ============================================================================

-- ── Downstream impact: everything that reads from a given source table ──────
-- Parameterise: ${src_catalog}, ${src_schema}, ${src_table}
SELECT DISTINCT
  target_table_catalog || '.' || target_table_schema || '.' || target_table_name AS downstream_table,
  entity_type,     -- NOTEBOOK / JOB / DASHBOARD / PIPELINE / etc.
  entity_run_id,
  MAX(event_time)  AS last_seen
FROM ${system_catalog}.access.table_lineage
WHERE source_table_catalog = '${src_catalog}'
  AND source_table_schema  = '${src_schema}'
  AND source_table_name    = '${src_table}'
  AND event_time >= CURRENT_DATE - INTERVAL 90 DAYS
GROUP BY 1, 2, 3
ORDER BY last_seen DESC;

-- ── Upstream provenance: where a gold table's data comes from ───────────────
SELECT DISTINCT
  source_table_catalog || '.' || source_table_schema || '.' || source_table_name AS upstream_table,
  MAX(event_time) AS last_seen
FROM ${system_catalog}.access.table_lineage
WHERE target_table_catalog = '${tgt_catalog}'
  AND target_table_schema  = '${tgt_schema}'
  AND target_table_name    = '${tgt_table}'
  AND event_time >= CURRENT_DATE - INTERVAL 90 DAYS
GROUP BY 1
ORDER BY last_seen DESC;

-- ── Column provenance (where a gold column originates) ──────────────────────
SELECT DISTINCT
  source_table_full_name,
  source_column_name,
  target_column_name,
  MAX(event_time) AS last_seen
FROM ${system_catalog}.access.column_lineage
WHERE target_table_catalog = '${tgt_catalog}'
  AND target_table_schema  = '${tgt_schema}'
  AND target_table_name    = '${tgt_table}'
  AND target_column_name   = '${tgt_column}'
GROUP BY 1, 2, 3
ORDER BY last_seen DESC;

-- ── Orphan detection: tables with NO downstream reads in 90d ─────────────────
-- Candidates for deprecation / cost saving (join with Phase 10 size to prioritise).
WITH read_targets AS (
  SELECT DISTINCT
    source_table_catalog AS cat, source_table_schema AS sch, source_table_name AS tbl
  FROM ${system_catalog}.access.table_lineage
  WHERE event_time >= CURRENT_DATE - INTERVAL 90 DAYS
)
SELECT
  t.table_catalog, t.table_schema, t.table_name
FROM ${system_catalog}.information_schema.tables t
LEFT JOIN read_targets r
  ON  t.table_catalog = r.cat
  AND t.table_schema  = r.sch
  AND t.table_name    = r.tbl
WHERE t.table_type != 'VIEW'
  AND r.tbl IS NULL
ORDER BY t.table_catalog, t.table_schema, t.table_name;

-- ── Cross-schema dependency edge counts (bronze→silver→gold coupling) ───────
SELECT
  source_table_schema AS from_schema,
  target_table_schema AS to_schema,
  COUNT(DISTINCT source_table_name || '->' || target_table_name) AS edges
FROM ${system_catalog}.access.table_lineage
WHERE event_time >= CURRENT_DATE - INTERVAL 30 DAYS
  AND source_table_schema <> target_table_schema
GROUP BY source_table_schema, target_table_schema
ORDER BY edges DESC;

-- NOTE: column names (source_table_*/target_table_*, entity_type, event_time)
-- follow the current system.access.*_lineage schema; confirm per workspace.
