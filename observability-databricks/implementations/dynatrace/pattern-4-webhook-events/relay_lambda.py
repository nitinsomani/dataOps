"""
Pattern 4 / Option B — Relay: Databricks webhook  ->  Dynatrace Events API v2.

Deploy as an AWS Lambda behind API Gateway. Databricks posts its fixed webhook
payload to the API GW URL; this relay:
  1. parses the Databricks notification body,
  2. maps it into the Dynatrace event schema,
  3. injects the Dynatrace token (kept server-side, NOT in Databricks),
  4. POSTs to /api/v2/events/ingest.

Env vars (from Lambda config, wired by dynatrace-relay.tf):
  DT_ENV_URL   = https://<env-id>.live.dynatrace.com
  DT_API_TOKEN = dt0c01...   (scope: events.ingest)
  RELAY_TOKEN  = shared secret Databricks must present (rejects unauthenticated calls)

Databricks webhook payload shape varies by event; this handles the common fields
defensively. Log + 200 back to Databricks even on partial parse so Databricks
doesn't retry-storm.
"""

import json
import os
import urllib.request


DT_ENV_URL = os.environ["DT_ENV_URL"].rstrip("/")
DT_API_TOKEN = os.environ["DT_API_TOKEN"]
RELAY_TOKEN = os.environ.get("RELAY_TOKEN", "")
EVENTS_URL = f"{DT_ENV_URL}/api/v2/events/ingest"


def _authorised(event) -> bool:
    """Reject calls that don't present the shared relay secret.
    Databricks can carry it as a custom header (X-Relay-Token) or query param."""
    if not RELAY_TOKEN:
        return True  # no secret configured -> open (dev only)
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    qs = event.get("queryStringParameters") or {}
    return headers.get("x-relay-token") == RELAY_TOKEN or qs.get("relay_token") == RELAY_TOKEN


def _post_dynatrace_event(title: str, description: str, props: dict) -> int:
    body = {
        "eventType": "ERROR_EVENT",
        "title": title,
        # Attach to a custom device representing the Databricks jobs fleet so
        # events group sensibly. Create the device or adjust the selector.
        "entitySelector": "type(CUSTOM_DEVICE),entityName(databricks-jobs)",
        "properties": {"dt.event.description": description, **props},
    }
    req = urllib.request.Request(
        EVENTS_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Api-Token {DT_API_TOKEN}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:  # noqa: S310 (trusted host)
        return resp.status


def handler(event, _context):
    # Reject unauthenticated callers (shared relay secret).
    if not _authorised(event):
        print("rejected: missing/invalid relay token")
        return {"statusCode": 401, "body": json.dumps({"ok": False})}

    # API Gateway proxy integration: the Databricks body is in event["body"].
    try:
        payload = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        payload = {}

    # Databricks webhook fields (defensive — names vary by notification type).
    job_name = (
        payload.get("job", {}).get("name")
        or payload.get("job_name")
        or "unknown-job"
    )
    run_id = str(payload.get("run", {}).get("run_id") or payload.get("run_id") or "")
    workspace = payload.get("workspace_id") or payload.get("workspace") or ""
    state = (
        payload.get("run", {}).get("state", {}).get("result_state")
        or payload.get("result_state")
        or "FAILED"
    )

    title = f"Databricks job failed: {job_name}"
    desc = f"Run {run_id} of {job_name} {state} (workspace {workspace})"
    props = {
        "job.name": job_name,
        "run.id": run_id,
        "workspace": str(workspace),
        "result_state": state,
    }

    try:
        status = _post_dynatrace_event(title, desc, props)
        print(f"dynatrace event ingest status={status} job={job_name} run={run_id}")
    except Exception as exc:  # don't fail the webhook; log for investigation
        print(f"ERROR posting to Dynatrace: {exc}")

    # Always 200 so Databricks doesn't retry-storm.
    return {"statusCode": 200, "body": json.dumps({"ok": True})}
