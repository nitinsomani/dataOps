# Phase 16: System Design — AWS Data Platform Architecture — Detailed Notes

> **Goal**: Product-based company interviews for a Databricks DataOps role frequently include a dedicated system design round centered on AWS (since Databricks runs its Data Plane inside your AWS account). This phase covers the AWS building blocks and how they combine with Databricks in real architectures.

---

## 1. Why This Round Exists Separately from Databricks-Specific Rounds

The Databricks-specific rounds (Phases 1-15) test whether you know the platform. The system design round tests whether you can **architect a solution using the platform plus the surrounding cloud ecosystem** — deciding what runs in Databricks vs. what runs in native AWS services, and justifying those tradeoffs (cost, latency, operational overhead, team ownership boundaries).

---

## 2. Core AWS Building Blocks for Data Platforms

| Service | Role | Databricks interaction |
|---------|------|--------------------------|
| **S3** | Durable object storage — the Lakehouse's data layer | Delta Lake files live here; Databricks Data Plane reads/writes directly via Storage Credentials |
| **Glue Data Catalog** | Hive-metastore-compatible metadata catalog | Can be used as an external metastore, but Unity Catalog is now the recommended governance layer instead |
| **Glue ETL / Glue Studio** | Serverless Spark-based ETL (AWS-native, non-Databricks) | Alternative to Databricks Jobs for simple ETL; teams often compare cost/features here |
| **EMR** | Managed Hadoop/Spark clusters (AWS-native, non-Databricks) | Direct competitor to Databricks clusters — worth knowing the comparison |
| **Kinesis Data Streams** | Managed real-time streaming ingestion | Structured Streaming can read directly from Kinesis as a source |
| **Kinesis Firehose** | Managed streaming delivery (buffers + writes to S3/Redshift) | Common "cheap and simple" alternative to a full streaming job when near-real-time (minutes) is acceptable |
| **MSK (Managed Kafka)** | Managed Kafka | Alternative to Kinesis; Structured Streaming Kafka connector applies (Phase 12) |
| **Lambda** | Serverless event-driven compute | Triggers Auto Loader-adjacent workflows, lightweight file-arrival notifications, or small transformations |
| **Step Functions** | Serverless workflow orchestration | Alternative/complement to Databricks Workflows — often orchestrates Databricks Jobs alongside other AWS services (Lambda, Glue, SNS) |
| **SQS / SNS** | Queueing / pub-sub messaging | Backing mechanism for Auto Loader's file notification mode (S3 event → SNS → SQS → Auto Loader) |
| **Redshift** | Cloud data warehouse | Common downstream consumer or complementary warehouse alongside Databricks SQL; Redshift Spectrum can query S3/Delta data directly |
| **Athena** | Serverless, ad hoc SQL query engine over S3 | Cheap way to query the same S3/Delta lake data without spinning up any compute — good for infrequent ad hoc queries |
| **DynamoDB** | NoSQL key-value store | Common for operational/low-latency lookups (e.g., feature serving, dedup tracking) alongside the analytical Lakehouse |
| **RDS / Aurora** | Managed relational databases | Common OLTP source system that gets CDC'd into the Lakehouse |
| **IAM** | Identity and access management | Underpins Storage Credentials, service principal cloud roles, cross-account access |
| **VPC** | Networking (see companion networking notes) | Databricks Data Plane deploys into a VPC — subnets, security groups, NAT gateways, VPC endpoints for S3/PrivateLink |
| **CloudWatch** | Logging & monitoring | Cluster logs, Lambda logs, can complement (not replace) Databricks system tables for a unified ops view |
| **KMS** | Key management | Customer-managed keys (CMK) for encryption at rest (Phase 7) |

---

## 3. Where Databricks Fits in an AWS Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Sources: RDS/Aurora (CDC), SaaS APIs, Kinesis/MSK streams,       │
│           on-prem files via Direct Connect/VPN                   │
└─────────────────────────────────────────────────────────────────┘
              │
              ▼
   S3 (raw landing zone) ◄── Kinesis Firehose / Lambda / DMS (CDC)
              │
              ▼
   Databricks Auto Loader (file notification via SNS/SQS)
   or Structured Streaming (direct Kinesis/MSK read)
              │
              ▼
   Delta Lake: Bronze → Silver → Gold  (on S3, governed by Unity Catalog)
              │
       ┌──────┴────────┬─────────────────┐
       ▼                ▼                 ▼
  Databricks SQL    Redshift Spectrum   Athena (ad hoc)
  (BI dashboards)    / Redshift          
       │
       ▼
  Model Serving / MLflow (if ML consumption)
