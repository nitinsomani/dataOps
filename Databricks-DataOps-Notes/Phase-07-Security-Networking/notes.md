# Phase 7: Security, Networking & Access Control — Detailed Notes

> **Goal**: Understand how Databricks secures the platform end-to-end — identity, secrets, network isolation, and encryption. Draws directly on networking fundamentals (VPC/VNet, PrivateLink) from the companion networking notes.

---

## 1. Identity & Authentication

- **SSO / Identity Provider integration**: Databricks integrates with Entra ID (Azure AD), Okta, Ping, etc. via SCIM for automated user/group provisioning — users and groups are synced from the IdP rather than manually managed in Databricks.
- **Service Principals**: non-human identities used for automation (CI/CD pipelines, Jobs running unattended, Terraform). Always prefer service principals over personal access tokens for production automation — avoids automation breaking when an employee leaves or rotates their own token.
- **Personal Access Tokens (PATs)**: user-scoped tokens for API/CLI access — should have expiration dates set and be rotated regularly; avoid embedding in code (use secrets).
- **OAuth (U2M / M2M)**: modern token flows — User-to-Machine (interactive login) and Machine-to-Machine (service principal client-credentials flow) — increasingly replacing long-lived PATs for API auth.

---

## 2. Secrets Management

```python
dbutils.secrets.get(scope="prod-scope", key="db-password")
```

```bash
databricks secrets create-scope prod-scope
databricks secrets put-secret prod-scope db-password
```

- **Secret scopes**: backed either by Databricks-managed storage or an external **Azure Key Vault** / AWS Secrets Manager-backed scope.
- Secrets are **redacted in notebook output/logs automatically** — printing a secret value shows `[REDACTED]` instead of the actual value, preventing accidental leakage.
- Access to secret scopes is itself governed by ACLs (`databricks secrets put-acl`) — not every user/cluster should have access to every scope.
- **Never hardcode credentials** in notebooks/code — always reference via `dbutils.secrets` or environment-injected secrets from your CI/CD secret store.

---

## 3. Cluster / Compute Access Control

- **Cluster policies**: admin-defined templates that constrain what configurations users can choose when creating clusters (instance types, max workers, allowed DBR versions, tags) — prevents cost overruns and enforces security baselines (e.g., forcing encryption, disallowing unrestricted internet egress).
- **Access mode**:
  - **Single User**: cluster usable by one user/service principal — required for some Unity Catalog features and highest isolation.
  - **Shared**: multiple users can attach, with per-user process isolation and full UC enforcement (row filters, column masks apply correctly per user).
  - Legacy "No isolation shared" mode is discouraged (weaker UC enforcement guarantees).
- **Table ACLs vs cluster-level access**: Unity Catalog governs at the data layer, independent of which cluster you use — this is why access mode matters (older modes could bypass fine-grained enforcement).

---

## 4. Network Security — VPC/VNet Injection

Recall from the networking notes (Phase 8 there): Databricks' Data Plane runs inside your cloud account. By default, Databricks creates and manages this network for you. For stricter environments:

- **VPC/VNet injection (Customer-managed VPC)**: deploy the Data Plane into a VPC/VNet **you control**, allowing you to apply your own security groups/NSGs, route tables, and peering/Transit Gateway connections to reach on-prem or other VPCs.
- **No Public IP (NPIP)**: worker/driver nodes get no public IPs, forcing all traffic through your controlled network path (NAT gateway, firewall) — a common security/compliance requirement.
- **PrivateLink / Private Endpoints**: keep both the control-plane-to-data-plane traffic AND user-to-workspace traffic entirely on private network paths (no traversal over the public internet), critical for regulated industries.
- **IP Access Lists**: restrict which source IPs can reach the workspace UI/API at all (allow-list corporate IP ranges/VPN egress only).

```
User → PrivateLink/VPN → Workspace (Control Plane)
                              │
                              ▼ (private connectivity)
                        Data Plane (your VPC/VNet)
                              │
                              ▼
                   Your Storage (S3/ADLS) via VPC Endpoint / Private Endpoint
```

---

## 5. Encryption

- **Encryption at rest**: cloud-provider default (SSE-S3/SSE-KMS on AWS, Storage Service Encryption on Azure) for underlying data; Databricks supports **customer-managed keys (CMK)** for additional control over the encryption key lifecycle (for both the managed storage/DBFS root and, in Enterprise tier, for the control plane's own storage of notebooks/queries).
- **Encryption in transit**: TLS enforced between client-workspace and internally between control plane/data plane components.
- **Enterprise security profile / Compliance security profile**: adds enhanced hardening (e.g., FIPS-compliant crypto) for regulated workloads (HIPAA, PCI, FedRAMP).

---

## 6. IAM Roles & Instance Profiles (Legacy) vs Storage Credentials (Modern)

- **Legacy**: clusters were launched with an AWS **instance profile** (IAM role) granting the cluster's compute broad access to specific S3 buckets — access control tied to *compute*, coarse-grained, hard to audit per-user.
- **Modern (Unity Catalog)**: **Storage Credentials** + **External Locations** tie access to the *data* itself via UC grants, independent of which cluster is used, and are fully auditable per-principal. New deployments should default to this model; instance profiles remain for legacy/edge cases only.

---

## 7. Compliance & Governance Overlap

- Audit logs (`system.access.audit`, or exported to CloudTrail/Azure Monitor) provide the evidence trail for SOC2/HIPAA/PCI audits.
- **Data residency**: choose workspace region carefully — data plane compute and storage should stay in the required geography; metastores are region-scoped.
- **Compliance Security Profile**: opt-in workspace setting enabling additional hardening controls required for regulated workloads.

---

## 8. Common Security Misconfigurations (What Interviewers Probe For)

- Broad instance profiles granting cluster-wide S3 access instead of governed UC storage credentials.
- Secrets hardcoded in notebooks or checked into Git (Repos) instead of secret scopes.
- All-purpose clusters left with public IPs and no IP access list restricting workspace access.
- Using "No Isolation Shared" cluster access mode where fine-grained UC enforcement is actually required.
- Personal access tokens without expiration used in production CI/CD instead of service principals with OAuth.

---

## 9. Key Takeaways for DataOps

- Security is layered: **identity (who) → network (where) → compute/cluster policy (how) → data governance/UC (what)** — a DataOps engineer needs literacy across all four layers, not just the data layer.
- Prefer **service principals + OAuth** over personal tokens for all automation.
- Prefer **Unity Catalog Storage Credentials** over legacy instance profiles for all new data access patterns.
- Networking concepts from the companion networking notes (VPC, PrivateLink, NAT, security groups) directly apply to securing the Databricks Data Plane — this is a natural intersection point between the two skill sets.
