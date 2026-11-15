# Spec: tiered verification for mega-goal runs (node, wave join, release)

Generated: 2026-11-15
Status: SHIPPED
Lane: full (the build touches `lib/gate/`, `lib/queue/orchestrate.sh` and the verification pipeline in `commands/execute.md`, all enforcement surfaces)
Depth: standard (every re-verification point below was read live in the tree and in the two mega-goal skills; the Spacedown numbers come from one run on clean main)
Type: spec-feature
Board: ID-945
File: `docs/specs/SPEC-421-tiered-verification.md`
References: `commands/execute.md` Step 3; `commands/ship.md` Step 2; `agents/task-verifier.md`; `agents/recheck-verifier.md`; `lib/gate/recheck-sample.sh`; `lib/gate/proof-ledger.sh`; `commands/battery.md` (baseline ingredient); `lib/queue/orchestrate.sh` (TIER-4 close); `kit.toml` `[test]` and `[execute]`; the `megagoal-agent-drive` and `plan-for-mega-goal` skills (dotfiles).

## Problem

The owner runs work in parallel through a mega-goal DAG. Each node re-verifies from the start, so the run spends most of its wall clock re-running the same suite. He wants each node to verify itself once, when its build ends, and the lead to trust that record.

Evidence (the pilot repo, not re-measured here): `bash tests/smoke.sh` in `dwarvesf/spacedown` takes 76 s and fails 1 of 149 checks on clean main at `286ef79` (`FAIL: Skim settings panel or its persistence wrong`). Every node that runs the full suite meets a failure it did not cause.

## Where a node re-verifies today

Traced in this tree and in the two skills that drive mega-goal runs. Each line is one place the same checks run again for the same node.

| # | Where | What runs again |
|---|---|---|
| R1 | `commands/execute.md:167` Step 3.1 | The whole project suite. `kit.toml:355` sets `[test] suite = "full"` by default. |
| R2 | `commands/execute.md:168`, `agents/task-verifier.md:55` | `kit:task-verifier` runs the project test suite again and records it. |
| R3 | `commands/execute.md:170` | `kit:acceptance-verifier` re-runs every `## Verification` command (often the suite). |
| R4 | `commands/execute.md:177-181` | On FAIL:fixable, `kit:fix-agent` then the failing end verifiers re-run, up to 2 times. A pre-existing red (the Spacedown case) lands here and burns both retries, then PARTIAL. |
| R5 | `commands/execute.md:186-194`, `lib/gate/recheck-sample.sh:12-13`, `kit.toml:349` | `kit:recheck-verifier` re-executes every PASS's command in a fresh Opus context for 1 run in 5 (rid hash), every run on the full lane. The sample is random, not risk-based. |
| R6 | `commands/ship.md:36-46` Step 2 | The suite runs again before packaging; `ship.md:45` stops on any red, including a baseline red. |
| R7 | `megagoal-agent-drive/SKILL.md:19` | A fresh-context Opus verify PER TASK before its merge. |
| R8 | `megagoal-agent-drive/SKILL.md:52` | `kit:recheck-verifier` before each PR merge: it re-executes the worker's recorded command, again. |
| R9 | `plan-for-mega-goal/references/invocation-template.md:137-140` | "loop verify, fix, re-verify until the proof holds" per sub-goal, with no baseline, so a baseline red loops to the cap. |
| R10 | `invocation-template.md:157-158`, `OPERATE.md:46-50`, `commands/verify.md:51`, `agents/system-verifier.md:29-46` | The convergence gate runs `/kit:verify`, whose system level runs the whole suite unscoped, then a recheck re-runs it. Fine at release, but it is the only join; there is no per-wave join. |

What already holds and is reused:

- `lib/queue/orchestrate.sh:2529`: the TIER-4 close says "Do NOT re-run each sub-goal's per-task V-model". The conductor itself does not re-verify; the repeats sit inside each node's pipeline (R1 to R6) and in the skills (R7 to R9).
- `lib/queue/orchestrate.sh:414-422`: checked boxes are never re-dispatched. An unchecked node that is re-dispatched (a dead worker, a re-run) rebuilds and re-verifies from scratch; no record says its content is unchanged.
- `kit.toml:355` `[test] suite = "affected"` already scopes R1, R6 and the system level to the tests a change touches. It is off by default and does not reach R2, R3, R5 or the skills.
- `commands/battery.md:114-117` already names a BASELINE ingredient ("N known failures; FAIL only on NEW failures"), stated by the lead in prose for each run. Nothing records it.
- `lib/gate/proof-ledger.sh:22-23`: a proof is "fresh" when the branch diff added the verification entry. It is keyed by the diff, not by content, so a rebased node looks the same as a changed one.
- `commands/mega.md:189-198` and `docs/patterns/worker-brief.md:28-38` already tell workers to iterate on affected suites only and run "the full check once, before opening the PR". That one run is still R1 plus R2 plus R6 in practice.

