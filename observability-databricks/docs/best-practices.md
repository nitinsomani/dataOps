# Industry Best Practices — and How This Program Maps to Them

This program is deliberately aligned to the **Databricks Well-Architected Framework
(Operational Excellence & Reliability pillars)** and general lakehouse/SRE practice.
This doc records the mapping so reviewers can see the "why" behind each phase.

## Databricks Well-Architected Framework coverage

| WAF principle | How this program addresses it | Phase(s) |
|---------------|-------------------------------|----------|
| Monitor & observe the lakehouse | System-table dashboards for cost, health, perf, audit, lineage | 0, 2, 4, 8, 9 |
| Automate deployments & config | Everything as Terraform / DAB YAML; no click-ops | all |
| Design for failure / alerting | Pipeline + job notifications; threshold + SLO alerts | 1, 5 |
| Manage data quality | DLT expectations + Lakehouse Monitoring | 3 |
| Right-size & control cost | Cost dashboards, policy compliance, table health | 0, 4, 10 |
| Secure by default / audit | Audit-log observability, least-privilege dashboards | 8 |
| Recover from incidents | Archival, lineage impact analysis, canary | 2, 6, 9 |

## SRE practices applied

| Practice | Where |
|----------|-------|
| **RED method** (Rate, Errors, Duration) for pipelines/queries | 2, 4 |
| **USE method** (Utilization, Saturation, Errors) for warehouses/clusters | 4, 7 |
| **SLO + error budgets** with multi-window burn-rate alerting | 5 |
| **Alert on symptoms/impact, not causes** | 1, 5 |
| **Black-box / synthetic monitoring** (canary) | 6 |
| **Three pillars correlated** (metrics/logs/traces via trace_id) | 7 |
| **Blameless retention of telemetry** for forensics | 2 (archival) |

## Lakehouse-specific best practices

| Practice | Where |
|----------|-------|
| **Quarantine bad rows, never drop silently** | 3 |
| **Drift detection** (distribution shift the source sneaks in) | 3 |
| **Small-file compaction** (`OPTIMIZE`) as highest-ROI maintenance | 10 |
| **VACUUM retention respects time-travel/compliance** | 10 |
| **Predictive optimization preferred over manual where available** | 10 |
| **Lineage-driven impact analysis before schema change** | 9 |
| **Own long-term telemetry** (don't rely on vendor retention defaults) | 2, 8 |
| **Interactive-cluster-for-jobs = anti-pattern to detect** | 0 |

## Things intentionally scoped OUT (and why)

| Not included | Why |
|--------------|-----|
| DORA metrics on the DAB deploy pipeline | That's CI/CD observability, not Databricks runtime observability. Add later if wanted. |
| Full PII/data-classification compliance monitoring | Only relevant if OSDU well data has classified fields with a control requirement — no evidence of that yet. Revisit if a control exists. |
| Third-party APM as the primary backend (Datadog/Dynatrace) | System tables cover pillars 1–6 without it; OTel (Phase 7) is the opt-in bridge if an external backend is mandated. |

## Review checklist (per phase PR)

- [ ] Defined as code (Terraform / DAB / SQL), not click-ops.
- [ ] Reuses existing patterns (dashboard module, webhook destination, AD groups).
- [ ] Least-privilege permissions on any sensitive dashboard/alert.
- [ ] System-catalog alias correct for the target workspace.
- [ ] Alert routes to the existing Teams destination, not a new silo.
- [ ] Verification steps in the phase doc pass in dev before promoting.
