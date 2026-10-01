# Phase 10: CI/CD & DataOps Automation — Detailed Notes

> **Goal**: This phase is the heart of "DataOps" — applying software engineering rigor (version control, automated testing, repeatable deployment) to data pipelines. Expect this to be a major focus area in interviews for this specific role title.

---

## 1. Databricks Repos — Git Integration

- **Repos** let you clone a Git repository (GitHub/GitLab/Bitbucket/Azure DevOps) directly into the Databricks Workspace, so notebooks and code live under normal Git version control instead of only in the Databricks-managed workspace filesystem.
- Supports standard Git operations from the UI/CLI: branch, commit, push, pull, merge conflict resolution.
- **Best practice**: never develop directly against `main`/`prod` branch in a shared Repo — use feature branches and PRs like any other software project.
- Repos are the foundation that makes CI/CD possible — without version-controlled source, there's nothing to build a pipeline around.

---

## 2. Databricks Asset Bundles (DAB) — Infrastructure & Code as YAML

DABs are Databricks' native **Infrastructure-as-Code** framework for defining and deploying jobs, DLT pipelines, clusters, and related resources as version-controlled YAML, deployable consistently across environments.

```yaml
# databricks.yml
bundle:
  name: sales_pipeline

targets:
  dev:
    workspace:
      host: https://dev-workspace.cloud.databricks.com
    mode: development
  prod:
    workspace:
      host: https://prod-workspace.cloud.databricks.com
    mode: production

resources:
  jobs:
    sales_etl_job:
      name: sales-etl-${bundle.target}
      tasks:
        - task_key: ingest
          notebook_task:
            notebook_path: ./src/ingest.py
          job_cluster_key: main_cluster
      job_clusters:
        - job_cluster_key: main_cluster
          new_cluster:
            spark_version: "15.4.x-scala2.12"
            node_type_id: "Standard_DS3_v2"
            num_workers: 2
```

```bash
databricks bundle validate            # check syntax/config correctness
databricks bundle deploy -t dev        # deploy resources to dev target
databricks bundle run sales_etl_job -t dev
databricks bundle deploy -t prod       # promote to prod (typically via CI/CD, not manually)
```

- **Targets** define per-environment overrides (workspace host, mode, variable values) while sharing the same base resource definitions — avoiding config drift between dev/staging/prod.
- **`mode: development`** vs **`mode: production`** changes default behaviors (e.g., dev mode prefixes resource names with the deploying user to avoid collisions when multiple developers deploy simultaneously).
- DABs replace older, more manual approaches (hand-written REST API calls, or ad hoc Terraform-only setups) specifically for Databricks-native resources, while Terraform remains the tool of choice for broader cloud infrastructure (networking, IAM, storage accounts) surrounding Databricks.

---

## 3. Terraform for Databricks

```hcl
resource "databricks_cluster" "shared" {
  cluster_name            = "shared-cluster"
  spark_version           = "15.4.x-scala2.12"
  node_type_id            = "Standard_DS3_v2"
  autotermination_minutes = 30
}

resource "databricks_job" "etl_job" {
  name = "etl-job"
  task {
    task_key = "main"
    notebook_task {
      notebook_path = "/Repos/prod/pipeline/etl_notebook"
    }
    existing_cluster_id = databricks_cluster.shared.id
  }
}

resource "databricks_grants" "sales_schema" {
  schema = "sales"
  grant {
    principal  = "data-engineers"
    privileges = ["USE_SCHEMA", "SELECT", "MODIFY"]
  }
}
```

