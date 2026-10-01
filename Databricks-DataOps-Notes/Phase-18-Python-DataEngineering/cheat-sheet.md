# Phase 18: Practical Python for Data Engineering — Cheat Sheet

---

## OOP Building Blocks

```python
@dataclass
class Config:
    path: str
    fmt: str = "json"

class Base(ABC):
    @abstractmethod
    def read(self): ...
    def run(self): ...    # shared orchestration logic
```
```
@staticmethod   → no self/cls, just grouped in class namespace
@classmethod    → receives cls, common for alt constructors
instance method → receives self, needs an instance
```

## Decorator Skeleton

```python
def retry(max_attempts=3):
    def decorator(func):
        @functools.wraps(func)          # preserves __name__/__doc__
        def wrapper(*args, **kwargs):
            for attempt in range(max_attempts):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    last = e
            raise last
        return wrapper
    return decorator
```
Order: decorators apply bottom-up; innermost decorator runs first.

## Generators vs Lists

```python
(x**2 for x in range(N))   # generator expression — lazy, memory-efficient
[x**2 for x in range(N)]   # list comprehension — eager, materializes fully
```
Use `yield` for functions producing large sequences without holding it all in memory.

## Context Manager Skeleton

```python
@contextmanager
def resource_scope():
    resource = acquire()
    try:
        yield resource
    finally:
        release(resource)   # guaranteed even on exception
```

## Error Handling Rules

```
[ ] Never use bare except:
[ ] Custom exceptions carry structured context, not just a string
[ ] Use logging module, not print(), in production code
```

## pytest Essentials

```python
@pytest.fixture
def spark(): ...

@pytest.mark.parametrize("input,expected", [(1,2),(5,6)])
def test_x(input, expected): ...

with patch("module.requests.get") as mock_get:
    mock_get.return_value = MagicMock(...)
```
Use `pyspark.testing.assertDataFrameEqual` for DataFrame comparisons.

## pandas vs PySpark

| pandas | PySpark |
|--------|---------|
| Fits in memory, one machine | Too large for one machine |
| Prototyping | Production distributed pipeline |

```python
spark_df.toPandas()   # ⚠️ pulls ALL data to driver — only for small results
import pyspark.pandas as ps   # pandas API, distributed execution
```

## Packaging for Databricks

```bash
python -m build
databricks libraries install --cluster-id <id> --whl dist/pkg.whl
```
Prefer wheel/cluster-scoped libraries over ad hoc `%pip install` for production.

## Classic Gotchas

```python
def f(x, target=[]): ...          # BAD: mutable default, persists across calls
def f(x, target=None):
    target = target or []          # FIX

funcs = [lambda: i for i in range(3)]        # all return 2 (late binding)
funcs = [lambda i=i: i for i in range(3)]    # FIX: default arg binds value now
```
GIL → Python threads don't give true CPU parallelism → Spark parallelism comes from separate JVM/process executors, not threads.
