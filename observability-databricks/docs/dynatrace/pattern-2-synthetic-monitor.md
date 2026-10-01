# Pattern 2 — Dynatrace Synthetic Monitor → Databricks Jobs REST API

**Direction:** Dynatrace **pulls** (polls) · **Serverless-safe:** ✅ · **Effort:** Low
**What it gives you:** an independent, black-box "is the job's last run healthy?"
uptime/SLA check that works even when Databricks itself can't push anything out.

---

## 1. Concept — what "health-check endpoint for a job" really means here

A batch job has no `/healthz`. But the **Databricks Jobs REST API** *is* effectively a
health endpoint: it can tell you the state of the most recent run of any job. A
Dynatrace **HTTP synthetic monitor** polls that API on a schedule, parses the JSON,
and asserts "the last run SUCCEEDED and was recent." If the assertion fails (run
failed, or no run in the expected window = a missed schedule), Dynatrace raises a
synthetic availability problem.

```
Dynatrace Synthetic (every 5–15 min, from a chosen location)
        │  HTTPS GET /api/2.1/jobs/runs/list?job_id=...&limit=1
        ▼
Databricks Jobs REST API 2.1  ──►  { runs: [ { state: { result_state, life_cycle_state }, start_time, end_time } ] }
        ▲
        │  Dynatrace validates:  result_state == "SUCCESS"  AND  end_time within freshness window
        ▼
  pass → available        fail → Dynatrace problem → alerting profile → Teams/email/etc.
```

## 2. Which Databricks API to poll

| Endpoint | Use |
|----------|-----|
| `GET /api/2.1/jobs/runs/list?job_id={id}&limit=1` | latest run summary for one job (recommended) |
| `GET /api/2.1/jobs/runs/get?run_id={id}` | full detail of a specific run |
| `GET /api/2.1/jobs/list` | enumerate jobs (to discover job_ids once) |

Run state fields to assert on:
- `state.life_cycle_state` ∈ `TERMINATED | INTERNAL_ERROR | RUNNING | PENDING | …`
- `state.result_state` ∈ `SUCCESS | FAILED | TIMEDOUT | CANCELED` (only meaningful
  once `life_cycle_state = TERMINATED`)
- `start_time` / `end_time` (epoch ms) — for the **freshness** check (missed schedule).

## 3. Two health assertions you want

1. **Last run succeeded:** `result_state == "SUCCESS"`.
2. **Schedule adherence (freshness):** `now - end_time < expected_interval + grace`.
   This catches a job that silently *stopped running* — a pure "did it succeed" check
   would look green forever if the scheduler never fired.

## 4. Prerequisites

- Dynatrace tenant + a synthetic-capable location (public or private ActiveGate
  synthetic location — private is usually required to reach a workspace behind
  networking controls).
- A **read-only Databricks credential**:
  - Preferred: a **service principal** with a scoped OAuth token, `CAN_VIEW` on the
    target jobs only.
  - Simpler: a **PAT** from a low-privilege service account.
  - Store it in the **Dynatrace credential vault**, reference it from the monitor —
    never inline in the request.
- Network path: Dynatrace synthetic location must reach the workspace host
  `https://<workspace>.cloud.databricks.com`. For private workspaces use a **private
  synthetic location** on an ActiveGate inside/peered to the VPC.

## 5. Implementation options (choose one)

### Option A — HTTP monitor (single job, simplest)
A single-request HTTP monitor with a validation rule on the JSON. Good for a few
critical jobs. Configure via the Dynatrace **Terraform provider**
(`dynatrace-oss/dynatrace`) so it's IaC, consistent with this repo's approach.
See `implementations/dynatrace/pattern-2-synthetic/http_monitor.tf`.

### Option B — Browser/HTTP multi-step monitor (many jobs)
If you want one monitor to check several jobs, use a multi-request HTTP monitor with
a step per job. More moving parts; only worth it if you're checking a handful of jobs
from one monitor.

### Option C — Monitoring-as-Code (Monaco)
If your org standardises on Dynatrace Monaco, define the monitor as a Monaco config
instead of Terraform. Same logic; different tooling. Example JSON in
`implementations/dynatrace/pattern-2-synthetic/monaco_http_monitor.json`.

## 6. Step-by-step (Option A, Terraform)

1. **Discover the job_id** once: `GET /api/2.1/jobs/list` (or copy from the Jobs UI
   URL).
2. **Create the Databricks read-only credential**, store it in the Dynatrace
   credential vault; note its credential-vault ID.
3. **Author the HTTP monitor** (Terraform) — set:
   - URL: `https://<workspace>/api/2.1/jobs/runs/list?job_id=<id>&limit=1`
   - Header: `Authorization: Bearer {{credentialVault:…}}`
   - Frequency: match roughly half the job's schedule interval (e.g. hourly job →
     30-min monitor) so a miss is caught within one interval.
   - Validation: HTTP 200 **and** body matches `result_state":"SUCCESS`.
   - (Optional) a JS/validation rule for the freshness window on `end_time`.
4. **Attach an alerting profile** routing synthetic availability problems to the
   right channel (Teams/email/ServiceNow).
5. **Apply** via Terraform; verify the monitor shows "Available" on a healthy job.

## 7. Verification

- Healthy job → monitor green, `result_state":"SUCCESS` matched.
- Force a dev job to fail → within one poll interval the monitor flips to a Dynatrace
  availability problem and alerts.
- Pause the job schedule (simulate a missed run) → freshness assertion flips it red
  even though the last recorded run "succeeded."

## 8. Pros / cons / gotchas

**Pros**
- Zero change to Databricks compute — works on serverless.
- Truly independent watchdog: detects workspace/auth/scheduler failure that a
  push-based approach (Patterns 3/4) would miss because Databricks couldn't push.
- Native Dynatrace availability SLOs on the monitor.

**Cons / gotchas**
- **Poll latency** — you learn about a failure at the next poll, not instantly (pair
  with Pattern 4 for instant paging).
- **Networking** — private workspaces need a private synthetic location/ActiveGate;
  this is the most common blocker.
- **Token management** — the Databricks credential must be rotated; prefer a service
  principal over a personal PAT.
- **Rate/limits** — keep the poll interval sane; don't hammer the Jobs API every 30s.
- **Freshness logic** — a plain "succeeded" check is not enough; always add the
  end_time recency assertion or a stopped scheduler looks healthy forever.
