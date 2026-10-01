"""
Phase 3 — DLT expectation PATTERNS (examples only — NOT production rules).

⚠️  The actual rules must come from Data Engineering, who own the business truth
    for well / wellbore / trajectory / DDR records. These are illustrative patterns
    showing the three enforcement levels and the quarantine approach.

Enforcement levels:
  @dlt.expect              -> log only, keep row      (advisory metric)
  @dlt.expect_or_drop      -> drop row, continue       (bad rows kept out of downstream)
  @dlt.expect_or_fail      -> fail the update          (structural invariant broken)
"""

import dlt
from pyspark.sql import functions as F


# ── Pattern 1: structural invariant — fail the pipeline if violated ──────────
@dlt.table(name="silver_wellbore")
@dlt.expect_or_fail("uwi_not_null", "uwi IS NOT NULL")
def silver_wellbore():
    # ... real transformation ...
    return dlt.read("bronze_wellbore")


# ── Pattern 2: bad rows dropped, but ALSO quarantined for auditability ───────
# Primary table: keep only valid rows.
@dlt.table(name="silver_trajectory")
@dlt.expect_or_drop("md_non_negative", "measured_depth >= 0")
@dlt.expect_or_drop("has_station", "station_id IS NOT NULL")
def silver_trajectory():
    return dlt.read("bronze_trajectory")


# Quarantine table: the SAME source, inverted predicate — captures what was dropped
# so data-quality issues are visible/auditable instead of silently discarded.
@dlt.table(name="silver_trajectory_quarantine")
def silver_trajectory_quarantine():
    df = dlt.read("bronze_trajectory")
    return df.filter(
        ~( (F.col("measured_depth") >= 0) & (F.col("station_id").isNotNull()) )
    )


# ── Pattern 3: advisory metric — log only, don't drop ────────────────────────
@dlt.table(name="gold_well")
@dlt.expect("status_known", "well_status IN ('ACTIVE','SUSPENDED','ABANDONED','PLANNED')")
def gold_well():
    return dlt.read("silver_well")


# ── Pattern 4: multiple expectations via decorator dict ──────────────────────
_WELL_RULES = {
    "uwi_not_null": "uwi IS NOT NULL",
    "name_not_blank": "length(trim(well_name)) > 0",
    "spud_before_completion": "spud_date IS NULL OR completion_date IS NULL OR spud_date <= completion_date",
}

@dlt.table(name="gold_well_curated")
@dlt.expect_all(_WELL_RULES)          # log all, keep rows
def gold_well_curated():
    return dlt.read("silver_well")

# Variants:
#   @dlt.expect_all_or_drop(_WELL_RULES)   -> drop rows failing ANY rule
#   @dlt.expect_all_or_fail(_WELL_RULES)   -> fail update if ANY row fails ANY rule
