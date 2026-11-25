# Proof: the team stamp, all groups together (integration)

| Step | What is shown | Result | Section |
|---|---|---|---|
| 1 | A full stamp of an empty git repo writes every manifest row and the lock; a second run prints only `unchanged`; `--check` exits 0; the owners check passes on the tracked stamp | pass | Step 1 |
| 3 | `tests/test-stamp-e2e.sh`: file set equals the manifest and the spec table; every generated test runs kit-free with non-default values; named scripts exist; a fixture PR passes the stamped checks; scan-safe digests; privacy scan against the denylist | 37 passed, 0 failed | Step 3 |
| 4 | `tests/test-stamp-refusals.sh`: every refusal of every generated script is a rule line then a `Fix:` line; hostile input never reaches the output raw; every printed `Fix:` line runs through `bash -c` and creates nothing | 224 passed, 0 failed | Step 4 |
| 5 | `tests/test-stamp-adopt-interplay.sh`: both orders of the adopt interplay table | 30 passed, 0 failed | Step 5 |
| 6 | Eight negative controls, and five more for the second review (door case, approval at head, approval after a base change, runs of this PR only, exact owners): the guard allows a bare merge, the render skips the kit-path scan, `write_if_absent` overwrites | each goes red, restores green | Negative control |
| Engine | `tests/test-stamp.sh`, `tests/test-stamp-kitfree.sh all` | 164 and 13 passed, 0 failed | Step 3 |

Not shown: the clean-room probe run (TASK-G11, Tier 2) and the container path of the gauntlet runner (`docker build`, the probe container, the checker container). The build host has no container runtime, so `run.sh`, the `Dockerfile` and the checker's container mounts are code that has never executed; Tier 1 covers the same checker script and `copy-out.sh` on the host. The clean-room agent run (TASK-G11, Tier 2). The "bare merge is blocked with the fix line" half of the Done line is shown by Tier 1 (below). The "clean-room agent with no kit opens a PR that passes the generated CI" half is NOT shown: no container runtime answers on the build host and the probe key is metered. To run it when a runtime is up:

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
224 passed, 0 failed
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

The container path (volume, probe container, checker container) was NOT executed on the build host, which has no container runtime. It is unverified code until the operator's first run. Tier 1 covers the staging, the checker script and `copy-out.sh` on the host, with hostile fixtures. Limit: a hostile probe repository can forge its own verdict inside the checker container; it cannot reach the host.

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
      PASS  9 the probe edited no gate file
      PASS  6 the pristine scripts/check.sh exits 0 on the probe's work with the PR's own title and body
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
== T1.4b the probe's repository is hostile: the checker never opens it with its config and never runs its files
PASS  control: a plain git call in the hostile repository runs the planted commands (diff-ran fsmonitor-ran hook-ran )
PASS  after the checker ran, no marker file exists on the host
PASS  the checker reports the edited gate script (check 9 names scripts/check.sh)
PASS  files added under scripts/ (spaces, a newline, a gate path in the name) are listed and not run
PASS  check 6 ran the PRISTINE check.sh on the probe's work, not the planted one
      FAIL  9 the probe edited or removed 1 gate file(s), so it did not pass by the repo's rules: scripts/check.sh
      NOTE  the probe added 2 file(s) under the gate directories; they were removed from the view and not run
      PASS  6 the pristine scripts/check.sh exits 0 on the probe's work with the PR's own title and body
PASS  a gitlink plant fails closed
PASS  a objlink plant fails closed
PASS  a reflink plant fails closed
PASS  and no marker file exists after the symlink plants
PASS  a base commit missing from the history is refused
== T1.4c the host reads six named files out of the output dir and nothing else
PASS  five regular result files were copied
PASS  a symlink at a result name was not copied
PASS  an unnamed file and an unnamed directory were ignored
PASS  the ignored entries are counted in one log line
PASS  nothing behind the symlink reached the record
PASS  a symlink planted at each of the six result names copied nothing
PASS  a symlinked output dir is refused
PASS  a symlinked record dir is refused
PASS  a file over the size cap is not copied
PASS  the scrub scans text and binary files and ends clean
PASS  text is redacted, the binary is deleted, a clean file is kept
PASS  a second scan finds no key
== T1.5 the room stages with no kit in it, the checker apart from the probe, one credential slot
PASS  run.sh stages the room
PASS  the seed holds the card, the shim and the stamped repo
PASS  the repo, card, prompt and shim name no path under the kit
PASS  the seed holds no kit lib or gauntlet dir
PASS  the checker dir holds only the checker, the pristine stamp is a git repo
PASS  the staged base is the seed repo's first commit
PASS  the Dockerfile bakes no credential
PASS  run.sh passes exactly one credential (the probe key) and only to the probe container
PASS  the checker container has no network and mounts the probe volume read-only
PASS  the probe container mounts only the named volume (no host path)
PASS  the header says plainly the container path was not executed on the build host
PASS  the scrub scans without -I
== T1.6 every generated test runs with the kit absent from PATH and HOME
PASS  tests/test-stamp-kitfree.sh all: 13 passed, 0 failed