Rough cost today, from the rows above and the 76 s figure (an estimate, not a measurement): 4 to 5 full-suite runs per node (R1, R2, R5 when sampled, R6, R8), plus up to 4 more through R4 on a red baseline. Nine pilot nodes means about 45 to 60 min of suite time alone, before the verifier agents' own turns.

## Solution (v1)

Make every re-run cheap; never skip a check on the strength of a record. Every existing step still runs, but inside a mega-goal node each run is narrow, so a repeat costs seconds instead of 76. The full suite runs once per wave, on the merged tree, inside the existing converge step.

```
 node (every existing step still runs)            wave join (lead, in _wave_converge)
 +-------------------------------------+          +------------------------------------------+
 | execute 3.1   -> affected tests     |          | full suite on the BASE tree -> baseline  |
 | task-verifier -> affected tests     |  wave    | merge the wave heads, pin each head SHA  |
 | recheck       -> affected tests     | -------> | full suite on the MERGED tree            |
 | ship step 2   -> affected tests     |  done    | new failures? red: stop, no merge        |
 | known failures (base file) never    |          | green: WAVE_MERGE_CMD with the pinned    |
 |   consume fix retries               |          |   head; head moved? rejoin, never land   |
 +-------------------------------------+          +------------------------------------------+
                                                    release: /kit:battery, negative control, build
```

The mode is `[mega] verify = "off" | "tiered"`, read at the base commit. `off` is today's flow.

## Rules

1. **Node scope is `affected`.** In a tiered mega-goal node, every verification step runs the `affected` selection the kit already has (`kit.toml:355`; `commands/execute.md:167` defines it: the tests that reference the changed paths, else the smallest command that fails if the change is wrong). The lead sets it per node with a `Test-suite: affected` line in the goal file (the node brief carries it verbatim); the repo default is read from `git show <base>:.kit.toml`, never from the node's branch. Execute 3.1, the task-verifier pass (`commands/execute.md:168`), the recheck sample (`commands/execute.md:186-194`) and ship's test step (`commands/ship.md:36-46`) all still run. Nothing is skipped and no record is trusted.
2. **Known failures are a lead-committed file in the target repo.** Default `tests/known-failures.txt`, path set by `[test] known_failures` at the base. One test name per line, read with `git show <base>:<path>`. A run whose failures are all listed, whose executed count is non-zero and at least the last full run's, does not consume fix retries (`commands/execute.md:177-181`) and does not stop ship. A non-zero exit with no parsed failure is a failure (a crash is never masked). A node diff that touches the file fails the node's gate unless the lead declared the change in the goal file (`Known-failures: edit <reason>`). Failure names and the executed count come from `[test] failure_line` and `[test] count_line`, read at the base; without them a red run is a plain failure.
3. **The wave join runs the full suite once per wave, on the merged tree.** Inside `_wave_converge` (`lib/queue/orchestrate.sh:2367`), before `WAVE_MERGE_CMD`: run the full suite on the base tree in a throwaway worktree to get this join's own baseline (never a ledger line), merge the wave's heads in a second throwaway worktree with each head SHA pinned, and run the full suite there. A failure not in the base run's set stops the wave: nothing merges and the lead routes it. Green: `WAVE_MERGE_CMD` receives each pinned head, and `mega-merge.sh` merges with `--match-head-commit <pinned>`. A PR head that moved since the join refuses the merge and the join reruns; it never lands an unjoined head.
4. **Rolling waves are refused in v1.** `orchestrate.sh run` exits with a message when `verify = "tiered"` and `WAVE_ROLLING=1`. With no wave formed (serial path), the join runs once per DAG level.
5. **The build branch is `feat/tiered-verification`**, so `spec_for_slug` finds this spec and its lane. The `skipped` rows appended on rid `tiered-verification` already cancel the spec-only overrides; the build records its own gates.

## Technical Design

