"""
Pattern 3 — Push Databricks job/pipeline metrics into Dynatrace (Metrics API v2).

Run as a trailing task on the orchestration job (Placement A):
    - depends_on: all gold tasks
    - run_if: ALL_DONE          # fire even on partial failure so success=0 is sent

Reads the run outcome and posts line-protocol metrics to:
    POST https://<tenant>/api/v2/metrics/ingest
    Authorization: Api-Token <token with metrics.ingest>

Token comes from a Databricks secret scope — NEVER hardcode.

Requires: requests (preinstalled on DBR) and the job's run context.
"""

from __future__ import annotations

import time
import requests

# --- Databricks runtime helpers (available in a job/notebook task) ------------
# dbutils is injected in the Databricks runtime. In a spark_python_task use the
# task-values / job context to derive outcome; simplified here.

def _secret(scope: str, key: str) -> str:
    return dbutils.secrets.get(scope=scope, key=key)  # noqa: F821 (dbutils is runtime-injected)


DT_ENV_URL = "https://<env-id>.live.dynatrace.com"     # set per env
DT_TOKEN   = _secret("dynatrace", "api-token")          # scope: metrics.ingest
INGEST_URL = f"{DT_ENV_URL}/api/v2/metrics/ingest"

ENV    = "prod"           # parameterise via job params / widgets
REGION = "eu-west-1"


def build_metric_lines(job_name: str, duration_s: float, rows_written: int, success: bool) -> str:
    """Dynatrace metric line protocol. Dimensions MUST be low-cardinality
    (job/env/region) — never run_id or timestamps."""
    ts_ms = int(time.time() * 1000)
    dims = f"job={job_name},env={ENV},region={REGION}"
    return "\n".join([
        f"databricks.job.duration_seconds,{dims} {duration_s:.1f} {ts_ms}",
        f"databricks.job.rows_written,{dims} {int(rows_written)} {ts_ms}",
        f"databricks.job.success,{dims} {1 if success else 0} {ts_ms}",
    ])


def push(payload: str) -> None:
    resp = requests.post(
        INGEST_URL,
        headers={
            "Authorization": f"Api-Token {DT_TOKEN}",
            "Content-Type": "text/plain; charset=utf-8",
        },
        data=payload.encode("utf-8"),
        timeout=15,
    )
    # Dynatrace returns 202 Accepted with an ingest summary.
    resp.raise_for_status()
    print(f"dynatrace ingest: {resp.status_code} {resp.text}")


if __name__ == "__main__":
    # Derive these from the run context / Jobs API / DLT event log in real use.
    job_name     = "silver_wellbore"
    duration_s   = 412.0
    rows_written = 1_543_221
    success      = True

    push(build_metric_lines(job_name, duration_s, rows_written, success))
