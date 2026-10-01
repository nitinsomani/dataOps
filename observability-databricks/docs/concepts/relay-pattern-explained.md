# Understanding Relays — Email, SMTP, DuoCircle, and the Webhook-Relay Pattern

> A from-first-principles explainer. Written because "DuoCircle" and "relay" show up
> in this repo (`terraform/.../scops-core/duocircle-relay.tf`) and the same pattern is
> reused for the Dynatrace integration. No prior knowledge assumed.
>
> **Want the full depth?** After this, read `relay-pattern-deep-dive.md` — it covers the
> networking packets, email deliverability (SPF/DKIM/DMARC), Lambda-in-VPC internals,
> API Gateway details, real payloads, failure modes, cost, and trade-offs.

---

## 1. The core problem: how does an application send a notification *out*?

Your platform sometimes needs to send something to the outside world — an email
("your pipeline failed"), or an event to a SaaS tool (Dynatrace, Teams). That sounds
trivial, but in a locked-down cloud environment it isn't, for three reasons:

1. **The sender's identity must be trusted.** Email providers and APIs reject messages
   from unknown/unverified senders (otherwise everyone would be a spammer). They often
   only accept traffic from a **specific, pre-approved IP address** or with a
   **specific credential/token**.
2. **Your workloads don't have a fixed, trusted IP.** Lambdas, containers, and
   Databricks clusters are ephemeral — they come and go with random private IPs
   (`10.x.x.x`) that mean nothing on the public internet.
3. **You don't want secrets spread everywhere.** The email password / API token that
   authorises sending shouldn't be copied into every app that wants to send a message.

A **relay** solves all three. It's a single, controlled "post office" that every app
hands its outbound message to; the relay is the one component with the trusted
identity, the fixed IP, and the secret.

---

## 2. What "relay" means (the general concept)

> **Relay** = an intermediary that receives a message from A and forwards it to B,
> usually adding something A couldn't provide itself (a trusted identity, a credential,
> a format conversion, a fixed network egress point).

Think of a **mailroom** in an office building. Employees (apps) drop letters in the
mailroom. The mailroom (relay):
- puts the **company's return address** on them (trusted identity),
- has the **franking machine / postage account** (the secret/credential),
- sends everything from **one loading dock** (the fixed IP),
- can **translate** a handwritten note into a formatted letter (payload conversion).

Employees never deal with the post office directly. That's exactly what a software
relay does for email or API notifications.

---

## 3. Email relay / SMTP relay specifically

**SMTP** (Simple Mail Transfer Protocol) is the language email servers speak to send
mail. An **SMTP relay** (a.k.a. email relay) is a server that accepts your outbound
email and delivers it to the recipients' mail servers on your behalf.

Why not just have each app talk SMTP directly to the internet?

- Most corporate/cloud networks **block outbound port 25** (SMTP) to stop compromised
  machines from becoming spam cannons.
- Recipient mail servers **distrust random IPs** — mail from an unknown IP lands in
  spam or is rejected outright (SPF/DKIM/DMARC checks, IP reputation).
- Managing deliverability (bounce handling, retries, reputation) is a whole discipline.

So you use a **hosted email relay service** that specialises in deliverability. You
authenticate to it (username/password or API key), it sends the mail from its
well-reputed infrastructure, and it handles the hard parts.

---

## 4. What DuoCircle is

**DuoCircle** (duocircle.com) is one of those **hosted email delivery / outbound SMTP
relay services** — the same category as SendGrid, Mailgun, Amazon SES, or Postmark.
You give it your message + credentials; it delivers the email reliably from its
reputable mail infrastructure.

In your repo, DuoCircle is how platform apps send **notification emails** (e.g.
failure alerts) to the outside world. The relevant config
(`duocircle-relay.tf`) shows the app-facing side of that:

