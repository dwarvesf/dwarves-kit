# Spec: tiered verification for mega-goal runs (node, wave join, release)

Generated: 2026-11-15
Status: DRAFT
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

## Solution

Three levels. Each check runs at the cheapest level that can catch what it guards.

```
 node (builder)          wave join (lead)                 release (lead)
 +------------------+    +---------------------------+    +---------------------+
 | touched tests    |    | merge wave heads in a     |    | /kit:battery        |
 | + its new test   |--->| throwaway worktree        |--->| negative control    |
 | + 1 artifact     |    | full suite (baseline-     |    | release build       |
 |   smoke          |    |   aware) + join checks    |    | (once per release)  |
 | record proof     |    | + ONE fresh review        |    +---------------------+
 | (key = tree hash)|    | record join proof         |
 +------------------+    +---------------------------+
          |                       ^
          | lead: key matches     |
          | and not risky? ------ trust, no re-run
          | risky? -------------- kit:recheck-verifier on the node command only
```

| Level | Who | Runs | When |
|---|---|---|---|
| Node done | the builder | the tests mapped to the files it touched, its new test, one cheap smoke of its artifact; records the proof | once, when its build ends |
| Wave join | the lead | the full project suite, the project's join checks (layout, integration), ONE fresh-context review of the merged wave diff | once per wave |
| Release | the lead | `/kit:battery` (or equivalent), negative control, release build | once per release |

The mode is opt-in per mega-goal: `[mega] verify = "tiered"` in `.kit.toml` or a `Verify: tiered` line in the ROADMAP header. Off, every flow is unchanged.

## Rules

1. **Node scope.** The node runs (a) every command its touched paths map to in `[test] node_map`, (b) the test files it added, (c) one artifact smoke the goal file names (`Smoke:` line). With no `node_map` entry for a touched path, the node runs the repo's full check once and records it; it is never silently skipped.
2. **Proof record.** One record per node build. Fields below. The builder writes it as its last step; the lead never writes a node record.
3. **Trust.** The lead does not re-run a node's checks when all hold: a record exists for the node; its `Key` equals the key recomputed at the PR head; its result is green or every failure is in the recorded baseline; its commands cover the `node_map` commands for the touched paths; the node is not in a risk class. Any miss: the lead re-runs the node's own commands (never the full suite) and records why.
4. **Risk classes get a fresh recheck.** A node whose diff hits a risk class gets `kit:recheck-verifier` in a fresh context, re-executing the node record's commands (not the full suite). Risk classes: the built-in hard-path kinds of `lib/classify/lane-classify.sh` (`migration`, `auth`, `secret`, `ci`, `infra`, `kitconfig`, data-loss lines), the `stateful` proof class (`lib/gate/proof-classes.tsv`), and the project's `[mega] recheck_paths` (Spacedown: `*.entitlements`, sandbox config, any money path). Every other node gets no recheck: the random 1-in-5 sample (R5) does not apply in tiered mode.
5. **Baseline.** Before the first wave, the lead runs the full suite once on the base commit and records the failing check names. A node or join failure whose name is in the baseline never blocks; it is listed as `baseline: <name>` in the record. A new failure blocks. A node that turns a baseline failure green says so (`fixed-baseline: <name>`), and the next wave's baseline drops it. Failure names come from `[test] failure_line`, an ERE with one capture group (Spacedown: `^  FAIL: (.*)$`). With no pattern, a red run on a red baseline is `inconclusive`: it does not block the node, and the wave join must judge it.
6. **Skip unchanged.** Before dispatching a node, the orchestrator recomputes the key on the node's existing branch. A matching green record means no worker, no verifier: the node goes straight to the merge queue. A re-run of the whole mega-goal therefore rebuilds only changed nodes.
7. **Wave join.** After every node of a wave has a trusted proof, the lead merges the wave's heads onto the base in a throwaway worktree, runs the full suite (baseline-aware), the project's `[mega] join_checks`, and ONE fresh-context review (`kit:code-reviewer` or `/kit:review-team` on a hard path) of the merged diff. It records a join proof keyed by the merged tree. Green: the lead lands the PRs in wave order through the existing `mega-merge.sh` path. Red: the lead routes the finding to the owning node by path, and only that node rebuilds.
8. **Release.** Unchanged from today's TIER-4 close plus `/kit:battery`, the negative control and the release build, once per release. The battery's baseline comes from the recorded baseline, not prose.

## Proof record

