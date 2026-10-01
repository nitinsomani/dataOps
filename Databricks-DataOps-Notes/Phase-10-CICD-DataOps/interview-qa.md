# Phase 10: CI/CD & DataOps Automation — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked. This phase is central to a "DataOps Engineer" title — expect deep questions here.

---

## Q1. ⭐ Walk me through your ideal CI/CD pipeline for deploying a Databricks data pipeline from dev to production.

**Answer:**
Code lives in Git via Databricks Repos, developed on feature branches with PRs (never committing directly to main). On PR open, CI runs lint/static analysis and unit tests against pure transformation logic. On merge to main, CI automatically deploys the pipeline (defined as a Databricks Asset Bundle) to a **staging** target, then runs integration/smoke tests against real staging data/clusters. Promotion to **production** requires a manual approval gate (e.g., a GitHub Environment protection rule) — no pipeline should auto-deploy to prod without human sign-off. The actual deploy step authenticates as a **service principal** (never a personal token), using `databricks bundle deploy -t prod`. Rollback, if needed, is a Git revert plus redeploying the prior bundle version, paired with Delta time travel/`RESTORE TABLE` if bad data was written.

---

## Q2. ⭐ What are Databricks Asset Bundles and how do they differ from just using the Databricks REST API or clicking through the UI?

**Answer:**
Asset Bundles are Databricks' native Infrastructure-as-Code framework — you define jobs, DLT pipelines, clusters, and related resources declaratively in YAML (`databricks.yml`), with **targets** representing different environments (dev/staging/prod) that can override workspace host, mode, and variables while sharing the same base resource definitions. This is fundamentally different from manually clicking through the UI (not version-controlled, not repeatable, prone to drift between environments) or hand-writing raw REST API calls (works, but you're reinventing dependency management, idempotent updates, and environment templating that DABs already solve). `databricks bundle deploy -t <target>` gives you a single repeatable command per environment, and `databricks bundle validate` catches configuration errors before deployment.

---

## Q3. When would you use Terraform instead of (or alongside) Databricks Asset Bundles?

**Answer:**
DABs are purpose-built for Databricks-native, pipeline-centric resources (jobs, DLT pipelines, job clusters) and are the more lightweight choice for a data engineering team iterating on pipeline deployments. Terraform is broader — it manages the surrounding cloud infrastructure (VPC/VNet, IAM roles, storage accounts, networking) alongside Databricks workspace-level resources (via the official Databricks Terraform provider, which also supports clusters, jobs, and Unity Catalog grants) using the same tool and state model as the rest of the organization's cloud infra. In practice, many organizations use **both**: a platform/infra team owns Terraform for workspace provisioning, networking, and account-level Unity Catalog setup, while data engineering teams use Asset Bundles on top of that foundation for day-to-day pipeline deployment — giving each team the right level of abstraction for their concerns.

---

## Q4. ⭐ How do you unit test Spark/PySpark transformation logic without needing a full production cluster?

**Answer:**
Structure transformation logic as pure functions taking a DataFrame in and returning a DataFrame out, decoupled from I/O (reading/writing tables) — this makes them testable with a small local SparkSession (or a lightweight test cluster) using tools like `pyspark.testing.assertDataFrameEqual` (or third-party libraries like `chispa`) to assert the output DataFrame matches an expected DataFrame given a known input. This runs fast in CI without needing an actual Databricks cluster, catching logic errors early (e.g., a broken deduplication key, an incorrect join condition) before more expensive integration tests run against real infrastructure with real Delta tables.

---

## Q5. What's the difference between unit tests, integration tests, and data quality tests in a DataOps pipeline, and why do you need all three?

**Answer:**
Unit tests validate pure transformation logic in isolation — fast, cheap, no cluster needed, catching code-level bugs. Integration tests run the actual pipeline (Job or DLT) against a real cluster and a scratch catalog/schema with representative sample data, validating things unit tests can't — actual Delta writes, MERGE behavior, checkpoint/streaming semantics, and interactions between multiple pipeline stages. Data quality tests assert on the **data itself** in production or near-production data (row counts within expected bounds, null rate thresholds, referential integrity, no duplicate keys) — these catch problems that are correct-by-code but wrong-by-data, like an upstream source silently sending malformed or incomplete data even though your transformation logic is bug-free. Without all three, you have blind spots: unit tests alone miss real infrastructure issues; integration tests alone are slow and miss fast logic-bug feedback; skipping data quality tests means bad data can pass a "correct" pipeline silently.

---

## Q6. How would you handle environment-specific configuration (like catalog names or cluster sizes) across dev/staging/prod without duplicating job definitions?

**Answer:**
Use Asset Bundle **variables** and **targets** — define variables like `catalog` with a default value, then override them per target (`dev`/`staging`/`prod`) in the `targets` section of `databricks.yml`, so a single job/pipeline definition is parameterized rather than copy-pasted three times with hardcoded values. This keeps the actual pipeline logic identical across environments (reducing "works in staging, breaks in prod" surprises caused by definition drift) while still allowing legitimately different settings (smaller clusters in dev, different catalog/schema names, different secret scopes) per environment.

---

## Q7. How do you roll back a bad production deployment, both at the infrastructure/pipeline level and the data level?

**Answer:**
At the infrastructure/pipeline level, since Jobs and DLT pipelines are defined declaratively in version-controlled YAML, rollback is simply reverting to the prior Git commit/tag and redeploying (`databricks bundle deploy -t prod` from that earlier state) — no manual undo of UI clicks needed. At the data level, if the bad deployment wrote incorrect data, Delta Lake's time travel/`RESTORE TABLE ... TO VERSION AS OF n` can revert affected tables to their pre-deployment state, provided the retention window hasn't expired and no destructive `VACUUM` has run since. A mature DataOps setup tests this rollback path deliberately (not just the forward deploy path) so it's a known, rehearsed procedure rather than something improvised during an incident.

---

## Q8. Why should a service principal be used for CI/CD deployments instead of a personal access token, and how does this tie into the deployment pipeline design?

**Answer:**
A personal access token ties the automation's identity to an individual employee — if that person's account is disabled, their token expires, or they change roles, the CI/CD pipeline breaks unexpectedly, and it's a poor security practice to have shared automation depend on one person's credentials. A service principal is a dedicated non-human identity for automation with its own lifecycle, typically authenticated via OAuth machine-to-machine (client ID + secret stored in the CI/CD system's secret store, e.g., GitHub Actions secrets), with permissions scoped specifically to what the deployment needs (e.g., deploy rights to the staging/prod Asset Bundle targets, appropriate Unity Catalog grants) — independently auditable via the audit log regardless of which individual triggered the pipeline run.
