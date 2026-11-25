---
name: queued-run-missing-from-lists
description: A queued CI run can be missing from filtered run lists, so wait for a run by its id or by the PR's check rollup, never by a branch filter.
---

A `pull_request` run once sat `queued` for 15 minutes. The unfiltered run list showed it. The `status=queued` list and `gh run list --branch <name>` did not, so no runner saw demand and none started. Cancel and rerun fixed it. The cause was not found.

**Why:** a wait loop on a filtered list never returns, and CI looks hung while the fleet is healthy.

**How to apply:** after a push, get the run id from the unfiltered list: `gh api "repos/<owner>/<repo>/actions/runs?per_page=5"`. Then wait on that id: `gh run view <id> --json status,conclusion`. If the run stays `queued` and only the unfiltered list shows it: `gh run cancel <id>`, wait for `completed`, then `gh run rerun <id>`. Do not claim CI is green from a list that may be missing the run. `scripts/pr-merge.sh --wait <number>` reads the PR's own check rollup and never merges on a pending check.