A run file in the existing verification convention (`docs/verification/README.md`, stage 3), committed on the node branch at `docs/verification/<spec-slug>/runs/node-<node-slug>.md`, so the PR carries it and `proof-ledger.sh check` sees a fresh entry. Fields, one per line:

| Field | Value |
|---|---|
| `Node:` | the sub-goal id and slug |
| `Key:` | the node key (below) |
| `Head:` | the commit SHA the run used (audit only; trust reads `Key`) |
| `Base:` | the base commit SHA |
| `Scope:` | the touched paths, one per line |
| `Command:` / `Exit:` / `Output (excerpt):` | one block per command run, the existing shape |
| `Baseline:` | the baseline id and the baseline failures this run hit |
| `Fixed-baseline:` | baseline failures this run turned green, or `none` |
| `Risk:` | `none` or the risk kinds hit |
| `Verdict:` | `PASS`, `PASS (baseline)`, `INCONCLUSIVE`, or `FAIL` |

**Key.** A git object id from `git hash-object --stdin` over sorted lines: `<path> <blob-oid>` for every touched path at the head (`<path> deleted` for a removed one), the same for every test file the node commands read, then each command string. It changes when the node's content, its tests or its commands change. It does not change when the node is rebased onto a moved base, which is the point: a rebased node keeps its proof.

**Index.** `node-proof.sh record` also appends one line to the run ledger through `ledger_append` (`node-proof | <repo-key> | <node> | <key> | <verdict> | <run file>`), keyed by the shared repo root the way `proof-ledger.sh` keys overrides, so every worktree of one repo reads the same index. The committed run file is the source of truth; the index is a lookup.

**Baseline record.** `node-proof.sh baseline record <root> <base>` runs the full suite once on a throwaway worktree at `<base>` and appends `baseline | <repo-key> | <base-tree> | <command> | <failure names>` to the ledger. Keyed by the base commit's tree, so it is reused until the base content changes.

## Technical Design

- **New: `lib/gate/node-proof.sh`.** Verbs: `key <root> <base> [--cmd <c>]...`, `record <root> <base> <run-file>`, `trust <root> <base> <node>` (exit 0 trust, 1 re-run, with one reason line), `risk <root> <base>` (prints `none` or the kinds), `baseline record|show|classify`. Bash plus git, readable in 30 seconds per verb, no new dependency. Reuses `lane-classify.sh floor` for the hard-path kinds, `proof-classes.sh` for `stateful`, `ledger_append`, `kit-config.sh`, and `negctl.sh`'s throwaway-worktree pattern for the baseline run.
- **`commands/execute.md` Step 3.** In tiered mode Step 3.1 runs the node scope (rule 1) instead of the full suite, then writes the record; Step 3.2 hands `kit:task-verifier` the record and the node scope, and it judges the criteria against that run instead of running the suite again (R2); R3 runs only `## Verification` commands the record does not already hold; the R4 loop never opens on a `PASS (baseline)` verdict; the recheck decision calls `node-proof.sh risk` instead of `recheck-sample.sh decide` (R5).
- **`agents/task-verifier.md`.** A node-mode paragraph: when given a node record whose key matches, do not run the project suite; re-run only a check the record lacks.
- **`commands/ship.md` Step 2.** In tiered mode, a trusted node record replaces the test run (R6); the baseline rule replaces "stop on any red".
- **`lib/gate/recheck-sample.sh`.** Unchanged outside tiered mode. Tiered mode does not call it.
- **`lib/queue/orchestrate.sh`.** Before dispatch: the skip-unchanged check (rule 6). After a wave's nodes report: the wave join (rule 7), then the existing merge path. The TIER-4 close becomes the release level and reads the baseline.
- **`commands/mega.md`.** Step 4 goal-file fields `Smoke:` and the `Verify:` header; Step 5 the trust rule, the join and the release level. Replaces the per-merge recheck wording for tiered runs.
- **`commands/battery.md`.** The baseline ingredient reads `node-proof.sh baseline show` when a record exists.
- **`kit.toml`.** `[mega] verify`, `[mega] join_checks`, `[mega] recheck_paths`, `[test] node_map`, `[test] failure_line`, each documented with its default (off or empty).
- **Docs.** `docs/WORKFLOW.md` "Mega-goal delegate execution", `docs/verification/README.md` (the node record shape), `CHANGELOG.md`.
- **Companion edits outside the kit (dotfiles, canonical skill copies).** `megagoal-agent-drive/SKILL.md:19` and `:52` (per-task verify and per-merge recheck become the trust rule plus risk-class recheck); `plan-for-mega-goal/references/invocation-template.md:137-140` and `:157-158` (the loop is baseline-aware; TIER 4 is the release level, after per-wave joins). Shipped in the same cycle as a dotfiles PR, cited from this spec's implementation notes.

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: key, record, trust, risk | `lib/gate/node-proof.sh`, `tests/test-node-proof.sh` | AC1 to AC3, AC5 |
| T2: baseline | `lib/gate/node-proof.sh`, `tests/test-node-proof.sh` | AC4 |
| T3: execute and ship in node mode | `commands/execute.md`, `agents/task-verifier.md`, `commands/ship.md`, `tests/test-meta.sh` text checks | AC7 |
| T4: orchestrator skip and wave join | `lib/queue/orchestrate.sh`, `tests/test-orchestrate*.sh` | AC6, AC8 |
| T5: config, mega, battery, docs | `kit.toml`, `commands/mega.md`, `commands/battery.md`, `docs/WORKFLOW.md`, `docs/verification/README.md`, `CHANGELOG.md` | AC10 |
| T6: skills | dotfiles `megagoal-agent-drive`, `plan-for-mega-goal` | the R7 to R9 lines replaced |
| T7: pilot | Spacedown release 1 (below) | AC11 |

