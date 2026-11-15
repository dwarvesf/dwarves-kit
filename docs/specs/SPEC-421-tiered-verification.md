# Spec: tiered verification for mega-goal runs (node, wave join, release)

Generated: 2026-11-15
Status: DRAFT (revision 2: v1 cut to phase 1 after three REVISE reviews)
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

Two moves remove the per-step repeats. First, the kit script, not the builder, runs a node's checks once and writes the proof. Second, every later step in the same node reuses that run while the tree is unchanged. A recorded baseline stops a pre-existing failure from blocking a node. The full suite runs once per wave, inside the existing converge step.

```
 node (kit script, after the build)        wave join (lead, in _wave_converge)       release (lead)
 +----------------------------------+      +--------------------------------------+  +------------------+
 | node-proof.sh run <node>         |      | pin node heads, merge in a throwaway |  | /kit:battery     |
 |  clean worktree at Head          |      | worktree, pin the merged tree        |  | negative control |
 |  node_map cmds + Smoke + negctl  |      | full suite (baseline-aware)          |  | release build    |
 |  parse failures from full log    |      | re-run every node's Smoke + non-suite|  +------------------+
 |  write record, key = HEAD^{tree} |      | commands                             |
 +----------------------------------+      | green: WAVE_MERGE_CMD, landed tree   |
     |  same tree?  task-verifier, ship,   |   must equal joined tree, else rejoin|
     |  sampled recheck reuse the run      | red: bisect by merge prefix, else    |
     |  risky? fresh-context recheck       |   escalate                           |
     |  1 in N non-risky: cheap re-run     +--------------------------------------+
     v
  push gate (proof-ledger.sh check) sees a record with a green mark and a NEGATIVE CONTROL
```

| Level | Who runs it | Runs | When |
|---|---|---|---|
| Node done | `node-proof.sh run`, called by the lead's execute step | the `node_map` commands for the touched paths, the node's new tests, its `Smoke:` line, its `Negative control:` | once per node tree |
| Wave join | the lead, inside `_wave_converge` | the full suite, every node's `Smoke:` and non-suite commands again, one fresh-context review of the merged diff | once per wave (once per DAG level on the serial path) |
| Release | the lead | `/kit:battery`, negative control, release build | once per release |

The mode is `[mega] verify = "off" | "baseline" | "tiered"`, read at the base commit (rule 4). `baseline` turns on rule 3 alone, so the pilot can measure each part. `off` is today's flow.

## Rules

1. **The kit writes the proof.** `node-proof.sh run <node>` checks out Head in a clean throwaway worktree, runs the node's commands itself, and writes the record: each `Command:`, `Exit:`, the sha256 of the FULL output, the parsed failure set, and a `Writer: node-proof.sh <version>` line. It also appends a `node-proof` ledger line with the same output hashes. `trust` refuses any record whose hashes and key do not match a ledger line the script wrote. A builder never writes or edits a record. One non-risky node in N (`[mega] rerun_sample`, default 5, keyed on the rid like `recheck-sample.sh`) is re-run by the script, without an agent, and must reproduce the recorded failure set.
2. **Same-tree reuse inside one node.** The key is `git rev-parse HEAD^{tree}`. The task-verifier pass (`commands/execute.md:168`), the sampled recheck (`commands/execute.md:186-194`) and ship's test step (`commands/ship.md:36-46`) read the record when the key equals the current tree, and judge from it instead of running the checks again. A different tree means a new `node-proof.sh run`, never a partial reuse. This is the change that removes the per-step re-verification.
3. **Baseline-aware verdicts.** The script parses failures from the full log with `[test] failure_line` (one capture group: the name) and counts executed checks with `[test] count_line`. A failure is matched by name plus the sha256 of its whole line. Verdicts: `PASS` when exit 0 and no failures; `PASS (baseline)` only when the failure set is non-empty, every entry is in the baseline, and the executed count is at least the baseline's count; `FAIL` for any new failure, and for a non-zero exit with no parsed failure (a crash is never masked); `INCONCLUSIVE` when `failure_line` or `count_line` is missing. The baseline is a lead-only record, one per base tree, written by `node-proof.sh baseline record` on a throwaway worktree at the base. A green join's failure set becomes the next wave's baseline. The execute retry loop (`commands/execute.md:177-181`) never opens on `PASS (baseline)`.
4. **Trust config is read at the base commit.** `node_map`, `failure_line`, `count_line`, `recheck_paths`, `verify` and `rerun_sample` come from `git show <base>:.kit.toml`, the operator and kit-root layers as-is, the same split `_negctl_required` uses (`lib/gate/proof-ledger.sh:410-417`). A node whose diff changes any of these keys is risky and runs the full suite instead of its `node_map` commands.
5. **Risk is the highest of three signals.** (a) The class the lead writes in the goal file before dispatch (`Risk: none | behavioral | stateful | security`). (b) The path floor: `lane-classify.sh floor` with `extra_hard_paths` and `recheck_paths` read at the base. (c) A scan of the added lines for the data-loss signatures and the `stateful` words in `proof-classes.tsv`. A node that touches a path outside its `## Touches` plan is risky. A risky node gets `kit:recheck-verifier` in a fresh context, which re-executes the record's commands.
6. **The wave join lives in `_wave_converge`** (`lib/queue/orchestrate.sh:2367`), before `WAVE_MERGE_CMD`. It pins each node's head SHA, merges the heads onto the base in a throwaway worktree, pins the merged tree, runs the full suite (baseline-aware) and re-runs every node's `Smoke:` line and non-suite commands. Green: the existing merge path lands the PRs; afterwards the landed tree must equal the joined tree, or the join runs again on the landed tree. Red: bisect by merge prefix (join the first k nodes, k = 1, 2, ...) to the first red prefix and route the finding to that node; if no prefix isolates it, escalate to the human. The serial path (no wave formed) joins once per DAG level. Tiered mode refuses to start with `WAVE_ROLLING=1` in v1.
7. **Push-gate mapping.** Each node goal file carries `Negative control: <mutate-cmd>` against the narrowest test. `node-proof.sh run` runs it through `lib/gate/negctl.sh` and writes the `NEGATIVE CONTROL` block into the record, so `proof-ledger.sh check` (`:606-607`, `:653`) passes on real evidence. An `INCONCLUSIVE` verdict stops the node and goes to the lead before any push; it never passes (the gate also refuses it, `:655`).
8. **Isolated slots.** Parallel nodes each get their own `HOME` and macOS preferences domain per slot, set the way `negctl.sh --slot-env` sets a per-slot variable (`[test] slot_env`). Two nodes never share app state.

