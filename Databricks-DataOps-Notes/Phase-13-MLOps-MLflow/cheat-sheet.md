# Phase 13: MLOps & MLflow on Databricks — Cheat Sheet

---

## MLflow's Four Components

```
Tracking   → log params/metrics/artifacts per run
Projects   → reproducible packaged code
Models      → standard cross-framework packaging format
Registry    → versioning + lifecycle (now UC-integrated)
```

## Tracking Skeleton

```python
import mlflow
mlflow.autolog()   # auto-captures common framework params/metrics

with mlflow.start_run(run_name="run1"):
    mlflow.log_param("max_depth", 5)
    mlflow.log_metric("accuracy", 0.92)
    mlflow.sklearn.log_model(model, "model")
```

## Unity Catalog Model Registry

```python
mlflow.register_model("runs:/<run_id>/model", "catalog.schema.model_name")
```
```sql
GRANT EXECUTE ON MODEL catalog.schema.model_name TO `ml-engineers`;
```
Aliases (`champion`/`challenger`) replace legacy numeric stages (Staging/Production/Archived).

## Feature Store Skeleton

```python
from databricks.feature_engineering import FeatureEngineeringClient
fe = FeatureEngineeringClient()
fe.create_table(name="catalog.schema.features", primary_keys=["id"], df=features_df)
training_set = fe.create_training_set(df=labels_df, feature_lookups=[...], label="target")
```
Solves: training/serving skew + point-in-time correctness.

## Model Serving

```
Fully managed REST endpoint, autoscale + scale-to-zero
Supports A/B traffic splitting between model versions
Can proxy external models (OpenAI/Anthropic) through same interface
```

## MLOps CI/CD Flow

```
Train → log to MLflow Tracking → register to UC → automated validation tests
  → promote via alias update (challenger → champion) → deploy to Serving
  → monitor drift/accuracy in production → retrain trigger if threshold crossed
```

## Monitoring

```
Drift detection        → Lakehouse Monitoring (Inference profile) vs training baseline
Prediction quality      → join predictions to delayed ground truth outcomes
Retraining triggers      → scheduled Job, or automated on drift/accuracy threshold
```

## Databricks-native vs Alternatives

| Concern | Databricks | Alternative |
|---------|------------|-------------|
| Tracking | MLflow | W&B, Neptune |
| Registry | UC Model Registry | Standalone MLflow, SageMaker |
| Feature store | UC Feature Engineering | Feast, Tecton |
| Serving | Model Serving | SageMaker, KServe |