```hcl
environment_variables = {
  RELAY_TOKEN  = var.duocircle_relay_token   # shared secret: "only our apps may use me"
  DC_API_URL   = var.duocircle_relay.api_url # where DuoCircle listens
  DC_USERNAME  = var.duocircle_relay.username # DuoCircle account
  DC_PASSWORD  = var.duocircle_password       # DuoCircle secret (the postage account)
  DC_FROM      = var.duocircle_relay.from_email
  DC_FROM_NAME = var.duocircle_relay.from_name
}
```

Read that as: *"To send mail, authenticate to DuoCircle at `DC_API_URL` as
`DC_USERNAME`/`DC_PASSWORD`, from address `DC_FROM`."*

---

## 5. The specific twist in your setup: the *allow-listed static IP*

Here's the detail that explains the whole architecture. The Terraform comment says:

> *"Relays app notifications to DuoCircle from within the VPC (**allow-listed NAT
> egress IP**)"*
> *"Run inside the private subnets so egress uses the NAT public IP."*

What's happening:

- DuoCircle (like many providers) is configured to **only accept mail from a known,
  fixed public IP address** — an "allow-list" (a.k.a. IP whitelist). This is a security
  control: even with the password, a request from an unexpected IP is refused.
- But your compute has **no fixed public IP** — a Lambda's outbound traffic, left to
  itself, can leave from various addresses.
- **Fix:** put the relay Lambda in **private subnets** with **no direct internet
  access**, so all its outbound traffic is forced through the VPC's **NAT gateway**,
  which has **one stable public IP** (an Elastic IP). That NAT IP is the one address
  you register on DuoCircle's allow-list.

So the network path guarantees *every* email leaves from the one IP DuoCircle trusts:

```
Lambda (private subnet, 10.x.x.x)
   → NAT Gateway (one fixed Elastic IP, e.g. 52.1.2.3)   ← this IP is allow-listed at DuoCircle
      → Internet → DuoCircle → recipient inboxes
```

This is why the relay is a **VPC Lambda in private subnets**, not a simple internet
Lambda — the whole point is to pin egress to the trusted IP.

---

## 6. Why an API Gateway sits in front (the app-facing door)

Apps need a way to *reach* the relay. That's the **HTTP API Gateway** — it gives the
relay a single URL apps can POST to:

```
POST https://<api-id>.execute-api.<region>.amazonaws.com/send
```

- API Gateway is the **front door**; the Lambda is the **worker** behind it.
- The `RELAY_TOKEN` shared secret ensures only *your* apps (who know the token) can use
  the relay — otherwise anyone who found the URL could send mail as your company.

Full app-facing + provider-facing flow:

```
Your app / notification
   │  POST /send   (+ RELAY_TOKEN, + message body)
   ▼
API Gateway  ──►  Relay Lambda (private subnet)
                     │  authenticates to DuoCircle (DC_USERNAME/DC_PASSWORD)
                     │  sends from DC_FROM
                     ▼
                  NAT Gateway (fixed allow-listed IP)
                     ▼
                  DuoCircle  ──►  recipient email inboxes
```

---

## 7. Walking through `duocircle-relay.tf` piece by piece

The file has four parts — each maps to a concept above:

| Terraform block | What it is | Concept |
|-----------------|-----------|---------|
| `module "..._security_group"` — egress-only 443 | firewall: Lambda may only make **outbound HTTPS** | least privilege; no inbound from internet |
| `module "..._lambda"` — VPC Lambda from `lambda/duocircle-relay` | the **worker** that talks to DuoCircle | the relay itself |
| `vpc_subnet_ids = ...private_subnet_ids` | run in **private subnets** | forces egress through NAT (fixed IP) |
| `module "..._apigw"` — HTTP API, `POST /send` | the **front door** apps call | app-facing entry point |
| `aws_lambda_permission` | lets API Gateway invoke the Lambda | plumbing/authorisation |
| `output "..._api_endpoint"` | the URL apps POST to | how apps find the relay |

