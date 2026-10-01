# Phase 21: Linux, Shell Scripting & Git Fundamentals — Lab Exercises

> Run in a Linux terminal, WSL, or a Databricks `%sh` notebook cell where noted.

---

## Lab 1: Essential Command Practice

```bash
mkdir -p /tmp/lab21/{raw,processed,logs}
touch /tmp/lab21/raw/file1.csv /tmp/lab21/raw/file2.json

find /tmp/lab21 -name "*.csv"
du -sh /tmp/lab21/*
ls -la /tmp/lab21/raw
```

### Questions to Answer
- [ ] What does the `-p` flag do in `mkdir -p /tmp/lab21/{raw,processed,logs}` (hint: brace expansion + parent directory creation)?
- [ ] Modify the `find` command to also match files modified in the last hour (`-mmin -60`).

---

## Lab 2: Write a Defensive Ingestion Shell Script

```bash
#!/bin/bash
set -euo pipefail

SOURCE_DIR="/tmp/lab21/raw"
PROCESSED_DIR="/tmp/lab21/processed"
LOG_FILE="/tmp/lab21/logs/ingest.log"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "ERROR: source directory not found" >&2
  exit 1
fi

file_count=0
for file in "$SOURCE_DIR"/*; do
  [ -e "$file" ] || continue
  echo "$(date '+%Y-%m-%d %H:%M:%S'): Processing $(basename "$file")" >> "$LOG_FILE"
  cp "$file" "$PROCESSED_DIR/"
  file_count=$((file_count + 1))
done

echo "Processed $file_count files."
```

### Questions to Answer
- [ ] Run this script twice — is it idempotent (safe to run again without unwanted side effects)? What would make it NOT idempotent?
- [ ] Deliberately break it (remove `set -euo pipefail`, introduce an unset variable reference) — observe how the failure mode changes.

---

## Lab 3: Cron Syntax Practice

Write the cron expression for each:
1. Every day at 6:30 AM
2. Every Monday at 9 AM
3. Every 10 minutes
4. The last day of scheduling flexibility: first day of each quarter at midnight (Jan 1, Apr 1, Jul 1, Oct 1)

### Questions to Answer
- [ ] Write out all 4 cron expressions.
- [ ] Cross-check expression #4 against a cron syntax validator or Databricks Job schedule UI — does standard 5-field cron support quarterly scheduling directly, or does it require `0 0 1 1,4,7,10 *`?

---

## Lab 4: Git Merge vs Rebase Hands-On

```bash
mkdir /tmp/lab21_git && cd /tmp/lab21_git
git init
echo "line1" > file.txt && git add . && git commit -m "initial commit"

git checkout -b feature
echo "line2" >> file.txt && git add . && git commit -m "feature commit"

git checkout main
echo "line3 on main" >> file.txt && git add . && git commit -m "main commit"

git checkout feature
git rebase main    # observe conflict or clean rebase depending on changes
```

### Questions to Answer
- [ ] Did the rebase produce a conflict? If so, resolve it and run `git rebase --continue`.
- [ ] Reset your test repo and redo this using `git merge main` from the `feature` branch instead — compare the resulting `git log --oneline --graph` output between the two approaches.

---

## Lab 5: Practice Reset vs Revert

```bash
cd /tmp/lab21_git
echo "oops bad change" >> file.txt && git add . && git commit -m "bad commit"

# Scenario A: this commit is only local, not pushed
git reset --hard HEAD~1
git log --oneline

# Redo the bad commit
echo "oops bad change again" >> file.txt && git add . && git commit -m "bad commit again"

# Scenario B: pretend this commit was already pushed/shared
git revert HEAD --no-edit
git log --oneline
```

### Questions to Answer
- [ ] After the `reset --hard`, does the bad commit still appear in `git log`?
- [ ] After the `revert`, does the bad commit still appear in `git log`? What's different about how the "undo" is represented?

---

## Lab 6: Simulate and Remediate a Leaked Secret

```bash
cd /tmp/lab21_git
echo "API_KEY=sk-fake-1234567890" > .env
git add .env && git commit -m "oops committed a secret"
```

### Questions to Answer
- [ ] Write out the full remediation checklist you would follow (rotation + history cleanup), referencing Phase 7's secret scope practices.
- [ ] Research `git filter-repo` (or find it already installed) — what command would purge `.env` from this repo's entire history?

---

## Lab 7: Databricks Init Script Debugging Simulation

```bash
#!/bin/bash
# init_script.sh - deliberately broken
set -euo pipefail
pip install some-package-that-does-not-exist-xyz123
echo "This line should not be reached if the above fails"
```

### Questions to Answer
- [ ] Run this script locally — confirm it exits before the final `echo` due to `set -e`.
- [ ] Rewrite it with proper logging (`echo` before/after each risky command) so that if deployed as a real Databricks init script, the failure point would be immediately obvious from the init script log file.
