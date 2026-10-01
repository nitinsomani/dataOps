# Phase 21: Linux, Shell Scripting & Git Fundamentals — Interview Q&A

> Ordered basic → advanced. ⭐ = Frequently asked.

---

## Q1. ⭐ What does `set -euo pipefail` do at the top of a bash script, and why should it be a default habit?

**Answer:**
`-e` causes the script to exit immediately if any command returns a non-zero (failure) exit code, instead of silently continuing to the next line. `-u` treats any reference to an unset variable as an error rather than silently substituting an empty string — catching typos in variable names early. `-o pipefail` makes a pipeline (`cmd1 | cmd2`) fail if *any* command in the chain fails, not just the last one — without it, a failing first command in a pipe can be masked by a successful second command. Together, these turn a script from "fails silently and continues in an unknown state" into "fails loudly and immediately" — critical for scripts run unattended in CI/CD pipelines or Databricks cluster init scripts, where a silent partial failure can be far more damaging than an obvious early exit.

---

## Q2. ⭐ Explain the difference between `git merge` and `git rebase`, and when would you avoid rebasing?

**Answer:**
`git merge` combines two branches by creating a new merge commit with two parents, preserving the exact history of both branches (including all the individual commits as they happened). `git rebase` instead replays your branch's commits on top of the target branch one by one, producing a linear history — but this **rewrites commit hashes**, since each replayed commit is technically a new commit object even if the content is similar. The critical rule: never rebase commits that have already been pushed and are potentially in use by others — if you rebase and force-push a shared branch, everyone else's local branch history (built on the old, now-nonexistent commit hashes) breaks, causing confusing merge conflicts and potentially lost work for collaborators. Rebasing is safe and often preferred for your own local, not-yet-pushed feature branch commits to keep history clean before opening a PR.

---

## Q3. What's the difference between `git reset` and `git revert`, and which is safer for a commit that's already been pushed to a shared branch?

**Answer:**
`git reset` moves the branch pointer backward (optionally discarding — `--hard` — or keeping — `--soft` — the changes from the undone commits), effectively rewriting history as if those commits never happened. `git revert` instead creates a **new** commit that applies the inverse of a previous commit's changes, leaving the original commit still present in history. For a commit already pushed to a shared branch (main, a shared feature branch others have pulled), `git revert` is the safe choice — it doesn't rewrite any existing history, so it doesn't break anyone else's local repository state. `git reset` on a shared branch (especially followed by a force-push) is dangerous for the same reason rebasing shared history is dangerous.

---

## Q4. If a secret (like an API key) gets accidentally committed to a Git repository, what's the correct remediation?

**Answer:**
The most important step is **rotating the leaked credential immediately** — treating it as compromised regardless of what happens to the Git history, since the secret existed in a commit that may have already been pushed, cloned, or cached elsewhere, and simply deleting the file in a new commit leaves it fully recoverable from history. After rotation, if the repository's history needs cleaning (e.g., for compliance or to stop the secret from appearing in future clones), tools like `git filter-repo` (or BFG Repo-Cleaner) can purge the secret from all historical commits, followed by a force-push and requiring all collaborators to re-clone — but this history-scrubbing step is secondary to, and doesn't substitute for, actually rotating the credential.

---

## Q5. Why does cron syntax matter for a Databricks DataOps role, given Databricks has its own scheduling UI?

**Answer:**
Databricks Job schedules use standard cron syntax under the hood (visible directly when configuring a schedule, or when defining it programmatically in a Databricks Asset Bundle YAML) — so understanding cron (`minute hour day month day-of-week`) is directly transferable knowledge, not a separate skill. It also matters because DataOps work regularly involves scheduling things *outside* Databricks Jobs entirely — cron-based Linux automation for auxiliary scripts, or cron expressions in Airflow DAGs (Phase 20) — so fluency here pays off across multiple tools rather than being narrowly scoped to one system's UI.

---

## Q6. What branching strategy would you recommend for a data engineering team practicing the CI/CD pipeline described in Phase 10 (auto-deploy to staging on merge, manual approval to prod)?

**Answer:**
I'd recommend a **trunk-based or GitHub Flow** style strategy: short-lived feature branches, frequent small PRs merged into `main`, with the CI/CD pipeline automatically deploying every merge to `main` into staging and gating production behind manual approval. This pairs naturally with the fast-moving, frequently-deployed nature of a well-automated CI/CD pipeline — long-lived Git Flow-style `develop`/`release` branches add process overhead that doesn't buy much once automated testing and staged deployment already provide safety, and they tend to accumulate large, risky merges rather than small, easily-reviewable, easily-rolled-back changes.

---

## Q7. How would you debug a Databricks cluster that fails to start due to an init script error?

**Answer:**
I'd check the cluster's **Event Log** in the Databricks UI first, which typically surfaces init script failure at a high level, then look at the actual init script logs (written to a configured location, often DBFS/Volumes, e.g. `/databricks/init_scripts/`) for the specific stderr/stdout output of the failing command. Since init scripts run as root on every node at startup, a common root cause is a `pip install` failing due to network/firewall restrictions (tying to Phase 7's network isolation) or a typo in a package version — this is exactly why defensive scripting (`set -euo pipefail`, explicit logging of each step with `echo`) in the init script itself makes this debugging dramatically faster, since a script without it might fail on an early line but continue executing (or fail with no useful log output pinpointing which command actually broke).
