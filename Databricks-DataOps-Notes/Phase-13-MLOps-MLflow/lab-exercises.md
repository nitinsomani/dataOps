# Phase 13: MLOps & MLflow on Databricks — Lab Exercises

> Use the ML Runtime for these labs (cluster with Databricks ML Runtime selected).

---

## Lab 1: Basic MLflow Tracking

```python
import mlflow
from sklearn.ensemble import RandomForestClassifier
from sklearn.datasets import make_classification
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score

X, y = make_classification(n_samples=1000, n_features=10, random_state=42)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2)

mlflow.autolog()

with mlflow.start_run(run_name="rf_baseline"):
    model = RandomForestClassifier(max_depth=5, n_estimators=100)
    model.fit(X_train, y_train)
    preds = model.predict(X_test)
    acc = accuracy_score(y_test, preds)
    mlflow.log_metric("test_accuracy", acc)
```

### Questions to Answer
- [ ] Open the Experiments UI — what parameters/metrics did autologging capture automatically vs what you logged manually?
- [ ] Run the same code with `max_depth=10` in a second run — compare both runs side by side in the UI.

---

## Lab 2: Register a Model to Unity Catalog

```python
mlflow.set_registry_uri("databricks-uc")

run_id = "<paste run_id from Lab 1>"
model_uri = f"runs:/{run_id}/model"
mlflow.register_model(model_uri, "main.lab13.churn_model")
```

```sql
SHOW GRANTS ON MODEL main.lab13.churn_model;
GRANT EXECUTE ON MODEL main.lab13.churn_model TO `account users`;
```

### Questions to Answer
- [ ] Where do you see this registered model in Catalog Explorer, and what lineage information is shown?
- [ ] What privilege is required to actually invoke/serve this model?

---

## Lab 3: Set an Alias and Simulate Promotion

```python
from mlflow import MlflowClient
client = MlflowClient()

client.set_registered_model_alias("main.lab13.churn_model", "challenger", version=1)
# After validation passes...
client.set_registered_model_alias("main.lab13.churn_model", "champion", version=1)
```

### Questions to Answer
- [ ] How would you load a model by alias instead of a specific version number (`models:/main.lab13.churn_model@champion`)?
- [ ] Design a simple validation check (e.g., accuracy > 0.8) that must pass before the alias is moved from `challenger` to `champion`.

---

## Lab 4: Feature Store Basics

```python
from databricks.feature_engineering import FeatureEngineeringClient
import pandas as pd

features_df = spark.createDataFrame(pd.DataFrame({
    "customer_id": range(1, 101),
    "total_purchases": [i * 10.0 for i in range(1, 101)],
    "avg_order_value": [i * 1.5 for i in range(1, 101)]
}))

fe = FeatureEngineeringClient()
fe.create_table(
    name="main.lab13.customer_features",
    primary_keys=["customer_id"],
    df=features_df,
    description="Lab customer features"
)
```

### Questions to Answer
- [ ] What does the feature table look like in Catalog Explorer — is it just a Delta table with extra metadata?
- [ ] Use `fe.create_training_set()` with a labels DataFrame joined against this feature table — what does the resulting training set contain?

---

## Lab 5: Deploy a Model Serving Endpoint

```python
# Via UI: Serving -> Create Serving Endpoint -> select main.lab13.churn_model, version/alias @champion
# Or via API:
import requests

endpoint_config = {
    "name": "lab13-churn-endpoint",
    "config": {
        "served_entities": [{
            "entity_name": "main.lab13.churn_model",
            "entity_version": "1",
            "workload_size": "Small",
            "scale_to_zero_enabled": True
        }]
    }
}
```

### Questions to Answer
- [ ] Once deployed, how would you send a test prediction request to the endpoint (REST call with a JSON payload)?
- [ ] What does `scale_to_zero_enabled` mean for cost when the endpoint has no traffic?

---

## Lab 6: Simulate Drift Monitoring

```python
# Simulate a shift in the input feature distribution over time (baseline vs "current")
import numpy as np

baseline = pd.DataFrame({"avg_order_value": np.random.normal(50, 10, 1000)})
current = pd.DataFrame({"avg_order_value": np.random.normal(80, 15, 1000)})  # shifted mean

print("Baseline mean/std:", baseline["avg_order_value"].mean(), baseline["avg_order_value"].std())
print("Current mean/std:", current["avg_order_value"].mean(), current["avg_order_value"].std())
```

### Questions to Answer
- [ ] Based on this simple mean/std comparison, would you flag this as meaningful drift? What statistical test could formalize this (e.g., KS test)?
- [ ] How would Lakehouse Monitoring's Inference profile automate this comparison in production rather than doing it manually like this lab?