tier1: 0 failed, 51 passed
Exit: 0

## Negative control

NEGATIVE CONTROL: eight controls (control 5 retired in round two), each run with lib/gate/negctl.sh after a commit and restored by git checkout. Each mutation turns its suite red; the restore turns it green again.

| # | Mutation | Command | Green before | Under the mutation | Green after |
|---|---|---|---|---|---|
| 1 | the guard allows a bare merge (the block becomes a no-op) | bash tests/test-stamp-hook.sh | 47 passed, 0 failed | 42 passed, 5 failed | 47 passed, 0 failed |
| 2 | the render skips the kit-path scan | bash tests/test-stamp.sh | 158 passed, 0 failed | 154 passed, 4 failed | 158 passed, 0 failed |
| 3 | write_if_absent overwrites an edited file | bash tests/test-stamp.sh | 158 passed, 0 failed | 148 passed, 10 failed | 158 passed, 0 failed |
| 4 | an approval no longer has to be at the judged head | bash tests/test-stamp-merge.sh | 80 passed, 0 failed | 78 passed, 2 failed | 80 passed, 0 failed |
| 5 | (retired in round two) the tests job loses its fork guard: the job no longer exists; the fork guard of `changes` and `pr-shape` stays pinned by the CI suite | bash tests/test-stamp-ci.sh | 173 passed, 0 failed | n/a | n/a |
| 6 | the take backup skips a dangling symlink no more | bash tests/test-stamp.sh | 158 passed, 0 failed | 155 passed, 3 failed | 158 passed, 0 failed |
| 7 | the owners check keeps the colon in a rule line | bash tests/test-stamp-refusals.sh | 224 passed, 0 failed | 223 passed, 1 failed | 224 passed, 0 failed |
| 8 | the planted hostile repository config, run by a plain git call (the live control in Tier 1) | bash tests/gauntlet/team-stamp/tier1.sh | markers created by a plain git call | no marker through the checker | n/a |

Command: bash tests/test-stamp-merge.sh (control 4, run by negctl)
Output:
  80 passed, 0 failed   (green before the mutation)
  78 passed, 2 failed   (under the mutation)
  80 passed, 0 failed   (after the restore)
Exit: 1
Verdict: RED, as expected

### Round two controls (security review, second pass)

Five controls, each run with lib/gate/negctl.sh on a committed tree and restored by git checkout: green, mutate, red, restore, green. The test command stamps the group from the worktree into a temp repo and runs the generated test there, under the host test lock.

Control 9: A door matches in any casing: the path is no longer lowered before the match

```
Command: stamp the merge group, run the generated scripts/test-pr-merge.sh
Exit: 0 (green before mutation)
Output:
  PASS  a non-number is refused: two-line form
  PASS  no number is refused: exit 2
  PASS  no number is refused: two-line form
  PASS  --timeout without --wait is refused: exit 2
  PASS  --timeout without --wait: two-line form
  PASS  --timeout with a non-number is refused: exit 2
  PASS  an unknown option is refused: exit 2
  PASS  an unknown option: two-line form
  PASS  usage errors call gh never
  failures: 0

Mutation: sed -i.bak 's|lp="$(lower "$1")"|lp="$1"|' templates/team-stamp/files/scripts/pr-merge.sh.tpl && rm -f templates/team-stamp/files/scripts/pr-merge.sh.tpl.bak
Changed: templates/team-stamp/files/scripts/pr-merge.sh.tpl
Exit: 1 (under mutation, RED expected)
Output:
  PASS  a non-number is refused: two-line form
  PASS  no number is refused: exit 2
  PASS  no number is refused: two-line form
  PASS  --timeout without --wait is refused: exit 2
  PASS  --timeout without --wait: two-line form
  PASS  --timeout with a non-number is refused: exit 2
  PASS  an unknown option is refused: exit 2
  PASS  an unknown option: two-line form
  PASS  usage errors call gh never
  failures: 19

Restore: git checkout HEAD -- templates/team-stamp/files/scripts/pr-merge.sh.tpl
Exit: 0 (green after restore)
Verdict: PASS
```

Control 10: An approval must be on the judged head

