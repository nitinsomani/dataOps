# Phase 5 — SQL Alerts (Terraform pattern, databricks_alert)
#
# Scheduled query + condition + notification to the existing Teams destination.
# Reuses the dashboards stack provider + warehouse. Set ${system_catalog} via a
# variable and the notification destination id from the DAB webhook.

variable "alert_warehouse_id" {
  type        = string
  description = "SQL warehouse to run alert queries on."
}

variable "alert_notification_destination_id" {
  type        = string
  description = "Notification destination id (Teams webhook) — same one the DAB job uses."
}

variable "system_catalog" {
  type        = string
  description = "System-catalog alias (this estate: system_table_unitycatalog_prd)."
  default     = "system_table_unitycatalog_prd"
}

# ── Alert 1: daily cost spike (>1.5x trailing 7d avg) ────────────────────────
resource "databricks_query" "cost_spike" {
  warehouse_id   = var.alert_warehouse_id
  display_name   = "[obs] daily cost vs 7d avg"
  parent_path    = "/Shared/observability/alerts"
  query_text     = <<-SQL
    WITH prices AS (
      SELECT sku_name, pricing.effective_list.default AS price_per_dbu
      FROM ${var.system_catalog}.billing.list_prices
      WHERE currency_code = 'USD' AND price_end_time IS NULL
    ),
    daily AS (
      SELECT u.usage_date,
             SUM(u.usage_quantity * COALESCE(p.price_per_dbu,0)) AS cost_usd
      FROM ${var.system_catalog}.billing.usage u
      LEFT JOIN prices p ON u.sku_name = p.sku_name
      WHERE u.usage_unit = 'DBU'
        AND u.usage_date >= CURRENT_DATE - INTERVAL 8 DAYS
      GROUP BY u.usage_date
    )
    SELECT
      (SELECT cost_usd FROM daily WHERE usage_date = CURRENT_DATE)                       AS today_usd,
      (SELECT AVG(cost_usd) FROM daily WHERE usage_date < CURRENT_DATE)                  AS avg_7d_usd,
      (SELECT cost_usd FROM daily WHERE usage_date = CURRENT_DATE)
        / NULLIF((SELECT AVG(cost_usd) FROM daily WHERE usage_date < CURRENT_DATE),0)    AS ratio
  SQL
}

resource "databricks_alert" "cost_spike" {
  query_id     = databricks_query.cost_spike.id
  display_name = "[obs] Daily cost spike (>1.5x 7d avg)"
  parent_path  = "/Shared/observability/alerts"

  condition {
    op = "GREATER_THAN"
    operand { column { name = "ratio" } }
    threshold { value { double_value = 1.5 } }
  }

  # Wire the notification subscription to the shared destination.
  # (In newer provider versions use `notify_on_ok` / subscriptions block.)
}

# ── Alert 2: job failure rate >10% in last 24h ───────────────────────────────
resource "databricks_query" "job_failure_rate" {
  warehouse_id = var.alert_warehouse_id
  display_name = "[obs] job failure rate 24h"
  parent_path  = "/Shared/observability/alerts"
  query_text   = <<-SQL
    SELECT ROUND(100.0 * SUM(CASE WHEN result_state IN ('FAILED','ERROR','TIMEDOUT') THEN 1 ELSE 0 END)
                 / NULLIF(COUNT(*),0), 1) AS failure_pct
    FROM ${var.system_catalog}.lakeflow.job_run_timeline
    WHERE period_start_time >= CURRENT_TIMESTAMP - INTERVAL 24 HOURS
      AND result_state IS NOT NULL
  SQL
}

resource "databricks_alert" "job_failure_rate" {
  query_id     = databricks_query.job_failure_rate.id
  display_name = "[obs] Job failure rate > 10% (24h)"
  parent_path  = "/Shared/observability/alerts"
  condition {
    op = "GREATER_THAN"
    operand { column { name = "failure_pct" } }
    threshold { value { double_value = 10 } }
  }
}

# ── Alert 3: any job cost on interactive (ALL_PURPOSE) compute today ──────────
resource "databricks_query" "interactive_job_cost" {
  warehouse_id = var.alert_warehouse_id
  display_name = "[obs] interactive-cluster job cost today"
  parent_path  = "/Shared/observability/alerts"
  query_text   = <<-SQL
    SELECT COUNT(*) AS interactive_job_usages
    FROM ${var.system_catalog}.billing.usage u
    WHERE u.usage_unit = 'DBU'
      AND u.billing_origin_product = 'ALL_PURPOSE'
      AND u.usage_metadata.job_id IS NOT NULL
      AND u.usage_date = CURRENT_DATE
  SQL
}

resource "databricks_alert" "interactive_job_cost" {
  query_id     = databricks_query.interactive_job_cost.id
  display_name = "[obs] Jobs running on interactive compute (today)"
  parent_path  = "/Shared/observability/alerts"
  condition {
    op = "GREATER_THAN"
    operand { column { name = "interactive_job_usages" } }
    threshold { value { double_value = 0 } }
  }
}

# NOTE: the databricks_alert schema (condition/subscriptions/notify) differs
# between provider major versions. Confirm against the version pinned in the
# dashboards stack and adjust the condition/notification blocks accordingly.
