# Phase 6: Unity Catalog & Data Governance — Cheat Sheet

---

## Three-Level Namespace

```
catalog.schema.table
metastore (1 per region/account) → catalogs → schemas → tables/views/volumes/functions/models
```

## GRANT Cheat Sheet

```sql
GRANT USE CATALOG ON CATALOG c TO `group`;
GRANT USE SCHEMA ON SCHEMA c.s TO `group`;
GRANT SELECT ON TABLE c.s.t TO `group`;
GRANT MODIFY ON TABLE c.s.t TO `group`;
REVOKE SELECT ON TABLE c.s.t FROM `group`;
SHOW GRANTS ON TABLE c.s.t;
```

Hierarchy rule: `USE CATALOG` + `USE SCHEMA` required even if table-level `SELECT` is granted.

## Row Filter / Column Mask Skeleton

```sql
-- Column mask
CREATE FUNCTION mask_fn(col STRING) RETURNS STRING
RETURN CASE WHEN is_account_group_member('admins') THEN col ELSE '***' END;
ALTER TABLE t ALTER COLUMN col SET MASK mask_fn;

-- Row filter
CREATE FUNCTION filter_fn(region STRING) RETURNS BOOLEAN
RETURN region = current_user_region();
ALTER TABLE t SET ROW FILTER filter_fn ON (region);
```

## Storage Setup Chain

```sql
CREATE STORAGE CREDENTIAL cred WITH (AWS_IAM_ROLE = '...');
CREATE EXTERNAL LOCATION loc URL 's3://bucket/path' WITH (STORAGE CREDENTIAL cred);
CREATE CATALOG cat MANAGED LOCATION 's3://bucket/cat/';
```

## Delta Sharing

```sql
CREATE SHARE s;
ALTER SHARE s ADD TABLE cat.sch.t;
CREATE RECIPIENT r;
GRANT SELECT ON SHARE s TO RECIPIENT r;
```

## Lineage & Audit

```
Lineage    → automatic, column + table level, view in Catalog Explorer
Audit log  → system.access.audit table, or export to CloudTrail/Azure Monitor
```

## Legacy vs Modern Governance

| Legacy | Modern (UC) |
|--------|-------------|
| Hive metastore per workspace | One metastore per region/account |
| DBFS mounts | Volumes + External Locations |
| Cluster instance profiles | Storage Credentials |
| Per-tool access control | Centralized, tool-agnostic GRANTs |

## Common Gotchas

- Forgetting `USE CATALOG`/`USE SCHEMA` grants → "table not found" even with correct `SELECT` grant.
- Granting to individual users instead of IdP-synced groups → unmaintainable at scale.
- Masking/row filters apply regardless of client (SQL, notebook, BI tool) — don't rebuild access logic per tool.
