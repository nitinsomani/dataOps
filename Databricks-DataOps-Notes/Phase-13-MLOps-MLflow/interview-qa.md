# Phase 13: MLOps & MLflow on Databricks — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ What is MLflow and what are its four main components?

**Answer:**
MLflow is an open-source platform (created by Databricks, tightly integrated into the product) for managing the ML lifecycle, with four components: **Tracking** (log parameters, metrics, and artifacts for every training run, enabling comparison and reproducibility), **Projects** (a standard format for packaging reusable, reproducible ML code), **Models** (a standard packaging format that works across ML frameworks — scikit-learn, TensorFlow, PyTorch, etc. — so downstream tools can load/serve them uniformly), and **Registry** (centralized model versioning and lifecycle management, now integrated with Unity Catalog for governance).

---

## Q2. ⭐ How does registering a model in Unity Catalog change how models are governed compared to the legacy workspace model registry?

**Answer:**
With the legacy workspace-scoped registry, models had their own separate access control model disconnected from the rest of the data platform's governance. Registering a model in Unity Catalog (`catalog.schema.model_name`) makes it a first-class governed object just like tables — subject to the same three-level namespace, GRANT/REVOKE permission model, lineage tracking, and audit logging as any other UC asset. This also enables cross-workspace model sharing/governance consistent with how data access is already managed, and ties model lineage directly to the training data tables and feature tables that produced it.

---

## Q3. What problem does a Feature Store solve, and what is "point-in-time correctness"?

**Answer:**
A Feature Store centralizes feature computation into governed, reusable Delta tables so the exact same feature logic is used both when training a model and when serving predictions in production — without a Feature Store, teams often end up with subtly different feature computation code in the training pipeline versus the serving pipeline, causing "training/serving skew" that silently degrades model performance in ways that are hard to detect. **Point-in-time correctness** means that when constructing a training set, features are joined to each label using only feature values that were actually available *as of* that label's timestamp — preventing data leakage where a model is inadvertently trained using information that wouldn't have existed yet at prediction time in production (e.g., using a customer's "total lifetime purchases" computed with data from after the churn label date).

---

## Q4. ⭐ Describe a CI/CD pattern for promoting an ML model from training to production, analogous to how you'd promote a data pipeline.

**Answer:**
A data scientist trains a model and logs the run (params, metrics, artifacts) to MLflow Tracking, then registers a model version to a Unity Catalog-governed model. An automated CI/CD pipeline then runs validation — accuracy/performance thresholds against a held-out test set, latency benchmarks, schema/input-contract checks — analogous to integration and data quality tests for a data pipeline. Only after passing these automated gates does the model get promoted, typically by moving an alias (e.g., `challenger` → `champion`) rather than manually re-deploying, and the newly-promoted version is what the Model Serving endpoint actually serves. This mirrors the dev→staging→prod promotion discipline from Phase 10 — no direct, ungated path from a training notebook straight to a production serving endpoint.

---

## Q5. How do "aliases" in the Unity Catalog Model Registry differ from the older "stages" concept (Staging/Production/Archived)?

**Answer:**
The legacy stage model used a fixed, global set of stage names (Staging, Production, Archived) that every model had to fit into, which was rigid — e.g., no clean way to represent "the model version currently being A/B tested against production" without overloading a stage name. Aliases are flexible, user-defined labels (like `champion`, `challenger`, `shadow`) that can be attached to any model version and moved independently — better matching real-world MLOps patterns like canary/shadow deployment or multi-armed A/B testing, where you need more nuanced concepts than three fixed global stages.

---

## Q6. How would you detect and respond to model drift in a production model served on Databricks?

**Answer:**
I'd use Lakehouse Monitoring's Inference profile (or a custom equivalent) to continuously compare the distribution of production inference input features against the training-time baseline distribution — significant divergence (feature drift) suggests the real-world data the model now sees no longer resembles what it was trained on, an early warning sign even before accuracy visibly degrades. Where ground truth becomes available with a delay (e.g., actual churn outcome known weeks later), I'd also join predictions back to eventual outcomes to track realized accuracy/precision/recall over time, not just training-time metrics. I'd configure alerting on both drift metrics and delayed-accuracy metrics crossing a threshold, triggering either a manual investigation or an automated scheduled retraining Job, depending on the organization's risk tolerance for automated model updates.

---

## Q7. As a DataOps engineer (not a data scientist), what's your role in an ML pipeline on Databricks?

**Answer:**
Even without owning model development, I'd own the surrounding automation and reliability: setting up the Feature Store pipelines that compute and refresh feature tables on a schedule (using the same Jobs/DLT patterns as any other ETL), building the CI/CD pipeline that validates and promotes models through the registry (Phase 10 patterns applied to ML artifacts), configuring Model Serving endpoints and their autoscaling/access control, setting up drift/monitoring dashboards and alerts, and ensuring Unity Catalog governance (grants, lineage) is correctly applied across training data, feature tables, and registered models. This is the "MLOps" analog of DataOps — the same discipline of automation, testing, observability, and governance, applied to the ML lifecycle rather than pure data pipelines.
