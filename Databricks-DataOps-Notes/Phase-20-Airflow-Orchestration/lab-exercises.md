# Phase 20: Apache Airflow & External Orchestration — Lab Exercises

> Requires a local Airflow install (`pip install apache-airflow` + `apache-airflow-providers-databricks`) or the Astro CLI / Docker Compose quickstart.

---

## Lab 1: Your First DAG

```python
# dags/lab20_hello_dag.py
from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime

def say_hello():
    print("Hello from Airflow!")

with DAG(
    dag_id="lab20_hello_dag",
    schedule="@daily",
    start_date=datetime(2026, 9, 1),
    catchup=False,
) as dag:
    hello_task = PythonOperator(task_id="say_hello", python_callable=say_hello)
```

### Questions to Answer
- [ ] After placing this in your `dags/` folder, how long does it take to appear in the Airflow UI?
- [ ] Trigger it manually from the UI — where do you find the task's logs?

---

## Lab 2: Build a Multi-Task DAG with Dependencies

```python
from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime

def extract(**context):
    context["ti"].xcom_push(key="row_count", value=42)

def transform(**context):
    count = context["ti"].xcom_pull(task_ids="extract", key="row_count")
    print(f"Transforming {count} rows")

def load(**context):
    print("Loading transformed data")

with DAG("lab20_etl_dag", schedule="@daily", start_date=datetime(2026, 9, 1), catchup=False) as dag:
    extract_task = PythonOperator(task_id="extract", python_callable=extract)
    transform_task = PythonOperator(task_id="transform", python_callable=transform)
    load_task = PythonOperator(task_id="load", python_callable=load)

    extract_task >> transform_task >> load_task
```

### Questions to Answer
- [ ] View the Graph view — does it correctly show the linear dependency chain?
- [ ] Check the `transform` task's logs — did it correctly receive `row_count=42` via XCom?

---

## Lab 3: Connect Airflow to Databricks

```bash
# Set up the connection (via CLI, or Admin -> Connections in the UI)
airflow connections add 'databricks_default' \
  --conn-type 'databricks' \
  --conn-host 'https://<your-workspace>.cloud.databricks.com' \
  --conn-password '<service-principal-oauth-token>'
```

```python
from airflow import DAG
from airflow.providers.databricks.operators.databricks import DatabricksRunNowOperator
from datetime import datetime

with DAG("lab20_databricks_dag", schedule=None, start_date=datetime(2026, 9, 1), catchup=False) as dag:
    trigger_job = DatabricksRunNowOperator(
        task_id="trigger_existing_job",
        databricks_conn_id="databricks_default",
        job_id=123456,   # replace with a real job ID from your workspace
    )
```

### Questions to Answer
- [ ] Trigger this DAG manually — does the Airflow task correctly show as "running" while the Databricks job executes, then reflect success/failure?
- [ ] What authentication method did you use, and why is a service principal OAuth token preferred over a personal access token (tie back to Phase 7)?

---

## Lab 4: Sensors — Wait for a File

```python
from airflow.sensors.filesystem import FileSensor
from airflow.operators.python import PythonOperator
from airflow import DAG
from datetime import datetime

def process_file():
    print("Processing the file now that it exists")

with DAG("lab20_sensor_dag", schedule=None, start_date=datetime(2026, 9, 1), catchup=False) as dag:
    wait_for_file = FileSensor(task_id="wait_for_file", filepath="/tmp/lab20_trigger.txt", poke_interval=10, timeout=120)
    process = PythonOperator(task_id="process_file", python_callable=process_file)
    wait_for_file >> process
```

### Questions to Answer
- [ ] Trigger the DAG, then manually create `/tmp/lab20_trigger.txt` after ~30 seconds — does `process_file` run once the file appears?
- [ ] What happens if you never create the file — does the sensor eventually time out, and what state does the task end up in?

---

## Lab 5: Simulate a Failure and Test Retries

```python
import random
from airflow.operators.python import PythonOperator
from airflow import DAG
from datetime import datetime, timedelta

def flaky_task():
    if random.random() < 0.7:
        raise ValueError("Simulated failure")
    print("Succeeded!")

with DAG(
    "lab20_retry_dag", schedule=None, start_date=datetime(2026, 9, 1), catchup=False,
    default_args={"retries": 4, "retry_delay": timedelta(seconds=10)},
) as dag:
    flaky = PythonOperator(task_id="flaky_task", python_callable=flaky_task)
```

### Questions to Answer
- [ ] Trigger this DAG a few times — how many retries did it take to eventually succeed (or exhaust all retries)?
- [ ] Check the task instance history in the UI — can you see each individual retry attempt logged separately?

---

## Lab 6: Backfill Exercise

```bash
airflow dags backfill lab20_hello_dag --start-date 2026-09-01 --end-date 2026-09-05
```

### Questions to Answer
- [ ] How many DAG runs were created by this backfill command?
- [ ] If `say_hello()` in Lab 1 wrote to a Delta table via `INSERT` instead of just printing, what would happen if you ran this same backfill twice? How would you fix it to be idempotent?
