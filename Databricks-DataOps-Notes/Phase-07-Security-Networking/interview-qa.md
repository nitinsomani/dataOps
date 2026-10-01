# Phase 7: Security, Networking & Access Control — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ How should credentials/secrets be managed in Databricks pipelines, and what's wrong with hardcoding them in a notebook?

**Answer:**
Secrets should be stored in a **secret scope** — either Databricks-managed or backed by an external vault like Azure Key Vault/AWS Secrets Manager — and referenced at runtime via `dbutils.secrets.get(scope, key)`. Databricks automatically redacts secret values in notebook output/logs (`[REDACTED]`), preventing accidental leakage through printed output or job logs. Hardcoding credentials in a notebook is risky because notebook source is stored (and often version-controlled via Repos), meaning the credential becomes visible to anyone with read access to that notebook or its Git history, and it can't be centrally rotated/audited/revoked the way a secret scope entry can.

---

## Q2. ⭐ Explain VPC/VNet injection and why an enterprise might require it over Databricks' default managed networking.

**Answer:**
By default, Databricks provisions and manages the network for the Data Plane (the cloud account where clusters run) on the customer's behalf. **VPC/VNet injection** (customer-managed network) instead deploys the Data Plane into a VPC/VNet the customer explicitly controls, so they can apply their own security groups/NSGs, custom route tables, and connect it to existing infrastructure via peering or Transit Gateway — necessary when an organization has centralized network security policies, needs to reach on-prem systems, or must satisfy compliance requirements mandating explicit control over all network paths touching regulated data.

---

## Q3. What is PrivateLink and when would you use it with Databricks?

**Answer:**
PrivateLink (and equivalent Azure Private Endpoints) allows both control-plane-to-data-plane traffic and user-to-workspace traffic to travel over private cloud network infrastructure instead of the public internet. This is required in regulated environments (finance, healthcare, government) where any traffic touching sensitive data crossing the public internet — even encrypted — is disallowed by policy, or where the organization wants to eliminate public internet exposure of the workspace entirely, combined with No Public IP (NPIP) cluster configuration and IP access lists as complementary controls.

---

## Q4. ⭐ What's the difference between Single User, Shared, and "No Isolation Shared" cluster access modes, and why does this matter for governance?

**Answer:**
Single User clusters are dedicated to one user or service principal and support full Unity Catalog enforcement including row filters and column masks. Shared clusters support multiple concurrent users with per-user process isolation, also with full UC enforcement — each user's queries are governed correctly according to their own permissions. The legacy "No Isolation Shared" mode does **not** reliably enforce fine-grained UC controls (row filters/column masks can be bypassed) because it lacks proper per-user process isolation — it should be avoided for any cluster touching governed/sensitive data, and is generally being phased out in favor of the properly-isolated Shared mode.

---

## Q5. How do Storage Credentials and External Locations improve security compared to legacy instance profiles?

**Answer:**
Instance profiles attach broad IAM permissions to a **cluster** — anyone who can attach to that cluster inherits whatever S3/storage access the profile grants, regardless of their actual data permissions, and it's hard to audit exactly who accessed what through a shared instance profile. Storage Credentials + External Locations (Unity Catalog) instead tie access to the **data** itself: a credential defines the cloud IAM identity, an external location scopes it to a specific path, and actual access is governed by UC GRANTs to specific principals — fully auditable per-user/per-query via the audit log, and independent of which cluster happens to be used. This is a strictly stronger, more granular model and is the recommended default for all new work.

---

## Q6. What's the difference between a Personal Access Token and a Service Principal, and why should CI/CD pipelines use the latter?

**Answer:**
A Personal Access Token (PAT) is tied to an individual human user's identity — if that person leaves the company, changes teams, or has their account disabled, anything authenticating with their PAT (including production automation) breaks immediately, and it's a security anti-pattern to have production pipelines depend on an individual's personal credentials. A Service Principal is a non-human identity specifically meant for automation — it has its own lifecycle independent of any individual employee, supports OAuth machine-to-machine (client credentials) authentication, and its permissions can be scoped and audited independently. CI/CD pipelines, scheduled Jobs, and Terraform deployments should always authenticate as a service principal, not a personal token.

---

## Q7. How would you secure a Databricks workspace end-to-end for a healthcare (HIPAA-regulated) workload?

**Answer:**
Layer the defenses: (1) **Identity** — SSO via the corporate IdP with SCIM-synced groups, service principals for all automation, no long-lived personal tokens; (2) **Network** — VPC/VNet injection with No Public IP nodes, PrivateLink for both control-plane and user connectivity, IP access lists restricting workspace access to corporate network ranges; (3) **Compute** — cluster policies enforcing approved instance types/DBR versions, Shared or Single User access mode only (never legacy no-isolation); (4) **Data governance** — Unity Catalog with Storage Credentials/External Locations (no instance profiles), row filters/column masks on PHI columns, audit logging enabled and exported to a long-term SIEM; (5) **Encryption** — customer-managed keys for data at rest, TLS enforced in transit, and enabling the Compliance Security Profile / Enhanced Security Monitoring add-ons Databricks offers for regulated workloads. I'd also ensure the workspace region matches data residency requirements.
