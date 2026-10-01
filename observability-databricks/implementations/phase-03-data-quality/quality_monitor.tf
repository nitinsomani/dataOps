# Phase 3 — Lakehouse Monitoring (quality monitor) — Terraform pattern
#
# Enables profile + drift monitoring on key GOLD tables. Data Engineering picks
# WHICH tables and, for time-series monitors, the timestamp column + granularity.
#
# Place in a dashboards-style stack or a dedicated monitors stack. Requires the
# databricks provider already configured (see dashboards/providers.tf).

variable "monitor_tables_snapshot" {
  type        = list(string)
  description = "Fully-qualified gold dimension tables to monitor (snapshot type)."
  default     = []
  # e.g. ["subsurface_prd.gold_edm.gold_well", "subsurface_prd.gold_edm.gold_wellbore"]
}

variable "monitor_output_schema" {
  type        = string
  description = "Schema where monitor metric tables are written (e.g. subsurface_prd.observability)."
}

variable "monitor_assets_dir" {
  type        = string
  description = "Workspace dir for monitor dashboard assets (e.g. /Shared/lakehouse-monitoring)."
  default     = "/Shared/lakehouse-monitoring"
}

# ── Snapshot monitors for dimension-style gold tables ────────────────────────
resource "databricks_quality_monitor" "snapshot" {
  for_each   = toset(var.monitor_tables_snapshot)
  table_name = each.value

  assets_dir = "${var.monitor_assets_dir}/${replace(each.value, ".", "_")}"
  output_schema_name = var.monitor_output_schema

  snapshot {}

  schedule {
    quartz_cron_expression = "0 0 6 * * ?" # daily 06:00
    timezone_id            = "America/Chicago"
  }
}

# ── Example time-series monitor (event/fact table) ───────────────────────────
# Uncomment + set the timestamp col with Data Engineering.
#
# resource "databricks_quality_monitor" "trajectory_ts" {
#   table_name         = "subsurface_prd.gold_edm.gold_trajectory"
#   assets_dir         = "${var.monitor_assets_dir}/gold_trajectory"
#   output_schema_name = var.monitor_output_schema
#
#   time_series {
#     timestamp_col  = "event_timestamp"   # DE to confirm
#     granularities  = ["1 day"]
#   }
#
#   schedule {
#     quartz_cron_expression = "0 0 6 * * ?"
#     timezone_id            = "America/Chicago"
#   }
# }