## Test plan

| # | AC | Check | Case |
|---|---|---|---|
| P1 | AC1 | a fixture repo; key a node, rebase it onto a moved base, key again | `key-survives-rebase`; `key-changes-on-touched-edit`, `-on-test-edit`, `-on-command-edit` |
| P2 | AC2 | record without a command or exit code | `record-refuses-incomplete` |
| P3 | AC3 | trust: match green, match baseline-red, key mismatch, new failure, missing `node_map` command, risk hit | `trust-*` |
| P4 | AC4 | a base with one known failure; node run hits it, adds a new one, fixes it | `baseline-known-never-blocks`, `baseline-new-blocks`, `baseline-fixed-reported`, `baseline-no-pattern-inconclusive` |
| P5 | AC5 | diffs touching a migration dir, an auth file, `.env`, `.github/`, `*.entitlements`, a `recheck_paths` match, plain code | `risk-*` |
| P6 | AC6 | orchestrate dry run with a stub claude; a node with a matching record and one without | `orchestrate-skips-unchanged-node` (no dispatch line for it) |
| P7 | AC8 | orchestrate dry run, a two-node wave; join runs once; red join routes to the node by path | `orchestrate-wave-join-once`, `orchestrate-join-red-routes` |
| P8 | AC10 | the same fixtures with tiered mode off | `tiered-off-unchanged` (dispatch and prompt bytes equal the pre-change output) |
| P9 | regressions | `bash tests/run-all.sh --changed` | exit 0 |

Negative control, through `lib/gate/negctl.sh` with `bash tests/test-node-proof.sh` as the test command: make `trust` skip the key comparison. P3 must go red.

## After state

In a tiered mega-goal run each node verifies itself once, records a proof keyed by its content, and is not re-verified while that content holds. The full suite runs once per wave and once per release, never once per node. A failure that already exists on the base is recorded once and never blocks a node. Only risky nodes pay for a fresh-context recheck. A re-run of the mega-goal rebuilds only the nodes whose content changed. A run without `verify = "tiered"` behaves exactly as today.

## Acceptance Criteria (global)

| AC | Check |
|---|---|
| AC1 the key ignores a rebase onto a moved base and changes on any edit to a touched path, a node test, or a command | P1 |
| AC2 a record without `Command:`, `Exit:` or `Key:` is refused | P2 |
| AC3 `trust` exits 0 only on: key match, green or baseline-covered, `node_map` commands covered, no risk class; otherwise exits 1 naming the reason | P3 |
| AC4 a baseline failure never blocks; a new failure blocks; a fixed one is reported; no pattern gives `INCONCLUSIVE` | P4 |
| AC5 every built-in hard-path kind, `stateful`, and `recheck_paths` mark a node risky; plain code does not | P5 |
| AC6 an unchanged node with a green record is not dispatched on a re-run | P6 |
| AC7 in tiered mode, `/kit:execute` and `/kit:ship` run the full suite zero times per node, and `kit:task-verifier` does not re-run a recorded check | T3 text checks in `tests/test-meta.sh` plus the pilot's run ledger |
| AC8 the wave join runs once per wave and a red join rebuilds only the owning node | P7 |
| AC9 the negative control turns P3 red | `docs/verification/tiered-verification.md` |
| AC10 tiered mode off: every flow is byte-identical | P8 |
| AC11 the pilot meets the success metric below | the pilot record |