```
Command: stamp the merge group, run the generated scripts/test-pr-merge.sh (failures only)
Exit: 0 (green before mutation)
Output:
  test dir: <tmp>/pr-merge-test.5VarLS
  failures: 0

Mutation: sed -i.bak 's|and .commit.oid == ($head)|and true|' templates/team-stamp/files/scripts/pr-merge.sh.tpl && rm -f templates/team-stamp/files/scripts/pr-merge.sh.tpl.bak
Changed: templates/team-stamp/files/scripts/pr-merge.sh.tpl
Exit: 1 (under mutation, RED expected)
Output:
  test dir: <tmp>/pr-merge-test.oWjC2O
  FAIL  an approval that is stale does not count: refused
  FAIL  an approval that is stale: no merge call
  FAIL  approval rule: stale-head: refused, exit 1
  FAIL  approval rule: stale-head: no merge call
  failures: 4

Restore: git checkout HEAD -- templates/team-stamp/files/scripts/pr-merge.sh.tpl
Exit: 0 (green after restore)
Verdict: PASS
```

Control 11: An approval older than the last base change does not count

```
Command: stamp the merge group, run the generated scripts/test-pr-merge.sh (failures only)
Exit: 0 (green before mutation)
Output:
  test dir: <tmp>/pr-merge-test.VjPsH2
  failures: 0

Mutation: sed -i.bak 's|and ((.submittedAt // "") > basechg)|and true|' templates/team-stamp/files/scripts/pr-merge.sh.tpl && rm -f templates/team-stamp/files/scripts/pr-merge.sh.tpl.bak
Changed: templates/team-stamp/files/scripts/pr-merge.sh.tpl
Exit: 1 (under mutation, RED expected)
Output:
  test dir: <tmp>/pr-merge-test.DvTvjx
  FAIL  an approval submitted before the last base change does not count: refused
  failures: 1

Restore: git checkout HEAD -- templates/team-stamp/files/scripts/pr-merge.sh.tpl
Exit: 0 (green after restore)
Verdict: PASS
```

Control 12: Only this pull request's runs count (a run that names another pull request on the same head is dropped no more)

```
Command: stamp the merge group, run the generated scripts/test-pr-merge.sh (failures only)
Exit: 0 (green before mutation)
Output:
  test dir: <tmp>/pr-merge-test.MJEj4S
  failures: 0

Mutation: sed -i.bak 's|select(((.pull_requests // \[\]) \| length) == 1 and .pull_requests\[0\].number == $number)|select(true)|' templates/team-stamp/files/scripts/pr-merge.sh.tpl && rm -f templates/team-stamp/files/scripts/pr-merge.sh.tpl.bak
Changed: templates/team-stamp/files/scripts/pr-merge.sh.tpl
Exit: 1 (under mutation, RED expected)
Output:
  test dir: <tmp>/pr-merge-test.YsG1dK
  FAIL  a run that also lists another pull request on the same head does not count: refused
  FAIL  a run shared with another pull request: no merge call
  failures: 2

Restore: git checkout HEAD -- templates/team-stamp/files/scripts/pr-merge.sh.tpl
Exit: 0 (green after restore)
Verdict: PASS
```

Control 13: Ownership is an exact match (the row compare ignores case)

```
Command: stamp the owners group, run the generated scripts/test-check-owners.sh (failures only)
Exit: 0 (green before mutation)
Output:
  test dir: <tmp>/check-owners-test.52XFPz
  failures: 0

Mutation: sed -i.bak 's|grep -Fxq -- "$file"|grep -Fxiq -- "$file"|' templates/team-stamp/files/scripts/check-owners.sh && rm -f templates/team-stamp/files/scripts/check-owners.sh.bak
Changed: templates/team-stamp/files/scripts/check-owners.sh
Exit: 1 (under mutation, RED expected)
Output:
  test dir: <tmp>/check-owners-test.SAel1S
  FAIL  a row for scripts/deploy.sh does not own scripts/Deploy.sh: names the tracked path
  failures: 1

Restore: git checkout HEAD -- templates/team-stamp/files/scripts/check-owners.sh
Exit: 0 (green after restore)
Verdict: PASS
```


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
| AC16 negative controls | 40 | the block above (controls 1 to 3 are the original three; 4 to 8 cover the security fixes) |
| AC17, AC18, AC19 guidance, repo-living files, scan-safe digests | 47, 48, 51 | `tests/test-stamp-rules.sh`, `tests/test-stamp.sh`, `tests/test-stamp-e2e.sh` |
| AC15 the gauntlet run | 39 | Tier 1 only (`tests/gauntlet/team-stamp/tier1.sh`); Tier 2 NOT RUN, see `docs/verification/gauntlet/2026-11-25-custom-team-stamp-scratch/ROUNDS.md` |

## Rollback

The stamp is a generator and the kit holds no state for a stamped repo. Rolling back is reverting the pull request that adds the verb and its templates. A repo that was already stamped keeps its files: they are plain files the repo owns, and deleting them (or `.claude/team-stamp.lock`) is a repo decision, not a kit one.

Verdict: PASS
