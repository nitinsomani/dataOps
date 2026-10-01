# Phase 6: Unity Catalog & Data Governance — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ What is Unity Catalog and what problem did it solve compared to the legacy Hive metastore?

**Answer:**
Unity Catalog is Databricks' centralized governance layer for data and AI assets across every workspace attached to a single metastore, using a three-level namespace (`catalog.schema.table`). Before UC, each workspace had its own isolated Hive metastore with independent, often inconsistent permissions — managing access across dozens of workspaces meant duplicating grants everywhere with no single source of truth, no cross-workspace lineage, and no unified audit trail. UC centralizes all of that: one place to define access control, one place to see lineage regardless of which workspace a query ran in, and one audit log across the whole account.

---

## Q2. ⭐ Explain the Unity Catalog permission hierarchy — why would a user with `SELECT` on a table still get "table not found"?

**Answer:**
Permissions cascade hierarchically: to query `catalog.schema.table`, a principal needs `USE CATALOG` on the catalog, `USE SCHEMA` on the schema, **and** `SELECT` on the table — all three, not just the table-level grant. This is a common gotcha: someone grants `SELECT` on a table but forgets `USE CATALOG`/`USE SCHEMA`, and the user gets a permission/not-found error despite having the "right" grant. Best practice is to grant `USE CATALOG`/`USE SCHEMA` broadly to a group up front, then manage fine-grained `SELECT`/`MODIFY` at the table level.

---

## Q3. What are row filters and column masks, and why are they preferable to building access control into each BI tool?

**Answer:**
Row filters are SQL functions attached to a table (`ALTER TABLE t SET ROW FILTER fn ON (col)`) that restrict which rows a querying principal can see, evaluated per-query based on things like group membership. Column masks (`ALTER TABLE t ALTER COLUMN col SET MASK fn`) dynamically redact or transform column values (e.g., masking SSNs for non-HR roles) at query time without altering the underlying stored data. Because these are enforced centrally by Unity Catalog at the table level, they apply uniformly no matter which client queries the data — a notebook, Databricks SQL, or an external BI tool connecting via JDBC/ODBC — eliminating the need to duplicate and maintain separate access logic in every downstream tool.

---

## Q4. ⭐ How does Unity Catalog handle data lineage, and why does it matter operationally?

**Answer:**
UC automatically captures column-level and table-level lineage for any query executed through Databricks — notebooks, Jobs, DLT pipelines, Databricks SQL — with no manual instrumentation required, viewable as a graph in Catalog Explorer. Operationally this is critical for **impact analysis** (before changing or dropping a column, see everything downstream that depends on it) and **root cause analysis** (when a Gold-layer metric looks wrong, trace backward through Silver and Bronze to find where the discrepancy was introduced) — both of which are otherwise extremely time-consuming to do manually across a large pipeline estate.

---

## Q5. What are Storage Credentials and External Locations, and how do they improve on the older "cluster instance profile" model?

**Answer:**
A Storage Credential represents a cloud IAM identity (e.g., an AWS IAM role or Azure managed identity) that Unity Catalog uses to access underlying cloud storage, defined once centrally. An External Location pairs that credential with a specific storage URL prefix, governing exactly which paths can be accessed and by whom via standard UC grants. This replaces the legacy model where access control was tied to which **cluster** you attached to (instance profiles) — a much coarser, harder-to-audit mechanism where anyone attaching to a cluster with a broad instance profile got broad storage access regardless of their actual data permissions. With Storage Credentials + External Locations, access control is tied to the **data** itself, independent of which compute resource is being used.

---

## Q6. What is Delta Sharing and how does it differ from just giving another team read access to your Databricks workspace?

**Answer:**
Delta Sharing is an open, cross-platform protocol for sharing live Delta table data with external recipients **without copying the data or requiring them to use Databricks** — a recipient can read a shared table using Spark, pandas, PowerBI, or any Delta Sharing-compatible client, authenticated via a shared credential token rather than needing a Databricks account/workspace access. This is different from granting a partner org access to your workspace (which requires them to be Databricks users within your account) — Delta Sharing decouples data sharing from platform lock-in, letting you share governed data with partners regardless of what platform they run on.

---

## Q7. As a DataOps engineer setting up governance for a new Databricks environment, what catalog/schema strategy would you propose and why?

**Answer:**
I'd typically propose a catalog-per-environment strategy (`dev`, `staging`, `prod` catalogs) combined with schema-per-domain within each (`prod.sales`, `prod.marketing`), rather than catalog-per-domain-only — this cleanly isolates environments so a dev experiment can never accidentally touch production data, while schemas provide logical grouping within an environment for team/domain ownership. I'd set default catalog/schema per workspace to prevent accidental cross-environment writes (e.g., a dev workspace should never default-write into the prod catalog), establish naming/tagging conventions (tagging PII columns explicitly) early, and grant access via IdP-synced groups rather than individual users so permissions stay maintainable as headcount changes. Restructuring catalog strategy after the fact is painful, so this decision should be made deliberately up front.

---

## Q8. How would you use system tables for governance/security monitoring?

**Answer:**
`system.access.audit` logs every governed action — queries executed, grants/revokes, table creation/deletion — queryable with standard SQL, which lets you build automated alerts (e.g., notify security if a table containing PII is dropped, or if grants are made outside business hours) without needing to export logs to a separate SIEM first (though exporting to CloudTrail/Azure Monitor/Cloud Audit Logs is also supported for long-term retention and integration with existing security tooling). This turns governance monitoring into a standard data engineering problem — you can build a Delta table + dashboard on top of the audit system table just like any other pipeline.
