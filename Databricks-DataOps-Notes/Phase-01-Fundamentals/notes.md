# Phase 1: Databricks & Lakehouse Fundamentals — Detailed Notes

> **Goal**: Understand what Databricks is, why the Lakehouse pattern exists, and how the platform is architected under the hood.
> **Target**: DataOps Engineer / Data Platform Engineer role

---

## 1. What is Databricks?

**Databricks** is a unified, cloud-based data platform built by the original creators of **Apache Spark**. It combines data engineering, data warehousing, streaming, and machine learning into a single "Lakehouse" platform, running on top of your cloud provider (AWS, Azure, or GCP).

### Why Databricks exists — the problem it solves

| Old world | Problem | Databricks / Lakehouse answer |
|-----------|---------|-------------------------------|
| Data Warehouse (Snowflake, Redshift) | Great for BI/SQL, poor for ML/unstructured data, expensive at scale | Lakehouse = warehouse features on top of open data lake files |
| Data Lake (raw S3/ADLS files) | Cheap, flexible, but no ACID, no schema enforcement, "data swamp" | Delta Lake adds ACID transactions, schema enforcement, time travel |
| Two separate systems (lake + warehouse) | Data duplication, sync lag, double the pipelines & cost | Single copy of data serves both BI and ML/AI workloads |

### Core value proposition
- **One copy of data** (in open Parquet/Delta format) serves SQL analytics, BI, streaming, and ML
- **Open formats** — no vendor lock-in on storage (Delta Lake is open source)
- **Separation of storage and compute** — scale each independently, pay only for compute used
- **Multi-cloud** — same platform experience on AWS, Azure, GCP

---