- **`commands/execute.md` Step 3 and `commands/ship.md` Step 2.** Read the node's `Test-suite:` line, falling back to `[test] suite` at the base; read the known-failures file at the base; the retry loop and ship's stop skip a run that is all-known with a non-dropping count.
- **`agents/task-verifier.md`, `agents/recheck-verifier.md`.** Run the same `affected` selection the lead names; apply the known-failures rule.
- **`lib/gate/known-failures.sh` (new, small).** `read <root> <base>`, `classify <log> <root> <base>` (prints `pass`, `known`, `fail`), `guard <root> <base> <goal-file>` (exit 1 when the diff touches the file without a declaration). Bash and git only.
- **`lib/queue/orchestrate.sh`.** `_wave_converge` gains the join before the merge loop and passes the pinned head as an extra arg to `WAVE_MERGE_CMD`; `run` refuses `tiered` with rolling waves; the serial path joins per DAG level. No new call happens when `verify = "off"`.
- **`lib/goal/mega-merge.sh`.** `merge` accepts `--expect-head <sha>` and refuses when the fetched head differs (it already pins and passes `--match-head-commit`, `:457-538`).
- **`kit.toml`, `lib/config/module-registry.md`.** `[mega] verify`, `[test] known_failures`, `[test] failure_line`, `[test] count_line`, registered for `tests/test-config-registry.sh`.
- **`commands/mega.md`, `docs/WORKFLOW.md`, `CHANGELOG.md`.** The goal-file lines and the join. Companion dotfiles edits: `megagoal-agent-drive/SKILL.md:19`, `:52` and `plan-for-mega-goal/references/invocation-template.md:137-140`, `:157-158` point at the join instead of per-task and per-merge full runs.

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T0: golden first | commit the orchestrator dry-run output from `master` under `tests/fixtures/` before any `orchestrate.sh` edit | AC6 |
| T1: known failures | `lib/gate/known-failures.sh`, `tests/test-known-failures.sh` | AC2, AC3 |
| T2: node scope | `commands/execute.md`, `commands/ship.md`, the two agents | AC1 |
| T3: join and merge | `lib/queue/orchestrate.sh`, `lib/goal/mega-merge.sh`, `tests/test-orchestrate-tiered.sh` | AC4, AC5 |
| T4: config and docs | `kit.toml`, `lib/config/module-registry.md`, `commands/mega.md`, `docs/WORKFLOW.md`, `CHANGELOG.md` | AC7 |
| T5: skills | dotfiles `megagoal-agent-drive`, `plan-for-mega-goal` | R7 to R9 replaced |
| T6: pilot | Spacedown release 1 | AC8 |

## Test plan

Fixture `tests/lib/node-fixture.sh`: a repo with a stub suite driven by env (failures, executed count, exit code, crash), a node branch, and a semantic-conflict pair (each node green alone, red merged).

| # | Case | Check |
|---|---|---|
| C1 | `node-runs-affected` | a tiered node's execute, verifier and ship steps each run the affected selection, never the full suite (stub records its invocations) |
| C2 | `known-failures-read-at-base` | a branch edit to `tests/known-failures.txt` does not change `classify`; the base copy decides |
| C3 | `known-failures-edit-guarded` | a node diff touching the file fails `guard`; with `Known-failures: edit` declared it passes |
| C4 | `known-failure-no-retry` | an all-known run with a non-dropping count does not open the retry loop; a dropped count does |
| C5 | `crash-not-masked` | exit 1 with no parsed failure classifies `fail` |
| C6 | `join-once-merged-tree` | one wave runs the full suite twice (base, merged) and only in `_wave_converge`; the semantic-conflict pair goes red and nothing merges |
| C7 | `join-head-moved-refused` | a PR head moved after the join: `mega-merge.sh merge --expect-head` refuses, the join reruns, nothing lands |
| C8 | `rolling-refused` | `verify = "tiered"` with `WAVE_ROLLING=1` exits non-zero before any dispatch |
| C9 | `tiered-off-golden` | `verify = "off"`: orchestrator output equals the T0 golden |

Negative control, through `lib/gate/negctl.sh` with `bash tests/test-known-failures.sh` as the test command: make `read` use the branch copy (`git show HEAD:<path>`) instead of the base. C2 must go red.

## After state

In a tiered mega-goal run every existing verification step still runs, but on the affected tests only, so repeats cost seconds. A failure listed in the lead's known-failures file never burns a retry or stops ship, and a node cannot edit that list unannounced. The full suite runs once per wave on the merged tree, against a baseline it measured itself, and only the joined head can land. With `verify = "off"` nothing changes.

## Acceptance Criteria (global)

| AC | Check |
|---|---|
| AC1 every node verification step runs the affected selection | C1 |
| AC2 known failures are read at the base and a node cannot change them undeclared | C2, C3, negative control |
| AC3 all-known runs with a non-dropping count consume no retry; a crash is a failure | C4, C5 |
| AC4 the join runs the full suite once per wave on the merged tree with its own base run, and catches the semantic conflict | C6 |
| AC5 only the pinned head merges; a moved head reruns the join; rolling waves are refused | C7, C8 |
| AC6 `verify = "off"` leaves orchestrator output unchanged | C9 |
| AC7 new keys are registered | `tests/test-config-registry.sh` |
| AC8 the pilot metric is reported | the pilot record |

