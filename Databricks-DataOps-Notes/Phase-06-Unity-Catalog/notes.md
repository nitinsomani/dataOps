# Phase 6: Unity Catalog & Data Governance — Detailed Notes

> **Goal**: Unity Catalog (UC) is Databricks' unified governance layer across all workspaces/clouds. This is critical for any real-world DataOps role — governance failures are a top cause of production incidents and compliance issues.

---

## 1. What is Unity Catalog?

Unity Catalog is a **centralized governance solution** for all data and AI assets (tables, views, volumes, models, functions) across every Databricks workspace attached to a single **metastore**. Before UC, each workspace had its own isolated Hive metastore with inconsistent permissions — UC unifies this into one account-level governance plane.

### Three-Level Namespace

```
catalog.schema.table
   │       │      │
   │       │      └── table/view/volume/function
   │       └───────── schema (a.k.a. database)
   └───────────────── catalog (top-level container, e.g., per environment/business unit)
```

```sql
SELECT * FROM production.sales.orders;
SELECT * FROM dev.sales.orders;
```

- **Metastore**: one per region/account, the top-level container attached to workspaces. All catalogs live under a metastore.
- **Catalog**: typically maps to an environment (`dev`/`staging`/`prod`) or business domain (`sales`, `marketing`).
- **Schema**: logical grouping within a catalog (equivalent to a "database" in older terminology).

---

## 2. Securable Objects in Unity Catalog

```
Metastore
 └── Catalog
      └── Schema
           ├── Table / View
           ├── Volume (managed/external file storage, replaces DBFS mounts)
           ├── Function (UDFs registered centrally, governed like tables)
           └── Model (registered ML models, governed the same way)
```

- **Volumes**: governed, non-tabular file storage — the modern replacement for DBFS mounts, supporting fine-grained access control on file paths (images, PDFs, arbitrary files, ML checkpoints).

---

## 3. Access Control — GRANT/REVOKE Model

Unity Catalog uses standard SQL GRANT semantics, inherited hierarchically.

```sql
GRANT USE CATALOG ON CATALOG production TO `data-engineers`;
GRANT USE SCHEMA ON SCHEMA production.sales TO `data-engineers`;
GRANT SELECT ON TABLE production.sales.orders TO `data-analysts`;
GRANT MODIFY ON TABLE production.sales.orders TO `data-engineers`;
GRANT SELECT ON SCHEMA production.sales TO `data-analysts`;   -- applies to all tables in schema

REVOKE SELECT ON TABLE production.sales.orders FROM `data-analysts`;

SHOW GRANTS ON TABLE production.sales.orders;
```

- Permissions cascade down the hierarchy: `USE CATALOG` and `USE SCHEMA` are prerequisites to accessing anything nested inside, even if the object itself has been granted `SELECT`.
- Grants are typically made to **groups** (synced from your identity provider — Entra ID/Okta/etc.), not individual users, for maintainability.
- Common privilege types: `SELECT`, `MODIFY`, `CREATE TABLE`, `CREATE SCHEMA`, `USE CATALOG`, `USE SCHEMA`, `EXECUTE` (for functions/models), `ALL PRIVILEGES`.

---

## 4. Row-Level and Column-Level Security

```sql
-- Column masking via a function
CREATE FUNCTION mask_ssn(ssn STRING) RETURNS STRING
RETURN CASE WHEN is_account_group_member('hr-admins') THEN ssn ELSE '***-**-****' END;

ALTER TABLE employees ALTER COLUMN ssn SET MASK mask_ssn;

-- Row filtering
CREATE FUNCTION region_filter(region STRING) RETURNS BOOLEAN
RETURN region = current_user_region() OR is_account_group_member('global-admins');

ALTER TABLE sales SET ROW FILTER region_filter ON (region);
```

