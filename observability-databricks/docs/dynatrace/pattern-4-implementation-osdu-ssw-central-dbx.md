# Pattern 4 — Implementation Runbook for `osdu-ssw-central-dbx`

**Goal:** wire Databricks job/pipeline **failures → Dynatrace problems** using the
webhook-destination approach, with the relay infrastructure living in this repo
(`osdu-ssw-central-dbx`) exactly like the existing **DuoCircle relay**.

> This is the infra-side runbook. The relay (VPC Lambda + HTTP API Gateway) is
> deployed here; the Databricks notification-destination registration and the DAB
> job reference live in `ssw-dbx-idl2-de`. Both steps are covered below.

---

## Why a relay (recap)

Databricks `webhook_notifications` can only POST a **fixed Databricks JSON body** to a
**pre-registered destination URL** — you can't add the `Authorization: Api-Token …`
header Dynatrace needs, or reshape the body to Dynatrace's Events API schema. A tiny
relay Lambda fixes both: it receives the Databricks payload, maps it to a Dynatrace
`ERROR_EVENT`, injects the token (kept in AWS, not Databricks), and forwards to
`/api/v2/events/ingest`.

This is the **identical shape** to the DuoCircle email relay already in this repo
(`terraform/uat/public/us-east-1/scops-core/duocircle-relay.tf`): VPC Lambda behind an
HTTP API Gateway, egress via NAT, packaged from a local `lambda/` dir. We mirror it.

```
Databricks job FAILS
   │  webhook_notifications.on_failure  (destination id)
   ▼
HTTP API Gateway  (POST /ingest)
   ▼
Dynatrace relay Lambda (in VPC private subnets, egress via NAT)
   │  maps Databricks body -> Dynatrace event schema; injects Api-Token
   ▼
https://<tenant>/api/v2/events/ingest   -> Dynatrace problem -> alerting profile
```

---

## Prerequisites (one-time)

| Item | Where | Notes |
|------|-------|-------|
| Dynatrace tenant URL | e.g. `https://<env-id>.live.dynatrace.com` | SaaS or Managed |
| Dynatrace API token (`events.ingest` scope) | Dynatrace → Access Tokens | store as a **sensitive tfvar / AWS secret**, never in git |
| A shared-secret for the relay URL | generated | so only Databricks can call the relay (same idea as `duocircle_relay_token`) |
| Target VPC + private subnet ids | this repo's `scops-core` | reuse the workspace VPC (the one in `vpc.tf`) |
| Databricks workspace admin | — | needed to register the notification destination |

---

## Step 1 — Add the relay Terraform (mirror DuoCircle)

Create `dynatrace-relay.tf` in the appropriate `scops-core` stack (same stack that
hosts the DuoCircle relay, or the eu-west-1 `scops-core` if that's where the workspace
lives). The full file is provided at:

`observability-dbx/implementations/dynatrace/pattern-4-webhook-events/dynatrace-relay.tf`

It reuses the same modules already proven here:
- `terraform-aws-modules/security-group/aws` — egress-only 443 SG
- `terraform-aws-modules/lambda/aws` — VPC Lambda from `lambda/dynatrace-relay/`
- `terraform-aws-modules/apigateway-v2/aws` — HTTP API, `POST /ingest`
- `aws_lambda_permission` — allow API GW to invoke

### Variables to add (`variables.tf` in that stack)

```hcl
variable "dynatrace_relay" {
  type = object({
    vpc_id             = string
    private_subnet_ids = list(string)
    tenant_url         = string   # https://<env-id>.live.dynatrace.com
  })
  description = "Networking + tenant config for the Dynatrace events relay."
}

variable "dynatrace_api_token" {
  type        = string
  sensitive   = true
  description = "Dynatrace API token with events.ingest scope."
}

variable "dynatrace_relay_token" {
  type        = string
  sensitive   = true
  description = "Shared secret Databricks must present to call the relay."
}
```

Set the non-secret parts in `commons.auto.tfvars`; inject the two secrets via the
same mechanism the repo already uses for `duocircle_password` /
`duocircle_relay_token` (TFE/CI sensitive vars), **not** in a committed tfvars.

## Step 2 — Add the Lambda source

Create `lambda/dynatrace-relay/lambda_function.py` (handler = `lambda_function.handler`
to match the module convention). Source provided at:

