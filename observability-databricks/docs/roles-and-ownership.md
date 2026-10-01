# Roles & Ownership (RACI)

Who does what across the 11 phases, and — the question that keeps coming up —
**where a data engineer is actually required** vs. where platform can deliver solo.

## TL;DR

- **8 of 11 phases are platform-only** (0, 1, 2, 4, 5*, 6, 8, 9) — infra, Terraform,
  DAB config, and SQL over system tables. I can build these end-to-end.
- **2 phases need data-engineering domain input** (3, 7) — because they encode
  business truth (quality rules) or require choosing what's worth tracing.
- **1 phase is shared** (10) — platform builds/schedules; DE signs off on per-table
  tuning parameters.

\* Phase 5 is platform except for **nominating the critical pipelines + target times**
for SLOs.

## RACI matrix

| Phase | Platform | Data Engineering | Security | Notes |
|------:|:--------:|:----------------:|:--------:|-------|
| 0 — eu-west-1 dashboards + policy compliance | **R/A** | — | — | Pure infra replication + cost query |
| 1 — Pipeline notifications | **R/A** | C | — | DE consulted on recipient list |
| 2 — Job health + archival | **R/A** | C | — | DE names "critical" pipelines |
| 3 — Data quality (expectations) | C / R(plumbing) | **R/A (rules)** | — | ⚠️ Blocked on DE rule definitions |
| 4 — Query/warehouse performance | **R/A** | I | — | DE may act on slow-query output |
| 5 — Alerts + SLO burn-rate | **R/A** | C (SLO targets) | I | DE nominates SLO targets only |
| 6 — AWS obs + canary | **R/A** | — | C | Flow logs relevant to security |
| 7 — OpenTelemetry | **R/A (infra)** | **R (instrumentation)** | — | ⚠️ Split; backend choice joint |
| 8 — Security & audit | **R** | — | **A** | Security owns acceptance |
| 9 — Data lineage | **R/A** | I | — | DE benefits from impact analysis |
| 10 — Delta table health | **R/A (build+schedule)** | **C/A (tuning params)** | — | DE signs off ZORDER/VACUUM |

R = Responsible, A = Accountable, C = Consulted, I = Informed.

## The two hard dependencies on Data Engineering

### Phase 3 — Data quality rules (hard blocker)
Expectation rules (`@dlt.expect_or_drop(...)`) encode what "valid" means for a well /
wellbore / trajectory record. Only the owner of the transformation code knows these.
Platform provides the patterns, quarantine wiring, monitors, and dashboards — but the
**rules themselves must come from DE**. Generating them blind creates false confidence.

### Phase 7 — Instrumentation points (soft blocker, pairing)
Platform can stand up the OTel/ADOT collector, init scripts, and export pipeline
alone. But **which functions deserve a span, and what attributes to record**, requires
someone who knows the pipeline logic. Best done as a 1–2 hour pairing session per
pipeline, not generated blind.

## What platform can start today without any DE

Phases **0, 1, 2, 4, 6, 8, 9** — and the dashboard/alert scaffolding for **5** and
**10**. That's the bulk of the value, deliverable without blocking on DE availability.

## Suggested working model

1. Platform ships the "no-DE-needed" phases first (0, 1, 2, 4, 9, 8) — fast wins.
2. Schedule **one DE workshop** to (a) nominate critical pipelines + SLO targets
   (Phase 5), (b) draft the first data-quality rules (Phase 3), (c) choose OTel
   instrumentation points and backend (Phase 7).
3. Platform implements the outputs of that workshop.
4. Phase 10 tuning params reviewed with DE before the maintenance job is scheduled.
