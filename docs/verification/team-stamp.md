# Proof: the team stamp, all groups together (integration)

| Step | What is shown | Result | Section |
|---|---|---|---|
| 1 | A full stamp of an empty git repo writes every manifest row and the lock; a second run prints only `unchanged`; `--check` exits 0; the owners check passes on the tracked stamp | pass | Step 1 |
| 3 | `tests/test-stamp-e2e.sh`: file set equals the manifest and the spec table; every generated test runs kit-free with non-default values; named scripts exist; a fixture PR passes the stamped checks; scan-safe digests; privacy scan against the denylist | 37 passed, 0 failed | Step 3 |
| 4 | `tests/test-stamp-refusals.sh`: every refusal of every generated script is a rule line then a `Fix:` line; hostile input never reaches the output raw; every printed `Fix:` line runs through `bash -c` and creates nothing | 172 passed, 0 failed | Step 4 |
| 5 | `tests/test-stamp-adopt-interplay.sh`: both orders of the adopt interplay table | 30 passed, 0 failed | Step 5 |
| 6 | Three negative controls: the guard allows a bare merge, the render skips the kit-path scan, `write_if_absent` overwrites | each goes red, restores green | Negative control |
| Engine | `tests/test-stamp.sh`, `tests/test-stamp-kitfree.sh all` | 115 and 13 passed, 0 failed | Step 3 |

Not shown: the clean-room agent run (TASK-G11, Tier 2). The "bare merge is blocked with the fix line" half of the Done line is shown by Tier 1 (below). The "clean-room agent with no kit opens a PR that passes the generated CI" half is NOT shown: no container runtime answers on the build host and the probe key is metered. To run it when a runtime is up:

```bash
ANTHROPIC_API_KEY=<capped probe key> RUN_OUT=docs/verification/gauntlet/<date>-custom-team-stamp-scratch/round-N bash tests/gauntlet/team-stamp/run.sh
```

The rest of this paragraph is the earlier note. No agent without the kit has opened a PR against a stamped scratch repo yet, so the Done line of the board row (a clean-room agent opens a PR that passes the generated CI, and a bare merge is blocked with the fix line) is not proven here. The bare-merge block is shown by the guard's own tests, not by an agent. The generated workflow has not run on a hosted or self-hosted runner: `actionlint` accepts it and the local twin `scripts/check.sh` passes a fixture PR. Also not shown: an agent other than Claude Code, and the first digest post.

## Step 1: a full stamp

Command: bash lib/stamp.sh --owner alice (an empty git repo with origin/HEAD), run twice, then --check
Output:
  36 created
   1 merged
  37 unchanged
  --check exit=0
  check-owners: 21 paths, all owned
Exit: 0

## Step 3: the end to end suite

Command: bash tests/test-stamp-e2e.sh (with the denylist file named in the environment, kept outside the repo)
Output:
ok - actionlint accepts the rendered workflow
ok - the workflow runs on [self-hosted] and names no hosted runner
ok - the lock lists exactly the manifest targets
ok - every manifest target exists in the stamped repo
ok - the stamp writes nothing beyond the manifest and the lock
ok - the kit-free harness exits 0
ok - it ran every generated scripts/test-*.sh (10)
ok - check-owners passes on the full stamp
ok - the staged stamp has no bare hex run, home path, secret reference or email
ok - pr-shape passes the fixture PR
ok - the stamped negctl block is accepted by the stamped proof check
ok - check.sh passes the fixture PR (owners, pr-shape, every script test)
ok - no denylist string appears in the branch (0 hits)
ok - no denylist string appears in a stamped repo (0 files)
ok - no denylist string appears in the templates, fixtures, proof or gauntlet record (0 hits)
ok - the branch diff has no bare hex run
37 passed, 0 failed
Exit: 0

## Step 4: the refusal suite

Command: bash tests/test-stamp-refusals.sh
Output:
ok - guard: gh pr merge 7 --squash: exit 2
ok - guard: gh pr merge 7 --squash: the last two stderr lines are 'agent-guard: <rule>' then 'Fix: ...'
ok - pr-shape: a hostile title with a forged Fix line: every Fix: line follows a 'pr-shape: ' line
ok - pr-merge: a door path with no second person: the last two stderr lines are 'pr-merge: <rule>' then 'Fix: ...'
ok - negctl: a tracked file with uncommitted changes: the last two stderr lines are 'negctl: <rule>' then 'Fix: ...'
ok - no hostile payload ran anywhere: no marker file exists
172 passed, 0 failed
Exit: 0

## Step 5: the adopt interplay

Command: bash tests/test-stamp-adopt-interplay.sh
Output:
ok - stamp first: line 1 of AGENTS.md is the kit marker
ok - adopt left the stamp's AGENTS.md alone
ok - adopt first: AGENTS.md is the kit pointer
ok - --take AGENTS.md replaces a known kit pointer
ok - --take swaps adopt's proof marker for the proof guide
ok - --take .kit.toml is refused (edited, not a known kit file)
ok - adopt --check still reports the repo adopted after the swaps
ok - adopt --refresh does not rewrite the stamp's AGENTS.md
30 passed, 0 failed
Exit: 0

## Gauntlet Tier 1

Command: bash tests/gauntlet/team-stamp/tier1.sh
Output:
== T1.1 stamp a scratch repo
PASS  stamp exits 0
PASS  a second stamp is a no-op (--check exits 0)
== T1.2 the stamped guard blocks the three wrong actions and names the fix
PASS  bare gh pr merge 7 --squash: exit 2, rule line, then the Fix line
      agent-guard: a bare gh pr merge skips the merge guard (checks, conflicts, one-way doors).
      Fix: bash scripts/pr-merge.sh --wait 7
