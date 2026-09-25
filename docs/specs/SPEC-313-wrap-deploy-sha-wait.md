# SPEC-313: wrap deploy-wait blocks on a SHA's push-deploy check runs

**Status:** VALIDATED (the change lands in the same PR)
Lane: full
Type: spec-feature
**Proof:** `docs/verification/wrap-deploy-sha-wait.md`; `tests/test-wrap.sh`, the deploy-wait block.

## Problem

`/kit:wrap` step 4 (deploy check) knows one deploy shape: a `workflow_dispatch` run whose `headSha` must equal the merge SHA. Some repos deploy on push instead. GitHub then carries the deploy as a check run on the merge commit, for example Cloudflare `Workers Builds: <name>`. Step 4 has no verb for that shape. In one session the operator polled `gh api repos/<o>/<r>/commits/<sha>/check-runs` by hand in a loop, twice, before the report could say `DEPLOYED`.

## Contract

`bin/wrap deploy-wait <owner>/<name> <sha> [--check <name-substring>]... [--timeout <secs>]`

- `<owner>/<name>` matches `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`, and neither half may be `.` or `..`, so the slug cannot rewrite the API path. `<sha>` is 7 to 40 hex characters. A missing or malformed argument, an empty `--check`, an unknown flag, or a non-numeric `--timeout` exits 64 with a usage line.
- `--check` is repeatable. The verb keeps a check run when its name contains any `--check` value (case-sensitive, passed to jq with `--arg`). Without `--check`, every check run on the SHA counts.
- `--timeout` bounds the wait in seconds. Default 600.
- The verb reads `gh api --paginate repos/<slug>/commits/<sha>/check-runs?per_page=100` every 10 seconds. For each check name it keeps only the run with the highest `id`, so a rerun supersedes the run it replaced.
- The wait ends when at least one run is kept, every `--check` value matches at least one kept run, and every kept run reads `status == completed`. A repo that deploys several Workers passes one `--check` per Worker, so the first finished Worker cannot end the wait.
- On exit it prints one line per kept run, `<conclusion> <name>`, sorted by name. A run still open at the timeout prints its status in place of a conclusion.
- Exit codes:

| Exit | When | Last line |
|---|---|---|
| 0 | every kept run concluded `success` | `DEPLOYED <sha7>: N checks succeeded` |
| 1 | every kept run completed, and one or more concluded anything but `success` | `FAILED <sha7>: <name>, <name>` |
| 2 | gh missing or unauthenticated, or a read failed with a non-transient error | `ERROR <sha7>: <reason>` |
| 124 | the timeout elapsed before the wait ended | `TIMEOUT <sha7> after <N>s: open: <names>`, `no matching check run appeared[ for: <values>]`, or `no successful read of the check runs` |
| 64 | usage error | usage line |

- The verb captures gh's stdout and stderr apart. It judges stdout only when gh exits 0, because a failed later page still leaves the earlier pages on stdout. On a failure it matches the error text against `_gh_merge_transient`. A transient error counts as one pending poll, and the verb retries at the next poll.
- The verb writes nothing. It reads GitHub and prints.
- `commands/wrap.md` step 4 names the verb for a push-deploy repo. The report claims `DEPLOYED` only after it exits 0. Step 4 passes `--check` with the deploy check's name, so an early CI run that completes first cannot end the wait before the deploy check registers.

## Picture

```
 /kit:wrap step 4 (push-deploy repo)
          |
          v
 bin/wrap deploy-wait <slug> <sha> --check "Workers Builds"
          |
          v
 lib/wrap/wrap.sh cmd_deploy_wait ------ every 10s ------> gh api .../commits/<sha>/check-runs
          |                                                        |
          |<------------- check_runs[] (all pages) -----------------+
          v
   filter by --check, keep the highest id per name
          |
          v
   all completed? --no--> waited >= timeout? --no--> sleep 10, poll again
          |                       |
         yes                     yes --> exit 124 TIMEOUT
          |
          v
   all success? --yes--> exit 0 DEPLOYED  (step 4 may claim DEPLOYED)
          |
          no --> exit 1 FAILED <names>
```

## Design

Design-bearing: a new verb with a bounded polling loop and an external read (the GitHub check-runs API).

State of one run of the verb:

```
            +---------+   read ok, >=1 match,       +-----------+
  start --> | POLLING | --- all completed ---------> | JUDGED    | --> exit 0 or 1
            +---------+                             +-----------+
              |  ^   |
              |  |   +-- non-transient read error --> exit 2
              |  |
              |  +---- read ok but no match / some open,
              |        or transient read error; sleep 10
              |
              +-- waited >= timeout --> exit 124
```

Chosen approach: poll the commit's check-runs endpoint through `gh api`, slurp every page with `jq -s`, and judge with one `jq` program. This reuses what `wrap.sh` already has: `_gh_state` for the gh preflight, `_gh_merge_transient` for the retry whitelist, and the waited-counter pattern of `_pr_detail_settled`, whose bound the tests shrink by placing a no-op `sleep` first on PATH.

Approaches considered:

| Approach | Why not |
|---|---|
| `gh run watch` | It watches Actions workflow runs only. A Workers Builds check run is a third-party check run with no Actions run behind it. |
| `gh pr checks --watch` | It needs a PR. The merge commit on the default branch has none, and its check runs are the deploy. |
| Combined status API (`commits/<sha>/status`) | It reads commit statuses, not check runs. Workers Builds reports as a check run. |
| Fail fast on the first failed check | The brief asks for every matching run to complete first. A fast fail would also hide the conclusions of the runs still open. |

