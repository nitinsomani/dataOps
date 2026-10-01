# Phase 19: Data Modeling & Warehousing Fundamentals — Cheat Sheet

---

## OLTP vs OLAP

```
OLTP → normalized (3NF), small fast transactions, source systems
OLAP → denormalized (star schema), large aggregations, Gold layer/BI
```

## Star Schema Anatomy

```
fact_orders (grain: one row per order line)
  - order_line_id (PK)
  - customer_key, product_key, date_key (FKs to dimensions)
  - quantity, amount (measures)

dim_customer / dim_product / dim_date (descriptive, denormalized)
```

Star (denormalized dims) vs Snowflake (normalized dims further): prefer **star** in a Lakehouse — storage is cheap, joins are expensive.

## Fact Table Types

```
Transaction fact    → one row per event (order line)
Periodic snapshot    → one row per entity per period (daily balance)
Accumulating snapshot → one row per process, updated across stages (order lifecycle)
Factless fact          → no measures, just relationship occurred (attendance)
```

## SCD Types Quick Reference

```
Type 0 → never changes
Type 1 → overwrite, no history
Type 2 → new row + effective_date/end_date/is_current  ← DEFAULT INTERVIEW ANSWER
Type 3 → add "previous_value" column, limited history
Type 4 → separate current + historical archive table
Type 6 → hybrid of 1+2+3
```

## Surrogate vs Natural Key

```
Natural key   → business-meaningful (email, order#), can change/repeat
Surrogate key → system-generated (auto-increment/UUID), stable, REQUIRED for SCD Type 2
```

## Normalization Levels (source/OLTP side)

```
1NF → atomic values, no repeating groups
2NF → 1NF + no partial dependency on composite key
3NF → 2NF + no transitive dependency
```

## Data Vault (awareness level)

```
Hub    → core business entity + surrogate key
Link    → relationship between hubs
Satellite → descriptive/historical attributes
Used for: Silver/integration layer auditability; needs extra transform step to become BI-friendly star schema
```

## Lakehouse-Specific Modeling Notes

```
[ ] Bias toward wider, denormalized dimension tables (columnar storage is cheap)
[ ] Liquid Clustering/Z-Order key = common filter columns, NOT the SCD surrogate key
[ ] Grain must be stated explicitly before designing any fact table
```
