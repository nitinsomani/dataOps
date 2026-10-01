# Phase 16: System Design — AWS Data Platform Architecture — Lab Exercises

> Mix of hands-on AWS CLI/boto3 exercises and structured design exercises (full multi-service builds are optional/conceptual if you don't want to incur AWS costs).

---

## Lab 1: S3 as the Lakehouse Foundation

```bash
aws s3 mb s3://lab16-lakehouse-demo
aws s3api put-bucket-lifecycle-configuration --bucket lab16-lakehouse-demo --lifecycle-configuration file://lifecycle.json
```

```json
// lifecycle.json
{
  "Rules": [{
    "ID": "archive-bronze-after-90-days",
    "Filter": {"Prefix": "bronze/"},
    "Status": "Enabled",
    "Transitions": [{"Days": 90, "StorageClass": "GLACIER"}]
  }]
}
```

### Questions to Answer
- [ ] What storage class transition would you configure for Silver/Gold tables that are queried frequently vs Bronze tables rarely re-read after 90 days?
- [ ] How does S3 Intelligent-Tiering differ from manually configured lifecycle rules, and when would you prefer it?

---

## Lab 2: Set Up S3 Event Notifications for Auto Loader (File Notification Mode)

```bash
aws s3api put-bucket-notification-configuration --bucket lab16-lakehouse-demo \
  --notification-configuration file://notification.json
```

```json
// notification.json (conceptual - actual Auto Loader setup can auto-provision this)
{
  "TopicConfigurations": [{
    "TopicArn": "arn:aws:sns:us-east-1:123456789:lab16-new-file-topic",
    "Events": ["s3:ObjectCreated:*"],
    "Filter": {"Key": {"FilterRules": [{"Name": "prefix", "Value": "raw/orders/"}]}}
  }]
}
```

### Questions to Answer
- [ ] Trace the full path: S3 PUT event → SNS → SQS → Auto Loader. Why is SQS needed in addition to SNS?
- [ ] What IAM permissions does Auto Loader's managed identity need to set this up automatically versus manually?

---

## Lab 3: IAM Role for Unity Catalog Storage Credential

```bash
aws iam create-role --role-name uc-access-role --assume-role-policy-document file://trust-policy.json
aws iam put-role-policy --role-name uc-access-role --policy-name s3-access --policy-document file://s3-policy.json
```

```json
// s3-policy.json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
    "Resource": ["arn:aws:s3:::lab16-lakehouse-demo", "arn:aws:s3:::lab16-lakehouse-demo/*"]
  }]
}
```

### Questions to Answer
- [ ] What's the minimum set of S3 actions this role needs, and why should `s3:*` (wildcard) be avoided?
- [ ] Create this Storage Credential in Unity Catalog (Phase 6) referencing this role's ARN — confirm an External Location works end-to-end.

---

## Lab 4: Design Exercise — Draw the Full Architecture

**Objective**: For the prompt "Design a clickstream analytics platform supporting real-time fraud alerts and next-day BI" (Interview Q&A Q1), draw the full architecture diagram by hand or in a diagramming tool.

### Questions to Answer
- [ ] Label every component with the specific AWS/Databricks service used.
- [ ] Annotate which parts of the diagram are "always-on" (cost-continuous) vs "ephemeral" (cost only when running).
- [ ] Add a second diagram layer showing Unity Catalog governance boundaries (which catalogs/schemas, which grants).

---

## Lab 5: Cost Estimation Exercise

**Objective**: Given the multi-tenant platform design (Interview Q&A Q7), estimate a rough monthly cost breakdown.

1. Assume 3 business units, each running: 1 daily job cluster (2 hours/day, 4 workers, on-demand), 1 always-on SQL Warehouse (Serverless, auto-stop after 10 min idle) for BI.
2. Look up approximate DBU + EC2 pricing for a representative instance type in your region.
3. Estimate monthly cost per tenant, and total.

### Questions to Answer
- [ ] What's the single biggest cost lever you'd adjust first if asked to cut this estimate by 20%?
- [ ] How would S3 storage cost scale into this estimate, and what assumptions did you make about data volume?

---

## Lab 6: Step Functions Orchestrating a Databricks Job (Conceptual/API Walkthrough)

```json
{
  "Comment": "Orchestrate Databricks job after Glue crawler completes",
  "StartAt": "RunGlueCrawler",
  "States": {
    "RunGlueCrawler": {
      "Type": "Task",
      "Resource": "arn:aws:states:::glue:startCrawler.sync",
      "Parameters": {"Name": "lab16-crawler"},
      "Next": "TriggerDatabricksJob"
    },
    "TriggerDatabricksJob": {
      "Type": "Task",
      "Resource": "arn:aws:states:::http:invoke",
      "Parameters": {
        "ApiEndpoint": "https://<workspace>.cloud.databricks.com/api/2.1/jobs/run-now",
        "Method": "POST",
        "Authentication": {"ConnectionArn": "arn:aws:events:...:connection/databricks-conn"}
      },
      "End": true
    }
  }
}
```

### Questions to Answer
- [ ] Why would you choose Step Functions to coordinate this instead of a Databricks Workflow task alone?
- [ ] What authentication mechanism should the Step Functions state machine use to call the Databricks API (service principal + OAuth, tying back to Phase 7)?
