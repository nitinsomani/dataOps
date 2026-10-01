# Phase 18: Practical Python for Data Engineering — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ How would you design a reusable class structure for a set of pipeline ingestors that read from different sources (files, JDBC, Kafka) but share common downstream logic?

**Answer:**
I'd define an abstract base class (`ABC`) with an abstract `read()` method that each subclass must implement according to its source type (`AutoLoaderIngestor.read()`, `JDBCIngestor.read()`, `KafkaIngestor.read()`), while the base class provides shared, non-abstract methods like `write()` and an orchestrating `run()` method that calls `self.read()` then `self.write(df)`. Configuration would be a `@dataclass` (auto-generates `__init__`/`__repr__`, reduces boilerplate) passed into each ingestor's constructor. This lets me add a new source type by writing just one small subclass implementing `read()`, without duplicating the shared write/orchestration logic — a clean application of the template method pattern.

---

## Q2. ⭐ Why would you write a retry decorator instead of putting a try/except loop directly inside each function that needs retry logic?

**Answer:**
A decorator separates the cross-cutting concern (retry behavior — how many attempts, how long to wait between them) from the business logic of the function itself, so the retry policy can be applied consistently across many different functions (API calls, database connections, flaky external service calls) without duplicating the same try/except/sleep loop in each one. It also makes the retry policy independently configurable and testable, and keeps the wrapped function's actual logic readable without control-flow noise. Using `functools.wraps` inside the decorator is important so the wrapped function retains its original name/docstring for introspection and debugging — otherwise stack traces and logging would show the generic `wrapper` name instead.

---

## Q3. What's the difference between a generator and a list comprehension, and when does it actually matter in a data engineering context?

**Answer:**
A list comprehension (`[x for x in ...]`) eagerly computes and stores the entire result in memory immediately. A generator (`(x for x in ...)` or a function using `yield`) lazily produces values one at a time, on demand, without ever holding the full sequence in memory simultaneously. This matters when processing a sequence too large to comfortably fit in memory, or when you only need to iterate through it once without needing random access or the full collection at once — e.g., reading and processing a very large local file line-by-line in Python-side pre/post-processing code (as opposed to Spark's own distributed DataFrame processing, which has its own separate execution/memory model not directly governed by Python generators).

---

## Q4. Explain the mutable default argument bug in Python and how you'd fix it.

**Answer:**
Default argument values in Python are evaluated **once**, at function definition time, not fresh on every call — so `def f(x, target=[])` means every call to `f` that doesn't explicitly pass `target` shares the **same** list object across calls, and any mutation (like `.append()`) persists and accumulates across unrelated calls, which is almost never the intended behavior. The standard fix is to use `None` as the default and create a fresh mutable object inside the function body: `def f(x, target=None): target = target if target is not None else []`. This is a very common real-world bug source (a function silently "remembering" state from previous unrelated calls) and a frequently-asked interview gotcha question.

---

## Q5. What's the "late binding closure" problem, and how does it show up if you're dynamically building a list of functions in a loop?

**Answer:**
Python closures capture the **variable itself** (by reference to the enclosing scope), not its value at the time the closure was created — so `funcs = [lambda: i for i in range(3)]` creates three lambdas that all reference the *same* variable `i`, and by the time any of them are actually called, the loop has finished and `i` holds its final value (2), so all three calls return 2 instead of the expected 0, 1, 2. The fix is to force early binding by capturing the current value as a default argument: `lambda i=i: i` — default argument values *are* evaluated at function-definition time (each iteration), which correctly "freezes" the value per lambda. This comes up in practice whenever building dynamic collections of callables in a loop (e.g., dynamically generating validation functions per column).

---

## Q6. Why doesn't Python's Global Interpreter Lock (GIL) prevent Spark from being genuinely parallel?

**Answer:**
The GIL prevents multiple Python **threads within a single process** from executing Python bytecode simultaneously, meaning pure Python threading doesn't give true CPU-bound parallelism. Spark sidesteps this entirely because its actual distributed parallelism comes from separate **JVM executor processes** (for the core Spark engine, written in Scala/Java) running on different nodes/cores, not from Python threads — the Python driver code just orchestrates and describes the computation, while the heavy lifting happens in the JVM. For pure-Python UDFs specifically, PySpark uses separate **Python worker processes** (not threads) precisely to avoid the GIL bottleneck, at the cost of the serialization overhead discussed in Phase 2. This is a good question to connect Python fundamentals directly back to Spark architecture knowledge.

---

## Q7. How would you unit test a PySpark transformation function that also makes an external API call for enrichment data?

**Answer:**
I'd separate the transformation logic from the API-calling code so each can be tested independently — the transformation function itself takes a DataFrame (or a plain Python value) and returns a DataFrame/value, while a separate small function handles the actual HTTP call. For testing the transformation logic, I'd use a local `SparkSession` fixture (`@pytest.fixture`) and `pyspark.testing.assertDataFrameEqual` to compare expected vs actual output given known input. For anything that depends on the API call, I'd use `unittest.mock.patch` to replace the real HTTP request with a `MagicMock` returning a controlled fake response, so the test runs fast, deterministically, and without a real network dependency — testing the integration behavior (does my code correctly parse/handle the API's response shape) separately from testing whether the real external API is reachable (which would be an integration/smoke test concern, not a unit test).

---

## Q8. What's the risk of calling `.toPandas()` in a PySpark pipeline, and when is it actually appropriate?

**Answer:**
`.toPandas()` collects the **entire** distributed DataFrame back to the driver node's memory as a single pandas DataFrame — if the DataFrame is large, this can easily exceed driver memory and crash the job with an out-of-memory error, defeating the entire point of using distributed Spark in the first place. It's appropriate only when you're confident the result is genuinely small — typically after a significant aggregation (e.g., a summary table with a few hundred rows) that you then want to hand off to a single-machine tool like matplotlib for visualization, or a scikit-learn model that expects an in-memory pandas/numpy input. As a defensive practice, I'd add an explicit row-count check or `.limit()` before calling `.toPandas()` in production code, rather than assuming the upstream logic will always keep the result small.