## Proof record

A run file in the existing convention (`docs/verification/README.md`, stage 3), written by the script at `docs/verification/<spec-slug>/runs/node-<node-slug>.md` and committed by the lead with the node's branch.

| Field | Value |
|---|---|
| `Writer:` | `node-proof.sh <version>` |
| `Node:` | sub-goal id and slug |
| `Key:` | `HEAD^{tree}` at Head |
| `Head:` / `Base:` | commit SHAs |
| `Config:` | the base commit the trust keys were read at |
| `Scope:` | touched paths |
| `Command:` / `Exit:` / `Output-sha256:` / `Output (excerpt):` | one block per command |
| `Executed:` | the `count_line` count |
| `Failures:` | `name | line-sha256` per parsed failure |
| `Baseline:` | baseline id (base tree) and its count |
| `Risk:` | the level and which signal set it |
| `NEGATIVE CONTROL` | the negctl block |
| `Verdict:` | `PASS`, `PASS (baseline)`, `INCONCLUSIVE`, `FAIL` |

Ledger lines (through `ledger_append`, keyed by the shared repo root like the proof overrides): `node-proof | <node> | <key> | <output hashes> | <verdict>`, `baseline | <base-tree> | <count> | <failure set>`, and `suite-run | <node> | <start> | <end>` for every suite execution (the pilot metric reads these).

## Technical Design

