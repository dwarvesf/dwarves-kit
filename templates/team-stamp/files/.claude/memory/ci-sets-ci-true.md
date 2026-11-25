---
name: ci-sets-ci-true
description: GitHub Actions exports CI=true, so a script that branches on CI acts differently there; tests must set or clear it on purpose.
---

The runner exports `CI=true`. `scripts/pr-shape.sh` relies on it: a missing shellcheck is skipped on a laptop with a notice and is a failure when `CI=true`, so the check cannot pass silently in CI. A test that does not control `CI` gives a different answer on a laptop than on the runner.

**Why:** the same script has two modes, and only one of them runs on your machine. A green local run can hide a red CI run.

**How to apply:** a test of a CI-aware script clears the variable for the local case (`env -u CI ...`) and sets `CI=true` for the CI case. To reproduce a CI-only failure, run the script with `CI=true` on the command line.