- **Row filters**: restrict which *rows* a user sees based on a SQL function evaluated per-query (e.g., regional sales reps only see their own region's data).
- **Column masks**: dynamically redact/transform column values based on the querying user's group membership (e.g., mask PII columns for non-privileged roles) — the underlying data is untouched; masking happens at query time.
- Both apply uniformly regardless of which tool/client queries the table — a key advantage over per-tool access control.

---

## 5. Data Lineage

- UC automatically captures **column-level and table-level lineage** for any query executed through Databricks (notebooks, DLT, Jobs, SQL) — no manual instrumentation needed.
- Lineage graph shows upstream sources and downstream consumers for any table/column, viewable in **Catalog Explorer**.
- Critical for **impact analysis** ("if I change this column, what breaks downstream?") and **root cause analysis** ("this Gold metric looks wrong — trace back through Silver/Bronze to find where it diverged").

---

## 6. Audit Logging

- Every action (query executed, grant/revoke, table created/dropped) is logged and available via **system tables** (`system.access.audit`) or exported to cloud-native logging (CloudTrail/Azure Monitor/Cloud Audit Logs).
- Essential for compliance (SOC2, HIPAA, GDPR audits) and security incident investigation.

```sql
SELECT * FROM system.access.audit
WHERE action_name = 'deleteTable' AND event_time > current_date() - INTERVAL 7 DAYS;
```

---

## 7. Delta Sharing — Open Cross-Platform Data Sharing

- **Delta Sharing** is an open protocol for sharing live data across organizations/platforms **without copying it** — the recipient reads directly against the shared Delta table using any Delta Sharing-compatible client (Spark, pandas, PowerBI), even if they don't use Databricks at all.
- Two sharing types: **within the same account/metastore** (simpler, direct UC grants) and **open sharing** (cross-organization, using shared credential tokens).

```sql
CREATE SHARE sales_share;
ALTER SHARE sales_share ADD TABLE production.sales.orders;
CREATE RECIPIENT partner_org;
GRANT SELECT ON SHARE sales_share TO RECIPIENT partner_org;
```

---

## 8. Managed vs External Locations & Storage Credentials

```sql
CREATE STORAGE CREDENTIAL my_cred
  WITH (AWS_IAM_ROLE = 'arn:aws:iam::123456789:role/uc-access-role');

CREATE EXTERNAL LOCATION my_location
  URL 's3://my-bucket/data/'
  WITH (STORAGE CREDENTIAL my_cred);

CREATE CATALOG sales MANAGED LOCATION 's3://my-bucket/sales/';
```

- **Storage Credential**: the cloud IAM identity (role/service principal) UC uses to access underlying storage — centrally managed instead of per-cluster instance profiles.
- **External Location**: a governed URL prefix + credential pairing, used as the basis for external tables/volumes and to control exactly which paths a principal can read/write.
- This model replaces the older, less secure "cluster instance profile" approach where access control was tied to compute rather than to the data itself.

---

## 9. Unity Catalog Metastore Admin Responsibilities (Platform/DataOps Admin Angle)

- Assign metastore admin (a small, tightly controlled group).
- Define catalog-per-environment or catalog-per-domain strategy up front — hard to restructure later.
- Set up **default catalogs/schemas** per workspace to prevent accidental cross-environment writes.
- Establish **naming conventions** and **tagging** (e.g., `production.sales.*`, tag PII columns) for discoverability and governance automation.
- Enable **audit log** export and **Lakehouse Monitoring** on critical tables early — retrofitting governance later is painful.

---

## 10. Key Takeaways for DataOps

- Unity Catalog's 3-level namespace + hierarchical GRANTs is the backbone of governance — know the privilege model cold.
- Row filters and column masks give centralized, tool-agnostic fine-grained security — much stronger than per-BI-tool access control.
- Lineage and audit logs aren't just nice-to-haves — they're what makes incident response and compliance audits tractable in a Lakehouse.
- Volumes + Storage Credentials + External Locations are the modern replacement for DBFS mounts and cluster instance profiles — always prefer these for new work.