## 2. The Lakehouse Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      CONSUMPTION LAYER                       │
│   BI Tools | Databricks SQL | Notebooks | ML/AI | Genie      │
├─────────────────────────────────────────────────────────────┤
│                    GOVERNANCE LAYER                           │
│              Unity Catalog (Data + AI governance)             │
├─────────────────────────────────────────────────────────────┤
│                    PROCESSING LAYER                            │
│        Apache Spark | Photon Engine | Delta Live Tables       │
├─────────────────────────────────────────────────────────────┤
│                     STORAGE LAYER                              │
│   Delta Lake (ACID, schema, time travel) on cloud object store│
│           (S3 / ADLS Gen2 / GCS — open Parquet files)          │
└─────────────────────────────────────────────────────────────┘
```

**Key idea**: The Lakehouse stores data once, in open Delta/Parquet format, in your own cloud storage account — and layers transactional guarantees, governance, and performance optimizations on top.

---

## 3. Databricks Control Plane vs Data Plane

This is one of the **most commonly asked architecture questions** in interviews.

```
┌────────────────────────────┐        ┌──────────────────────────────┐
│      CONTROL PLANE          │        │         DATA PLANE            │
│   (Managed by Databricks)   │        │  (Runs in YOUR cloud account)  │
│                              │        │                                │
│  - Web UI / Notebooks        │◄──────►│  - Clusters (VMs/EC2/VMSS)     │
│  - Job scheduler              │  API   │  - Your data (S3/ADLS/GCS)     │
│  - Cluster manager             │ calls  │  - DBFS root & mounts           │
│  - Unity Catalog metastore*    │        │  - Actual Spark compute         │
│  - Notebook source/results      │        │                                │
└────────────────────────────┘        └──────────────────────────────┘
```

- **Control Plane**: Hosted by Databricks in their own AWS/Azure/GCP account. Contains the web application, REST APIs, job scheduling, notebook management, cluster manager. You never see the infrastructure.
- **Data Plane**: Runs inside **your** cloud account/subscription. This is where actual compute (clusters) spins up and where your data physically lives. This is **why Databricks can claim "your data never leaves your cloud account."**
- **Serverless compute** (newer offering) moves some data plane responsibility into a Databricks-managed serverless environment, but data still stays in your storage.

**Interview tip**: Emphasize that this split is why Databricks is popular with security-conscious enterprises — sensitive data never crosses into Databricks-owned infrastructure with classic (non-serverless) compute.

---

## 4. Workspace, Notebooks & DBFS

### Workspace
- The **Workspace** is the top-level container: notebooks, libraries, dashboards, experiments, files, Repos (Git folders).
- Organized like a filesystem: `/Workspace/Users/`, `/Workspace/Shared/`, `/Workspace/Repos/`.

### Notebooks
- Support multiple languages **per cell**: `%python`, `%sql`, `%scala`, `%r`, `%md` (markdown), `%sh` (shell), `%fs` (filesystem).
- Notebooks can be scheduled directly as Jobs, or chained into multi-task Workflows.

### DBFS (Databricks File System)
- An abstraction layer over your cloud object storage (S3/ADLS/GCS), mounted at `/dbfs` and accessible via `dbutils.fs`.
- `/dbfs/FileStore` — used for small files, images, libraries.
- `/dbfs/mnt/...` — legacy mount points to external storage (increasingly replaced by Unity Catalog **Volumes**).
- **Modern best practice**: Prefer Unity Catalog external locations & Volumes over DBFS mounts (DBFS root is being deprecated for new workloads; mounts lack fine-grained governance).

```python
# dbutils examples
dbutils.fs.ls("/mnt/raw/")
dbutils.fs.mkdirs("/mnt/raw/orders")
dbutils.secrets.get(scope="kv-scope", key="db-password")
dbutils.widgets.text("run_date", "2026-01-01")
```

---

## 5. Clusters — The Compute Layer

| Cluster Type | Use case | Lifecycle |
|--------------|----------|-----------|
| **All-Purpose Cluster** | Interactive notebook development, ad-hoc analysis | Manually created, can be shared, stays up (costly if idle) |
| **Job Cluster** | Runs a scheduled job, then terminates | Created at job start, auto-terminates at job end — cheaper |
| **SQL Warehouse** | Databricks SQL queries, BI tool connections | Serverless/Pro/Classic, optimized for SQL + Photon |
| **Instance Pools** | Pre-warmed idle VMs to reduce cluster start time | Pool manages VM lifecycle; clusters borrow from pool |

### Cluster components
- **Driver node**: Runs the Spark driver program, maintains SparkContext, schedules tasks, collects results.
- **Worker nodes**: Run executors that do the actual distributed computation.
- **Databricks Runtime (DBR)**: A curated, optimized distribution of Spark + libraries (e.g., DBR 15.4 LTS). Comes in flavors: Standard, **ML** (pre-installed ML libraries), **Photon** (vectorized native engine), **GPU**.

### Autoscaling
- Clusters can scale workers between a min/max based on workload (pending tasks in queue).
- **Autotermination**: Idle clusters shut down automatically after N minutes of inactivity — a key cost control.

---

## 6. Databricks Editions / Tiers

| Tier | Notes |
|------|-------|
| **Standard** | Core notebook/cluster features |
| **Premium** | Adds role-based access control, Unity Catalog eligibility, audit logs |
| **Enterprise** | Adds compliance security profile, customer-managed keys, IP access lists |

Cloud-specific naming: on Azure it's "Azure Databricks", tightly integrated with Entra ID (Azure AD), ADLS Gen2, and Azure networking (VNet injection).

---

## 7. Pricing Model — DBU (Databricks Unit)

- A **DBU** is a unit of processing capability per hour, billed **in addition to** the underlying cloud VM cost.
- Total cost = **Cloud infra cost (VMs, storage, network)** + **DBU cost (Databricks software layer)**.
- DBU rate varies by: workload type (Jobs vs All-Purpose vs SQL vs DLT), tier (Standard/Premium/Enterprise), and whether Photon is enabled.
- **Cost optimization levers** (deep dive in Phase 9/13): job clusters over all-purpose, spot/preemptible instances, autoscaling, autotermination, pools, serverless SQL warehouses with auto-stop.

---

## 8. Key Personas & How They Use Databricks

| Persona | Primary tools |
|---------|---------------|
| **Data Engineer / DataOps Engineer** | Notebooks, Jobs/Workflows, Delta Live Tables, Unity Catalog, Repos, Asset Bundles |
| **Data Analyst** | Databricks SQL, dashboards, Genie (natural language queries) |
| **Data Scientist / ML Engineer** | MLflow, Feature Store, Model Serving, notebooks with ML runtime |
| **Platform/DevOps Admin** | Account console, workspace admin, Unity Catalog metastore admin, cost/usage monitoring |

**A DataOps Engineer sits at the intersection**: building reliable, automated, governed, observable data pipelines — applying DevOps principles (CI/CD, IaC, testing, monitoring) to data engineering on Databricks.

---

## 9. Databricks vs Alternatives — Positioning

| Platform | Primary strength | Databricks differentiator |
|----------|------------------|----------------------------|
| Snowflake | Best-in-class SQL warehouse, easy to use | Databricks unifies ML/AI + streaming + open format (Delta) natively |
| AWS EMR / Glue | Cheaper raw Spark, more manual | Databricks adds managed runtime, collaborative notebooks, Unity Catalog, Photon speed |
| Synapse Analytics | Deep Azure/SQL Server integration | Databricks is more open-source aligned (Spark/Delta), stronger Lakehouse story |
| Plain Apache Spark (self-hosted) | Full control, no vendor cost | Databricks removes ops burden (cluster mgmt, tuning, upgrades) |

---

## 10. Key Takeaways for DataOps

- Everything in Databricks ultimately reduces to: **Spark compute + Delta storage + Unity Catalog governance + Workflow orchestration**, wrapped in a managed control plane.
- As a DataOps engineer, your job is to make this pipeline **repeatable, automated, observable, and governed** — that's the through-line for the rest of these notes.
- Understand the **control plane / data plane** split cold — it's asked constantly and underpins security/compliance discussions.