- **New `lib/gate/node-proof.sh`.** Verbs: `run <node>`, `trust <node>` (exit 0 reuse, 1 re-run, one reason line), `risk <node>`, `baseline record|show`, `classify <log>` (the verdict from a full log and a baseline), `join <wave>` (called by `_wave_converge`). Bash and git; reuses `negctl.sh` (throwaway worktrees, `--slot-env`), `lane-classify.sh floor`, `proof-classes.sh`, `ledger_append`, `kit-config.sh`.
- **`commands/execute.md` Step 3.** In `tiered` mode Step 3.1 is `node-proof.sh run`; Steps 3.2 and the recheck read the record when `trust` exits 0; the retry loop skips `PASS (baseline)`; the recheck decision is rule 5 plus the 1-in-N re-run of rule 1.
- **`agents/task-verifier.md`.** Node mode: given a record with a matching key, judge criteria from it; do not run the suite.
- **`commands/ship.md` Step 2.** Reads the record on a matching key; stops on `FAIL` and `INCONCLUSIVE` only.
- **`lib/queue/orchestrate.sh`.** `_wave_converge` calls `node-proof.sh join` before `WAVE_MERGE_CMD` and checks the landed tree after; the serial path joins per DAG level; `run` refuses `tiered` with `WAVE_ROLLING=1`; no `node-proof.sh` call when the mode is `off`.
- **`commands/mega.md`.** Goal-file fields `Risk:`, `Smoke:`, `Negative control:`; the levels and the trust rule.
- **`commands/battery.md`.** The baseline ingredient reads `node-proof.sh baseline show`.
- **`kit.toml` and `lib/config/module-registry.md`.** New keys `[mega] verify`, `[mega] recheck_paths`, `[mega] rerun_sample`, `[test] node_map`, `[test] failure_line`, `[test] count_line`, `[test] slot_env`, and any `KIT_*` env read, registered so `tests/test-config-registry.sh` and the naming lints pass.
- **Docs.** `docs/WORKFLOW.md` mega section, `docs/verification/README.md` (the node record), `CHANGELOG.md`.
- **Companion edits in dotfiles.** `megagoal-agent-drive/SKILL.md:19`, `:52` and `plan-for-mega-goal/references/invocation-template.md:137-140`, `:157-158` point at the levels instead of per-task and per-merge re-runs.

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T0: golden first | commit the orchestrator dry-run output from `master` as a golden under `tests/fixtures/`, BEFORE any `orchestrate.sh` edit | AC10 |
| T1: fixture | `tests/lib/node-fixture.sh` | used by T2 to T4 |
| T2: run, trust, classify, baseline, risk | `lib/gate/node-proof.sh`, `tests/test-node-proof.sh` | AC1 to AC6 |
| T3: execute, verifier, ship | `commands/execute.md`, `agents/task-verifier.md`, `commands/ship.md` | AC7 |
| T4: join | `lib/queue/orchestrate.sh`, `tests/test-orchestrate-tiered.sh` | AC8, AC9 |
| T5: config, mega, battery, docs | `kit.toml`, `lib/config/module-registry.md`, `commands/mega.md`, `commands/battery.md`, `docs/WORKFLOW.md`, `docs/verification/README.md`, `CHANGELOG.md` | AC11 |
| T6: skills | dotfiles `megagoal-agent-drive`, `plan-for-mega-goal` | R7 to R9 replaced |
| T7: pilot | Spacedown release 1 | AC12 |

## Test plan

**Fixture** `tests/lib/node-fixture.sh`: a repo with a stub suite whose checks, failures, count and exit code come from env (`STUB_FAIL`, `STUB_COUNT`, `STUB_EXIT`, `STUB_CRASH`); a node branch; a base that moves on a file the node does not touch; and a semantic-conflict pair (each node green alone, red merged). Node cases go in `tests/test-node-proof.sh`, orchestrator cases in a new `tests/test-orchestrate-tiered.sh`.

