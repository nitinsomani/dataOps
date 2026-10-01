# Phase 8 — Security & Audit Observability

**Pillar:** Security  ·  **Owner:** Platform / Security  ·  **Effort:** Medium  ·  **Repo:** `osdu-ssw-central-dbx`

## Objective

See **security events**, not just activity. The existing "User Usage / Active Users"
dashboards track who created/modified tables — useful, but they are *activity*
metrics, not *security* signals. This phase surfaces failed logins, permission
changes, token/service-principal creation, and anomalous access.

## Data source

`${system_catalog}.access.audit` — the Unity Catalog / workspace audit log as a
queryable table. Every action (login, grant, query, job, token op) with actor,
source IP, timestamp, and request params.

## Panels / alerts

| Signal | Why it matters | Query shape |
|--------|----------------|-------------|
| **Failed logins** | brute-force / stale creds | `action_name = 'login' AND response.status_code != 200` |
| **Permission grants/revokes** | privilege escalation, over-sharing | `service_name='unityCatalog' AND action_name IN ('updatePermissions','grantPermission')` |
| **Token / PAT creation** | long-lived credential sprawl | `action_name IN ('createToken','generateTemporaryTableCredential')` |
| **Service-principal changes** | new machine identities | `service_name='accounts' AND action_name LIKE '%ServicePrincipal%'` |
| **Access from new IPs/geos** | compromised account | distinct `source_ip_address` per actor vs baseline |
| **Data exfil signals** | unusual large reads / downloads | large `response` row counts, external-location reads |

SQL: `implementations/phase-08-security-audit/audit-queries.sql`.

## Dashboard + alerts

- A **Security & Audit** Lakeview dashboard (same `databricks_dashboard` pattern),
  restricted to the admin/security AD group only (not the general users group).
- High-severity signals (failed-login spikes, unexpected grant changes) also become
  **SQL alerts** (Phase 5) to the security channel.

## Best practice applied

- **Audit log is the SOC2/compliance backbone** — surfacing it satisfies a standard
  audit-readiness control and shortens incident forensics.
- **Least-privilege on the dashboard itself** — security signals are sensitive;
  restrict view to security/admin groups.
- **Retain beyond the window** — Phase 2's archival job snapshots `access.audit` so
  audit history outlives system-table retention.

## Verification

- Failed-login panel shows real entries after a deliberate bad login in dev.
- A test grant change appears in the permissions panel within the audit latency.

## Ownership & DE involvement

**Platform / Security-owned.** No data-engineering input needed.