`observability-dbx/implementations/dynatrace/pattern-4-webhook-events/relay_lambda.py`
→ copy it to `lambda/dynatrace-relay/lambda_function.py` in the scops-core stack.

It:
- verifies the shared `RELAY_TOKEN` (rejects calls that don't present it),
- parses the Databricks webhook body defensively,
- builds a Dynatrace `ERROR_EVENT`,
- POSTs to `${DT_ENV_URL}/api/v2/events/ingest` with the `Api-Token` header,
- always returns 200 so Databricks doesn't retry-storm.

Environment variables (wired by the Terraform):
`DT_ENV_URL`, `DT_API_TOKEN`, `RELAY_TOKEN`.

## Step 3 — Deploy

```bash
cd terraform/<env>/<public|private>/<region>/scops-core
terraform plan    # review: SG, Lambda, API GW, permission, 1 output
terraform apply
```

Capture the output `dynatrace_relay_api_endpoint` — the invoke URL. The relay route
is `POST {api_endpoint}/ingest`.

## Step 4 — Register the Databricks notification destination

In the **target workspace** (admin): Settings → Notifications → Notification
destinations → **Add** → type *Webhook*:
- URL: `{api_endpoint}/ingest`
- (If the relay expects the shared secret in a header) add a custom header carrying
  `RELAY_TOKEN`, or embed it as a query param the Lambda checks.

Copy the resulting **destination id** (a UUID like the existing
`5d3a96e1-52d4-4a71-aa87-4bf29d064fff` used for Teams).

> This step is manual/admin — Databricks notification destinations aren't managed by
> the DAB bundle. Do it once per workspace.

## Step 5 — Reference it from the DAB job (`ssw-dbx-idl2-de`)

Add the Dynatrace destination alongside the existing Teams webhook in
`resources/edm_medallion.job.yml`:

```yaml
      webhook_notifications:
        on_failure:
          - id: ${var.webhook_destination_id}            # existing Teams
          - id: ${var.dynatrace_webhook_destination_id}  # NEW: relay -> Dynatrace
```

Declare + set the variable per target (mirroring `webhook_destination_id`):

```yaml
  dynatrace_webhook_destination_id:
    description: "Notification destination id for the Dynatrace events relay."
    default: ""
```

Set the real UUID in each target's `variables:` block (dev/uat/prod) once registered.

## Step 6 — Verify

1. `terraform apply` clean; `curl -XPOST {api_endpoint}/ingest` with the shared token
   and a sample Databricks body → a Dynatrace `ERROR_EVENT` appears.
2. Force a dev job failure → within seconds a Dynatrace problem opens and routes to
   the configured alerting profile.
3. A successful run produces **no** event.

---

## Security notes (match repo conventions)

- **Token never in git or Databricks** — `dynatrace_api_token` is a sensitive tfvar
  living only in TFE/CI and the Lambda env (same as `duocircle_password`).
- **Relay is authenticated** — the `RELAY_TOKEN` shared secret prevents anyone who
  learns the API GW URL from injecting fake events (same as `duocircle_relay_token`).
- **Egress-only SG + private subnets** — the Lambda sits in private subnets and egresses
  via NAT, identical to the DuoCircle relay; no inbound from the internet except via API GW.
- **CloudWatch logs retention** — set to match the repo default (120 days) for audit.

## Rollout order

Do it once in the **workspace that has the most job failures to catch** (likely prod),
validate end-to-end, then replicate the `dynatrace-relay.tf` + destination registration
to the other env/region scops-core stacks. Each region gets its own relay if the
workspaces are in different VPCs.

## How this maps to the existing repo

| Concern | DuoCircle (existing) | Dynatrace relay (new) |
|---------|----------------------|------------------------|
| Terraform file | `duocircle-relay.tf` | `dynatrace-relay.tf` |
| Lambda dir | `lambda/duocircle-relay/` | `lambda/dynatrace-relay/` |
| Route | `POST /send` | `POST /ingest` |
| Secret token | `duocircle_relay_token` | `dynatrace_relay_token` |
| Upstream secret | `duocircle_password` | `dynatrace_api_token` |
| Output | `duocircle_relay_api_endpoint` | `dynatrace_relay_api_endpoint` |

You already run this exact architecture in production — the Dynatrace relay is a
copy with a different destination and payload mapping.
