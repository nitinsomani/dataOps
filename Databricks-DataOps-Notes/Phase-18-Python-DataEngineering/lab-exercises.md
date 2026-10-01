# Phase 18: Practical Python for Data Engineering — Lab Exercises

> Run these in a local Python environment or a Databricks notebook (mix of plain Python and PySpark-specific labs).

---

## Lab 1: Build an Ingestor Class Hierarchy

```python
from abc import ABC, abstractmethod
from dataclasses import dataclass

@dataclass
class IngestionConfig:
    source_path: str
    target_table: str
    file_format: str = "json"

class BaseIngestor(ABC):
    def __init__(self, config: IngestionConfig):
        self.config = config

    @abstractmethod
    def read(self):
        ...

    def run(self):
        data = self.read()
        print(f"Writing {len(data)} records to {self.config.target_table}")
        return data

class MockFileIngestor(BaseIngestor):
    def read(self):
        return [{"id": 1}, {"id": 2}, {"id": 3}]
```

### Questions to Answer
- [ ] Try instantiating `BaseIngestor` directly — what error occurs, and why?
- [ ] Add a second subclass `MockAPIIngestor` that returns different mock data — confirm `run()` works unchanged for both.

---

## Lab 2: Write a Retry Decorator with Exponential Backoff

```python
import time, functools, random

def retry(max_attempts=3, base_delay=1):
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(1, max_attempts + 1):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    if attempt == max_attempts:
                        raise
                    wait = base_delay * (2 ** (attempt - 1))
                    print(f"Attempt {attempt} failed ({e}), retrying in {wait}s")
                    time.sleep(wait)
        return wrapper
    return decorator

call_count = 0
@retry(max_attempts=4, base_delay=0.5)
def flaky_function():
    global call_count
    call_count += 1
    if call_count < 3:
        raise ValueError("Simulated failure")
    return "success"

print(flaky_function())
print(f"Total attempts: {call_count}")
```

### Questions to Answer
- [ ] How many attempts did it take to succeed, and did the delay between attempts double each time?
- [ ] Modify the decorator to only retry on specific exception types (e.g., `ConnectionError`), re-raising immediately on others.

---

## Lab 3: Generators for Memory-Efficient Batch Processing

```python
def batch_generator(items, batch_size):
    batch = []
    for item in items:
        batch.append(item)
        if len(batch) == batch_size:
            yield batch
            batch = []
    if batch:
        yield batch

items = range(1, 23)
for batch in batch_generator(items, batch_size=5):
    print(f"Processing batch: {list(batch)}")
```

### Questions to Answer
- [ ] How many batches were produced for 22 items with batch_size=5, and what's in the last (partial) batch?
- [ ] Rewrite this as a list-based (non-generator) function — what's the memory tradeoff difference for a hypothetical 100-million-item input?

---

## Lab 4: Context Manager for Resource Scoping

```python
from contextlib import contextmanager

@contextmanager
def timer_scope(name):
    import time
    start = time.time()
    print(f"Starting {name}")
    try:
        yield
    finally:
        print(f"{name} took {time.time() - start:.3f}s")

with timer_scope("data load"):
    import time
    time.sleep(1)
    # raise ValueError("oops")  # uncomment to test cleanup still runs
```

### Questions to Answer
- [ ] Uncomment the `raise` line — does the "took Xs" message still print despite the exception?
- [ ] Write a second context manager that manages a mock "database connection" (print "connecting"/"disconnecting").

---

## Lab 5: pytest with Fixtures, Parametrize, and Mocking

```python
# transforms.py
def clean_email(email):
    return email.strip().lower() if email else None

# test_transforms.py
import pytest
from transforms import clean_email

@pytest.mark.parametrize("input_val,expected", [
    (" Test@Example.com ", "test@example.com"),
    (None, None),
    ("ALREADY@LOWER.com", "already@lower.com"),
])
def test_clean_email(input_val, expected):
    assert clean_email(input_val) == expected
```

```bash
pip install pytest
pytest test_transforms.py -v
```

### Questions to Answer
- [ ] Do all 3 parametrized cases pass? Add a 4th case with an empty string `""` — what should the expected behavior be, and does the current implementation handle it correctly?
- [ ] Add a mocking-based test for a function that calls `requests.get()` internally, using `unittest.mock.patch`.

---

## Lab 6: Fix the Classic Gotchas

```python
# Gotcha 1: mutable default argument
def add_to_list(item, target=[]):
    target.append(item)
    return target

print(add_to_list(1))
print(add_to_list(2))   # what do you expect vs what you get?

# Gotcha 2: late-binding closures
funcs = [lambda: i for i in range(3)]
print([f() for f in funcs])   # what do you expect vs what you get?
```

### Questions to Answer
- [ ] Run both snippets — confirm the "surprising" output described in the notes.
- [ ] Fix both functions and confirm corrected behavior.

---

## Lab 7: PySpark-Specific Testing

```python
import pytest
from pyspark.sql import SparkSession
from pyspark.testing.utils import assertDataFrameEqual

@pytest.fixture(scope="module")
def spark():
    spark = SparkSession.builder.master("local[2]").appName("lab18").getOrCreate()
    yield spark
    spark.stop()

def dedup_orders(df):
    from pyspark.sql.functions import col
    return df.dropDuplicates(["order_id"]).filter(col("amount") > 0)

def test_dedup_orders(spark):
    input_df = spark.createDataFrame(
        [(1, 100.0), (1, 100.0), (2, -5.0), (3, 50.0)], ["order_id", "amount"]
    )
    result = dedup_orders(input_df)
    expected = spark.createDataFrame([(1, 100.0), (3, 50.0)], ["order_id", "amount"])
    assertDataFrameEqual(result, expected)
```

### Questions to Answer
- [ ] Run this test — does it pass? Introduce a deliberate bug in `dedup_orders` and confirm the test correctly fails.
- [ ] Why is `scope="module"` used on the fixture instead of the default per-test scope — what's the tradeoff?