Latest per name by `id`, not by timestamp: GitHub assigns check-run ids in increasing order, and a rerun gets a new id. An open rerun has no `completed_at`, so a timestamp sort needs a fallback chain. PR #760 fixed the same stale-rerun bug in `_pr_gate` for the rollup shape.

Only `success` passes. `_pr_gate` also passes `skipped` for a merge gate. A skipped deploy check means nothing deployed, so it fails here.

## Failure modes

| Class | Detection | Mitigation |
|---|---|---|
| Deploy check not registered yet | zero runs match `--check` | keep polling; exit 124 names `no matching check run appeared` |
| CI finishes before the deploy registers (no `--check`) | none inside the verb | step 4 always passes `--check` |
| One Worker of several finishes before another registers | a `--check` value with no kept run | step 4 passes one `--check` per deploy check; the wait lasts until each value matches |
| A later page fails after earlier pages printed | gh non-zero | stdout is discarded on a failure; the error text alone is classified |
| Every read fails transiently until the timeout | zero good reads | exit 124 names `no successful read of the check runs` |
| Rerun leaves a stale failed run | two runs share one name | keep the highest id per name |
| GitHub 5xx or rate limit | gh non-zero, text on the transient whitelist | counts as a pending poll |
| Wrong slug or SHA (404, 422) | gh non-zero, text off the whitelist | exit 2 at once, first error line printed |
| gh missing or logged out | `_gh_state` | exit 2 at once |
| Deploy hangs | timeout | exit 124 with the pending names |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: the verb | `lib/wrap/wrap.sh`, `bin/wrap` | the Contract above; `wrap --help` names `deploy-wait` |
| T2: tests | `tests/test-wrap.sh` | every row of the Test plan passes with gh stubbed |
| T3: docs | `commands/wrap.md`, `docs/consumer-contract.md`, `docs/CHANGELOG.md` | step 4 names the verb and the exit-0 rule for `DEPLOYED`; its `nothing to check here` sentence is rewritten to cover the push-deploy shape |

## Test plan

| Case | Setup (gh stubbed) | Expected |
|---|---|---|
| All success | two runs, both completed success | exit 0, one `success <name>` line each, `DEPLOYED` |
| One failure | one success, one failure | exit 1, `FAILED` names the failed run only |
| Pending then success | first read in_progress, second read completed success | exit 0 after two reads |
| Timeout | always in_progress, `--timeout 20` | exit 124, `TIMEOUT` names the pending run |
| No match then timeout | runs exist, none match `--check` | exit 124, `no matching check run appeared` |
| `--check` filter | a failed CI run and a successful `Workers Builds: x` | `--check "Workers Builds"` exits 0 and never names the CI run |
| Rerun supersedes | same name, id 1 failure, id 2 success | exit 0 |
| Second page | the failed deploy run sits on page two | exit 1 naming it |
| Partial pages on a failed read | read 1 prints page one then fails 502; read 2 is complete with a failure | exit 1 from read 2, two reads |
| Skipped | the deploy run concluded `skipped` | exit 1 naming it |
| Repeated `--check` | one value matches, the other never does | exit 124 naming the unmatched value; both matched and green exits 0 |
| Outage | every read 503 | exit 124, `no successful read` |
| gh logged out | `gh auth status` fails | exit 2, no read |
| Non-transient read error | gh exits 1 with `HTTP 422` | exit 2, `ERROR` |
| Transient read error | first read `HTTP 502`, second read success | exit 0 |
| Usage | no args, a bad slug, a `.` or `..` slug half, a bad sha, `--timeout abc`, an unknown flag | exit 64, no read |

Negative control: `lib/gate/negctl.sh` mutates the success test in `cmd_deploy_wait` so a failed conclusion passes. The suite must go red.

## Verification

`bash tests/test-wrap.sh` exits 0. `bash tests/run-all.sh --changed` exits 0.

## After state

For a push-deploy repo, `/kit:wrap` step 4 runs `bin/wrap deploy-wait <slug> <merge-sha> --check "<deploy check name>"` and claims `DEPLOYED` only on exit 0. Nobody polls check runs by hand.

Not covered: a repo that deploys through a commit status instead of a check run; the verb reads check runs only. The timeout counts wall time or summed poll sleeps, whichever is larger, so a slow `gh` call cannot stretch it; a value that is not a multiple of the poll rounds up to the next poll, and a hung `gh api` call has no bound of its own. Knowing a repo's deploy check name stays with the operator or the repo's own docs.

## Decision Log

- Slug argument, not a local checkout path: the hand loop it replaces takes `repos/<o>/<r>`, and a local path adds an origin-URL parse the verb does not need.
- No env knob for the poll interval: a constant 10s. The tests bypass the wait with a no-op `sleep`.
- Validation (six lenses, APPROVED, design record PASS) raised six warnings, all folded in: repeatable `--check` for a multi-Worker repo; tests for a second page, `skipped`, and gh logged out; stdout and stderr captured apart; a distinct timeout line when no read succeeded; `.` and `..` slug halves refused; step 4's `nothing to check here` sentence rewritten rather than appended to.
- Review (security, architecture, test-coverage, advisor lenses) found one MEDIUM: step 4 did not say the wait can outlast a tool call's time limit. Fixed in the step text. Also fixed: the transient check reads gh's stderr only, a newline in the slug or sha is refused, a trap removes the temp file on a kill, step 4 names how to find the deploy check name and how to report exit 2. Kept: the sleep-counted timeout, recorded under Not covered.
- The endpoint's default `filter=latest` already returns the newest run per name. The highest-id dedupe stays as a second defence for an open rerun. Do not add `filter=all` without a reason.
