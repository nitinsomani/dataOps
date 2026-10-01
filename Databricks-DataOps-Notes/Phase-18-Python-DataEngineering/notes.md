# Phase 18: Practical Python for Data Engineering — Detailed Notes

> **Goal**: Beyond PySpark syntax, product companies expect solid general Python engineering practices — OOP design, testing, error handling, and writing maintainable pipeline code. This phase covers the Python skills that make you look like a software engineer, not just a notebook user.

---

## 1. Why This Matters Beyond "Knowing PySpark"

Writing `df.filter(...).groupBy(...)` is necessary but not sufficient. Interviewers assessing a DataOps Engineer often probe whether you can structure pipeline code as **maintainable, testable, reusable software** — not one giant notebook. This phase is about that layer: OOP for reusable components, decorators for cross-cutting concerns (retry/logging), generators for memory efficiency, and testing discipline.

---

## 2. OOP for Pipeline Design

```python
from abc import ABC, abstractmethod
from dataclasses import dataclass

@dataclass
class IngestionConfig:
    source_path: str
    target_table: str
    file_format: str = "json"

class BaseIngestor(ABC):
    def __init__(self, config: IngestionConfig, spark):
        self.config = config
        self.spark = spark

    @abstractmethod
    def read(self):
        ...

    def write(self, df):
        df.write.format("delta").mode("append").saveAsTable(self.config.target_table)

    def run(self):
        df = self.read()
        self.write(df)

class AutoLoaderIngestor(BaseIngestor):
    def read(self):
        return (self.spark.readStream.format("cloudFiles")
                .option("cloudFiles.format", self.config.file_format)
                .load(self.config.source_path))

class JDBCIngestor(BaseIngestor):
    def read(self):
        return self.spark.read.format("jdbc").option("dbtable", self.config.source_path).load()
```

- **`@dataclass`**: auto-generates `__init__`, `__repr__`, `__eq__` for simple data-holding classes — ideal for configuration objects, reduces boilerplate significantly vs a hand-written class.
- **Abstract Base Classes (`ABC`)**: define a contract (`read()` must be implemented) that subclasses must fulfill — useful for building a family of interchangeable ingestors/transformers sharing common orchestration logic (`run()`).
- **`@staticmethod` vs `@classmethod` vs instance method**: instance methods operate on `self` (need an instance); `@classmethod` receives the class (`cls`) instead, commonly used for alternative constructors (`from_config_file(cls, path)`); `@staticmethod` needs neither — just a function logically grouped inside the class namespace.

---

## 3. Decorators — Essential for DataOps Automation

```python
import time
import functools

def retry(max_attempts=3, delay_seconds=2):
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            last_exception = None
            for attempt in range(1, max_attempts + 1):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    last_exception = e
                    print(f"Attempt {attempt} failed: {e}")
                    time.sleep(delay_seconds)
            raise last_exception
        return wrapper
    return decorator

def timed(func):
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        start = time.time()
        result = func(*args, **kwargs)
        print(f"{func.__name__} took {time.time() - start:.2f}s")
        return result
    return wrapper

@retry(max_attempts=3, delay_seconds=5)
@timed
def call_flaky_api():
    ...
```

- **`functools.wraps`**: preserves the original function's `__name__`/`__doc__` — omitting it is a common mistake that breaks introspection/debugging.
- Decorators are exactly how production DataOps code implements cross-cutting concerns (retry logic for flaky upstream APIs, execution timing for performance logging, access logging) without cluttering business logic.
- **Order matters**: decorators apply bottom-up — `@retry` wrapping `@timed` here means each retry attempt is individually timed.

---

## 4. Generators & Iterators — Memory-Efficient Processing

```python
def read_large_file_in_chunks(path, chunk_size=1000):
    with open(path) as f:
        chunk = []
        for line in f:
            chunk.append(line)
            if len(chunk) == chunk_size:
                yield chunk
                chunk = []
        if chunk:
            yield chunk

# Generator expression (memory-efficient vs a list comprehension)
squares = (x**2 for x in range(1_000_000))   # lazy, computed on demand
```

