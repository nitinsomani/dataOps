"""
Pattern 4 / Option C — Task-based Dynatrace event (NO relay, NO webhook plumbing).

Add as a trailing task that only runs when something upstream failed:

    - task_key: notify_dynatrace_on_failure
      depends_on: [ { task_key: gold_well }, { task_key: gold_wellbore }, ... ]
      run_if: AT_LEAST_ONE_FAILED
      spark_python_task:
        python_file: ../ops/post_dynatrace_event.py

Posts an ERROR_EVENT straight to the Dynatrace Events API v2. Token from a
Databricks secret scope (server-side control of headers + body, no AWS relay).
"""

from __future__ import annotations

import json
import os
import urllib.request


def _secret(scope: str, key: str) -> str:
    return dbutils.secrets.get(scope=scope, key=key)  # noqa: F821 (runtime-injected)


DT_ENV_URL = "https://<env-id>.live.dynatrace.com"
DT_TOKEN   = _secret("dynatrace", "events-token")   # scope: events.ingest
EVENTS_URL = f"{DT_ENV_URL}/api/v2/events/ingest"


def post_event(job_name: str, run_id: str, workspace: str, state: str = "FAILED") -> int:
    body = {
        "eventType": "ERROR_EVENT",
        "title": f"Databricks job failed: {job_name}",
        "entitySelector": "type(CUSTOM_DEVICE),entityName(databricks-jobs)",
        "properties": {
            "dt.event.description": f"Run {run_id} of {job_name} {state} (workspace {workspace})",
            "job.name": job_name,
            "run.id": run_id,
            "workspace": workspace,
            "result_state": state,
        },
    }
    req = urllib.request.Request(
        EVENTS_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={"Authorization": f"Api-Token {DT_TOKEN}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:  # noqa: S310
        return resp.status


if __name__ == "__main__":
    # Pull real context from job params / task values / Jobs API in production.
    # Databricks exposes these via spark conf / job parameters, e.g.:
    #   job_name  = spark.conf.get("spark.databricks.job.name", "unknown")
    #   run_id    = spark.conf.get("spark.databricks.job.runId", "")
    job_name  = os.environ.get("JOB_NAME", "edm_medallion_orchestration")
    run_id    = os.environ.get("JOB_RUN_ID", "")
    workspace = os.environ.get("WORKSPACE", "")

    status = post_event(job_name, run_id, workspace)
    print(f"dynatrace event ingest status={status}")
