# Phase 6 — AWS-Side Observability + Synthetic Canary Checks

**Pillar:** Infrastructure  ·  **Owner:** Platform  ·  **Effort:** Medium  ·  **Repo:** `osdu-ssw-central-dbx`

## Objective

Observe the **infrastructure under** Databricks (the eu-west-1 VPC you're building)
and add a **canary** that detects platform-level outages independent of the pipelines.

## Part A — VPC Flow Logs (eu-west-1)

The new `terraform/{env}/public/eu-west-1/scops-core/vpc.tf` provisions the VPC,
subnets, NAT, IGW. Add **VPC Flow Logs** to CloudWatch (or S3) for:

- Network forensics (who talked to what) for audit/incident response.
- Detecting NAT saturation / rejected traffic (SG/NACL misconfig).

```hcl
# add to scops-core (eu-west-1)
resource "aws_flow_log" "vpc" {
  vpc_id          = module.vpc.vpc_id
  traffic_type    = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination = aws_cloudwatch_log_group.vpc_flow.arn
  iam_role_arn    = aws_iam_role.vpc_flow.arn
  tags = merge(var.tags, { Name = "${local.databricks_name_prefix}-vpc-flow-log" })
}
```

Full example: `implementations/` is Databricks-focused; the flow-log resource lives
next to the VPC module in `scops-core`. Mirror any existing us-east-1 flow-log setup
if present; otherwise this is net-new.

## Part B — NAT / IGW / budget CloudWatch alarms

- **NAT gateway** — alarm on `BytesOutToDestination` / `ErrorPortAllocation`
  (port exhaustion is a classic silent failure for busy egress).
- **Budgets** — `budget.tf` already exists at account level; add a per-region /
  per-tag budget alarm for the EU Databricks spend so cost surprises page early.

## Part C — Synthetic canary

A tiny scheduled Databricks job (every 5–15 min) that runs a trivial
`SELECT 1` on the SQL warehouse and a no-op notebook on a small cluster, with
`on_failure` → Teams webhook. It detects **platform-level** problems (workspace
down, warehouse cold-start failure, auth/token expiry) that your real pipelines —
which run on a schedule — wouldn't reveal until their next run.

Config: `implementations/phase-06-aws-canary/canary-job.yml` (DAB) — a single-task
job with a short cron and failure webhook.

### Best practice applied

- **Black-box monitoring** — test the platform the way a user experiences it, not
  just from inside a pipeline.
- **Flow Logs = audit + debugging** — the standard first artifact any cloud network
  incident review asks for.
- **Budget alarms are observability too** — cost is a signal; a 3× day should page,
  not be discovered at month-end.

## Verification

- Flow logs appear in the CloudWatch log group / S3 prefix.
- Stop the warehouse and confirm the canary fails and alerts.

## Ownership & DE involvement

**Platform-only.**
