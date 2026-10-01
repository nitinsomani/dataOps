# Phase 1 — Job & DLT Pipeline Notifications

**Pillar:** Reliability  ·  **Owner:** Platform  ·  **Effort:** Small  ·  **Repo:** `ssw-dbx-idl2-de`

## Objective

Guarantee that **every** pipeline failure reaches a human — not just failures of the
orchestration job.

## The gap

`resources/edm_medallion.job.yml` already notifies on failure:

```yaml
email_notifications:
  on_failure: ${var.medallion_notification_emails}
webhook_notifications:
  on_failure:
    - id: ${var.webhook_destination_id}
```

But the **18 individual DLT pipelines** (`bronze_edm_ingest_pipeline.yml`,
`silver_*.yml`, `gold_*.yml`) have **no `notifications:` block of their own**. The DAB
doc explicitly states each pipeline "still deploys and runs standalone." So when a
pipeline is triggered ad-hoc (a manual run, a dev test, a partial re-run outside the
orchestration job), a failure is **silent** — nobody is paged.

## Fix

Add a `notifications:` block to each pipeline resource. DLT pipelines support
pipeline-level notifications with these alert types:

- `on-update-failure` — the pipeline update failed
- `on-update-fatal-failure` — failed and will not retry
- `on-flow-failure` — an individual flow (table) failed

Reuse the **same Teams webhook destination** the job already uses
(`${var.webhook_destination_id}`) plus email for the owning group.

### Snippet (add to each `resources/*pipeline*.yml`)

```yaml
      notifications:
        - email_recipients: ${var.pipeline_notification_emails}
          alerts:
            - on-update-failure
            - on-update-fatal-failure
            - on-flow-failure
```

> DLT pipeline `notifications` currently supports **email** recipients natively.
> For Teams/webhook parity, keep the webhook on the orchestration **job** (which
> already has it) and, for standalone pipeline runs, either (a) rely on email, or
> (b) wrap standalone runs in a thin single-task job that carries
> `webhook_notifications.on_failure`. See `implementations/phase-01-notifications/`
> for both variants.

## New variable

Add to `databricks.yml` `variables:`:

```yaml
  pipeline_notification_emails:
    description: "Email recipients for standalone DLT pipeline failures."
    default: ""
```

Set per-target (dev/uat/prod) alongside the existing `medallion_notification_emails`.

## Best practice applied

- **No silent failures** — coverage on every runnable unit, not just the happy-path
  orchestration.
- **Single destination of record** — reuse the existing webhook id so alerts land in
  the same Teams channel operators already watch.
- **Notify on fatal separately** — `on-update-fatal-failure` (no retry left) is the
  one that needs immediate human action vs. a transient `on-update-failure`.

## Verification

- `databricks bundle validate` passes with the new blocks.
- Force a failure in a dev pipeline (e.g. reference a non-existent source) and
  confirm the email/alert fires.

## Ownership & DE involvement

**Platform-owned config**, but the **recipient list** should be agreed with data
engineering (who owns which pipeline). No code logic changes.