- The Databricks Terraform provider manages workspace-level resources (clusters, jobs, Unity Catalog grants, secret scopes) as code, alongside the surrounding cloud infrastructure (VPC/VNet, IAM roles, storage accounts) using the same tool — valuable when Databricks provisioning needs to be coordinated with broader cloud infra changes.
- **DAB vs Terraform**: DABs are more lightweight and Databricks-native for job/pipeline-centric CI/CD (better fit for a data engineering team's day-to-day pipeline deployment); Terraform is broader and better suited for platform/infra teams managing the full workspace + cloud resource lifecycle including networking and account-level settings. Many orgs use both — Terraform for platform setup, DABs for pipeline deployment on top of it.

---

## 4. CI/CD Pipeline Design (GitHub Actions Example)

```yaml
# .github/workflows/deploy.yml
name: Deploy Databricks Pipeline
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v5
        with: { python-version: '3.11' }
      - name: Install deps & run unit tests
        run: |
          pip install -r requirements.txt
          pytest tests/

  deploy-staging:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: databricks/setup-cli@main
      - name: Deploy to staging
        env:
          DATABRICKS_HOST: ${{ secrets.STAGING_HOST }}
          DATABRICKS_CLIENT_ID: ${{ secrets.STAGING_SP_CLIENT_ID }}
          DATABRICKS_CLIENT_SECRET: ${{ secrets.STAGING_SP_SECRET }}
        run: databricks bundle deploy -t staging

  deploy-prod:
    needs: deploy-staging
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production   # requires manual approval gate in GitHub
    steps:
      - uses: actions/checkout@v4
      - uses: databricks/setup-cli@main
      - name: Deploy to production
        env:
          DATABRICKS_HOST: ${{ secrets.PROD_HOST }}
          DATABRICKS_CLIENT_ID: ${{ secrets.PROD_SP_CLIENT_ID }}
          DATABRICKS_CLIENT_SECRET: ${{ secrets.PROD_SP_SECRET }}
        run: databricks bundle deploy -t prod
```

### Typical pipeline stages
1. **Lint/static analysis** (e.g., `flake8`/`ruff`, SQLFluff for SQL).
2. **Unit tests** — pure Python transformation logic tested with `pytest` + local/small Spark session (`chispa`/`pyspark-test` for DataFrame equality assertions).
3. **Integration tests** — run against a real (small) Databricks cluster/job in a dev/test target, validating end-to-end behavior with actual Spark/Delta.
4. **Deploy to staging** — automatic on merge to main.
5. **Manual approval gate** — required before prod (a hallmark of mature DataOps — no fully automatic prod deploys without human sign-off for most orgs).
6. **Deploy to prod** — via Asset Bundles/Terraform, authenticated as a service principal.

---

## 5. Testing Strategies for Data Pipelines

- **Unit tests**: test pure transformation functions in isolation (given this input DataFrame, assert this output DataFrame) — fast, no cluster needed, use a local SparkSession or `pyspark.testing.assertDataFrameEqual`.
- **Integration tests**: run the actual DLT pipeline / Job against a scratch catalog/schema with sample data, verifying end-to-end behavior including Delta writes, MERGE logic, and DLT expectations.
- **Data quality tests** (deep dive Phase 11): assert on the actual data itself (row counts, null rates, referential integrity) as a pipeline gate, not just code correctness.
- **Contract tests**: validate that upstream schema hasn't silently drifted in a way that breaks downstream consumers — often implemented as an explicit schema-check step in CI or a `failOnNewColumns` Auto Loader configuration in a canary environment.

```python
# Example unit test using pyspark.testing
from pyspark.testing.utils import assertDataFrameEqual

def test_dedup_logic(spark):
    input_df = spark.createDataFrame([(1, "a"), (1, "a"), (2, "b")], ["id", "val"])
    result = dedup_transform(input_df)
    expected = spark.createDataFrame([(1, "a"), (2, "b")], ["id", "val"])
    assertDataFrameEqual(result, expected)
```

---

## 6. Environment Promotion Strategy

```
Feature branch → PR → automated tests → merge to main
     → auto-deploy to staging (DAB target: staging)
     → validation/smoke tests against staging
     → manual approval
     → deploy to prod (DAB target: prod)
```

- Keep **environment-specific configuration** (catalog names, cluster sizes, secret scope names) in DAB `targets`/variables — never hardcode environment-specific values in notebook source code.
- Use **variables** in Asset Bundles to parameterize things like catalog name per target, avoiding copy-pasted job definitions per environment.

```yaml
variables:
  catalog:
    default: dev_catalog

targets:
  prod:
    variables:
      catalog: prod_catalog
```

---

## 7. Rollback Strategy

- Since Jobs/DLT pipelines are defined declaratively in version control, rolling back = redeploying a previous Git commit's bundle definition (`databricks bundle deploy` from a prior tag/commit) — infrastructure rollback is just a Git revert + redeploy.
- Data-level rollback uses Delta **time travel** / `RESTORE TABLE` (Phase 3) — a bad deployment that corrupted data can potentially be paired with restoring affected tables to a pre-deployment version.
- Always test rollback procedures, not just forward deploys — a DataOps engineer should be able to answer "how do you undo a bad prod deploy" concretely.

---

## 8. Key Takeaways for DataOps

- **Repos → Asset Bundles → CI/CD (GitHub Actions/Azure DevOps) → environment promotion with approval gates** is the standard modern pattern — know this flow end-to-end.
- DABs are Databricks-native IaC for pipeline resources; Terraform covers broader cloud infra — many orgs use both together.
- Testing spans unit (pure logic), integration (real cluster/Delta), and data quality (the data itself) — a mature pipeline has all three, not just one.
- Deployments authenticate as **service principals**, never personal tokens (ties back to Phase 7).
- Rollback = version-controlled redeploy + Delta time travel for data — always have an answer for this in interviews.
