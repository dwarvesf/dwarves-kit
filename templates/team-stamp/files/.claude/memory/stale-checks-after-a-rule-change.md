---
name: stale-checks-after-a-rule-change
description: A PR keeps the green checks of the rules it ran under, and a close and reopen can run CI on an old merge commit, so a rule change needs a branch update.
---

CI runs a PR on its merge with the default branch at the time of the run. After a new check merged in `scripts/pr-shape.sh`, open PRs stayed green on the old rules and were one command from merging. A close and reopen ran the OLD rules again: the event carried a merge commit computed before the default branch moved. A plain re-run replays the old event too.

**Why:** a green check means the PR passed the rules of that run, not today's rules. Reopens also leave cancelled runs on the same head commit.

**How to apply:** after `scripts/pr-shape.sh` or `.github/workflows/ci.yml` changes on the default branch, update every open PR with `gh pr update-branch <n>` (a merge, no force push). Never close and reopen a PR to refresh CI: push a commit (an empty one works) for a new head and clean checks. A run's log shows its rules in the checkout line `Merge <head> into <base>`.