## Verification

```bash
bash tests/test-node-proof.sh
bash tests/test-orchestrate.sh
bash tests/test-meta.sh
bash tests/run-all.sh --changed
```

## Pilot: Spacedown release 1

The first tiered mega-goal. Repo `dwarvesf/spacedown`, base `286ef79`, baseline 1 known failure (`Skim settings panel or its persistence wrong`).

Nodes (the roadmap sets the edges; this is the expected shape):

| Node | Work | Node smoke |
|---|---|---|
| 0 | contract node: the shared interfaces the others plug into, plus a section filter for `tests/smoke.sh` so a node can run only its section (the suite is one 1,644-line script with no subset flag today) | `bash tests/smoke.sh --only contract` |
| 1 | box-diagram fix plus woff2 fonts | render the box fixture, check the font files load |
| 2 | size trim | the size budget script node 2 adds |
| 3 | CLI renders through the Quick Look JS core via `osascript -l JavaScript` | render `tests/fixture/fixture.md` through the CLI and diff against the Quick Look output |
| 4 | X-ray | its smoke section |
| 5 | present mode | its smoke section |
| 6 | settings (touches the baseline failure's area; may turn it green, which tests `Fixed-baseline`) | its smoke section |
| 7 | onboarding | its smoke section |
| 8 | landing page | `scripts/layout-check` on the landing page |

Wave join, every wave: `bash tests/smoke.sh` (baseline-aware), `scripts/layout-check` on the reading fixtures, the size budget. Release: `/kit:battery`, negative control, the release build.

Spacedown config: `[mega] verify = "tiered"`, `[test] failure_line = '^  FAIL: (.*)$'`, `[test] node_map` from smoke sections to source paths (node 0 writes it), `[mega] recheck_paths` for the entitlements and sandbox files, `[mega] join_checks` for layout-check and the size budget.

**Success metric.** Before and after wall clock on the same host:

- A/B: nodes 1 and 6 run twice from the same base, once in today's flow and once tiered. Measure from builder done to merge-ready (the ledger's OUTCOME durations). Pass: the tiered run takes at most half the wall clock of today's flow for both nodes.
- Whole release: total wall clock and full-suite run count from the run ledger. Pass: full-suite runs equal the number of waves plus one baseline plus the release; zero nodes blocked or retried by the baseline failure.
- Report what the wave joins caught that node runs missed, as a count with the findings. A join that catches nothing across the release is not a failure; a defect that reaches release past a join is, and goes in the Decision Log.

## Out of Scope

- Changing what the ship-gate or `proof-ledger.sh check` enforce at push. A node record is a fresh verification entry, so the existing gate is satisfied as is.
- Changing the lane floor or the hard-path kinds. Risk classes reuse them read-only; `recheck_paths` is a recheck list, not a lane trigger.
- `/kit:execute` outside a tiered mega-goal, and single-spec runs.
- Per-node `/kit:spec` and `/kit:spec-validate` cost. It is planning ceremony, not re-verification, and is not measured here; if the pilot shows it dominates, that is a separate row.
- Cross-repo nodes. One repo per mega-goal in this version.
- CI. The levels are local by contract (AGENTS.md "The check is local by contract").

## Touches

```
lib/gate/**
lib/queue/**
commands/**
agents/**
tests/**
docs/**
kit.toml
CHANGELOG.md
```

## Decision Log

- Key by the tree of the touched paths, not the commit SHA. A commit SHA changes on every rebase, and in a wave every node after the first rebases, so a SHA key would re-verify every node after every merge: the slowness this spec removes. The wave join covers cross-node effects the node key cannot see.
- The proof is a committed run file, not only a ledger line. It travels with the PR, the existing proof gate reads it, and a reviewer can re-run its `Command:` lines. The ledger index is a lookup and can be rebuilt from the files.
- Random recheck sampling (1 in 5) is replaced by risk classes in tiered mode. A random sample spends Opus on safe nodes and can miss a risky one; the owner named the risky classes.
- The baseline is recorded by name, not by count. A count hides a swap (one old failure fixed, one new failure added). Without a name pattern the verdict is `INCONCLUSIVE`, never `PASS`.
- The wave join merges in a throwaway worktree before any PR lands, so a red join never leaves the default branch red.
- The pilot threshold (half the wall clock on the A/B nodes) is this spec's pick; the owner set the direction, not a number.
- `[test] suite = "affected"` already exists but is global and does not reach the verifier agents or the skills; tiered mode is a separate switch so a repo can keep its dev-loop setting.
