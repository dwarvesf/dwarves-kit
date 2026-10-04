# Proof of done: `wrap deploy-wait` waits on a SHA's push-deploy check runs

2026-09-25. Spec: `docs/specs/SPEC-313-wrap-deploy-sha-wait.md`. Lane: full. Files: `lib/wrap/wrap.sh`, `bin/wrap`, `tests/test-wrap.sh`, `commands/wrap.md`, `docs/consumer-contract.md`, `docs/CHANGELOG.md`, `docs/FEATURES.md` (regenerated), this file.

Acceptance: `bin/wrap deploy-wait <owner>/<name> <sha> [--check S]... [--timeout N]` polls the commit's check runs every 10s until each `--check` value matches a run and every matching run is completed. It keeps the highest id per name, prints `<conclusion> <name>` per run, and exits 0 only when every run concluded `success`. Exit 1 names the failures, 2 is a gh or read error, 124 is the timeout, 64 is a usage error. `/kit:wrap` step 4 claims `DEPLOYED` for a push-deploy repo only after it exits 0.

`proof-gate.sh contract` classes this item `stateful` because it names a deploy. The verb itself never deploys and writes nothing but its own temp file, so the recorded run below is a read of real GitHub state, and the rollback is a revert.

## Green run

```
Command: bash tests/test-wrap.sh
Exit: 0
Output: test-wrap: all 1144 passed
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed
Exit: 0
Output: run-all: --changed against 8b173936: 9 changed files -> 18 suites (14 named, the rest always-on)
        run-all: all 18 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

`--changed` covered `test-meta` (854/854), `test-no-scattered-ids`, `test-boundary-lint`, `test-bin-forwarders` and `test-registry-freshness-guard` among the 18, and `feature-registry.sh check` reports `docs/FEATURES.md is fresh`.

## Recorded run (real GitHub, read-only)

`dwarvesf/foundation-workers` at `f68ab2b` carries five check runs: `deploy`, `store-check` and `vendored-sync` succeeded, `preview` and `test` were skipped.

```
Command: bin/wrap deploy-wait dwarvesf/foundation-workers f68ab2b77c9fca6beafafd21e82dbf580f2694da --check deploy
Output:  success deploy
         DEPLOYED f68ab2b: 1 checks succeeded
Exit: 0

Command: bin/wrap deploy-wait dwarvesf/foundation-workers f68ab2b77c9fca6beafafd21e82dbf580f2694da
Output:  success deploy
         skipped preview
         success store-check
         skipped test
         success vendored-sync
         FAILED f68ab2b: preview, test
Exit: 1

Command: bin/wrap deploy-wait dwarvesf/foundation-workers deadbeefdeadbeef --timeout 0
Output:  ERROR deadbee: gh: No commit found for SHA: deadbeefdeadbeef (HTTP 422)
Exit: 2

Command: bin/wrap deploy-wait dwarvesf/foundation-workers f68ab2b77c9fca6beafafd21e82dbf580f2694da --check "Workers Builds" --timeout 0
Output:  deploy-wait f68ab2b: no matching check run appeared for: Workers Builds, 0s of 0s   (stderr)
         TIMEOUT f68ab2b after 0s: no matching check run appeared for: Workers Builds
Exit: 124
Verdict: PASS (every exit path reached against the live API)
```

Rollback: `git revert` of the feature commit. The verb holds no state, so nothing else needs undoing.

## Test plan coverage

| SPEC-313 test-plan row | Run |
|---|---|
| All success | `all success` block, 5 assertions, including the paginated API path |
| One failure | `one failure` block, 4 assertions |
| Pending then success | `pending then success` block, 4 assertions, 3 reads |
| Timeout | `timeout` block, 4 assertions, reads at 0s, 10s, 20s |
| No match then timeout | `no match` block, 2 assertions |
| `--check` filter | `--check` block, 2 assertions |
| Rerun supersedes | `rerun` block, 2 assertions |
| Non-transient read error | `read errors` block, 4 assertions, one read only; a 404 whose partial stdout reads transient still exits 2 |
| Transient read error | `read errors` block, 2 assertions |
| Second page | `every page is read` block, 2 assertions |
| Partial pages on a failed read | `partial page set` block, 2 assertions |
| Skipped | `only success passes` block, 2 assertions |
| Repeated `--check` | `repeated --check` block, 4 assertions |
| Outage | `transient error on every read` block, 2 assertions |
| gh logged out | `gh logged out` block, 2 assertions |
| Usage | `usage` block, 8 arg sets, a newline in the slug and in the sha, an empty `--check`, a bare `--timeout`, plus a no-read assertion |
| Step 4 doc | 2 assertions on `commands/wrap.md` |

## Negative control

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh >/dev/null 2>&1
Exit: 0 (green before mutation)
Mutation: sed -i '' 's/select(.conclusion != "success")/select(.conclusion == "__never__")/' lib/wrap/wrap.sh
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation lets a failed or skipped conclusion pass. Under it the suite reports `test-wrap: 1136 passed, 8 FAILED of 1144`:

```
  FAIL deploy-wait with a failed check exits 1
  FAIL deploy-wait names the failed check
  FAIL deploy-wait never claims DEPLOYED on a failure
  FAIL deploy-wait judges a failure on the second page
  FAIL deploy-wait names the second page's failed check
  FAIL deploy-wait rereads after a failed paginated read (exit 1 from the full read)
  FAIL deploy-wait fails a skipped check
  FAIL deploy-wait names the skipped check
```

The restore left the tree clean (`git status --short` empty).

## Review

A fresh-context review ran the security, architecture, test-coverage and advisor lenses on the first commit: one MEDIUM (step 4 did not warn that the wait can outlast a tool call's time limit) and six LOW. The MEDIUM and five LOW are fixed in `fix(wrap): harden deploy-wait from review findings`; the green run and negative control above ran on that commit. The sleep-counted timeout stays, recorded in the spec's Not covered.

## Not proven

- No live run against a Cloudflare `Workers Builds: <name>` check run. The recorded run read a GitHub Actions `deploy` check run, which the API serves in the same shape.
- A run that polls across a real in-progress deploy. The pending-then-complete path is proven with a stubbed gh only.
- The timeout counts wall time or summed poll sleeps, whichever is larger. A hung `gh api` call has no bound of its own.
- A repo that reports its deploy as a commit status instead of a check run. The verb does not read statuses (spec, Not covered).
