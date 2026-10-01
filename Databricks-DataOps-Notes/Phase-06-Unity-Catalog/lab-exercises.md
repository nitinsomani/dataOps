# Phase 6: Unity Catalog & Data Governance — Lab Exercises

> Requires a Unity Catalog-enabled workspace (Premium tier or above) with metastore admin or sufficient catalog creation privileges.

---

## Lab 1: Explore the Three-Level Namespace

```sql
SHOW CATALOGS;
SHOW SCHEMAS IN main;
SHOW TABLES IN main.default;

CREATE CATALOG IF NOT EXISTS lab6_catalog;
CREATE SCHEMA IF NOT EXISTS lab6_catalog.sales;
CREATE TABLE lab6_catalog.sales.orders (id INT, amount DOUBLE, region STRING);
INSERT INTO lab6_catalog.sales.orders VALUES (1, 100.0, 'US'), (2, 200.0, 'EU'), (3, 150.0, 'US');
```

### Questions to Answer
- [ ] What catalogs exist by default in a new workspace (hint: `main`, `system`, `samples`)?
- [ ] What's the fully qualified name of the table you just created?

---

## Lab 2: Grants and Permission Hierarchy

```sql
CREATE GROUP IF NOT EXISTS lab6_analysts;  -- or use an existing account group

GRANT SELECT ON TABLE lab6_catalog.sales.orders TO `lab6_analysts`;
-- Intentionally skip USE CATALOG/USE SCHEMA grants for now

SHOW GRANTS ON TABLE lab6_catalog.sales.orders;
```

### Questions to Answer
- [ ] If a member of `lab6_analysts` tries `SELECT * FROM lab6_catalog.sales.orders` right now, what error do you expect (missing USE CATALOG/USE SCHEMA)?
- [ ] Add `GRANT USE CATALOG ON CATALOG lab6_catalog TO `lab6_analysts`` and `GRANT USE SCHEMA ON SCHEMA lab6_catalog.sales TO `lab6_analysts`` — does the query now succeed?

---

## Lab 3: Row Filters and Column Masks

```sql
CREATE FUNCTION lab6_catalog.sales.region_filter(region STRING) RETURNS BOOLEAN
RETURN region = 'US' OR is_account_group_member('global-admins');

ALTER TABLE lab6_catalog.sales.orders SET ROW FILTER lab6_catalog.sales.region_filter ON (region);

SELECT * FROM lab6_catalog.sales.orders;   -- run as a non-admin user in `lab6_analysts`
```

```sql
CREATE FUNCTION lab6_catalog.sales.mask_amount(amount DOUBLE) RETURNS DOUBLE
RETURN CASE WHEN is_account_group_member('finance') THEN amount ELSE NULL END;

ALTER TABLE lab6_catalog.sales.orders ALTER COLUMN amount SET MASK lab6_catalog.sales.mask_amount;
```

### Questions to Answer
- [ ] As a non-admin, how many rows do you see after the row filter is applied?
- [ ] What value do you see in the `amount` column if you're not in the `finance` group?
- [ ] Remove the row filter (`ALTER TABLE ... DROP ROW FILTER`) — does the visible row count change back?

---

## Lab 4: Lineage Exploration

1. Create a small pipeline: `bronze_orders` → `silver_orders` (dedup) → `gold_totals` (aggregate), each as a separate table write via notebook cells.
2. Open **Catalog Explorer** → navigate to `gold_totals` → **Lineage** tab.

### Questions to Answer
- [ ] Does the lineage graph correctly show `bronze_orders` → `silver_orders` → `gold_totals`?
- [ ] Click into column-level lineage for the aggregated column — which upstream column(s) does it trace back to?

---

## Lab 5: Storage Credentials & External Locations (requires cloud admin access)

```sql
-- Example (AWS) — adjust ARNs/paths for your environment
CREATE STORAGE CREDENTIAL lab6_cred
  WITH (AWS_IAM_ROLE = 'arn:aws:iam::<account-id>:role/uc-access-role');

CREATE EXTERNAL LOCATION lab6_location
  URL 's3://<your-bucket>/lab6/'
  WITH (STORAGE CREDENTIAL lab6_cred);

CREATE TABLE lab6_catalog.sales.external_orders (id INT, amount DOUBLE)
USING DELTA LOCATION 's3://<your-bucket>/lab6/external_orders/';
```

### Questions to Answer
- [ ] What IAM permissions does the storage credential's role need at minimum (list, read, write on the bucket path)?
- [ ] Drop the external table — did the underlying S3 files get deleted? Compare with dropping a managed table.

---

## Lab 6: Audit Log Query

```sql
SELECT event_time, action_name, request_params, user_identity.email
FROM system.access.audit
WHERE action_name IN ('createTable', 'deleteTable', 'generateTemporaryPathCredential')
ORDER BY event_time DESC
LIMIT 20;
```

### Questions to Answer
- [ ] Do you see the `createTable` events for the tables you created in this lab?
- [ ] How would you build an alert that fires when a table in `lab6_catalog.sales` is dropped outside business hours?
