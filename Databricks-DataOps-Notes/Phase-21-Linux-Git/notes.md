# Phase 21: Linux, Shell Scripting & Git Fundamentals — Detailed Notes

> **Goal**: Practical, often-assumed-but-lightly-tested skills. Technical screens frequently include a quick bash or git question, and DataOps automation (init scripts, CI/CD runners, cluster bootstrapping) runs on Linux.

---

## 1. Why This Matters for a Databricks DataOps Role

- Databricks clusters run Linux under the hood — init scripts, library installation, and debugging cluster startup issues all involve shell commands (`%sh` cells, cluster init scripts).
- CI/CD runners (GitHub Actions) execute in Linux containers — your deployment scripts are bash/shell at some level even if wrapped in YAML.
- Git is the substrate for everything in Phase 10 (Repos, Asset Bundles, CI/CD) — fluency beyond "git add/commit/push" (rebasing, resolving conflicts, branching strategy) signals engineering maturity.

---

## 2. Essential Linux Commands for DataOps Work

```bash
# File/directory navigation & inspection
ls -la                     # list all, including hidden, long format
find /path -name "*.log" -mtime -1     # files modified in the last day
grep -r "ERROR" /var/log/              # recursive search for a pattern
tail -f /var/log/app.log                # follow a log file live
du -sh /data/*                           # disk usage per subdirectory, human-readable
df -h                                     # disk free space

# Process management
ps aux | grep spark        # find running Spark processes
top / htop                  # live resource usage
kill -9 <pid>                 # force-kill a process

# Permissions
chmod +x script.sh           # make executable
chown user:group file        # change ownership

# Networking (ties to companion networking notes)
curl -v https://api.example.com
netstat -tlnp / ss -tlnp     # listening ports
```

---

## 3. Shell Scripting for Automation

```bash
#!/bin/bash
set -euo pipefail   # exit on error, undefined var, or pipe failure — always include this

SOURCE_DIR="/data/incoming"
LOG_FILE="/var/log/ingest.log"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "Source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

for file in "$SOURCE_DIR"/*.csv; do
  echo "$(date): Processing $file" >> "$LOG_FILE"
  # process the file...
done

echo "Done. Processed $(ls "$SOURCE_DIR"/*.csv | wc -l) files."
```

- **`set -euo pipefail`**: `-e` exits immediately on any command failure, `-u` treats unset variables as errors, `-o pipefail` makes a pipeline fail if *any* command in it fails (not just the last one) — the standard defensive header for production shell scripts.
- **Exit codes**: `0` = success, non-zero = failure — scripts called from CI/CD or cluster init scripts rely on this to detect failure programmatically.
- **Variables**: `"$VAR"` (always quote to handle spaces/globbing safely), `${VAR:-default}` (default value if unset).
- **Common gotcha**: unquoted variables in `if [ $VAR == "x" ]` break if `$VAR` is empty or contains spaces — always quote: `if [ "$VAR" == "x" ]`.

---

## 4. Cron Syntax (Scheduling Fundamentals)

```
* * * * *  command
│ │ │ │ │
│ │ │ │ └── day of week (0-6, Sun=0)
│ │ │ └──── month (1-12)
│ │ └────── day of month (1-31)
│ └──────── hour (0-23)
└────────── minute (0-59)

0 2 * * *        → daily at 2:00 AM
*/15 * * * *      → every 15 minutes
0 0 1 * *          → first day of every month at midnight
0 9 * * 1-5          → 9 AM on weekdays only
```
- Databricks Job schedules use this same cron syntax under the hood — directly transferable knowledge.

---

## 5. Databricks Init Scripts (Where Shell Meets Databricks)

```bash
#!/bin/bash
# Cluster-scoped init script - runs on every node at cluster startup
set -euo pipefail
pip install --index-url https://internal-pypi.company.com my-internal-lib==1.2.3
echo "Custom init script completed" >> /databricks/init_scripts/custom.log
```
- Stored in a Workspace file or Unity Catalog Volume, referenced in cluster configuration.
- Runs as root on every node — errors here can silently prevent cluster startup, so defensive scripting (`set -euo pipefail`, clear logging) is critical for debuggability.