PASS  git push origin main: exit 2, rule line, then the Fix line
      agent-guard: a push to main skips review, and nothing lands on main except through a PR.
      Fix: git switch -c <type>/<slug> && git push -u origin <type>/<slug> && gh pr create
PASS  git commit on main: exit 2, rule line, then the Fix line
      agent-guard: you are on main, and nothing commits to main directly (your changes come with you to a branch).
      Fix: git switch -c <type>/<slug>
== T1.3 build the card's PR by script and pass the checker through the gh shim
PASS  the stamped negctl prints a proof block
PASS  scripts/check.sh exits 0 with the PR's own title and body
PASS  scripts/pr-merge.sh --wait 1 merges through the shim
PASS  the checker passes on the card's PR
      PASS  1 the pull request was merged
      PASS  2 the title is a conventional commit subject
      PASS  3 a proof file holds a NEGATIVE CONTROL block with a red verdict
      PASS  4 the changelog gained a tagged line
      PASS  5 the body links the work (Closes #<n>)
      PASS  6 scripts/check.sh exits 0 with the PR's own title and body
      PASS  7 no bare gh pr merge was issued
      SKIP  8 no transcript given: the kit-path scan did not run
      check-submission: 0 failed
== T1.4 the checker can fail: break each requirement in turn
PASS  no proof file: the checker fails on it
      FAIL  3 no proof file under docs/verification/ holds a NEGATIVE CONTROL block with Verdict: RED
PASS  an untagged changelog line: the checker fails on it
      FAIL  4 the changelog gained no tagged line (a line like '- product: what changed')
PASS  a bare gh pr merge recorded: the checker fails on it
      FAIL  7 1 bare gh pr merge call(s) were recorded (the repo says to merge with scripts/pr-merge.sh)
== T1.5 the clean room stages with no kit in it and one credential slot
PASS  run.sh stages the room
PASS  the room holds the card, the shim, and the stamped repo
PASS  the repo, card, prompt and shim name no path under the kit
PASS  the room holds no kit lib or gauntlet dir
PASS  the Dockerfile bakes no credential
PASS  run.sh passes exactly one credential (the probe key) into the room
== T1.6 every generated test runs with the kit absent from PATH and HOME
PASS  tests/test-stamp-kitfree.sh all: 13 passed, 0 failed

tier1: 0 failed, 19 passed
Exit: 0

## Negative control

NEGATIVE CONTROL: three controls, each run with lib/gate/negctl.sh after a commit and restored by git checkout.

1. The guard allows a bare merge (the block of a bare `gh pr merge` in the guard template becomes a no-op).
Command: bash tests/test-stamp-hook.sh
Output:
  47 passed, 0 failed   (green before the mutation)
  42 passed, 5 failed   (under the mutation)
  47 passed, 0 failed   (after the restore)
Exit: 1 under the mutation, 0 after the restore

2. The render skips the kit-path scan (the check in `lib/stamp.sh` is replaced with a constant false).
Command: bash tests/test-stamp.sh
Output:
  115 passed, 0 failed  (green before the mutation)
  111 passed, 4 failed  (under the mutation)
  115 passed, 0 failed  (after the restore)
Exit: 1 under the mutation, 0 after the restore

3. `write_if_absent` overwrites (the write step also writes a file the repo edited).
Command: bash tests/test-stamp.sh
Output:
  115 passed, 0 failed  (green before the mutation)
  105 passed, 10 failed (under the mutation)
  115 passed, 0 failed  (after the restore)
Exit: 1 under the mutation, 0 after the restore
Verdict: RED, as expected

## Test plan coverage

| Acceptance criterion | Test plan rows | Covered by |
|---|---|---|
| AC1 file set | 1 | `tests/test-stamp-e2e.sh` |
| AC2, AC3 kit-free text and run | 3, 4, 5, 46 | `tests/test-stamp-e2e.sh`, `tests/test-stamp-kitfree.sh`, `tests/test-stamp.sh` |
| AC4 to AC7 idempotent, never overwrites, drift, refresh and take | 2, 6 to 11, 48 | `tests/test-stamp.sh` |
| AC8, AC9 refusals | 12 to 23, 25 to 28, 41 to 49 | each generated test, `tests/test-stamp-refusals.sh` |
| AC10 parity | 22 | the generated `scripts/test-pr-shape.sh`, `tests/test-stamp-e2e.sh` |
| AC11, AC12 runner and twin | 29 to 32 | `tests/test-stamp-ci.sh`, `tests/test-stamp-e2e.sh` (actionlint, hosted-label scan) |
| AC13 adopt interplay | 33, 34, 36 | `tests/test-stamp-adopt-interplay.sh`, `tests/test-stamp.sh` |
| AC14 privacy | 35, 50 | `tests/test-stamp-e2e.sh` privacy section (0 hits against the denylist held outside the repo) |
| AC16 negative controls | 40 | the block above |
| AC17, AC18, AC19 guidance, repo-living files, scan-safe digests | 47, 48, 51 | `tests/test-stamp-rules.sh`, `tests/test-stamp.sh`, `tests/test-stamp-e2e.sh` |
| AC15 the gauntlet run | 39 | Tier 1 only (`tests/gauntlet/team-stamp/tier1.sh`); Tier 2 NOT RUN, see `docs/verification/gauntlet/2026-11-25-custom-team-stamp-scratch/ROUNDS.md` |

## Rollback

The stamp is a generator and the kit holds no state for a stamped repo. Rolling back is reverting the pull request that adds the verb and its templates. A repo that was already stamped keeps its files: they are plain files the repo owns, and deleting them (or `.claude/team-stamp.lock`) is a repo decision, not a kit one.

Verdict: PASS
