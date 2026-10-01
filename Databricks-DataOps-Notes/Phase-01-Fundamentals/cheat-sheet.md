# Phase 1: Databricks & Lakehouse Fundamentals — Cheat Sheet

> Quick-reference for revision. Pin this for interview day.

---

## Lakehouse in One Line

> "A Lakehouse stores data once in open formats (Delta/Parquet) on cheap object storage, and layers ACID transactions, schema management, and performance on top — so one copy of data serves BI, streaming, and ML."

---

## Control Plane vs Data Plane

```
CONTROL PLANE (Databricks-managed)      DATA PLANE (Your cloud account)
────────────────────────────────        ──────────────────────────────
Web UI / REST API                        Clusters (compute)
Job scheduler                             Your data (S3/ADLS/GCS)
Cluster manager                           DBFS root / mounts / Volumes
Unity Catalog metastore (metadata)        Actual query execution
```

Rule of thumb: **"Metadata & orchestration = control plane. Data & compute = data plane."**

---

## Cluster Types Quick Table

| Type | Cost profile | When to use |
|------|--------------|-------------|
| All-Purpose | $$$ (stays up) | Interactive dev/notebooks |
| Job Cluster | $ (ephemeral) | Scheduled production jobs |
| SQL Warehouse | $ (auto-stop) | BI/SQL queries, dashboards |
| Pools | reduces startup latency | Frequent job clusters, faster spin-up |

---

## DBFS Paths Quick Reference

```
/dbfs/FileStore/...      small files, libraries, images
/dbfs/mnt/<name>/...     legacy mount to external storage (avoid for new work)
/Volumes/catalog/schema/volume/...   Unity Catalog managed/external volumes (preferred)
```

---

## Databricks Runtime (DBR) Flavors

```
Standard   → Base Spark + curated libraries
ML         → + TensorFlow, PyTorch, XGBoost, MLflow pre-installed
Photon     → native vectorized engine, faster SQL/DataFrame ops
GPU        → CUDA drivers for deep learning
LTS        → Long Term Support version, recommended for production
```

---

## Pricing Formula

```
Total Cost = Cloud VM Cost (EC2/VM) + DBU Cost (Databricks software)
DBU rate varies by: workload type × tier × Photon on/off
```

---

## Personas Cheat Table

| Persona | Tool |
|---------|------|
| DataOps/Data Engineer | Jobs, DLT, Unity Catalog, Repos, Asset Bundles |
| Analyst | Databricks SQL, Genie, Dashboards |
| Data Scientist | MLflow, Feature Store, Model Serving |
| Platform Admin | Account console, metastore admin |

---

## Common Gotchas

- DBFS root is **not** encrypted with customer-managed keys by default and is being phased out — use Unity Catalog **Volumes** for new file-based workloads.
- All-purpose clusters left running are the #1 cause of surprise cost overruns — always set autotermination.
- Control plane never stores your actual data (with classic compute) — only metadata, notebook source, and job configs.