---

## 6. Git Fundamentals Beyond Add/Commit/Push

```bash
git status
git log --oneline --graph --all     # visualize branch history

# Branching
git checkout -b feature/new-pipeline
git branch -d feature/old-branch     # delete local branch

# Merging vs Rebasing
git merge feature/new-pipeline        # creates a merge commit, preserves both histories
git rebase main                        # replays your commits on top of main, linear history

# Resolving conflicts
git status                              # shows conflicted files
# edit files to resolve <<<<<<< ======= >>>>>>> markers
git add <resolved-file>
git rebase --continue                    # or: git commit (if merging)

# Undoing things
git reset --soft HEAD~1     # undo last commit, keep changes staged
git reset --hard HEAD~1      # undo last commit, DISCARD changes (destructive!)
git revert <commit-hash>       # create a NEW commit that undoes a previous one (safe for shared branches)

# Stashing work-in-progress
git stash
git stash pop

# Cherry-picking a specific commit onto another branch
git cherry-pick <commit-hash>
```

### Merge vs Rebase (commonly asked)
```
Merge:   A---B---C (main)
              \       \
               D---E---M (feature, merged)   ← preserves exact history, extra merge commit

Rebase:  A---B---C---D'---E' (feature, rebased onto main)  ← linear history, commits rewritten (new hashes)
```
- **Never rebase commits that have already been pushed/shared** with others — rebasing rewrites commit hashes, and force-pushing a rebased shared branch breaks everyone else's local history built on the old commits.
- **`git revert` vs `git reset`**: revert is safe for shared/pushed history (adds a new undo commit); reset rewrites history (fine for local-only, unpushed commits; dangerous on shared branches).

---

## 7. Branching Strategies (Team Workflow Awareness)

| Strategy | Pattern |
|----------|---------|
| **Git Flow** | `main` (prod) + `develop` (integration) + feature/release/hotfix branches — more ceremony, common in slower-release enterprises |
| **Trunk-based development** | Short-lived feature branches merged directly into `main` frequently, feature flags for incomplete work — common in fast-shipping product companies, pairs well with CI/CD (Phase 10) |
| **GitHub Flow** | Simpler: `main` + feature branches + PR + deploy on merge — a lightweight middle ground |

- Product companies with mature CI/CD (like the GitHub Actions pipeline in Phase 10) usually lean toward **trunk-based** or **GitHub Flow** — small, frequent PRs merged to main, deployed automatically through the staging→prod pipeline, rather than long-lived Git Flow release branches.

---

## 8. .gitignore & Secrets Hygiene

```
# .gitignore for a Databricks Asset Bundle project
.databricks/
*.pyc
__pycache__/
.env
*.whl
dist/
```
- Never commit secrets/credentials — combine `.gitignore` discipline with the secret-scope practices from Phase 7.
- `git log -p | grep -i "password"` (or dedicated tools like `git-secrets`/`truffleHog`) can retroactively scan history for leaked credentials — worth knowing this is a real remediation step if a secret is ever accidentally committed (note: removing it from the latest commit isn't enough, it must be purged from history via `git filter-repo` or similar, and the credential must be rotated regardless).

---

## 9. Key Takeaways for DataOps

- `set -euo pipefail` should be reflexive in any shell script you write — it's a strong, cheap signal of production-mindedness.
- Cron syntax is directly reusable between Linux scheduling and Databricks Job schedules — one mental model, two contexts.
- Know merge vs rebase and revert vs reset well enough to explain *why* you'd choose one over the other, not just the commands.
- If a secret is ever committed, rotating the credential is mandatory regardless of whether history is scrubbed — the commit having existed at all means it must be treated as compromised.