- A **generator function** (`yield`) produces values lazily, one at a time, without holding the entire result set in memory — critical when processing data too large to fit in memory on the driver (though in Spark itself, this pattern applies more to Python-side pre/post-processing than to Spark's own distributed execution).
- **Generator expressions** `(x for x in ...)` vs **list comprehensions** `[x for x in ...]`: the former is lazy/memory-efficient, the latter materializes the full list immediately — prefer generators when you don't need random access or don't need the full collection in memory simultaneously.

---

## 5. Context Managers — Resource Management

```python
from contextlib import contextmanager

@contextmanager
def spark_session_scope(app_name):
    from pyspark.sql import SparkSession
    spark = SparkSession.builder.appName(app_name).getOrCreate()
    try:
        yield spark
    finally:
        spark.stop()

with spark_session_scope("test_job") as spark:
    df = spark.range(10)
    df.show()
# spark.stop() guaranteed even if an exception occurs inside the with block
```

- The `with` statement guarantees cleanup code runs even if an exception occurs — essential for resource management (database connections, file handles, temporary Spark sessions in tests).
- `@contextmanager` is the simplest way to write one without a full class implementing `__enter__`/`__exit__`.

---

## 6. Error Handling & Custom Exceptions

```python
class DataQualityError(Exception):
    """Raised when a data quality check fails."""
    def __init__(self, message, failed_rows_count=None):
        super().__init__(message)
        self.failed_rows_count = failed_rows_count

def validate_no_nulls(df, column):
    null_count = df.filter(df[column].isNull()).count()
    if null_count > 0:
        raise DataQualityError(f"{column} has {null_count} nulls", failed_rows_count=null_count)

try:
    validate_no_nulls(df, "order_id")
except DataQualityError as e:
    logger.error(f"Quality check failed: {e}, count={e.failed_rows_count}")
    raise
```

- **Custom exceptions** carry structured context (not just a string message) — makes upstream error handling/alerting logic able to branch on specific failure types and metadata.
- **Never use bare `except:`** — always catch specific exception types; a bare except silently swallows things like `KeyboardInterrupt` and masks real bugs.
- **Logging vs printing**: use the `logging` module (with structured levels — DEBUG/INFO/WARNING/ERROR) instead of `print()` in production code — integrates properly with Databricks cluster logs and downstream log aggregation.

---

## 7. Testing with pytest

```python
import pytest
from unittest.mock import patch, MagicMock

# Fixture: reusable test setup
@pytest.fixture
def spark():
    from pyspark.sql import SparkSession
    spark = SparkSession.builder.master("local[2]").appName("test").getOrCreate()
    yield spark
    spark.stop()

def test_dedup_logic(spark):
    df = spark.createDataFrame([(1, "a"), (1, "a"), (2, "b")], ["id", "val"])
    result = df.dropDuplicates(["id"])
    assert result.count() == 2

# Parametrized tests - run the same test with multiple inputs
@pytest.mark.parametrize("input_val,expected", [(1, 2), (5, 6), (-1, 0)])
def test_add_one(input_val, expected):
    assert input_val + 1 == expected

# Mocking external dependencies
def test_api_call_with_mock():
    with patch("mymodule.requests.get") as mock_get:
        mock_get.return_value = MagicMock(status_code=200, json=lambda: {"result": "ok"})
        from mymodule import fetch_data
        result = fetch_data("http://fake-url")
        assert result["result"] == "ok"
```

- **Fixtures** (`@pytest.fixture`) provide reusable setup/teardown — e.g., a shared local `SparkSession` for all tests in a module, avoiding repeated boilerplate.
- **`@pytest.mark.parametrize`**: run the same test logic against multiple input/output pairs without duplicating test code.
- **Mocking** (`unittest.mock.patch`): replace external dependencies (API calls, database connections) with controlled fake objects — keeps unit tests fast and independent of external systems.
- For DataFrame equality assertions specifically, prefer `pyspark.testing.assertDataFrameEqual` over manual `.collect()` comparisons (handles column order/nullability nuances correctly).

---

## 8. pandas vs PySpark — When to Use Each

| Use pandas when... | Use PySpark when... |
|----------------------|------------------------|
| Data fits comfortably in memory on one machine | Data is too large for a single machine |
| Rapid prototyping/exploration on a sample | Production pipeline processing full-scale data |
| Rich single-machine ecosystem needed (matplotlib, scikit-learn direct integration) | Need distributed processing, Delta Lake integration |

```python
# Converting between them
pandas_df = spark_df.toPandas()          # pulls ALL data to driver memory - use only for small results!
spark_df = spark.createDataFrame(pandas_df)

# Pandas API on Spark (pandas-like syntax, distributed execution)
import pyspark.pandas as ps
psdf = ps.read_csv("path/to/file.csv")   # pandas-like API, but runs distributed
```

- **`toPandas()` is a common production bug source** — calling it on a large DataFrame can OOM the driver; always ensure the result is small (e.g., after aggregation) before converting.

---

## 9. Packaging & Dependency Management for Databricks

```bash
# requirements.txt for a project
pip install -r requirements.txt

# Building a wheel for a custom shared library
python -m build
databricks libraries install --cluster-id <id> --whl dist/my_lib-0.1.0-py3-none-any.whl
```

```python
# In a notebook (dev-only; avoid for production - not reproducible/version-pinned)
%pip install some-package==1.2.3
```

- Prefer **cluster-scoped libraries** or job-level dependency specs (in an Asset Bundle) over ad hoc `%pip install` in notebooks for production — ensures consistent, reproducible environments across runs.
- Structure shared transformation logic as an installable Python package (with `setup.py`/`pyproject.toml`), tested independently via pytest, then installed as a wheel dependency on job clusters — this is what makes Phase 10's unit testing pattern actually practical at scale.

---

## 10. Common Python Gotchas (Frequently Tested)

```python
# Mutable default argument — classic bug
def append_item(item, target=[]):   # BAD: target list persists across calls!
    target.append(item)
    return target

def append_item_fixed(item, target=None):
    if target is None:
        target = []
    target.append(item)
    return target

# Late-binding closures in loops
funcs = [lambda: i for i in range(3)]
print([f() for f in funcs])   # [2, 2, 2] - NOT [0, 1, 2]! all closures reference the same `i`

funcs_fixed = [lambda i=i: i for i in range(3)]  # fix: bind i as a default argument
print([f() for f in funcs_fixed])   # [0, 1, 2]
```

- **Mutable default arguments** are evaluated **once** at function definition time, not per call — a very common, subtle bug.
- **Closures capture variables by reference**, not by value — a loop building a list of lambdas/functions referencing the loop variable will have all of them see the loop variable's **final** value unless explicitly bound as a default argument.
- **GIL (Global Interpreter Lock)**: Python threads don't achieve true CPU parallelism for pure-Python code due to the GIL — this is *why* Spark's actual parallelism comes from separate JVM executor processes (or, for pure-Python UDFs, separate Python worker processes), not Python threading.

---

## 11. Key Takeaways for DataOps

- OOP (dataclasses, ABCs) turns "notebook scripts" into a **reusable pipeline framework** — a strong signal of engineering maturity.
- Decorators (retry, timing, logging) are directly applicable to production DataOps automation, not just academic Python trivia.
- Testing discipline (pytest + fixtures + mocking + `assertDataFrameEqual`) is what makes Phase 10's CI/CD testing pyramid actually implementable.
- Know the mutable-default-argument and closure-in-loop gotchas cold — both are extremely common "gotcha" interview questions.
