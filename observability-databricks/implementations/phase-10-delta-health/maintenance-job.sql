-- ============================================================================
-- Phase 10 — Delta maintenance job (OPTIMIZE / VACUUM) — TEMPLATE
-- Run as a scheduled Databricks job (e.g. nightly) with failure alerting.
--
-- ⚠️ TWO things need Data-Engineering sign-off before scheduling:
--    1. ZORDER columns per table (depend on query/filter patterns).
--    2. VACUUM retention (default 7 days) — must respect time-travel / GDPR /
--       compliance needs. Shortening it can BREAK time travel and restores.
--
-- ⚠️ For DLT/managed tables with PREDICTIVE OPTIMIZATION enabled, the platform
--    already maintains them — do NOT double-schedule. Confirm per table first:
--      SHOW TBLPROPERTIES <table> ('delta.autoOptimize.optimizeWrite');
-- ============================================================================

-- ── OPTIMIZE (compaction) — high-ROI, safe ──────────────────────────────────
OPTIMIZE subsurface_prd.silver_edm.silver_wellbore;

-- With ZORDER (DE confirms the columns that are frequently filtered/joined):
-- OPTIMIZE subsurface_prd.gold_edm.gold_well ZORDER BY (uwi);

-- ── VACUUM — reclaim storage from tombstoned files ──────────────────────────
-- Default retention is 168 hours (7 days). Only lower with DE/compliance sign-off.
VACUUM subsurface_prd.silver_edm.silver_wellbore;                 -- default 7d retention
-- VACUUM subsurface_prd.gold_edm.gold_well RETAIN 168 HOURS;      -- explicit 7d

-- ── Pattern: drive across the medallion from the inventory ──────────────────
-- In a notebook task, loop over Phase-10 inventory query results and run
-- OPTIMIZE (+ optional ZORDER) then VACUUM per table, catching + reporting
-- failures to the Teams webhook (reuse Phase 6 job notification pattern).
--
-- Pseudocode:
--   for t in inventory:
--       spark.sql(f"OPTIMIZE {t.fqn}" + (f" ZORDER BY ({zcols[t]})" if t in zcols else ""))
--       spark.sql(f"VACUUM {t.fqn}")            # retention per DE policy map
--
-- Prefer enabling predictive optimization where available and only hand-running
-- this for tables it does not cover.
