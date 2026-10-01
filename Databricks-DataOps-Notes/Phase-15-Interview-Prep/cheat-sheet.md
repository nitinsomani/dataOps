# Phase 15: Interview Preparation & Scenarios — Cheat Sheet

---

## System Design Answer Framework (memorize this order)

```
1. Clarify requirements   (volume, velocity, consumers, compliance)
2. High-level architecture (ingestion → medallion → orchestration → governance)
3. Reliability & ops       (idempotency, retries, quality gates, monitoring)
4. CI/CD & environments    (Asset Bundles/Terraform, dev/staging/prod, testing)
5. Cost & performance      (compute choice, autoscaling, partitioning, Photon)
6. Security                (network isolation, secrets, access control)
```

## 60-Second Concepts Checklist

```
[ ] Lakehouse & why it matters
[ ] Control plane vs Data plane
[ ] ACID via Delta transaction log
[ ] Medallion architecture (Bronze/Silver/Gold)
[ ] Jobs vs DLT
[ ] Unity Catalog namespace + grant hierarchy
[ ] Shuffle & why it's expensive
[ ] Photon
[ ] Asset Bundles & CI/CD flow
[ ] Watermarking
[ ] MLflow Tracking + Registry
```

## "Debug This" Quick Reference

| Symptom | Check first |
|---------|-------------|
| Job slower than usual | Skew, small files, stale stats, join strategy |
| Streaming falling behind | Input vs processing rate, watermark config |
| Table not found despite grant | USE CATALOG/USE SCHEMA missing |
| Duplicate rows on retry | Non-idempotent write, INSERT instead of MERGE |
| Cost spike | Idle all-purpose clusters, missing autotermination |
| Dashboard wrong despite success | Missing freshness/volume checks |
| Works in staging, breaks in prod | Hardcoded env values instead of bundle variables |

## Behavioral Question Themes

```
- Pipeline failure → business impact → response (detect/diagnose/fix/prevent)
- Working with non-technical stakeholders (self-service tooling, docs)
- Cost vs performance tradeoff (quantify with real numbers)
- Technical disagreement resolution (tradeoff-based reasoning)
```

## Mock Interview Loop

```
1. Pick scenario → 5 min requirements+architecture out loud
2. 15 min deep dive on 2-3 likely-probed areas
3. 3-5 rapid-fire Q&A from other phases
4. Review gaps → update notes → repeat
```
