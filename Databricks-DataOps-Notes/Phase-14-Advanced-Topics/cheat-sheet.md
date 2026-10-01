# Phase 14: Advanced Topics — Multi-Cloud, DR & Federation — Cheat Sheet

---

## DR Vocabulary

```
RPO = max acceptable data loss (time)
RTO = max acceptable downtime
Active-Passive → standby region idle until failover (most common for data platforms)
Active-Active  → both regions serving, rare for batch/near-real-time data platforms
```

## Logical vs Physical Recovery

```
Logical (bad deploy/bad data)  → Delta time travel / RESTORE TABLE
Physical (region outage)        → cross-region storage replication + IaC workspace rebuild
```

## Lakehouse Federation Skeleton

```sql
CREATE CONNECTION conn TYPE postgresql OPTIONS (host '...', user '...', password secret(...));
CREATE FOREIGN CATALOG fc USING CONNECTION conn OPTIONS (database 'db');
SELECT * FROM fc.public.orders;   -- live query, no ETL/copy
```

## Delta Sharing Modes

```
Databricks-to-Databricks  → simple, uses UC identities directly
Open Sharing               → bearer-token .share credential file, works for non-Databricks recipients
```

## Multi-Cloud Bridges

```
Same cloud, different region  → cross-region replication + secondary metastore/workspace
Different cloud entirely       → Delta Sharing, or cross-cloud object storage replication
```

## Data Mesh Mapping to Unity Catalog

```
Domain team → owns a catalog (catalog-per-domain)
Data product → governed table/view with clear ownership + SLA
Cross-domain access → UC grants or Delta Sharing, not central team gatekeeping
```

## Enterprise Scale Governance

```
Chargeback/showback  → tags + system.billing.usage
Policy as code        → Terraform-managed cluster policies, UC grants, network config
                          applied consistently across all workspaces
```

## Emerging Patterns

```
Vector Search    → UC-governed vector indexes for RAG, incremental via Delta CDF
Genie             → natural language querying, bounded by UC permission model
Serverless GPU     → GenAI/LLM workloads alongside traditional Spark ETL
```
