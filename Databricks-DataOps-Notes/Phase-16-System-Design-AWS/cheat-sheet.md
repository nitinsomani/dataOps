# Phase 16: System Design — AWS Data Platform Architecture — Cheat Sheet

---

## AWS Service → Data Engineering Function Map

```
S3                → Lakehouse storage (Delta/Parquet files)
Glue Catalog       → legacy metastore (UC now preferred)
Glue ETL           → serverless AWS-native Spark ETL (Databricks alternative)
EMR                → managed Hadoop/Spark (Databricks competitor)
Kinesis Streams     → real-time ingestion source
Kinesis Firehose    → simple buffered stream-to-S3 delivery
MSK                 → managed Kafka
Lambda              → event-driven serverless compute
Step Functions       → workflow orchestration (multi-AWS-service pipelines)
SQS/SNS              → messaging (backs Auto Loader file notification mode)
Redshift             → data warehouse (Spectrum queries S3 directly)
Athena               → serverless ad hoc SQL over S3
DynamoDB             → NoSQL, low-latency lookups
RDS/Aurora            → OLTP source systems (CDC source)
IAM                   → underpins Storage Credentials
VPC                   → Databricks Data Plane network home
CloudWatch            → logs/monitoring (complements system tables)
KMS                    → encryption keys (CMK)
```

## Databricks vs Native AWS Decision Table

| Need | Databricks | Native AWS |
|------|------------|------------|
| Complex ETL + governance | ✅ | Glue for simple/infrequent |
| Streaming with Delta sink | ✅ Structured Streaming | Firehose for simple buffering only |
| Ad hoc rare SQL | — | ✅ Athena |
| Frequent governed BI SQL | ✅ Databricks SQL | Redshift if deep existing investment |
| Multi-service orchestration | Databricks Workflows if Databricks-only | ✅ Step Functions if spanning services |

## Non-Functional Requirements Checklist (use in every design answer)

```
[ ] Scalability   — 10x growth handling, partitioning/autoscaling
[ ] Availability   — component failure blast radius, multi-AZ
[ ] Durability     — S3 11 nines (usually a non-issue, mention briefly)
[ ] Consistency    — Delta ACID vs eventual consistency elsewhere
[ ] Latency        — batch vs near-real-time vs real-time → drives tooling choice
[ ] Cost           — storage tiering, job clusters, spot, serverless
[ ] Security/Gov   — UC grants, encryption, network isolation
```

## Architecture Diagram Template (redraw for any prompt)

```
Sources → Landing (S3) → Ingestion (Auto Loader/Streaming) →
  Bronze → Silver → Gold (Delta, Unity Catalog governed) →
  Consumption (Databricks SQL / Redshift Spectrum / Athena / Model Serving)
Orchestration: Databricks Workflows or Step Functions (if multi-service)
Network: VPC injection + VPC endpoints + PrivateLink
```

## Common Prompts to Practice

```
1. Clickstream ingestion: real-time fraud + next-day BI
2. CDC from on-prem Oracle, <5 min latency
3. Cost-optimized spiky batch ETL
4. Multi-tenant platform, isolated compute + governed sharing
5. Real-time feature lookups + batch training pipeline
```