Nothing exotic — it's the mailroom, wired up in AWS.

---

## 8. The generalisation: this is the "webhook-relay pattern"

Here's the payoff. **Email is just one kind of outbound message.** The *same* mailroom
pattern works for **any** outbound integration where you need a trusted identity, a
fixed egress IP, a held-back secret, or a payload conversion.

That's exactly why the **Dynatrace** integration (Pattern 4, see
`../dynatrace/pattern-4-implementation-osdu-ssw-central-dbx.md`) reuses this identical
shape — only the destination and the payload mapping change:

| Concern | DuoCircle relay (email) | Dynatrace relay (events) |
|---------|-------------------------|---------------------------|
| Front door | API Gateway `POST /send` | API Gateway `POST /ingest` |
| Worker | VPC Lambda | VPC Lambda |
| Held-back secret | DuoCircle password | Dynatrace API token |
| Caller auth | `duocircle_relay_token` | `dynatrace_relay_token` |
| Payload conversion | app note → email | Databricks webhook JSON → Dynatrace event JSON |
| Destination | DuoCircle email API | Dynatrace Events API v2 |
| Egress | NAT fixed IP → DuoCircle | NAT → Dynatrace tenant |

So when the earlier docs say *"the Dynatrace relay is a copy of the DuoCircle relay with
a different destination"* — this is what that means. You already run this pattern in
production for email; adding one for Dynatrace is low-risk because it's the same
well-understood machinery.

---

## 9. When do you need a relay (and when not)?

**Use a relay when any of these are true:**
- The destination **allow-lists a fixed IP** and your compute has none.
- You must **not embed the destination's secret** in many apps.
- The destination needs a **different payload/format** than your source emits.
- You want **one auditable choke point** for all outbound traffic of a kind.

**You don't need a relay when:**
- The destination accepts calls from anywhere with a token and your app can safely hold
  that token (then just call it directly).
- There's no IP allow-list, no payload mismatch, and no secret-sprawl concern.

(For Databricks specifically, webhook notifications *force* a relay for Dynatrace
because Databricks can't add the `Authorization` header or reshape the body itself —
so the relay does it.)

---

## 10. Glossary

| Term | Meaning |
|------|---------|
| **Relay** | intermediary that receives a message and forwards it, adding identity/credential/format/egress |
| **SMTP** | the protocol email servers use to send mail |
| **SMTP / email relay** | a service that delivers your outbound email on your behalf |
| **DuoCircle** | a hosted email-delivery / SMTP-relay provider (like SendGrid/SES) |
| **Allow-list (whitelist)** | a set of pre-approved IPs/identities the destination will accept |
| **NAT gateway** | AWS component giving private-subnet resources a **single fixed public IP** for outbound traffic |
| **Elastic IP** | a static public IP in AWS (what the NAT uses) |
| **Private subnet** | a subnet with no direct internet route; egress goes via NAT |
| **API Gateway** | AWS front-door service that exposes an HTTP URL routing to a Lambda |
| **Lambda** | AWS serverless function — runs code without managing servers |
| **Webhook** | an HTTP callback: system A POSTs to a URL when an event happens |
| **Shared secret / relay token** | a value the caller must present so only trusted apps can use the relay |
| **Payload mapping** | converting the incoming message shape into the shape the destination expects |

---

## 11. One-paragraph summary

DuoCircle is a hosted email-delivery service. Your repo can't email it directly from
random ephemeral compute because DuoCircle only trusts one fixed IP, so you run a small
**relay** — a Lambda in a private subnet (egress pinned to the NAT's stable IP) behind
an API Gateway — that holds the DuoCircle credential, sends from the trusted IP, and is
itself protected by a shared token. That "front-door API Gateway → worker Lambda →
trusted egress → external provider" shape is a **reusable relay pattern**, and the
Dynatrace failure-notification integration is the exact same pattern pointed at a
different destination.
