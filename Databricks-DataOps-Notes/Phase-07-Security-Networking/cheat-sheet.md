# Phase 7: Security, Networking & Access Control — Cheat Sheet

---

## Identity Types

```
Human user       → SSO via IdP (Entra ID/Okta), SCIM-synced groups
Service Principal → non-human identity for automation (CI/CD, Jobs) — PREFERRED
PAT               → user-scoped token, set expiration, avoid in production automation
OAuth U2M/M2M     → modern token flow replacing long-lived PATs
```

## Secrets

```bash
databricks secrets create-scope <scope>
databricks secrets put-secret <scope> <key>
databricks secrets put-acl <scope> <principal> <permission>
```
```python
dbutils.secrets.get(scope="s", key="k")   # auto-redacted in notebook output
```

## Cluster Access Modes

| Mode | UC Enforcement | Use case |
|------|-----------------|----------|
| Single User | Full | Dedicated user/service principal workloads |
| Shared | Full, per-user isolation | Multi-user interactive clusters |
| No Isolation Shared (legacy) | Weak | Avoid for governed data |

## Network Security Layers

```
Default (Databricks-managed VPC/VNet)
  → VPC/VNet injection (customer-managed network)
    → No Public IP (NPIP) on cluster nodes
      → PrivateLink / Private Endpoints (fully private control<->data plane & user<->workspace)
        → IP Access Lists (allow-list source IPs to workspace)
```

## Encryption

```
At rest    → cloud default (SSE) or Customer-Managed Keys (CMK)
In transit → TLS enforced everywhere
Enterprise → Compliance Security Profile (FIPS, HIPAA/PCI/FedRAMP hardening)
```

## Legacy vs Modern Storage Access

| Legacy | Modern |
|--------|--------|
| Instance profile (IAM role on cluster) | Storage Credential + External Location (UC) |
| Access tied to compute | Access tied to data, auditable per-principal |

## Top Misconfigurations to Flag

```
[ ] Broad instance profiles instead of scoped UC storage credentials
[ ] Hardcoded secrets in notebooks/Git instead of secret scopes
[ ] No IP access list on workspace + public IPs on cluster nodes
[ ] "No Isolation Shared" clusters used for governed data
[ ] Long-lived PATs in production CI/CD instead of service principals
```
