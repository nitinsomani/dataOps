# Phase 3: Delta Lake Deep Dive — Cheat Sheet

---

## Delta Table Anatomy

```
my_table/
├── _delta_log/*.json          ← transaction log (source of truth)
├── _delta_log/*.checkpoint.parquet   ← every 10 commits
└── part-*.parquet             ← actual data files
```

## ACID via the Log

```
Write → new JSON commit file → atomic (all-or-nothing) → readers see consistent snapshot
```

## Core DDL/DML Cheat Sheet

```sql
-- Time travel
SELECT * FROM t VERSION AS OF 5;
SELECT * FROM t TIMESTAMP AS OF '2026-09-01';
RESTORE TABLE t TO VERSION AS OF 5;

-- Upsert
MERGE INTO target t USING source s ON t.id = s.id
  WHEN MATCHED THEN UPDATE SET *
  WHEN NOT MATCHED THEN INSERT *;

-- Maintenance
OPTIMIZE t;
OPTIMIZE t ZORDER BY (col1, col2);
VACUUM t RETAIN 168 HOURS;

-- Schema evolution
ALTER TABLE t ADD COLUMN new_col STRING;
-- df.write.option("mergeSchema","true")...

-- CDF
ALTER TABLE t SET TBLPROPERTIES (delta.enableChangeDataFeed = true);
SELECT * FROM table_changes('t', 2, 5);

-- Constraints
ALTER TABLE t ADD CONSTRAINT chk CHECK (amount >= 0);
```

## Maintenance Cadence (typical production schedule)

```
OPTIMIZE (+ ZORDER/Liquid Clustering)  → daily or after N writes
VACUUM RETAIN 168 HOURS                → weekly
ANALYZE TABLE ... COMPUTE STATISTICS   → after major loads
```

## Managed vs External Table

| | Managed | External |
|-|---------|----------|
| Location | UC-managed storage | User-specified `LOCATION` |
| DROP TABLE | Deletes data too | Metadata only |

## Small Files Problem → Fix

```
Many tiny files → slow scans, overhead
  → OPTIMIZE (bin-packing) merges to ~1GB target files
  → ZORDER / Liquid Clustering (CLUSTER BY) for data skipping
```

## Deletion Vectors

```
UPDATE/DELETE/MERGE → mark rows deleted in auxiliary file
  instead of rewriting whole Parquet file → faster writes
  → reconciled later during OPTIMIZE
```

## Retention Gotcha

```
VACUUM RETAIN 0 HOURS  → breaks time travel + concurrent long-running readers. Avoid.
Default safe retention: 168 hours (7 days)
```
