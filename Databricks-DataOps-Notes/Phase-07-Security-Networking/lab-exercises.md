# Phase 7: Security, Networking & Access Control — Lab Exercises

> Some labs require account/cloud admin privileges (VPC injection, PrivateLink); others are runnable in any workspace.

---

## Lab 1: Secret Scopes

```bash
databricks secrets create-scope lab7-scope
databricks secrets put-secret lab7-scope api-key --string-value "super-secret-value-123"
databricks secrets list-secrets lab7-scope
```

```python
# In a notebook
secret_val = dbutils.secrets.get(scope="lab7-scope", key="api-key")
print(secret_val)          # should print [REDACTED]
print(f"Length: {len(secret_val)}")  # metadata about it is fine to print
```

### Questions to Answer
- [ ] What did printing the secret directly show instead of the actual value?
- [ ] Set an ACL restricting the scope to a specific group (`databricks secrets put-acl`) — what happens if a user outside that group tries to read it?

---

## Lab 2: Cluster Policies

1. Go to **Compute** → **Policies** → **Create Policy**.
2. Define a policy restricting: max workers = 4, allowed instance types = a small list, require a `cost-center` tag, disallow "No Isolation Shared" access mode.
3. Create a cluster using this policy.

### Questions to Answer
- [ ] What options disappeared/were locked in the cluster creation UI once the policy was applied?
- [ ] What happens if you try to create a cluster exceeding the policy's max worker count via the API?

---

## Lab 3: Access Mode and Unity Catalog Enforcement

1. Create two clusters: one in **Shared** access mode, one attempting **No Isolation Shared** (if available in your workspace/tier).
2. On a UC table with a row filter applied (from Phase 6 Lab 3), query it from both clusters as a restricted user.

### Questions to Answer
- [ ] Did both cluster types correctly enforce the row filter, or did one bypass it?
- [ ] Why might your organization choose to disable "No Isolation Shared" clusters entirely via a cluster policy?

---

## Lab 4: IP Access Lists (Account/Workspace Admin Required)

1. Navigate to workspace admin settings → **IP Access Lists**.
2. Add your current public IP as an "Allow" entry, and add a deliberately wrong CIDR range as another "Allow" entry (removing your access temporarily is risky — read the docs on lockout prevention first).

### Questions to Answer
- [ ] What safeguard does Databricks provide to avoid accidentally locking yourself out?
- [ ] How would this feature combine with PrivateLink to fully eliminate public internet access paths to the workspace?

---

## Lab 5: Audit Trail for Security Events

```sql
SELECT event_time, action_name, user_identity.email, request_params
FROM system.access.audit
WHERE action_name IN ('tokenCreate', 'tokenDelete', 'changeSecretAcl', 'createScope')
ORDER BY event_time DESC
LIMIT 20;
```

### Questions to Answer
- [ ] Can you find the audit entry corresponding to the secret scope you created in Lab 1?
- [ ] Design a scheduled alert query: flag any `tokenCreate` events for PATs with no expiration set.

---

## Lab 6: Service Principal Setup for CI/CD (Conceptual/API Walkthrough)

```bash
# Using Databricks CLI with account admin privileges
databricks service-principals create --display-name "ci-cd-pipeline-sp"
databricks service-principals list

# Grant it access to a workspace and generate an OAuth secret for machine-to-machine auth
```

### Questions to Answer
- [ ] Why is a service principal with an OAuth client-credentials flow preferable to a PAT for a GitHub Actions pipeline deploying Databricks Asset Bundles?
- [ ] What UC grants would this service principal need to deploy a DLT pipeline into a `staging` catalog?
