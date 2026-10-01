# Phase 10: CI/CD & DataOps Automation — Cheat Sheet

---

## The Standard Flow

```
Git (Repos) → Asset Bundles (YAML IaC) → CI/CD (GitHub Actions/Azure DevOps)
   → deploy dev → test → deploy staging → smoke test → manual approval → deploy prod
```

## Databricks Asset Bundles (DAB) Commands

```bash
databricks bundle init
databricks bundle validate
databricks bundle deploy -t dev
databricks bundle run <job_name> -t dev
databricks bundle deploy -t prod
databricks bundle destroy -t dev
```

## DAB YAML Skeleton

```yaml
bundle:
  name: my_pipeline
targets:
  dev:
    mode: development
  prod:
    mode: production
resources:
  jobs:
    my_job:
      tasks:
        - task_key: main
          notebook_task: { notebook_path: ./src/main.py }
          job_cluster_key: cluster
      job_clusters:
        - job_cluster_key: cluster
          new_cluster: { spark_version: "15.4.x-scala2.12", num_workers: 2 }
```

## DAB vs Terraform

| | DAB | Terraform |
|-|-----|-----------|
| Scope | Databricks jobs/pipelines/clusters | Full cloud infra + Databricks |
| Owner | Data engineering teams | Platform/infra teams |
| Best for | Pipeline CI/CD | Workspace + network + IAM provisioning |

## Testing Pyramid

```
Unit tests        → pure transform logic, local SparkSession, assertDataFrameEqual
Integration tests  → real cluster/job against scratch catalog
Data quality tests → row counts, nulls, referential integrity (Phase 11)
Contract tests      → schema drift detection (failOnNewColumns canary)
```

## GitHub Actions Auth (Service Principal)

```yaml
env:
  DATABRICKS_HOST: ${{ secrets.HOST }}
  DATABRICKS_CLIENT_ID: ${{ secrets.SP_CLIENT_ID }}
  DATABRICKS_CLIENT_SECRET: ${{ secrets.SP_SECRET }}
run: databricks bundle deploy -t prod
```

## Rollback Strategy

```
Infra/pipeline rollback → git revert + redeploy bundle from prior commit/tag
Data rollback           → RESTORE TABLE ... TO VERSION AS OF n  (Delta time travel)
```

## Promotion Checklist

```
[ ] Feature branch + PR, never commit directly to main
[ ] Automated tests gate merge
[ ] Auto-deploy to staging on merge
[ ] Smoke/validation tests in staging
[ ] Manual approval gate before prod
[ ] Deploy authenticated as service principal, not personal token
[ ] Environment-specific values via bundle variables, not hardcoded
```
