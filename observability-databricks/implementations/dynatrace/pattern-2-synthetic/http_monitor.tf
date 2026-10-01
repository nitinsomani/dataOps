# Pattern 2 — Dynatrace HTTP synthetic monitor polling the Databricks Jobs API
#
# Provider: dynatrace-oss/dynatrace  (Monitoring-as-Code via Terraform).
# Polls GET /api/2.1/jobs/runs/list?job_id=<id>&limit=1 and asserts the latest run
# SUCCEEDED. Add a freshness check (end_time recency) via a validation rule too.
#
# ⚠️ Store the Databricks token in the Dynatrace credential vault and reference it —
#    never inline. Field names below follow the current dynatrace provider schema;
#    confirm against the provider version you pin.

terraform {
  required_providers {
    dynatrace = {
      source  = "dynatrace-oss/dynatrace"
      version = "~> 1.0"
    }
  }
}

provider "dynatrace" {
  dt_env_url   = var.dynatrace_env_url   # https://<env-id>.live.dynatrace.com
  dt_api_token = var.dynatrace_api_token # token with synthetic config scopes
}

variable "dynatrace_env_url"   { type = string }
variable "dynatrace_api_token" { type = string, sensitive = true }
variable "databricks_workspace_host" {
  type        = string
  description = "e.g. https://shell-prj5642893-...-eu-west-1-prd.cloud.databricks.com"
}
variable "databricks_job_id" { type = string }
variable "databricks_credential_vault_id" {
  type        = string
  description = "Dynatrace credential-vault ID holding the read-only Databricks token."
}
variable "synthetic_location_id" {
  type        = string
  description = "Dynatrace synthetic location (private ActiveGate location for private workspaces)."
}

resource "dynatrace_http_monitor" "databricks_job_health" {
  name      = "Databricks job health — ${var.databricks_job_id}"
  enabled   = true
  frequency = 15 # minutes; ~half the job's schedule interval

  locations = [var.synthetic_location_id]

  anomaly_detection {
    outage_handling {
      global_outage = true
    }
  }

  script {
    request {
      description = "latest run status"
      method      = "GET"
      url         = "${var.databricks_workspace_host}/api/2.1/jobs/runs/list?job_id=${var.databricks_job_id}&limit=1"

      configuration {
        accept_any_certificate = false

        # Auth header pulled from the Dynatrace credential vault (not inline).
        header {
          name  = "Authorization"
          value = "Bearer {{credentialVault:${var.databricks_credential_vault_id}}}"
        }
      }

      # Assertion 1: HTTP 200 and the latest run result_state is SUCCESS.
      validation {
        rule {
          type        = "httpStatusesList"
          pass_if_found = false
          value       = ">=400"
        }
        rule {
          type          = "patternConstraint"
          pass_if_found = true
          value         = "\"result_state\":\"SUCCESS\""
        }
      }
    }
  }
}

# ── Freshness (missed-schedule) check ────────────────────────────────────────
# The provider's HTTP monitor can't do arithmetic on end_time directly. Two ways:
#   (a) a second BROWSER monitor with a JS validation step comparing
#       (Date.now() - run.end_time) against the expected interval, or
#   (b) push an availability metric from Pattern 3 and alert on staleness there.
# Prefer (b) if you're already doing Pattern 3 — keep this monitor to "last run
# succeeded" and let the freshness SLO live with the pushed metrics.
