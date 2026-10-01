# =============================================================================
# Dynatrace events relay — VPC Lambda + HTTP API Gateway
# Mirrors duocircle-relay.tf. Databricks job-failure webhooks POST here; the
# Lambda maps the payload to a Dynatrace ERROR_EVENT and forwards to the
# Events API v2 with the Api-Token header (kept in AWS, not in Databricks).
#
# Place in the scops-core stack for the target workspace. Copy the Lambda source
# (relay_lambda.py) to lambda/dynatrace-relay/lambda_function.py in that stack.
# =============================================================================

locals {
  dynatrace_relay_name = "${local.resources_name_prefix}-dynatrace-relay"
}

# Egress-only SG: HTTPS out to the Dynatrace tenant via the VPC NAT gateway.
module "dynatrace_relay_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.1"

  name        = "${local.dynatrace_relay_name}-sg"
  description = "Egress-only SG for the Dynatrace events relay Lambda"
  vpc_id      = var.dynatrace_relay.vpc_id

  egress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPS to Dynatrace tenant via NAT"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  tags = var.tags
}

# Lambda: packaged from the local lambda/dynatrace-relay directory.
module "dynatrace_relay_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 8.0"

  function_name = local.dynatrace_relay_name
  description   = "Relays Databricks job-failure webhooks to the Dynatrace Events API v2"
  handler       = "lambda_function.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 128

  source_path = "${path.module}/lambda/dynatrace-relay"

  # Run inside the private subnets so egress uses the NAT public IP.
  vpc_subnet_ids         = var.dynatrace_relay.private_subnet_ids
  vpc_security_group_ids = [module.dynatrace_relay_security_group.security_group_id]
  attach_network_policy  = true

  cloudwatch_logs_retention_in_days = 120

  environment_variables = {
    DT_ENV_URL   = var.dynatrace_relay.tenant_url # https://<env-id>.live.dynatrace.com
    DT_API_TOKEN = var.dynatrace_api_token        # scope: events.ingest (sensitive)
    RELAY_TOKEN  = var.dynatrace_relay_token       # shared secret Databricks must present
  }

  tags = var.tags
}

# HTTP API Gateway: single POST /ingest route -> Lambda proxy integration.
module "dynatrace_relay_apigw" {
  source  = "terraform-aws-modules/apigateway-v2/aws"
  version = "~> 5.0"

  name          = "${local.dynatrace_relay_name}-api"
  description   = "HTTP API front for the Dynatrace events relay Lambda"
  protocol_type = "HTTP"

  create_domain_name = false

  routes = {
    "POST /ingest" = {
      integration = {
        uri                    = module.dynatrace_relay_lambda.lambda_function_arn
        payload_format_version = "2.0"
        timeout_milliseconds   = 30000
      }
    }
  }

  stage_access_log_settings = {
    create_log_group            = true
    log_group_retention_in_days = 120
  }

  tags = var.tags
}

# Allow API Gateway to invoke the Lambda.
resource "aws_lambda_permission" "dynatrace_relay_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.dynatrace_relay_lambda.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${module.dynatrace_relay_apigw.api_execution_arn}/*/*"
}

output "dynatrace_relay_api_endpoint" {
  description = "Base invoke URL of the Dynatrace relay HTTP API (append /ingest)"
  value       = module.dynatrace_relay_apigw.api_endpoint
}

output "dynatrace_relay_lambda_name" {
  description = "Name of the Dynatrace relay Lambda function"
  value       = module.dynatrace_relay_lambda.lambda_function_name
}

# ── Variables (add to the stack's variables.tf) ─────────────────────────────
# variable "dynatrace_relay" {
#   type = object({
#     vpc_id             = string
#     private_subnet_ids = list(string)
#     tenant_url         = string
#   })
# }
# variable "dynatrace_api_token"   { type = string, sensitive = true }
# variable "dynatrace_relay_token" { type = string, sensitive = true }
