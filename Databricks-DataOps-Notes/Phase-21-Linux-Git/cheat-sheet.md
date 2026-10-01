# Phase 21: Linux, Shell Scripting & Git Fundamentals — Cheat Sheet

---

## Essential Commands

```bash
ls -la | find | grep -r | tail -f | du -sh | df -h    # inspection
ps aux | top/htop | kill -9 <pid>                        # process mgmt
chmod +x | chown user:group                                # permissions
curl -v | ss -tlnp                                            # networking
```

## Shell Script Defensive Header

```bash
#!/bin/bash
set -euo pipefail
# -e exit on error | -u error on unset var | -o pipefail fail pipeline on any stage failing
```

Always quote variables: `"$VAR"` not `$VAR`. Use `${VAR:-default}` for defaults.

## Cron Syntax

```
* * * * *   → min hour day month day-of-week
0 2 * * *    → daily 2 AM
*/15 * * * *  → every 15 min
0 9 * * 1-5    → weekdays 9 AM
```
Same syntax used by Databricks Job schedules.

## Databricks Init Scripts

```bash
#!/bin/bash
set -euo pipefail
pip install --index-url <internal-repo> my-lib==1.2.3
```
Runs as root on every node at cluster startup — errors here silently block cluster start.

## Git Commands Beyond Basics

```bash
git log --oneline --graph --all      # visualize history
git checkout -b feature/x             # new branch
git merge feature/x                    # merge commit, preserves history
git rebase main                         # linear history, rewrites commit hashes

git reset --soft HEAD~1     # undo commit, keep changes staged
git reset --hard HEAD~1      # undo commit, DISCARD changes (destructive)
git revert <hash>              # safe undo for SHARED history (new commit)

git stash / git stash pop        # shelve WIP
git cherry-pick <hash>            # apply one commit onto current branch
```

## Merge vs Rebase Rule

```
Merge  → preserves full history, extra merge commit, SAFE for shared branches
Rebase → linear history, rewrites hashes, NEVER rebase already-pushed/shared commits
```

## Reset vs Revert

```
reset  → rewrites history — fine for LOCAL unpushed commits only
revert → adds a new undo commit — SAFE for shared/pushed history
```

## Branching Strategies

```
Git Flow          → main + develop + feature/release/hotfix (enterprise, slower release)
Trunk-based         → short-lived branches, frequent merge to main + feature flags (fast CI/CD shops)
GitHub Flow           → main + feature branch + PR + deploy on merge (lightweight middle ground)
```

## Secrets Hygiene

```
[ ] .gitignore covers .env, *.whl, dist/, __pycache__/
[ ] Never commit credentials — use secret scopes (Phase 7)
[ ] If leaked: rotate the credential regardless of history scrubbing
[ ] git filter-repo / truffleHog for retroactive history scanning/purging
```
