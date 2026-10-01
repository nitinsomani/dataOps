# Phase 19: Data Modeling & Warehousing Fundamentals — Detailed Notes

> **Goal**: "Design a schema for X" is one of the most common data-role interview questions at product companies, and it's independent of which platform you use. This phase covers dimensional modeling fundamentals and how they map onto the Lakehouse's Gold layer.

---

## 1. Why Data Modeling Still Matters in a Lakehouse World

Even though Delta Lake removes many traditional warehouse constraints (schema-on-write flexibility, no rigid indexing), the **Gold layer** of a medallion architecture is still, functionally, a data warehouse — and it still benefits from decades of dimensional modeling wisdom (Kimball methodology) for making data intuitive to query and performant for BI tools.

---

## 2. OLTP vs OLAP

| | OLTP (operational) | OLAP (analytical) |
|---|---------------------|----------------------|
| Purpose | Run the business (transactions) | Analyze the business (reporting/BI) |
| Schema | Highly normalized (3NF) — minimize redundancy | Denormalized (star schema) — optimize for read/aggregation |
| Query pattern | Many small reads/writes, single-row lookups | Few large reads, heavy aggregation/joins |
| Example | Postgres/MySQL backing an e-commerce app | Databricks Gold layer / Redshift / Snowflake |

- Source systems feeding a Lakehouse are typically OLTP; the Gold layer is OLAP-shaped, which is why Bronze→Silver→Gold transformation involves progressive denormalization.

---

## 3. Star Schema — The Default Pattern

```
                 ┌──────────────┐
                 │  dim_date     │
                 └──────┬───────┘
┌──────────────┐        │        ┌──────────────┐
│ dim_customer  ├───────┼────────┤ dim_product   │
└──────────────┘        │        └──────────────┘
                 ┌───────┴────────┐
                 │  fact_orders    │
                 │  - order_id      │
                 │  - customer_key   │  (FK to dim_customer)
                 │  - product_key     │  (FK to dim_product)
                 │  - date_key          │  (FK to dim_date)
                 │  - quantity, amount   │  (measures)
                 └────────────────────┘
```

- **Fact table**: the "verb" — records events/transactions (orders, page views, payments), contains foreign keys to dimensions plus numeric **measures** (quantity, amount, duration).
- **Dimension table**: the "nouns" — descriptive context (customer, product, date, region), typically smaller, denormalized, often with many descriptive text columns.
- **Grain**: the single most important design decision — precisely what one row of the fact table represents (e.g., "one row per order line item," not "one row per order"). Get the grain wrong and every downstream aggregation is subtly incorrect.

### Star vs Snowflake Schema
```
Star:     dimensions are flat/denormalized (dim_product has category_name directly)
Snowflake: dimensions are normalized further (dim_product -> dim_category -> dim_department)
```
- **Snowflake** reduces redundancy (classic 3NF thinking) but requires more joins at query time.
- **Star** is generally preferred in modern Lakehouse/columnar-storage contexts — storage is cheap, joins are the expensive part, and BI tools generate simpler/faster queries against a flat star schema.

---

## 4. Fact Table Types

| Type | Description | Example |
|------|-------------|---------|
| **Transaction fact** | One row per discrete event | One row per order line |
| **Periodic snapshot** | One row per entity per fixed time period, regardless of activity | Daily account balance snapshot |
| **Accumulating snapshot** | One row per process/pipeline instance, updated as it progresses through stages | One row per order, updated as it moves shipped→delivered→returned |
| **Factless fact** | No measures, just records that an event/relationship occurred | Student attended class (just the FK combination matters) |

---

## 5. Slowly Changing Dimensions (SCD) — Conceptual Deep Dive

(Delta/DLT *implementation* syntax is in Phase 3/5 — this is the conceptual modeling decision behind *which* SCD type to use.)

| Type | Behavior | Use when... |
|------|----------|-------------|
| **Type 0** | Never changes (immutable attribute) | Original signup date |
| **Type 1** | Overwrite — no history kept | Correcting a typo; history doesn't matter |
| **Type 2** | New row per change, with validity date range + current flag | Need full historical accuracy (e.g., "what was the customer's address when this order shipped") |
| **Type 3** | Add a new column for the previous value (limited history) | Only need to compare "current vs previous," not full history |
| **Type 4** | Separate current table + historical/archive table | High-change-frequency dimensions, keep current table small/fast |
| **Type 6** | Hybrid (1+2+3) — combines overwrite, versioning, and previous-value columns | Complex reporting needing both current and historical views simultaneously |

- **Type 2 is the default answer expected in most interviews** — know the surrogate-key + `effective_date`/`end_date`/`is_current` pattern cold, and be able to explain why a natural/business key alone isn't sufficient (it can't distinguish between historical versions of the same entity).

---

## 6. Surrogate Keys vs Natural Keys

- **Natural key**: a business-meaningful identifier (email, SSN, order number) — can change, can be reused, can differ in format across source systems.
- **Surrogate key**: a system-generated, meaningless identifier (auto-increment integer, UUID) — stable, always unique, insulates the warehouse from source-system key changes, and is *required* for SCD Type 2 (since the same natural key legitimately has multiple valid rows over time).

---

## 7. Normalization Recap (for the OLTP/source side)

```
1NF: atomic values, no repeating groups
2NF: 1NF + no partial dependency on a composite key
3NF: 2NF + no transitive dependency (non-key columns depend only on the key)
```
- Relevant mainly for reasoning about **source system** schemas (e.g., a normalized Postgres OLTP schema you're extracting from) — the Gold layer intentionally denormalizes away from this for query performance.

---

## 8. Data Vault (Alternative Modeling Approach — Awareness Level)

- **Data Vault** (Hubs, Links, Satellites) is an alternative to Kimball star schemas, popular in some large enterprises for the **Silver/integration layer** specifically — optimized for auditability, parallel loading, and handling many disparate source systems, at the cost of needing an extra transformation step (Data Vault → star schema) before it's BI-friendly.
- Not required to implement, but worth being able to describe at a high level if asked "have you heard of Data Vault modeling."

---

## 9. Modeling Decisions Specific to the Lakehouse/Delta Context

- **Liquid Clustering / Z-Order key choice** (Phase 3/8) is itself a modeling decision — usually the most common fact table filter columns (date, a key dimension FK) or high-cardinality join keys.
- **Wide vs narrow tables**: Lakehouse storage is columnar and cheap, so unlike a traditional RDBMS, adding many descriptive columns to a dimension isn't costly — bias toward wider, more denormalized dimensions than you might in a traditional normalized warehouse.
- **Partition/cluster key should generally NOT be the same as the Type 2 SCD surrogate key** — partition/cluster on something query-pattern-relevant (date, region), not on an arbitrary generated key.

---

## 10. Key Takeaways for DataOps

- Grain is the single most important, most-tested modeling concept — always state it explicitly when designing a fact table in an interview.
- SCD Type 2 (surrogate key + effective/end date + current flag) is the expected default answer for "how do you track historical changes" — know it well enough to design the schema from scratch on a whiteboard.
- Star schema remains the default recommendation in a Lakehouse Gold layer — snowflake/full normalization is rarely the right answer given cheap columnar storage.
- Data modeling questions are platform-agnostic — this knowledge transfers directly whether the interviewer asks about Databricks, Snowflake, or a generic warehouse.