```

- **Orchestration**: either Databricks Workflows (if the pipeline is entirely Databricks-centric) or **Step Functions** (if it needs to coordinate Lambda, Glue, SNS notifications, and Databricks Jobs together as one broader AWS-native pipeline).
- **Networking**: Databricks Data Plane deployed via **VPC injection** into a customer-managed VPC, with **VPC endpoints** for private S3 access (avoiding public internet egress) and **PrivateLink** for control-plane connectivity (Phase 7).
- **IAM**: Unity Catalog **Storage Credentials** reference an IAM role that Databricks assumes to access S3 — replacing the older per-cluster instance profile model.

---

## 4. Databricks vs Native AWS Alternatives — Decision Framework

| Decision | Choose Databricks when... | Choose native AWS service when... |
|----------|----------------------------|--------------------------------------|
| ETL compute | Complex transformations, need Delta/Unity Catalog governance, ML integration | Simple, infrequent transforms; team wants zero cluster management (Glue serverless) |
| Orchestration | Pipeline is Databricks-centric (Jobs/DLT sufficient) | Pipeline spans many non-Databricks AWS services (Step Functions is the natural glue) |
| Streaming ingestion | Need Delta Lake sink with ACID/schema evolution, Structured Streaming operators | Extremely simple stream-to-S3 buffering with no transformation (Kinesis Firehose) |
| Ad hoc SQL | Frequent, governed, needs UC access control | Rare, one-off queries where spinning up a warehouse isn't worth it (Athena) |
| Data warehouse | Want single Lakehouse serving BI + ML from one copy of data | Org has deep existing Redshift investment/skillset, needs Redshift-specific features |

---

## 5. Non-Functional Requirements Framework (Apply to Any Design Question)

When asked "design X," explicitly address:
- **Scalability**: does the design handle 10x data growth? (partitioning/clustering strategy, autoscaling compute)
- **Availability**: what's the blast radius of a component failure? (multi-AZ S3 by default, DR strategy from Phase 14)
- **Durability**: S3 gives 11 nines durability by default — usually a non-issue, but call it out
- **Consistency**: Delta Lake gives strong consistency via ACID; note where eventual consistency is acceptable (e.g., a downstream cache)
- **Latency**: batch (minutes-hours) vs near-real-time (seconds) vs real-time (sub-second) — drives the ingestion mechanism choice (Auto Loader batch vs Kinesis/MSK streaming)
- **Cost**: storage class tiering (S3 Intelligent-Tiering/Glacier for cold data), job vs all-purpose clusters, spot instances, serverless SQL warehouses
- **Security/Governance**: Unity Catalog grants, encryption, network isolation (Phase 6/7)

---

## 6. Common System Design Prompts for This Role

1. "Design a data platform ingesting clickstream events at 50K events/sec, supporting both real-time fraud alerts and next-day BI reporting."
2. "Design a CDC pipeline replicating an on-prem Oracle database into the Lakehouse with under 5-minute latency."
3. "Design a cost-optimized architecture for a company with highly variable (spiky) daily batch ETL workloads."
4. "Design a multi-tenant data platform where each business unit needs isolated compute and governed cross-unit data sharing."
5. "Design a system where data scientists need low-latency feature lookups for real-time model inference, alongside the batch training pipeline."

For each, apply the framework in Section 5, and be explicit about **which pieces run in Databricks vs. native AWS services**, and why.

---

## 7. Key Takeaways for DataOps

- Know the AWS service landscape well enough to have an informed opinion on Databricks-vs-native tradeoffs — interviewers are testing judgment, not memorization.
- Always frame answers around the **non-functional requirements framework** — it signals structured, senior-level thinking.
- Tie back to networking fundamentals (VPC, PrivateLink, security groups) from the companion networking notes — this is where the two skill sets visibly intersect in an interview.
- Cost and operational ownership boundaries (who manages what) are just as important as raw technical capability when justifying a design choice.
