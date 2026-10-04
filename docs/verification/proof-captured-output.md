# Verification -- proof-captured-output

A proof of done now has to carry what its run printed. The ship-gate refuses a typed `Exit: 0` / `Verdict: PASS`, `wrap land` puts the proof in the PR body, and a merged land ends on a `PROOF OF DONE` block. Spec: `docs/specs/SPEC-384-proof-captured-output.md`.

## Green run: the gate, the producers, the body builder

Command: `bash tests/test-proof-captured-output.sh`
Exit: 0
Output (tail):
```
PASS body opens with the one-line summary
PASS body carries the '## Proof of done' section
PASS body carries the captured output
PASS a relative image link is pinned to the head sha
PASS a dangling image link is left as written
PASS the PROOF OF DONE block names the file, the PR and the output
PASS a long proof is cut under the body limit with a pointer to the file (40154 chars)
PASS a cut inside a fence closes the fence before the pointer
PASS no proof file on the branch builds no body
PASS no proof file on the branch prints no block

test-proof-captured-output: all 44 passed
```
Verdict: PASS

## Green run: `wrap land` end to end against the gh stub

Command: `LAND_CACHE=0 LAND_ONLY=proofbody bash tests/test-wrap-land.sh`
Exit: 0
Output (tail):
```
test-wrap-land: LAND_ONLY='proofbody' selected 1 of 11 sections
test-wrap-land: 1 sections, 1 ran, 0 cached (0 checks credited)
test-wrap-land: all 23 passed
```
Verdict: PASS

## Green run: the existing gate suites, fixtures updated to carry output

Command: `CLAUDE_PLUGIN_ROOT=$PWD bash tests/test-hooks.sh; bash tests/test-proof-negctl.sh; bash tests/test-proof-verdict-hint.sh; bash tests/test-proof-visual-evidence.sh; bash tests/test-ship-gate-profiles.sh`
Exit: 0
Output (tail):
```
Passed: 826 / 826
test-proof-negctl: all 39 passed
ALL PASS (10/10)
ALL PASS (4/4)
ALL PASS (3 profiles x allow+block)
```
Verdict: PASS

## What the operator sees: the refusal for a typed-only proof

A throwaway repo, a behavioral diff, and a proof file holding `Command:`, `Exit: 0`, `Verdict: PASS` and nothing the run printed.

Command: `bash lib/gate/proof-ledger.sh check <repo> <base> thing`
Exit: 1
Output:
```
BLOCKED: proof of done. This is a 'behavioral' change; it cannot ship/merge without a matching proof-of-done entry in docs/verification/.
  Need: a docs/verification/<slug>.md added by this branch with a green run AND a NEGATIVE CONTROL (revert -> RED -> restore).
  Hint: docs/verification/thing.md has no captured output: a typed Exit: 0 or Verdict: PASS is a claim, not evidence. Add an `Output:` line to the run block and paste under it what the run really printed (the test recap, the tail of the run); a slot left empty or holding only a <placeholder> does not count. For visual work embed a committed screenshot or GIF instead: `![after](shot.png)`.
```
Result: refused as intended

## NEGATIVE CONTROL 1: the new suite against the old gate

Produced by the new `negctl.sh` itself, pasted as printed (its `Output:` slots are the captured runs).

```
## Negative control (negctl)
Command: bash tests/test-proof-captured-output.sh
Exit: 0 (green before mutation)
Output:
  PASS no proof file on the branch prints no block

  test-proof-captured-output: all 44 passed

Mutation: git show origin/master:lib/gate/proof-ledger.sh >| lib/gate/proof-ledger.sh
Changed: lib/gate/proof-ledger.sh
Exit: 1 (under mutation, RED expected)
Output:
  FAIL body lost the captured output
  FAIL image link not rewritten:
  FAIL dangling link was rewritten
  FAIL PROOF OF DONE block:
  FAIL long body is 0 chars, tail:

  test-proof-captured-output: 25 FAILED of 44

Restore: git checkout HEAD -- lib/gate/proof-ledger.sh
Exit: 0 (green after restore)
```
Result: RED as expected, restored

## NEGATIVE CONTROL 2: the land section against the old `wrap-land.sh`

Run with `negctl.sh --at HEAD`, so the export took the mutation and the worktree stayed untouched while the full suite ran.

```
## Negative control (negctl)
At: HEAD
Command: LAND_ONLY=proofbody bash tests/test-wrap-land.sh
Exit: 0 (green before mutation)
Output:
  test-wrap-land: all 23 passed

Mutation: git show 0bc686956db2a3521a8a80c371d2391133f61221:lib/wrap/wrap-land.sh >| lib/wrap/wrap-land.sh
Changed: lib/wrap/wrap-land.sh
Exit: 1 (under mutation, RED expected)
Output:
  test-wrap-land: 11 passed, 12 FAILED of 23

Restore: git checkout HEAD -- lib/wrap/wrap-land.sh
Exit: 0 (green after restore)
```
Result: RED as expected, restored

## Full suite

Command: `LAND_CACHE=0 CLAUDE_PLUGIN_ROOT=$PWD bash tests/run-all.sh --all`
Exit: 1
Output (tail):
```
test-wrap-land                                 ok
test-wrap-merge                                ok
test-wrap-start                                ok

run-all: FAILED -> test-stats-no-persist
run-all: 192 suites run, 0 skipped for missing tooling
```
Result: 191 of 192 green. The one red suite does not touch this change: under its `env -i` with a temp HOME, the mise `uv` shim refuses an untrusted config (`mise ERROR Config files in ~/.config/mise/config.toml are not trusted`), so `stats gate-yield` never starts. This diff touches nothing under `lib/stats`. An export of origin/master has no `.venv` and skips the same case.

## What the operator sees: the closing block of `wrap land`

`_land_proof_block` run on this branch's own proof file (the PR number is a placeholder here; a real land prints the URL `gh` returned):

```
PROOF OF DONE
  proof: docs/verification/proof-captured-output.md
  PR:    https://github.com/dwarvesf/dwarves-kit/pull/<n>
    | PASS body opens with the one-line summary
    | PASS body carries the '## Proof of done' section
    | PASS body carries the captured output
    | PASS a relative image link is pinned to the head sha
    | PASS a dangling image link is left as written
    | PASS the PROOF OF DONE block names the file, the PR and the output
    | PASS a long proof is cut under the body limit with a pointer to the file (40154 chars)
    | PASS a cut inside a fence closes the fence before the pointer
    | PASS no proof file on the branch builds no body
    | PASS no proof file on the branch prints no block
    | test-proof-captured-output: all 44 passed
    | test-wrap-land: LAND_ONLY='proofbody' selected 1 of 11 sections
    | test-wrap-land: 1 sections, 1 ran, 0 cached (0 checks credited)
    | test-wrap-land: all 23 passed
    | Passed: 826 / 826
```

The PR for this branch carries the body `_land_proof_body` built from this file.

## Not proven

- No real PR was created by a test. The `pr create` / `pr edit` calls are checked against the gh stub. This branch's own PR body is the first live run.
- The table-first proof layout, with results only in table cells, gets no credit. That is deliberate: a cell saying PASS is a claim. Such a proof passes once its run-detail section carries `Output:` lines.
- The parser cannot tell whether pasted lines are true. That stays with review.