| # | AC | Cases |
|---|---|---|
| P1 | AC1 | `run-writes-record-and-ledger`; `trust-refuses-hand-written-record`; `trust-refuses-edited-output-hash`; `rerun-sample-reproduces` |
| P2 | AC2 | `reuse-same-tree`; `rerun-on-new-tree` (one commit after the run) |
| P3 | AC3 | `baseline-known-passes`; `crash-not-masked` (exit 1, no parsed failure = FAIL); `swap-blocks` (one fixed plus one new); `name-collision` (same name, different line hash = new); `count-drop-blocks` (fewer executed checks than the baseline); `flaky` (a baseline failure that passes counts as fixed, never as new); `stale-baseline-after-wave` (the next wave reads the green join's set); `no-pattern-inconclusive` |
| P4 | AC4 | `config-read-at-base` (a working-tree `.kit.toml` edit is ignored); `config-diff-is-risky` (a diff to a trust key runs the full suite) |
| P5 | AC5 | `risk-declared`, `risk-floor-base-config`, `risk-added-lines`, `risk-outside-touches`, `plain-code-not-risky` |
| P6 | AC6 | `negctl-block-written`; `inconclusive-stops-before-push` |
| P7 | AC8 | `join-once-per-wave`; `join-semantic-conflict-red`; `join-bisect-owner`; `join-bisect-escalates`; `landed-tree-mismatch-rejoins`; `serial-joins-per-level`; `rolling-refused` |
| P8 | AC9 | `slots-isolated` (two parallel nodes see different `HOME` and preferences domain) |
| P9 | AC10 | `tiered-off-golden` (dispatch and prompt output equal the T0 golden; a shim on `PATH` records zero `node-proof.sh` calls) |
| P10 | regressions | `bash tests/run-all.sh --changed` exit 0 |

**Negative controls**, each through `lib/gate/negctl.sh` with the named suite as the test command; each mutation must turn its named case red:

| Trust rule | Mutation | Case that must go red |
|---|---|---|
| script-written check | `trust` skips the ledger-hash match | `trust-refuses-hand-written-record` |
| baseline classify | `classify` treats any non-zero exit with a baseline as `PASS (baseline)` | `crash-not-masked` |
| risk floor | `risk` drops the path floor | `risk-floor-base-config` |
| base-config read | config read from the working tree | `config-read-at-base` |
| join | `_wave_converge` skips `node-proof.sh join` | `join-semantic-conflict-red` |

## After state

In a `tiered` mega-goal run, the kit script runs each node's checks once and writes the proof; the task verifier, the recheck and ship reuse it while the tree holds. A failure already on the base is recorded once and never blocks a node or burns a retry. The full suite runs at most once per node (only on a `node_map` miss), once per wave and once per release. Only risky nodes and a 1-in-N sample pay for a re-run. With the mode `off`, the orchestrator's output is unchanged.

## Acceptance Criteria (global)

| AC | Check |
|---|---|
| AC1 `trust` accepts only records `node-proof.sh run` wrote; the 1-in-N re-run reproduces the failure set | P1 |
| AC2 a record is reused only on an equal `HEAD^{tree}` | P2 |
| AC3 the verdict rules of rule 3 hold for every baseline case | P3 |
| AC4 trust keys are read at the base; a diff to them makes the node risky | P4 |
| AC5 each risk signal alone marks a node risky; plain code does not | P5 |
| AC6 the record carries a negctl block; `INCONCLUSIVE` stops before push | P6 |
| AC7 at most one full-suite run per node, only on a `node_map` miss, checked from the `suite-run` ledger lines | P3 fixture run plus the pilot ledger |
| AC8 the join runs once per wave (per level when serial), catches the semantic conflict, finds the owner by merge-prefix bisect or escalates, and rejoins on a landed-tree mismatch | P7 |
| AC9 parallel slots are isolated | P8 |
| AC10 mode `off`: orchestrator output equals the golden committed from `master` before any `orchestrate.sh` edit, and no `node-proof.sh` call happens | P9 |
| AC11 every new key and `KIT_*` read is registered | `tests/test-config-registry.sh` |
| AC12 the pilot metric is reported as specified | the pilot record |
| AC13 each negative control turns its case red | `docs/verification/tiered-verification.md` |

## Verification

```bash
bash tests/test-node-proof.sh
bash tests/test-orchestrate-tiered.sh
bash tests/test-orchestrate.sh
bash tests/test-config-registry.sh
bash tests/run-all.sh --changed
```

## Pilot: Spacedown release 1

The first tiered mega-goal. Repo `dwarvesf/spacedown`, base `286ef79`, baseline 1 known failure (`Skim settings panel or its persistence wrong`).

| Node | Work | Smoke |
|---|---|---|
| 0 | contract node: the shared interfaces, plus a section filter for `tests/smoke.sh` (one 1,644-line script with no subset flag today) so `node_map` can name sections | `bash tests/smoke.sh --only contract` |
| 1 | box-diagram fix plus woff2 fonts | render the box fixture; the font files load |
| 2 | size trim | the size budget script node 2 adds |
| 3 | CLI renders through the Quick Look JS core via `osascript -l JavaScript` | render `tests/fixture/fixture.md` through the CLI and diff against the Quick Look output |
| 4 | X-ray | its smoke section |
| 5 | present mode | its smoke section |
| 6 | settings (the baseline failure's area; may turn it green) | its smoke section |
| 7 | onboarding | its smoke section |
| 8 | landing page | `scripts/layout-check` on the landing page |

Wave join: `bash tests/smoke.sh` (baseline-aware), `scripts/layout-check` on the reading fixtures, the size budget. Release: `/kit:battery`, negative control, release build. Spacedown config: `failure_line = '^  FAIL: (.*)$'`, `count_line` from the `smoke: N passed, M FAILED` summary, `node_map` from smoke sections (node 0 writes it), `recheck_paths` for the entitlements and sandbox files, `slot_env` for `HOME` and the app's preferences domain.

**Metric.** Three arms on the same host: `off` (today), `baseline`, `tiered`, measured in that order of introduction so each part's benefit shows. Nodes 1 and 6 run at least 3 times per arm, arms alternating in order between runs, compared by median. Suite seconds come from the `suite-run` ledger lines; agent seconds come from the run ledger's OUTCOME durations minus suite seconds; both are reported apart. "Merge-ready" is the end point; a node that ends `PARTIAL` after the retry cap counts as merge-ready at that point, and the count of PARTIAL endings is reported per arm. Pass: the `tiered` median is at most half the `off` median for both nodes, and no node in `baseline` or `tiered` is blocked or retried by the baseline failure. Also reported: what the wave joins caught that node runs missed.

## Out of Scope

Deferred to v2, with the reason:

- **Cross-rebase key** (a key over the touched paths' blobs that survives a rebase). It trusts a node's result on a tree it never ran on; the reviews showed a moved base can change a node's behavior through an untouched file. v1 keys on the whole tree and lets the join cover merges.
- **Skip-unchanged on re-runs** (the old rule 6). It depends on the cross-rebase key.
- **A Merkle chain over DAG edges** (a node's key folding in its parents' keys). Only needed once keys cross rebases.
- **Checkbox auto-flip and a reopen verb.** The ROADMAP box stays the lead's manual, PR-grounded flip; automating it and reopening a node after a red join need their own design.

Also out:

- **The push gate is not left unchanged by accident.** The first draft said the existing gate accepts a node record as is; it does not, because a behavioral change needs a `NEGATIVE CONTROL` block (`proof-ledger.sh:653`) that the old record lacked. Rule 7 supplies it from a real negctl run. `proof-ledger.sh` itself is not modified.
- Changing the lane floor or the hard-path kinds; risk reads them, never widens or narrows them.
- `/kit:execute` outside a mega-goal; cross-repo nodes; CI (the levels are local by contract).
- Per-node `/kit:spec` and `/kit:spec-validate` cost: planning, not verification, not measured here.

## Touches

```
lib/gate/**
lib/queue/**
lib/config/**
commands/**
agents/**
tests/**
docs/**
kit.toml
CHANGELOG.md
```

## Gate ledger for this spec

The draft PR carried 12 `spec-only draft PR` overrides on rid `tiered-verification`. They are superseded by `skipped` rows appended after this revision, so they cannot satisfy a later build push on that rid. The build branch is `feat/tiered-verify-build`, rid `tiered-verify-build`, and records its own gates.

## Decision Log

Three reviews (overall, security, test plan) returned REVISE. The lead cut v1 to the advisor's phase 1 and moved proof-writing from the builder to the kit script.

Taken:

- Builder-written proof is self-attestation; a script-written record with output hashes and a ledger match replaces it (rule 1). A cheap 1-in-N script re-run stays for non-risky nodes.
- The cross-rebase key trusted results on unrun trees; v1 keys on `HEAD^{tree}` and reuses only within one tree (rule 2). Skip-unchanged, the Merkle chain and the box flip go to v2 with it.
- The baseline matched by name only and could mask a crash or a swap; now name plus line hash, a crash with no parsed failure is FAIL, the executed count must not drop, and the baseline is lead-only per base tree (rule 3).
- Trust config read from the working tree lets a node rewrite its own rules; now read at the base, and a diff to it is risky (rule 4).
- Risk from paths alone missed declared intent and dangerous added lines; now the highest of three signals, plus out-of-plan paths (rule 5).
- A join placed outside the merge path could disagree with what lands; now inside `_wave_converge` with pinned heads and a landed-tree check; rolling waves refused in v1 (rule 6).
- The record would not pass the push gate honestly and the Out-of-Scope claim said it would; rule 7 adds a real negative control and the claim is corrected.
- Parallel nodes shared `HOME` and app preferences; rule 8 isolates them.
- AC7 rewritten to a ledger check; AC10 scoped to orchestrator output plus zero `node-proof.sh` calls with a golden from `master` committed first; AC8 names the merge-prefix bisect; one negative control per trust rule; the five named baseline cases; the shared fixture and a separate orchestrator suite; config keys registered.
- The pilot metric had one run per arm and mixed suite and agent time; now three arms, at least 3 runs each, alternating, by median, suite and agent seconds apart, PARTIAL handled, `suite-run` ledger lines.
- The gate overrides on the spec rid could leak to the build; superseded by `skipped` rows and the build gets its own rid.

Rejected: none of the relayed findings.

Residual risk, stated rather than solved: rule 1 stops an honest builder from shortcutting the proof, but an agent with shell access could still append a forged ledger line. The 1-in-N re-run and the risk-class recheck are the check on that; a signed ledger is not in v1.

Kept from the first draft: the three levels, the opt-in mode, the Spacedown pilot, and the pilot threshold (half the wall clock), which is this spec's pick, not the owner's.