## Verification

```bash
bash tests/test-known-failures.sh
bash tests/test-orchestrate-tiered.sh
bash tests/test-orchestrate.sh
bash tests/test-config-registry.sh
bash tests/run-all.sh --changed
```

## Pilot: Spacedown release 1

The first tiered mega-goal. Repo `dwarvesf/spacedown`, base `286ef79`, known failure `Skim settings panel or its persistence wrong` (the lead commits `tests/known-failures.txt` before wave 1).

| Node | Work | Note |
|---|---|---|
| 0 | contract node: shared interfaces, plus a section filter for `tests/smoke.sh` (one 1,644-line script with no subset flag today) | without it `affected` has nothing narrower than the whole suite to select |
| 1 | box-diagram fix plus woff2 fonts | |
| 2 | size trim | adds the size budget check |
| 3 | CLI renders through the Quick Look JS core via `osascript -l JavaScript` | |
| 4 | X-ray | |
| 5 | present mode | |
| 6 | settings | the known failure's area; a fix is declared with `Known-failures: edit` |
| 7 | onboarding | |
| 8 | landing page | |

Wave join: `bash tests/smoke.sh`, `scripts/layout-check` on the reading fixtures, the size budget. Release: `/kit:battery`, negative control, release build. Config: `failure_line = '^  FAIL: (.*)$'`, `count_line` from the `smoke: N passed, M FAILED` summary.

**Metric.** Two arms, `off` and `tiered`, on the same host. Nodes 1 and 6 run 3 times per arm, arms alternating, compared by median. Reported per node: suite seconds (summed test-command wall time) and agent seconds (node wall time minus suite seconds), apart. Pass: the `tiered` median node wall time is at most half the `off` median for both nodes, and no node in `tiered` spends a retry on the known failure.

## Out of Scope (v2)

The reviews showed each of these needs its own enforcement surface (a script or hook that checks it), not a rule in a command file:

- **Script-written proof records:** a builder or agent can still forge what a record or ledger line says until a hook verifies the writer.
- **Trust and the `trust` verb:** skipping a check on a record is safe only when a hook enforces the match at every consumer.
- **Tree keys (`HEAD^{tree}` or cross-rebase):** only useful once trust exists.
- **Skip-unchanged on re-runs:** depends on keys and trust.
- **Risk classes beyond today's:** declared class, added-line scan and out-of-plan paths each need a gate that reads base config, not the node's.
- **A ledger-held baseline:** a ledger line can be forged; v1 measures the join's baseline itself and keeps node baselines in a committed file.

Also out: changing the lane floor, hard-path kinds or `proof-ledger.sh`; `/kit:execute` outside a mega-goal; cross-repo nodes; CI; per-node `/kit:spec` cost.

## Touches

```
lib/gate/**
lib/queue/**
lib/goal/**
lib/config/**
commands/**
agents/**
tests/**
docs/**
kit.toml
CHANGELOG.md
```

## Decision Log

- **Round 1** (overall, security, test plan reviews): REVISE. Revision 2 moved proof-writing to a kit script and added trust, tree keys, risk signals and a ledger baseline.
- **Round 2** (confirmation review): REVISE with 3 new highs (trust was never enforced by a script or hook; the build rid missed its spec; the rule-4 precedent `_negctl_required` reads the project config from the node's own tree) and 2 partly open (forged baseline ledger lines; a push landing between join and merge).
- **Rescope, not another fold.** Each round cleared criticals and opened new ones in the trust machinery. v1 drops trust entirely: every check still runs, each run is narrow. That removes the whole class of skip-on-record attacks instead of patching it.
- **How each round-2 high is closed:** no trust to enforce (rule 1); the build branch is `feat/tiered-verification` (rule 5); every config and known-failures read is `git show <base>:...`, never the node's tree (rules 1 and 2); no ledger baseline, the join measures its own (rule 3); the merge passes the joined head with `--match-head-commit` and a moved head reruns the join (rule 3).
- **Known failures in a committed file** instead of a ledger: the lead's edit is reviewed in a PR, a node's edit is caught by a diff guard.
- **Rejected:** none of the relayed findings.
- **Cost accepted:** each repeat still runs. The bet is that `affected` makes repeats cheap enough; the pilot measures it. If it does not, v2's trust work gets its own spec.
- The pilot threshold (half the node wall time) is this spec's pick, not the owner's.
