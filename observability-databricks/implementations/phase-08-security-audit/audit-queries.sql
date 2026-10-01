-- ============================================================================
-- Phase 8 — Security & Audit observability queries
-- Source: ${system_catalog}.access.audit
-- Restrict the resulting dashboard to the security/admin AD group only.
-- ============================================================================

-- ── Failed logins (24h) ─────────────────────────────────────────────────────
SELECT
  event_time,
  user_identity.email        AS actor,
  source_ip_address,
  action_name,
  response.status_code
FROM ${system_catalog}.access.audit
WHERE action_name = 'login'
  AND response.status_code <> 200
  AND event_time >= CURRENT_TIMESTAMP - INTERVAL 24 HOURS
ORDER BY event_time DESC;

-- ── Failed-login spike by actor (for alerting) ──────────────────────────────
SELECT
  user_identity.email AS actor,
  source_ip_address,
  COUNT(*)            AS failed_logins
FROM ${system_catalog}.access.audit
WHERE action_name = 'login'
  AND response.status_code <> 200
  AND event_time >= CURRENT_TIMESTAMP - INTERVAL 1 HOUR
GROUP BY user_identity.email, source_ip_address
HAVING COUNT(*) >= 5
ORDER BY failed_logins DESC;

-- ── Permission grants / revokes (privilege escalation / over-sharing) ────────
SELECT
  event_time,
  user_identity.email AS actor,
  action_name,
  request_params
FROM ${system_catalog}.access.audit
WHERE service_name = 'unityCatalog'
  AND action_name IN ('updatePermissions', 'grantPermission', 'revokePermission')
  AND event_time >= CURRENT_DATE - INTERVAL 7 DAYS
ORDER BY event_time DESC;

-- ── Token / credential creation (long-lived credential sprawl) ──────────────
SELECT
  event_time,
  user_identity.email AS actor,
  action_name,
  source_ip_address
FROM ${system_catalog}.access.audit
WHERE action_name IN ('createToken', 'generateTemporaryTableCredential', 'getTokenPermissionLevels')
  AND event_time >= CURRENT_DATE - INTERVAL 30 DAYS
ORDER BY event_time DESC;

-- ── Service-principal changes (new machine identities) ──────────────────────
SELECT
  event_time,
  user_identity.email AS actor,
  action_name,
  request_params
FROM ${system_catalog}.access.audit
WHERE action_name LIKE '%ServicePrincipal%'
  AND event_time >= CURRENT_DATE - INTERVAL 30 DAYS
ORDER BY event_time DESC;

-- ── Access from new source IPs per actor (possible compromise) ──────────────
WITH baseline AS (
  SELECT user_identity.email AS actor, COLLECT_SET(source_ip_address) AS known_ips
  FROM ${system_catalog}.access.audit
  WHERE event_time BETWEEN CURRENT_DATE - INTERVAL 30 DAYS AND CURRENT_DATE - INTERVAL 1 DAY
  GROUP BY user_identity.email
)
SELECT
  a.event_time,
  a.user_identity.email AS actor,
  a.source_ip_address   AS new_ip,
  a.action_name
FROM ${system_catalog}.access.audit a
LEFT JOIN baseline b ON a.user_identity.email = b.actor
WHERE a.event_time >= CURRENT_DATE
  AND NOT ARRAY_CONTAINS(b.known_ips, a.source_ip_address)
ORDER BY a.event_time DESC;

-- NOTE: field paths (user_identity.email, response.status_code, request_params)
-- follow the current system.access.audit schema; confirm against the workspace.
