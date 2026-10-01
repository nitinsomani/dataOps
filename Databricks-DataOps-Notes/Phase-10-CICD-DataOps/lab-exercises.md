# Phase 10: CI/CD & DataOps Automation — Lab Exercises

> These labs assume the Databricks CLI is installed locally and configured, plus a GitHub (or similar) account for CI/CD labs.

---

## Lab 1: Set Up a Repo and Feature Branch Workflow

1. In the Databricks Workspace, go to **Repos** → **Add Repo**, clone a test GitHub repository.
2. Create a feature branch (`feature/add-silver-transform`) from within the Repos UI or CLI.
3. Add a notebook implementing a simple transformation, commit, and push.
4. Open a Pull Request on GitHub back to `main`.

### Questions to Answer
- [ ] What happens in the Databricks UI when you switch branches in a Repo?
- [ ] Can you resolve a merge conflict directly from the Databricks Repos UI, or do you need to do it in GitHub/locally?

---

## Lab 2: Initialize and Deploy a Databricks Asset Bundle

```bash
databricks bundle init   # choose a default Python template
cd my_bundle_project
databricks bundle validate
databricks bundle deploy -t dev
databricks bundle run <job_name> -t dev
```

### Questions to Answer
- [ ] What resources did `databricks bundle deploy` create in your workspace (check Workflows/Jobs UI)?
- [ ] Modify `databricks.yml` to add a `staging` target pointing to the same workspace but a different catalog variable — deploy it and confirm the resource names differ (development mode prefixing).

---

## Lab 3: Parameterize with Variables

```yaml
variables:
  catalog:
    default: dev_catalog
  cluster_size:
    default: 2

targets:
  dev:
    variables:
      catalog: dev_catalog
      cluster_size: 1
  prod:
    variables:
      catalog: prod_catalog
      cluster_size: 4
```

Reference `${var.catalog}` and `${var.cluster_size}` in your job/task definitions.

### Questions to Answer
- [ ] Deploy to both `dev` and a mock `prod` target — confirm the deployed job configs actually differ per target.
- [ ] What happens if you deploy without specifying a target — is there a default?

---

## Lab 4: Build a GitHub Actions CI/CD Pipeline

```yaml
# .github/workflows/deploy.yml
name: Deploy Bundle
on: { push: { branches: [main] } }
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: databricks/setup-cli@main
      - run: databricks bundle deploy -t dev
        env:
          DATABRICKS_HOST: ${{ secrets.DATABRICKS_HOST }}
          DATABRICKS_TOKEN: ${{ secrets.DATABRICKS_TOKEN }}
```

1. Add `DATABRICKS_HOST` and `DATABRICKS_TOKEN` (ideally a service principal token) as GitHub repo secrets.
2. Push a change to `main` and observe the Action run.

### Questions to Answer
- [ ] Did the deployment succeed? Check the Actions log for the `databricks bundle deploy` output.
- [ ] Add a manual approval gate (GitHub Environments) before a hypothetical `prod` deploy step — how does GitHub enforce this?

---

## Lab 5: Write a Unit Test for a Transformation Function

```python
# transforms.py
from pyspark.sql import DataFrame
from pyspark.sql.functions import col

def dedup_orders(df: DataFrame) -> DataFrame:
    return df.dropDuplicates(["order_id"]).filter(col("amount") > 0)
```

```python
# test_transforms.py
from pyspark.testing.utils import assertDataFrameEqual
from transforms import dedup_orders

def test_dedup_orders(spark):
    input_df = spark.createDataFrame(
        [(1, 100.0), (1, 100.0), (2, -5.0), (3, 50.0)], ["order_id", "amount"]
    )
    result = dedup_orders(input_df)
    expected = spark.createDataFrame([(1, 100.0), (3, 50.0)], ["order_id", "amount"])
    assertDataFrameEqual(result, expected)
```

```bash
pytest test_transforms.py -v
```

### Questions to Answer
- [ ] Does the test pass? Break the transformation logic intentionally — does the test correctly fail?
- [ ] How would you integrate this `pytest` run as a required check before merging a PR?

---

## Lab 6: Rollback Simulation

1. Deploy version 1 of a bundle (a job writing `status = 'v1'` into a table).
2. Deploy version 2 (a "bad" change writing `status = 'v2-broken'` with a bug that corrupts data).
3. Practice rolling back: revert the Git commit, redeploy the bundle, and use `RESTORE TABLE` to fix the corrupted data.

### Questions to Answer
- [ ] What Delta table version corresponds to the state right before the "bad" deployment ran?
- [ ] After rollback, confirm the table data matches the pre-bad-deploy state — what command did you use to verify?
