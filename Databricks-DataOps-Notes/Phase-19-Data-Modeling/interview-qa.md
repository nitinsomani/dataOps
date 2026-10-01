# Phase 19: Data Modeling & Warehousing Fundamentals — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ Design a star schema for an e-commerce order system. Walk through your fact and dimension tables.

**Answer sketch:**
First, I'd state the **grain** explicitly — I'd choose "one row per order line item" (not one row per order) since it's the finest useful grain and everything else (order totals, item counts) can be derived by aggregating up, while the reverse isn't true. `fact_order_lines` would contain foreign keys `customer_key`, `product_key`, `date_key`, `store_key`, plus measures `quantity`, `unit_price`, `discount_amount`, `line_total`. Dimensions: `dim_customer` (name, segment, signup_date, region — denormalized, no further normalization into a separate region table), `dim_product` (name, category, brand — flat, not snowflaked out to a separate category table), `dim_date` (a standard date dimension with year/quarter/month/day-of-week/is_holiday columns, pre-joined rather than computed at query time), and `dim_store`. I'd explicitly flag `dim_customer` as a candidate for SCD Type 2 if historical accuracy matters (e.g., "what was the customer's segment when they placed this order").

---

## Q2. ⭐ What is "grain" in dimensional modeling and why is getting it wrong so costly?

**Answer:**
Grain is the precise definition of what a single row in a fact table represents — e.g., "one row per order" vs "one row per order line item" vs "one row per order line item per fulfillment event." It must be decided *before* designing measures or dimensions, because it determines whether a given measure is even meaningful at that row level. Getting it wrong is costly because it's usually discovered late — e.g., if you build a fact table at "one row per order" grain but later need per-product revenue breakdowns, you either can't answer that question at all, or worse, someone writes a query assuming line-item detail exists and silently gets wrong (double-counted or under-counted) aggregates. Fixing grain after a warehouse has downstream consumers built on it is a major, disruptive migration.

---

## Q3. ⭐ Explain SCD Type 2 and why a natural key alone isn't sufficient for it.

**Answer:**
SCD Type 2 tracks the full history of changes to a dimension by inserting a new row every time a tracked attribute changes, rather than overwriting — each row gets an `effective_date`, an `end_date` (or NULL/9999-12-31 for the current row), and an `is_current` flag. A natural key (e.g., `customer_id`) by itself can't support this because the same natural key legitimately has multiple valid rows over time (one per historical version) — joining a fact table to the dimension on the natural key alone would be ambiguous (which version?). This is why SCD Type 2 requires a **surrogate key**: the fact table's foreign key points to the surrogate key of the dimension row that was current *at the time the fact occurred*, correctly capturing point-in-time historical context.

---

## Q4. When would you choose SCD Type 1 over Type 2, and what's the tradeoff?

**Answer:**
Type 1 (overwrite, no history) is appropriate when the change represents a **correction** rather than a meaningful business event — e.g., fixing a typo in a customer's name, or correcting an incorrectly-entered zip code. The tradeoff is that Type 1 permanently loses the ability to answer "what did this look like before the change" — if you later realize you actually needed that history (e.g., a "typo fix" turns out to have been a legitimate address change relevant to historical tax reporting), that information is unrecoverable unless you have upstream source system history to fall back on. Type 2 should be the default for any attribute where historical accuracy has plausible business value, reserving Type 1 for genuine data corrections.

---

## Q5. What's the difference between a star schema and a snowflake schema, and why is star generally preferred in a Lakehouse?

**Answer:**
A star schema keeps dimension tables flat/denormalized — e.g., `dim_product` includes `category_name` directly as a column. A snowflake schema normalizes dimensions further — `dim_product` would instead have a `category_key` foreign key pointing to a separate `dim_category` table, reducing storage redundancy at the cost of an extra join. In a Lakehouse specifically, columnar storage (Parquet/Delta) makes storing redundant descriptive text extremely cheap, while joins remain the most expensive operation (shuffle, Phase 2) — so the classic normalization tradeoff tips decisively toward star schema: accept some redundancy to minimize joins and keep BI tool queries simple and fast.

---

## Q6. What's an accumulating snapshot fact table, and when would you use one instead of a transaction fact table?

**Answer:**
An accumulating snapshot fact table has one row per instance of a business process (e.g., one row per order), which gets **updated in place** as the process moves through defined stages (order placed → paid → shipped → delivered → returned), typically with a column per milestone timestamp. This differs from a transaction fact table, which would instead have separate immutable rows for each event. Accumulating snapshots are useful for process/pipeline analysis — e.g., "what's the average time between order placement and shipment" is a simple column subtraction on one row, rather than requiring a self-join across multiple event rows. The tradeoff is that accumulating snapshots require updates (not pure appends), which is a different write pattern than the append-heavy nature of most Bronze/Silver Delta tables — typically implemented via `MERGE` in the Gold layer.

---

## Q7. How does dimensional modeling change (or not) when your warehouse is a Lakehouse (Delta Lake) instead of a traditional RDBMS-based warehouse?

**Answer:**
The core Kimball concepts — grain, fact/dimension separation, star schema preference, SCD handling — remain unchanged; dimensional modeling is a logical design discipline independent of the physical storage engine. What changes is the *physical* implementation: instead of traditional B-tree indexes, performance comes from Liquid Clustering/Z-Order on commonly-filtered columns (which itself becomes a modeling-adjacent decision — choosing good clustering keys); SCD Type 2 is implemented via `MERGE INTO` or DLT's `apply_changes` rather than stored-procedure-based warehouse ETL; and because columnar storage makes wide, denormalized dimension tables cheap, there's less pressure toward snowflaking for storage-efficiency reasons than there might be in a traditional row-oriented RDBMS warehouse.
