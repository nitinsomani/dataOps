# Phase 13: MLOps & MLflow on Databricks — Detailed Notes

> **Goal**: A DataOps Engineer often supports ML pipelines even without owning model development — understand the operational surface (tracking, registry, serving, feature store) well enough to build/support these pipelines reliably.

---

## 1. Why MLOps Matters to a DataOps Engineer

Data pipelines increasingly feed ML models, and ML pipelines have the same operational needs as data pipelines: versioning, reproducibility, CI/CD, monitoring, and governance. Databricks unifies this under the same platform (same clusters, same Unity Catalog, same Workflows) — a DataOps engineer is often the one building the **automation and infrastructure** around ML workflows even if data scientists own the modeling itself.

---

## 2. MLflow — The Core Framework

MLflow (open source, created by Databricks, deeply integrated into the platform) has four components:

```
Tracking     → log parameters, metrics, artifacts for every experiment run
Projects     → package code in a reusable, reproducible format
Models        → standard packaging format for models (works across frameworks)
Registry      → centralized model versioning, staging, and lifecycle management
```

### MLflow Tracking
```python
import mlflow

with mlflow.start_run(run_name="training_run_1"):
    mlflow.log_param("max_depth", 5)
    mlflow.log_param("n_estimators", 100)
    model = train_model(...)
    mlflow.log_metric("accuracy", 0.92)
    mlflow.log_metric("f1_score", 0.89)
    mlflow.sklearn.log_model(model, "model")
```
- Every run automatically records: code version (Git commit), parameters, metrics, and artifacts (model files, plots) — enabling reproducibility and comparison across experiments.
- Autologging (`mlflow.autolog()`) automatically captures common framework metrics/params (scikit-learn, XGBoost, TensorFlow, PyTorch) without manual `log_param`/`log_metric` calls.

### MLflow Model Registry (Unity Catalog-integrated)
```python
mlflow.register_model("runs:/<run_id>/model", "catalog.schema.model_name")
```
```sql
-- Models are now governed as Unity Catalog objects, just like tables
GRANT EXECUTE ON MODEL catalog.schema.model_name TO `ml-engineers`;
```
- Models registered in Unity Catalog get the same governance (grants, lineage, audit) as tables — a major shift from the older workspace-scoped model registry.
- **Aliases** (e.g., `champion`, `challenger`) replace the older numeric "stages" (Staging/Production/Archived) concept for marking which model version is currently deployed for a given purpose — more flexible than fixed stage names.

---

## 3. Feature Store

- A **Feature Store** (Unity Catalog Feature Engineering) centralizes feature computation and storage as governed Delta tables, so features are computed once and reused consistently across training and inference — preventing "training/serving skew" (where features are computed slightly differently in training vs production, causing silent model degradation).
- Feature tables support **point-in-time correctness** — when training, features are joined "as of" the label's timestamp, avoiding data leakage from future feature values.

```python
from databricks.feature_engineering import FeatureEngineeringClient

fe = FeatureEngineeringClient()
fe.create_table(
    name="catalog.schema.customer_features",
    primary_keys=["customer_id"],
    df=features_df,
    description="Customer aggregated features"
)

training_set = fe.create_training_set(
    df=labels_df,
    feature_lookups=[...],
    label="churned"
)
```

---

## 4. Model Serving

- **Databricks Model Serving**: fully managed, low-latency REST endpoint for a registered model, autoscaling (including scale-to-zero) — no need to manage your own serving infrastructure (Kubernetes, Flask apps, etc.).
- Supports A/B testing / traffic splitting between model versions, and can serve **external models** (e.g., proxying to OpenAI/Anthropic APIs) through the same governed endpoint interface — increasingly relevant as Databricks unifies traditional ML and generative AI serving.

```python
# Deploying is largely a UI/API operation referencing a registered UC model version
# databricks serving-endpoints create --json '{"name": "churn-model", "config": {...}}'
```

---

## 5. MLOps CI/CD Pattern

```
Data Scientist trains model in notebook → logs to MLflow Tracking
   → Register model version to UC (catalog.schema.model)
   → CI/CD pipeline runs validation tests (accuracy threshold, latency, schema checks)
   → Promote via alias update (e.g., move "challenger" alias to "champion")
   → Deploy new "champion" version to Model Serving endpoint
   → Monitor production predictions (Lakehouse Monitoring - Inference profile) for drift
```
- Model promotion should be gated by automated validation, not manual "looks good to me" — same CI/CD rigor as data pipelines (Phase 10).
- **Model lineage**: Unity Catalog tracks lineage from training data tables → feature tables → model versions → serving endpoints, giving full traceability for audits ("which data trained the model currently in production?").

---

## 6. Monitoring ML in Production

- **Drift detection**: compare production inference input feature distributions against the training baseline (Lakehouse Monitoring Inference profile) — flags when the real world has diverged from what the model was trained on.
- **Prediction quality monitoring**: where ground truth becomes available with a delay (e.g., "did the customer actually churn"), join predictions back to outcomes later to track real-world accuracy over time, not just at training time.
- Retraining triggers can be automated: schedule periodic retraining Jobs, or trigger retraining when drift/accuracy metrics cross a threshold.

---

## 7. Databricks vs Standalone MLOps Tools

| Concern | Databricks-native | Alternative |
|---------|---------------------|--------------|
| Experiment tracking | MLflow Tracking (built-in) | Weights & Biases, Neptune |
| Model registry | UC Model Registry | Standalone MLflow registry, SageMaker registry |
| Feature store | UC Feature Engineering | Feast, Tecton |
| Serving | Databricks Model Serving | SageMaker endpoints, KServe |

Databricks' pitch: unify all of this on one platform with one governance layer (Unity Catalog) rather than stitching together separate tools with separate access control models.

---

## 8. Key Takeaways for DataOps

- MLflow Tracking + Registry + Unity Catalog integration is the backbone — know how a model moves from a training run to a governed, deployable artifact.
- Feature Store solves training/serving skew and enables point-in-time-correct training sets — a common, specific interview topic.
- Model promotion should follow the same CI/CD discipline (automated validation gates, no direct-to-prod) as data pipelines.
- Drift monitoring closes the loop — a deployed model isn't "done," it needs the same production observability mindset as a data pipeline.
