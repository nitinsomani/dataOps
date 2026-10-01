# Phase 1: Databricks & Lakehouse Fundamentals — Lab Exercises

> Hands-on exercises. Use a **Databricks Community Edition** account (free) or a trial workspace on AWS/Azure/GCP.

---

## Lab 1: Create Your First Workspace & Cluster

**Objective**: Get comfortable with workspace navigation and cluster creation.

1. Sign up at `community.cloud.databricks.com` (free tier) or use a trial workspace.
2. Navigate to **Compute** → **Create Cluster**.
3. Configure:
   - Single node (for lab purposes)
   - Databricks Runtime: pick the latest **LTS** version
   - Enable autotermination at 30 minutes

### Questions to Answer
- [ ] What Databricks Runtime version did you select, and is it LTS?
- [ ] What VM instance type was provisioned?
- [ ] Where in the UI do you see the DBU/hour rate for this cluster?

---

## Lab 2: Explore the Workspace Filesystem

**Objective**: Understand DBFS and workspace file organization.

```python
# In a notebook cell
%fs ls /
%fs ls /databricks-datasets     # Databricks' built-in sample datasets

# Using dbutils
dbutils.fs.ls("/databricks-datasets/nyctaxi")
display(dbutils.fs.ls("/databricks-datasets/samples"))
```

```python
# Explore a sample dataset
df = spark.read.csv("/databricks-datasets/samples/population-vs-price/data_geo.csv", header=True, inferSchema=True)
display(df)
df.printSchema()
```

### Questions to Answer
- [ ] List 3 built-in sample datasets you found under `/databricks-datasets`.
- [ ] What's the difference between `%fs` magic command and `dbutils.fs`?

---

## Lab 3: Multi-Language Notebook

**Objective**: Practice switching languages within one notebook.

```python
# Cell 1 (Python)
df = spark.read.csv("/databricks-datasets/samples/population-vs-price/data_geo.csv", header=True, inferSchema=True)
df.createOrReplaceTempView("population_data")
```

```sql
-- Cell 2 (SQL)
%sql
SELECT `State Code`, `2014 Population estimate`
FROM population_data
ORDER BY `2014 Population estimate` DESC
LIMIT 10
```

```python
# Cell 3 (Shell)
%sh
echo "Cluster driver node info:"
hostname
nproc
```

### Questions to Answer
- [ ] What magic commands did you use to switch languages?
- [ ] Can a SQL cell reference a Python DataFrame directly, or does it need a temp view first?

---

## Lab 4: Cluster Cost Awareness Exercise

**Objective**: Understand cost implications of cluster configuration choices.

1. Go to **Compute** → your cluster → **Configuration**.
2. Note the "Summary" section showing estimated DBU/hour.
3. Toggle **Photon acceleration** on/off and observe the DBU rate change.
4. Change worker count and observe how total DBU/hour scales.

### Questions to Answer
- [ ] How much did enabling Photon change the estimated DBU rate?
- [ ] If you scaled from 2 to 4 workers, did DBU/hour roughly double?
- [ ] Where would you configure autotermination, and why is it critical in production?

---

## Lab 5: Identify Control Plane vs Data Plane Artifacts

**Objective**: Reinforce the architecture concept practically.

1. In your cloud account (AWS/Azure), locate the resource group / VPC that Databricks created (if you have console access on a trial account).
2. Identify: EC2 instances (or Azure VMs) — these are Data Plane.
3. Compare with the Databricks workspace UI (notebooks, job list) — this is Control Plane.

### Questions to Answer
- [ ] Which cloud-native resources (VMs, storage buckets) belong to the Data Plane?
- [ ] Where does your notebook *source code* live — control plane or data plane?
- [ ] Where does the actual query execution and data processing happen?
