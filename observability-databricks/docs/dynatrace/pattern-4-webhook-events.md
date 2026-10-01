# Pattern 4 — Databricks Webhook → Dynatrace Events (Problems)

**Direction:** Databricks **pushes on failure** · **Serverless-safe:** ✅ · **Effort:** Low–Medium
**What it gives you:** a job/pipeline failure becomes a **Dynatrace event/problem**
within seconds — the *instant paging* layer that complements the richer-but-slower
Patterns 2 and 3.

---

## 1. Concept

Databricks jobs support `webhook_notifications` that fire on `on_start` / `on_success`
/ `on_failure` / `on_duration_warning`. Point the `on_failure` webhook at Dynatrace's
**Events API v2** so a failure raises a Dynatrace custom event (which can open a
problem and trigger alerting).

```
Databricks job run FAILS
   │  webhook_notifications.on_failure
   ▼
HTTPS POST  (Databricks-defined JSON payload)
   │
   ├── Option A: direct → Dynatrace Events API v2         (if payload/headers accepted)
   │            POST https://<tenant>/api/v2/events/ingest
   │            Authorization: Api-Token dt0c01.XXXX  (scope: events.ingest)
   │
   └── Option B: → thin relay (Lambda/API GW) → Events API v2
                (transforms Databricks payload → Dynatrace event schema, injects token)
   ▼
Dynatrace event/problem → alerting profile → Teams / email / ServiceNow / on-call
```

## 2. The payload problem (why a relay is usually needed)

Databricks webhook notifications send a **fixed, Databricks-defined JSON body** and
you can register only the destination URL (managed in workspace admin → Notification
destinations). You **cannot** add the `Authorization: Api-Token …` header or reshape
the body to Dynatrace's event schema from the Databricks side.

Dynatrace Events API v2 expects a specific JSON shape and an `Api-Token` header. So in
most real setups you insert a **thin relay** between them:

- **Option B (recommended): relay** — a tiny AWS **Lambda behind API Gateway** (or an
  existing internal webhook proxy). Databricks posts to the relay URL; the relay adds
  the Dynatrace token, maps fields (job name, run id, state, workspace) into the
  Dynatrace event schema, and forwards to `/api/v2/events/ingest`. This also lets you
  keep the Dynatrace token server-side (not in Databricks).
- **Option A (direct)** — only viable if you use a Dynatrace ingest path that accepts
  the token in the URL/query or a generic webhook integration that tolerates the
  Databricks body. Simpler but less robust; most orgs go with the relay.

> There's also a **task-based** alternative that avoids webhooks entirely: a trailing
> job task with `run_if: AT_LEAST_ONE_FAILED` that runs a script POSTing directly to
> the Events API (token from a secret scope). This gives you full control of headers
> and body without a relay — see Option C below.

## 3. Dynatrace Events API v2 payload shape

```json
POST https://<tenant>/api/v2/events/ingest
Authorization: Api-Token dt0c01.XXXXXXXX        // scope: events.ingest
Content-Type: application/json

{
  "eventType": "ERROR_EVENT",
  "title": "Databricks job failed: silver_wellbore",
  "entitySelector": "type(CUSTOM_DEVICE),entityName(databricks-jobs)",
  "properties": {
    "dt.event.description": "Run 12345 of silver_wellbore FAILED in prod/eu-west-1",
    "job.name": "silver_wellbore",
    "run.id": "12345",
    "workspace": "prj5642893-...-eu-west-1-prd",
    "result_state": "FAILED"
  }
}
```

`eventType` options that matter: `ERROR_EVENT` (default problem-worthy),
`AVAILABILITY_EVENT`, `CUSTOM_INFO`. Use `ERROR_EVENT` for failures so Davis can open
a problem; attach via `entitySelector` to a custom device representing "Databricks
jobs" so events group sensibly.

## 4. Three implementation options

| Option | Databricks side | Middle | Token lives | Effort |
|-------:|-----------------|--------|-------------|--------|
| **A — direct webhook** | register Dynatrace URL as notification destination | none | in URL (weak) | Low |
| **B — relay (recommended)** | register **relay** URL as notification destination | Lambda/API GW transforms + auth | in Lambda env/secret | Medium |
| **C — task-based POST** | trailing task, `run_if: AT_LEAST_ONE_FAILED`, script POSTs to Events API | none | Databricks secret scope | Low–Medium |

- **Option B** is the most robust and keeps the Dynatrace token off Databricks.
- **Option C** is great when you want zero extra AWS infra and full payload control —
  it reuses the same secret-scope + POST approach as Pattern 3.

## 5. Prerequisites

- Dynatrace API token with **`events.ingest`** scope.
- Databricks **notification destination** registered (Option A/B) — workspace admin
  setting — OR a secret scope with the token (Option C).
- For Option B: a deployable relay (Lambda + API GW) reachable from Databricks egress.
- Tenant URL.

## 6. Step-by-step (Option B — relay)

1. Create Dynatrace token (`events.ingest`); store in the relay's secret/env (e.g.
   AWS Secrets Manager).
2. Deploy the relay Lambda (transform + forward) behind API Gateway; note its URL.
   Code: `implementations/dynatrace/pattern-4-webhook-events/relay_lambda.py`.
3. Register the relay URL as a Databricks **notification destination** (admin console).
4. Reference that destination on the job:
   ```yaml
   webhook_notifications:
     on_failure:
       - id: ${var.dynatrace_webhook_destination_id}
   ```
   (Mirror how `edm_medallion.job.yml` already uses `webhook_destination_id`.)
5. Force a dev failure → confirm a Dynatrace event/problem appears and alerts.

## 7. Step-by-step (Option C — task-based, no relay)

1. Create Dynatrace token (`events.ingest`); store in secret scope `dynatrace/events-token`.
2. Add a trailing task to the job:
   ```yaml
   - task_key: notify_dynatrace_on_failure
     depends_on: [ { task_key: gold_well }, ... ]
     run_if: AT_LEAST_ONE_FAILED
     spark_python_task:
       python_file: ../ops/post_dynatrace_event.py
   ```
3. Script reads the run context + token, POSTs an `ERROR_EVENT` to
   `/api/v2/events/ingest`. Code:
   `implementations/dynatrace/pattern-4-webhook-events/post_dynatrace_event.py`.

## 8. Verification

- Deliberately fail a dev run → a Dynatrace `ERROR_EVENT` appears within seconds and
  (if configured) opens a problem routed to the alerting profile.
- Successful runs produce **no** event (don't alert on success).

## 9. Pros / cons / gotchas

**Pros**
- Near-instant — the paging layer; seconds, not a poll interval.
- Config-light on the Databricks side (Option A/C).
- Integrates failures into Dynatrace's problem/alerting/on-call workflow.

**Cons / gotchas**
- **Payload/header mismatch** — raw Databricks webhook body ≠ Dynatrace event schema;
  Option A alone often isn't enough, hence the relay (B) or task-POST (C).
- **Same blind spot as all push** — if the run dies so hard the notification/task
  never fires, only Pattern 2 (external poll) catches it.
- **Token placement** — Option A leaks token into a URL; prefer B (server-side) or C
  (secret scope).
- **De-dup/flap** — set a sensible alerting profile so a retrying job doesn't spam
  problems; consider only firing on `on-update-fatal-failure`-equivalent (no retries
  left).
- **Notification destinations are workspace-admin-managed** — you need admin to
  register the relay/Dynatrace URL once per workspace.
