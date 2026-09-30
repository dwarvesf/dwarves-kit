# Spec: whole-spec dispatch for /kit:execute

Generated: 2026-09-29
Status: VALIDATED (round 2: fresh-context validator, 0 critical, three advisories folded)
Lane: full
Type: spec-feature
File: `docs/specs/SPEC-369-whole-spec-dispatch.md`
References: OpenRig `docs/reference/wave-sdlc.md:22-43` (the builder brief: goal, acceptance, routes, territory, self-navigation grant; a smaller chunk needs a named reason), and `:33-35` ("Detailed sequencing instructions were scaffolding when models were weak; today they are a cage"). Imitate the brief shape and the named-reason rule, nothing else.

Lane note: `lib/classify/lane-classify.sh classify` returns `tiny` on the task text and `normal` with `--files`. The spec takes `full` per the "when in doubt, take the heavier one" rule (`docs/WORKFLOW.md:62`), because the change rewrites the Build-phase HARD stop (`docs/WORKFLOW.md:168-169`) and moves verification from per task to per build, a validation change (`AGENTS.md:179`). The operator approved the direction (design D3, `docs/research/2026-09-29-openrig-absorption.md:114-122`) and, after validation round 1, the revisions below.

## Problem

`/kit:execute` runs a per-task spine. For every task it may dispatch a persona meta-agent (`commands/execute.md:150-162`), then a worker (`:167-253`), then `kit:task-verifier` (`:255-292`), then an Opus `kit:recheck-verifier` (`:294-316`), then up to two fix-agent rounds (`:318-369`), then a human phase checkpoint (`:382-405`). The worker template also orders the builder to expand its task into "bite-sized steps" before coding (`:231-236`).

What the record shows:

1. The recheck-verifier catches rarely, but not never. Recounted on 2026-09-29: 33 `Re-audit: PASS` lines across 7 verification logs, and recorded catches of FAIL:fixable at `docs/verification/loop-09-onboard-wizard.md:20,39` (a hardcoded roster left AC9 red) and at ops-toolkit `tools/vps-mon/docs/verification/SPEC-133-macos-agent-go.md:132` (a wrong recorded command). The research record's "29 PASS, 0 FAIL" (`docs/research/2026-09-29-openrig-absorption.md:60`) missed both. A low catch rate at Opus cost on every PASS argues for sampling, not deletion.
2. The per-task criterion check does catch real defects with a green suite. ops-toolkit `tools/circle/docs/verification/circle-intel.md` TASK-4 (`:35`) and TASK-5 (`:43`) needed a fix round (`:73`: weak tests, manual dedupe), and `docs/retro/RETRO-2026-05-22-release-hygiene-guard.md:17` records task-verifier catching a drift the other layers missed. `kit:integration-verifier` does not re-check per-task acceptance (`agents/integration-verifier.md:29`). So the criterion-level check must survive the rewrite; only its per-task placement goes.
3. The wire-first rule forbids retiring a wire before a real trial (`docs/research/2026-07-04-kit-utilization-audit.md:8-10`); the planned second recheck trigger was already a sampled audit of self-attested rows (`:65`).
4. A medium full-lane feature costs about 56 dispatches end to end (`docs/research/2026-09-29-openrig-absorption.md:36-42`, marked E). The per-task loop is the largest multiplier in it.

`commands/execute.md` is 36055 bytes and 513 lines at base `c5981b0f`.

## Solution

### Approaches considered

- **A. Keep the per-task spine, trim it.** Drop the persona dispatch and sample the recheck, keep one worker and one task-verifier per task. Tradeoff: cuts about 2 dispatches per task, keeps the sequencing cage, and execute.md barely shrinks.
- **B. Whole-spec dispatch with one end criterion check (chosen).** One builder gets the whole spec as a brief and navigates it. At the end, ONE `kit:task-verifier` pass checks every task's acceptance criteria, then integration and acceptance verifiers run. The recheck is sampled. A split happens only with a named reason. Tradeoff: a defect is found at the end, not after the task that caused it.
- **C. Opt-in whole-spec mode behind a flag, old spine as default.** Tradeoff: two pipelines in one file, execute.md grows, and CLAUDE.md:47 ("Replace, don't deprecate") forbids keeping both.

### Chosen approach + why

B. A trades away most of the saving. C doubles the surface the operator asked to shrink. B keeps every check that has caught something (criterion check, integration, acceptance, negative control, a sampled recheck) and drops only the per-task repetition and the persona hop. The late-defect cost is bounded: the end verifiers name the failed criterion, the fix loop (max 2) still runs, and the PARTIAL rule names what did not ship.

### Extensibility & boundaries

- The load-bearing dimension is spec size. R2 sets a task-count threshold and a continuation protocol for builders that run out of context.
- Units: (1) the brief (lead prose, no new code), (2) the builder, (3) end verification (one criterion pass, integration, acceptance), (4) the sampled recheck, (5) the PARTIAL rule. Each is one section of execute.md.

## Picture

```
 TODAY (per task, x N tasks)                   AFTER (once per spec)

 spec                                           spec
  |                                              |   tasks > 6 -> split: fork-risk (slices)
  v                                              v
 +-- for each task -------------------+        brief = goal + acceptance + routes
 | meta-agent Mode C (persona)        |                + territory + grant
 | worker (bite-sized steps)          |          |
 | task-verifier                      |          v
 | recheck-verifier (Opus, every PASS)|        builder (commits per task; near its limit
 | fix-agent x2                       |          returns PROGRESS: done=.. remaining=..
 +------------------------------------+          -> continuation builder, split: fork-risk)
  | phase checkpoint (human) per phase           |
  v                                              v
 integration-verifier                           task-verifier: ONE pass, every task's AC
  |                                              + integration-verifier (multi-task)
 recheck-verifier (every PASS)                   + acceptance-verifier; lead runs the
  |                                                non-allowlisted Verification commands
  v                                              |  FAIL:fixable -> fix-agent x2 -> re-verify
 negative control -> summary                     |  exhausted -> Result: PARTIAL
                                                 v
                                                check-edit signal; recheck sampled on
                                                HEAD sha, + every (self-attested) row
                                                 v
                                                negative control -> summary
```

## Design

Design-bearing: yes (it changes Build-phase control flow and the right-arm re-audit contract).

### Approaches considered + chosen

See `## Solution` above.

### Diagram

See `## Picture` above (a flowchart of both control flows).

### ADR link(s)

A NEW ADR, `docs/decisions/0038-whole-spec-dispatch-sampled-reaudit.md`, partially supersedes:
- ADR-0028 (`docs/decisions/0028-autonomous-loop-hardening.md:34`, P4 right-arm parity): "a fresh-context re-audit lens over each right-arm PASS" becomes a sampled re-audit plus every self-attested row.
- ADR-0005 (`docs/decisions/0005-separate-verifier-subagent.md:8-9`): the separate read-only verifier stands; its per-task consequence ("after a worker subagent completes a task") becomes one pass over every task's criteria at the end of the build.
Both old ADRs keep their bodies and gain a supersede note on the Status line, the convention ADR-0023 records ("the kit supersedes decisions ... it does not erase shipped history", `docs/decisions/0023-goal-draft-lifecycle.md:25`; example `docs/decisions/0011-goal-registry.md:3`). Number 0038 is free on main and on every sibling branch (`git ls-tree` on feat/lanes-as-data, ceremony-lens, execution-view, orca-mega-backend, adopt-pointer-onboarding tops out at 0036); if a sibling lands 0038 first, take the next free number.

### Boundaries & failure modes

Out of bounds: the other commands that name `kit:task-verifier` (`/kit:verify`, `/kit:dispatch`, `/kit:battery`, `/kit:debug`, `/kit:docs`, `/kit:greenlight`, `/kit:wrap`), `/kit:next`, and the verifiers' own checking logic. See `## Failure modes`.

## Requirements

R1. **Whole-spec brief.** `/kit:execute` dispatches ONE builder by default. Its prompt carries these labeled parts:
- `Goal`: the spec's `## Problem` and `## After state`.
- `Acceptance`: every acceptance criterion, the `## Verification` commands, and the `## Test plan` rows as data (keep the literal `## Test plan` reference; `tests/test-meta.sh:616-629` pins it).
- `Routes`: exact paths to read first: the spec, `docs/briefs/CONTEXT-<slug>.md` if present, each `References:` path, each file the spec names.
- `Territory`: the spec's `## Touches`; absent that, the files named in `## Task Breakdown`. A write outside territory is a stop-and-ask.
- The standing grant, verbatim: `Navigate the implementation yourself: derive what you need, decide your own build order; ask when stuck.`
- The kept worker rules: one commit per task (subject without IDs, as today), `docs/implementation-notes/<spec-slug>.md` upkeep, no `EnterWorktree`/`ExitWorktree`, the shell gotchas, stop on a blocker.
- The `## When done` return contract, extended: for each acceptance criterion the builder states `confirmed-by: run <command>` or `confirmed-by: read <file:line>`.
The prerequisite at `commands/execute.md:13` relaxes to: the spec has acceptance criteria, a `## Verification` section, and a `## Task Breakdown`. The tiering sentence stays verbatim, "workers dispatch at `sonnet` by default" (`tests/test-meta.sh:3043`); the builder is the worker.

R2. **Named-reason split and continuation.**
- A split happens only when the lead writes one reason from the closed list `unresolved-decision`, `territory-conflict`, `fork-risk` and records `bash lib/gate/gate-ledger.sh action "$RID" "split: <reason>: <slices>"`. Slices run one at a time; verification still runs once at the end.
- `fork-risk` threshold: more than 6 tasks in `## Task Breakdown` splits up front into slices of at most 6 tasks. Task count, not Touches count, because every executable spec has a task list (R1 prerequisite) while `## Touches` is optional (`commands/spec.md:226`), and a task is the unit the builder commits and reports on. 6 is a starting value; the AC-12 A/B run and later tagged runs tune it.
- Continuation: the builder commits after each task. When it nears its context limit it stops at a task boundary and returns `PROGRESS: done=<ids> remaining=<ids>`. The lead dispatches a continuation builder with the same brief narrowed to the remaining ids and records `split: fork-risk: continuation after <last done id>`.

R3. **Drop the persona dispatch.** Remove step 2b-0 (`commands/execute.md:120-165`) and the "bite-sized steps" mandate (`:231-236`). Keep ONE deterministic line: `bash lib/classify/role-classify.sh agent-for <domain>` on the spec text; a non-empty result names the builder's `subagent_type` (keeps `kit:db-migration-worker` and `kit:data-etl-worker` wired, and `tests/test-kit-contract.sh:324-328` green). Remove `### Mode C` from `agents/meta-agent.md:35-76`, its inline-spec clause in the mode chooser (`:15-17`, which becomes "Two modes"), and its exemption note (`:105`); this change orphans it (CLAUDE.md:47).

R4. **Verify once at the end.** Remove the per-task `kit:task-verifier` dispatch (`:255-292`), the per-task spec update loop (`:371-380`), and the phase checkpoints (`:382-405`). Step 4 then runs, in order:
1. The full suite and its verification-log entry (kept, `:411-415`).
2. ONE `kit:task-verifier` pass whose input is every task with its acceptance criteria, the whole-build diff from the base ref, and the builder's report. It returns one verdict per task plus the overall verdict.
3. `kit:integration-verifier` when `## Task Breakdown` lists more than one task (today's condition, `:439`).
4. `kit:acceptance-verifier` on every build. Its Bash allowlist (`agents/acceptance-verifier.md:4-12`) covers only `npm test`, `go test`, `pytest`, `bash tests/*`, `git diff`; it records `[NO EXECUTABLE CHECK]` for anything else (`:32`). The lead runs each such `## Verification` command itself and logs `Command:` / `Exit:` / `Output (excerpt):` with the literal tag `(lead-run)` on its Verdict line. A `(lead-run)` row cannot be rechecked: `kit:recheck-verifier` has the same narrow allowlist (`agents/recheck-verifier.md:4-12`), so the tag marks it as unaudited evidence rather than implying a re-audit. The read-only agents' allowlists are not widened.
5. **Check-edit signal:** `git diff --name-only <base> HEAD` intersected with the files the `## Verification` commands and the acceptance criteria name. A non-empty result is recorded as `check-edited: <paths>` and surfaced in the summary for the human; it is a finding, not a block.
Any FAIL:fixable routes through the kept fix-agent loop (max 2) and the attempt-state check (`:347-360`). Kept verbatim: verifier tier parity (`:182-188`), negative control (`:416-424`), proof-class gate (`:425-438`), build record and outcome bracket (`:484-495`). After an end PASS the lead checks off every task with `lib/spec/spec.sh task-done`. The human checkpoint moves to one point: before the builder dispatch (show the brief, ask to go).

R5. **Sampled recheck.** Replace both recheck sites (`:294-316`, `:444-457`) with one rule:
- `N=$(kit_config_get_root execute.recheck_sample 5)`. `0` turns sampling off; `1` rechecks every PASS (today's behavior).
- Key = HEAD at the FIRST end-verifier dispatch (step 2 of R4), read once with `git rev-parse HEAD` and reused. Fix-agent commits later in the run do not change it. The run is sampled when that SHA piped to `cksum` yields a first field divisible by N. Record `bash lib/gate/gate-ledger.sh action "$RID" "recheck: sampled key=<sha>"` or `"recheck: skipped key=<sha>"`, so anyone can recompute the decision.
- A sampled run rechecks every end-verifier PASS.
- Self-attested producer: each criterion the builder reports as `confirmed-by: read <file:line>` (confirmed by reading, not running) that no end verifier executed gets a verification-log row whose Verdict carries the literal tag `(self-attested)`. Every `(self-attested)` row is rechecked on every run, sampled or not.
- A PASS not rechecked gets `Re-audit: SKIPPED (sampled out, 1 in N)`.
- A recheck FAIL is recorded as `Re-audit: FAIL -- <finding>` and surfaced in the summary. It stays advisory + recorded, never a mid-flight hard block (`tests/test-right-arm-parity.sh:101-102` pins the phrase).
- Root-only key: a project `.kit.toml` rides inside an untrusted PR and must not lower verification. Adds `[execute] recheck_sample = 5` to `kit.toml`, a row in `lib/config/module-registry.md` and its `## Root-only keys` table, the operator-toml heredoc override `[execute]` / `recheck_sample = 1` in `tests/test-config-registry.sh:305-315`, and the KEYS row `execute.recheck_sample|5|1` (`:334-341`).

R6. **PARTIAL rule (M6), one paragraph.** When the build cannot meet a criterion after the fix loop: revise the claim down, mark the run `Result: PARTIAL`, name each unmet criterion and where the build stops with `file:line`, and route the gap as a follow-on in the final report. Building the missing capability inside this spec counts as scope creep. The acceptance verdict stays FAIL and names the criterion; PARTIAL never reads as PASS. The build record says `result=PARTIAL`; the outcome closes `caught=true policy=escalate`.

R7. **Shorter file.** `commands/execute.md` goes from 36055 bytes (base `c5981b0f`) to at most 30000 bytes. The frontmatter description and banner name whole-spec dispatch.

R8. **Run-id tag stays intact.** The `rid=<rid>` tag in every Agent dispatch description ships first as its own change (branch `feat/dispatch-rid-tag`). This spec rebases onto it and keeps the tag on every dispatch it writes or rewrites (builder, continuation builder, task-verifier pass, integration, acceptance, recheck, fix-agent). This spec does not introduce the tag.

R9. **Pinned tests.**
- `tests/test-meta.sh:1131-1135` (bite-sized marker): replace with an assertion on the R1 grant sentence.
- `tests/test-meta.sh:1258`: preflight wording "stops before task 1" becomes "stops before the build"; update with `commands/execute.md:60,63,65`.
- `tests/test-meta-agent.sh:45-55`: drop the Mode C and 2b-0 assertions; add a negative assertion that neither `agents/meta-agent.md` nor `commands/execute.md` mentions `Mode C`.
- `tests/test-right-arm-parity.sh:96-102`: assert the sampled rule (`execute.recheck_sample`, `recheck: sampled`, `(self-attested)`, `Re-audit: SKIPPED`) in place of "2+ recheck sites".
- `tests/test-role-classify.sh:47,49`: label text only.
- `tests/test-spec-task-done.sh:4`: header comment names "step 2e"; reword to the end-of-build check-off.
- `tests/test-config-registry.sh`: per R5.
- Must stay green unchanged: `tests/test-lane-escalation.sh:119-124`, `tests/test-outcome-emit-sweep.sh:69`, `tests/test-gate-vocab-recording.sh:72`, `tests/test-kit-contract.sh:320-330`, `tests/test-every-step-review.sh:23`, and the other `tests/test-meta.sh` execute pins (`:952-957`, `:1252-1261`, `:1436-1444`, `:2412-2451`, `:2473`, `:2493`, `:3042-3069`).
- New `tests/test-whole-spec-dispatch.sh`: the structural checks in `## Acceptance Criteria` plus the fixture check.
`tests/test-meta.sh` is a lead-owned hands-off surface (`docs/WORKFLOW.md` "### Hands-off shared-surface list").

R10. **Agent premise lines** (they describe the per-task pipeline as already run):
- `agents/task-verifier.md:3` description: "Run after each worker subagent completes a task" becomes a check of a task's acceptance criteria that its callers invoke per task or, under `/kit:execute`, once over every task of the build. Callers that name it: `commands/verify.md`, `dispatch.md`, `battery.md`, `debug.md`, `docs.md`, `greenlight.md`, `wrap.md`, `execute.md`.
- `agents/fix-agent.md:3,18`: name the end verifiers as feedback sources, not only task-verifier.
- `agents/integration-verifier.md:17,29`: "Each task in this build already passed `kit:task-verifier`" becomes "the end `kit:task-verifier` pass checked each task's criteria".
- `agents/acceptance-verifier.md:17,45`: same premise fix.
- `agents/data-etl-worker.md:3`, `agents/db-migration-worker.md:3`: "step 2b-0" becomes the builder lookup.

R11. **Docs describing the per-task spine.**
- `docs/WORKFLOW.md`, these sections only: "## The cycle (phase, exit, enforcer)" Build row (`:168-169`); "## The V-model lens" rows (`:241-242`, `:321-322`, `:342-344`); "## Role-specialist roster: two dispatch paths by type" (`:385-395`); "## Completion contract" (`:735`); "### The three bounded loops (engines)" execute pipeline paragraph and diagram (`:1237-1270`); "### The four hard stops (the only blockers)" verification row (`:1350`). SPEC-368 owns "## Size the work first" (`:51-70`, incl. `:62`), "## Lane×phase depth matrix" (`:409+`), and "### Pick a lane" (`:1159+`); untouched here.
- `docs/workflow-map.md:224` (phase checkpoint in the execute diagram).
- `docs/workflow-paths.md:117-120, 132, 262-264, 381, 414-417, 420`.
- `docs/verification/README.md:332` ("a run record at each phase checkpoint").
- `docs/guides/autonomy.md:19` ("check with me at each phase" row).
- `docs/MANUAL.md:201-203, 220, 223, 351, 363, 376-377, 491`.
- `docs/architecture.md:21, 44, 104, 116, 121, 169-170, 178, 462-467, 646, 717`.
- `README.md:3, 69, 210, 225, 247-272, 341, 372, 376`; `CLAUDE.md:7`.
- `commands/review-team.md:44` ("workers dispatch via /kit:execute 2b-0").
- `lib/classify/role-classify.sh:5, 11, 63`; `lib/spec/spec-task-done.sh:4` (comments).
- `docs/FEATURES.md`: regenerate with `bash lib/registry/feature-registry.sh generate`.
- ADR-0038 plus the supersede notes on ADR-0028 and ADR-0005.

R12. **Dispatch drop as a hypothesis, tested by an A/B run.** The estimate (about 56 to about 15 for a medium full-lane feature, E) stays a hypothesis until the post-ship A/B run (AC-12): ONE fixture spec run through the old spine (master just before SPEC-369 merges, which already carries the rid tag) and the new spine, both with `rid=<rid>`-tagged dispatches, with dispatch counts and tokens per run read by SPEC-367's reader and recorded side by side in `docs/verification/whole-spec-dispatch.md`. No doc claims the drop as fact before that record exists.

## Task Breakdown

### Phase 1: Command and config
- [ ] TASK-A: rewrite `commands/execute.md` per R1 to R8. AC-1 to AC-7.
- [ ] TASK-B: `[execute] recheck_sample = 5` in `kit.toml`, the `lib/config/module-registry.md` rows, the `tests/test-config-registry.sh` override and KEYS row. AC-6.
- [ ] TASK-C: R3 meta-agent Mode C removal and R10 agent premise lines; comments in `lib/classify/role-classify.sh`, `lib/spec/spec-task-done.sh`; `commands/review-team.md:44`. AC-4, AC-8.

### Phase 2: Tests and fixture
- [ ] TASK-D: R9 test updates, `tests/test-whole-spec-dispatch.sh`, `tests/fixtures/whole-spec-dispatch/`. AC-9.

### Phase 3: Docs and decision
- [ ] TASK-E1: ADR-0038 and the supersede notes on ADR-0028 and ADR-0005. AC-8.
- [ ] TASK-E2: R11 doc updates (WORKFLOW sections, workflow-map, workflow-paths, verification README, autonomy guide, MANUAL, architecture, README, CLAUDE.md). AC-8.
- [ ] TASK-E3: regenerate `docs/FEATURES.md`. AC-8.

### Phase 4: Trials (post-ship)
- [ ] TASK-F: run the T9 and T10 trials on the shipped command and log them with dispatch counts in `docs/verification/whole-spec-dispatch.md`. AC-10, AC-11.
- [ ] TASK-G: the A/B run (R12): the meetable fixture through the old spine and the new spine, both tagged, counts and tokens from SPEC-367's reader. AC-12.

## After state

- [ ] `/kit:execute` dispatches one builder with the R1 brief. (Today: one worker per task, `commands/execute.md:190-253`.)
- [ ] No persona meta-agent dispatch; `agents/meta-agent.md` has no Mode C. (Today: `commands/execute.md:150-162`, `agents/meta-agent.md:35`.)
- [ ] One task-verifier pass at the end checks every task's criteria; recheck is sampled on the HEAD sha plus every `(self-attested)` row. (Today: per task, recheck on every PASS.)
- [ ] `wc -c < commands/execute.md` prints 30000 or less. (Today: 36055.)
- [ ] ADR-0038 exists; ADR-0028 and ADR-0005 carry supersede notes.
- [ ] (post-ship) A seeded spec with one unmeetable criterion ends FAIL naming it, with `Result: PARTIAL`.

## Acceptance Criteria (global)

Run from the repo root. AC-1 to AC-9 gate the build; AC-10 to AC-12 are post-ship (they need the shipped command).

- [ ] AC-1 shorter: `test "$(wc -c < commands/execute.md)" -le 30000 && test "$(git show c5981b0f:commands/execute.md | wc -c)" -eq 36055`
- [ ] AC-2 brief: `grep -qF 'Navigate the implementation yourself: derive what you need, decide your own build order; ask when stuck.' commands/execute.md && grep -q 'Routes' commands/execute.md && grep -q 'Territory' commands/execute.md && grep -qF 'confirmed-by:' commands/execute.md && grep -qiE 'workers dispatch at .?sonnet.? by default' commands/execute.md`
- [ ] AC-3 split and continuation: `grep -qF 'unresolved-decision' commands/execute.md && grep -qF 'territory-conflict' commands/execute.md && grep -qF 'fork-risk' commands/execute.md && grep -qF 'PROGRESS: done=' commands/execute.md && grep -qF 'split: <reason>' commands/execute.md`
- [ ] AC-4 no persona dispatch: `! grep -qE 'Mode C|2b-0|kit:meta-agent|bite-sized' commands/execute.md && ! grep -q 'Mode C' agents/meta-agent.md && grep -qF 'role-classify.sh agent-for' commands/execute.md`
- [ ] AC-5 end verification: `test "$(grep -c 'kit:task-verifier' commands/execute.md)" -ge 1 && grep -qi 'every task' commands/execute.md && grep -q 'kit:acceptance-verifier' commands/execute.md && grep -q 'kit:integration-verifier' commands/execute.md && grep -qF 'check-edited:' commands/execute.md && grep -qi 'NEGATIVE CONTROL' commands/execute.md && grep -qF 'rid=<rid>' commands/execute.md`
- [ ] AC-6 sampled recheck: `grep -qF 'kit_config_get_root execute.recheck_sample 5' commands/execute.md && grep -qF 'recheck: sampled key=' commands/execute.md && grep -qF '(self-attested)' commands/execute.md && grep -qF 'Re-audit: SKIPPED (sampled out' commands/execute.md && bash tests/test-config-registry.sh`
- [ ] AC-7 PARTIAL: `grep -qF 'Result: PARTIAL' commands/execute.md && grep -qi 'scope creep' commands/execute.md && grep -qF 'file:line' commands/execute.md`
- [ ] AC-8 docs and decisions: `! grep -nE '2b-0|Mode C' docs/WORKFLOW.md docs/MANUAL.md docs/architecture.md docs/workflow-paths.md docs/workflow-map.md README.md CLAUDE.md commands/review-team.md agents/*.md lib/classify/role-classify.sh && ! grep -nE 'each phase checkpoint|phase checkpoint \(human' docs/workflow-map.md docs/workflow-paths.md docs/verification/README.md && bash lib/registry/feature-registry.sh check && test -f docs/decisions/0038-whole-spec-dispatch-sampled-reaudit.md && grep -q 'Superseded in part by ADR-0038' docs/decisions/0028-autonomous-loop-hardening.md && grep -q 'Superseded in part by ADR-0038' docs/decisions/0005-separate-verifier-subagent.md`
- [ ] AC-9 suites: `bash tests/test-meta.sh && bash tests/test-hooks.sh && bash tests/test-meta-agent.sh && bash tests/test-right-arm-parity.sh && bash tests/test-role-classify.sh && bash tests/test-kit-contract.sh && bash tests/test-lane-escalation.sh && bash tests/test-outcome-emit-sweep.sh && bash tests/test-gate-vocab-recording.sh && bash tests/test-every-step-review.sh && bash tests/test-spec-task-done.sh && bash tests/test-whole-spec-dispatch.sh`
- [ ] AC-10 (post-ship) negative control trial: `grep -A12 '^## NEGATIVE CONTROL' docs/verification/whole-spec-dispatch.md | grep -q 'Verdict: FAIL' && grep -A12 '^## NEGATIVE CONTROL' docs/verification/whole-spec-dispatch.md | grep -q 'AC-3' && grep -A12 '^## NEGATIVE CONTROL' docs/verification/whole-spec-dispatch.md | grep -qF 'Result: PARTIAL'`
- [ ] AC-11 (post-ship) dispatch hypothesis recorded: `grep -q 'Dispatches:' docs/verification/whole-spec-dispatch.md && grep -qi 'hypothesis' docs/verification/whole-spec-dispatch.md`
- [ ] AC-12 (post-ship) A/B run: `grep -A20 '^## A/B' docs/verification/whole-spec-dispatch.md | grep -q 'old spine' && grep -A20 '^## A/B' docs/verification/whole-spec-dispatch.md | grep -q 'new spine' && test "$(grep -A20 '^## A/B' docs/verification/whole-spec-dispatch.md | grep -cE 'Dispatches: [0-9]+')" -ge 2 && test "$(grep -A20 '^## A/B' docs/verification/whole-spec-dispatch.md | grep -cE 'Tokens: [0-9]+')" -ge 2`

## Verification

```bash
bash tests/test-whole-spec-dispatch.sh && bash tests/test-meta.sh && bash tests/test-hooks.sh \
  && bash tests/test-meta-agent.sh && bash tests/test-right-arm-parity.sh \
  && bash tests/test-config-registry.sh && bash tests/test-spec-task-done.sh \
  && bash lib/registry/feature-registry.sh check
```

## Test plan

| # | Case | Covers (AC) | Proof |
|---|---|---|---|
| T1 | execute.md at or under 30000 bytes; base is 36055 | AC-1 | `bash tests/test-whole-spec-dispatch.sh` |
| T2 | brief labels, grant sentence, `confirmed-by:`, sonnet tier phrase | AC-2 | same script |
| T3 | split closed list, fork-risk threshold, PROGRESS continuation | AC-3 | same script |
| T4 | no Mode C, 2b-0, meta-agent, bite-sized; agent-for kept | AC-4 | same script + `bash tests/test-kit-contract.sh` |
| T5 | one end task-verifier pass, acceptance + integration, check-edit signal, negative control, `rid=<rid>` | AC-5 | same script |
| T6 | recheck key: 5 by default, operator `1` wins, project toml ignored | AC-6 | `bash tests/test-config-registry.sh` |
| T7 | PARTIAL wording | AC-7 | same script |
| T8 | fixture is genuinely unmeetable: `check.sh unmeetable` exits non-zero printing `AC-3: FAIL`; `check.sh meetable` exits 0 on a tree where `hello.txt` holds `hello` | AC-10 | same script, on a temp copy |
| T9 | (post-ship) NEGATIVE CONTROL: `/kit:execute` on the unmeetable fixture ends `Verdict: FAIL` naming AC-3 and `Result: PARTIAL`; the check-edit signal is empty | AC-10 | recorded run in `docs/verification/whole-spec-dispatch.md` |
| T10 | (post-ship) positive trial: the meetable fixture ends PASS, so T9 is not an always-FAIL pipeline | AC-10 | recorded run, same log |
| T11 | structural negative control against the base command | AC-1..AC-7 | `t=$(mktemp -d) && git archive HEAD \| tar -x -C "$t" && git show c5981b0f:commands/execute.md >\| "$t/commands/execute.md" && ! bash "$t/tests/test-whole-spec-dispatch.sh"` |
| T12 | docs sweep, ADRs, FEATURES freshness | AC-8 | the AC-8 command |
| T13 | (post-ship) trial dispatch counts logged as a hypothesis | AC-11 | the AC-11 command |
| T14 | (post-ship) A/B: the meetable fixture through the old spine (master just before SPEC-369 merges) and the new spine, both tagged; SPEC-367's reader gives dispatches and tokens per rid; both logged under `## A/B` | AC-12 | the AC-12 command |

Fixture (new, `tests/fixtures/whole-spec-dispatch/`): `SPEC-900-unmeetable.md` (Lane: tiny, Status: VALIDATED; TASK-A writes `hello.txt` containing `hello`, AC-1; TASK-B names it in `README.md`, AC-2; AC-3 `[ $((2+2)) -eq 5 ]`; `## Touches` excludes `tests/**`; `## Verification`: `bash tests/fixtures/whole-spec-dispatch/check.sh unmeetable`), `SPEC-901-meetable.md` (same without AC-3), and `check.sh`. The trial copies the fixture into a `mktemp -d` git repo so the acceptance-verifier's `bash tests/*` grant can run the check. Lane tiny keeps the validation preflight out of the trial (`commands/execute.md:65`).

## Grounding

- No external data shape is asserted. Local samples: `wc -c commands/execute.md` printed `36055`, `wc -l` printed `513`. Recheck catches read at `docs/verification/loop-09-onboard-wizard.md:20` ("Round 1: FAIL:fixable , caught AC9 red") and ops-toolkit `tools/vps-mon/docs/verification/SPEC-133-macos-agent-go.md:132` ("The recheck-verifier's one FAIL:fixable was the anchored grep in the recorded command"). Per-task catches read at ops-toolkit `tools/circle/docs/verification/circle-intel.md:73` and `docs/retro/RETRO-2026-05-22-release-hygiene-guard.md:17`. `acceptance-verifier` tools read at `agents/acceptance-verifier.md:4-12`. `lane-classify.sh classify` printed `tiny` (text) and `normal` (`--files`).
- Negative control dry trace (T9): no kit mutation; the fixture's AC-3 is false by arithmetic. The builder builds `hello.txt` and the README line, committing per task, and cannot make `$((2+2))` equal 5. Step 4: the task-verifier pass reports AC-3 unmet; the acceptance-verifier runs `bash tests/fixtures/whole-spec-dispatch/check.sh unmeetable`, which prints `AC-3: FAIL` and exits 1. The fix loop runs at most twice and cannot change arithmetic, so the run applies the PARTIAL rule and logs `Verdict: FAIL` + `AC-3` + `Result: PARTIAL`. If the builder edits `check.sh`, the check-edit signal lists it and the trial is recorded as a territory failure.
- Structural negative control (T11): at `c5981b0f`, execute.md is 36055 bytes, carries `2b-0`, `Mode C`, `bite-sized`, and lacks the grant sentence, `check-edited:`, and `recheck: sampled key=`, so T1, T2, T4, T5, T6-wording go red.

## Edge Cases

1. Spec with no `## Touches`: territory falls back to `## Task Breakdown` files.
2. Spec with one task: integration-verifier skipped (today's rule); the task-verifier pass and acceptance-verifier still run.
3. Spec with 7+ tasks: up-front `split: fork-risk` into slices of at most 6.
4. Builder hits its context limit mid-slice: `PROGRESS:` return, continuation builder, `split: fork-risk: continuation`.
5. `execute.recheck_sample = 0`: no sampled rechecks; `(self-attested)` rows still rechecked.
6. `execute.recheck_sample = 1`: every PASS rechecked.
7. A project `.kit.toml` sets `recheck_sample = 0`: ignored (root-only); T6 proves it.
8. A `## Verification` command outside the acceptance-verifier allowlist: the lead runs and logs it tagged `(lead-run)`; it is never rechecked.
9. Builder goes silent: attempt-state resume via `SendMessage`, no retry spent (kept, `commands/execute.md:347-360`).
10. Builder reports a spec contradiction: stop and ask (kept, `:501`); added scope takes the mid-flight amend path.
11. A `Model: opus` spec: builder and every end verifier dispatch at opus (kept parity rule).
12. Split with a reason outside the closed list: not a split; one builder.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| A defect found late costs a bigger fix | fix loop exhausts on a large diff | per-task commits localize it; PARTIAL names the gap; follow-on routes it |
| Builder context overflows | builder returns `PROGRESS:` or stops mid-task | per-task commits; continuation builder recorded as `split: fork-risk`; the 6-task threshold splits big specs up front |
| Sampling misses a fabricated PASS | a later review or run finds it | `(self-attested)` rows always rechecked; `recheck_sample = 1` restores full coverage; tagged runs make catches countable |
| Builder edits a check to make it pass | `check-edited:` non-empty | surfaced in the summary; the task-verifier pass reads the criteria, not only the script |
| A Verification command the read-only verifier cannot run | `[NO EXECUTABLE CHECK]` in its record | the lead runs and logs it tagged `(lead-run)`, stated as not rechecked; the allowlists stay narrow |

## Out of Scope

- `/kit:verify`, `/kit:dispatch`, `/kit:battery`, `/kit:debug`, `/kit:docs`, `/kit:greenlight`, `/kit:wrap`: they keep their `kit:task-verifier` use. `/kit:next` and `/kit:mega` are unchanged.
- The verifiers' checking logic (only premise lines and one description change, R10).
- The worker model tier policy (`commands/execute.md:174-180`); see Open questions.
- Lane classification and the "when in doubt, heavier" rule (SPEC-368, D1).
- Building the ceremony lens that measures dispatches (SPEC-367).
- `commands/spec.md` template.

## Touches

A file path is not a `dir/**` prefix, so `lib/gate/dispatch-gate.sh` treats each one as unprovable and serializes this spec against every sibling. That is intended: it edits central surfaces shared with SPEC-368 (`docs/WORKFLOW.md`, `kit.toml`).
- commands/execute.md
- commands/review-team.md
- agents/meta-agent.md
- agents/task-verifier.md
- agents/fix-agent.md
- agents/integration-verifier.md
- agents/acceptance-verifier.md
- agents/data-etl-worker.md
- agents/db-migration-worker.md
- lib/classify/role-classify.sh
- lib/spec/spec-task-done.sh
- lib/config/module-registry.md
- kit.toml
- tests/test-meta.sh
- tests/test-meta-agent.sh
- tests/test-right-arm-parity.sh
- tests/test-role-classify.sh
- tests/test-config-registry.sh
- tests/test-spec-task-done.sh
- tests/test-whole-spec-dispatch.sh
- tests/fixtures/whole-spec-dispatch/**
- docs/WORKFLOW.md
- docs/workflow-map.md
- docs/workflow-paths.md
- docs/MANUAL.md
- docs/architecture.md
- docs/guides/autonomy.md
- docs/FEATURES.md
- docs/decisions/0038-whole-spec-dispatch-sampled-reaudit.md
- docs/decisions/0028-autonomous-loop-hardening.md
- docs/decisions/0005-separate-verifier-subagent.md
- docs/verification/README.md
- docs/verification/whole-spec-dispatch.md
- docs/implementation-notes/whole-spec-dispatch.md
- README.md
- CLAUDE.md

Overlap notes: `docs/WORKFLOW.md` sections are listed in R11 and are disjoint from SPEC-368's. `kit.toml` gets a new `[execute]` section only; SPEC-368 adds `[lane.*]`.

## Siblings

| Spec | Relation | Shared file |
|---|---|---|
| SPEC-366 execution-view | reads the run ledger; this spec adds `split:` and `recheck:` action lines and `result=PARTIAL` | none expected |
| SPEC-367 ceremony-lens | its reader supplies the AC-12 A/B dispatch and token counts, joined on the `rid=<rid>` tag | none expected |
| feat/dispatch-rid-tag | ships the `rid=<rid>` dispatch tag first; this spec rebases onto it (R8) | `commands/execute.md` (the tag lines) |
| SPEC-368 lanes-as-data | owns lane-classify, `kit.toml` lanes, WORKFLOW.md lane table | `docs/WORKFLOW.md` (disjoint sections, R11), `kit.toml` (different sections) |
| SPEC-370 orca-mega-backend | dispatches mega sub-goals; unaffected by execute's inner shape | none expected |
| SPEC-371 adopt-pointer-onboarding | adopted-repo AGENTS.md pointer | none expected |

## Decision Log

- DEC-1: whole-spec dispatch over trimming the per-task spine; trimming keeps most of the cost (Solution A).
- DEC-2: keep the criterion-level check as ONE end `kit:task-verifier` pass; it has caught defects a green suite missed, and integration-verifier does not re-check per-task acceptance (`agents/integration-verifier.md:29`).
- DEC-3: sample the recheck, do not delete it; it has caught two FAIL:fixable, and the wire-first rule applies.
- DEC-4: sample key is HEAD at the first end-verifier dispatch, recorded in the ledger, so later fix commits cannot move it and the decision is recomputable.
- DEC-5: the sample key is root-only (`lib/config/module-registry.md` "## Root-only keys").
- DEC-6: `fork-risk` threshold on task count (more than 6), since every executable spec has tasks and `## Touches` is optional.
- DEC-7: keep `role-classify.sh agent-for` as a zero-dispatch builder lookup; remove only the meta-agent hop and Mode C.
- DEC-8: a new ADR-0038 partially supersedes ADR-0028 and ADR-0005, per ADR-0023's supersede convention; no in-place rewrite.
- DEC-9: do not widen the acceptance-verifier's allowlist; the lead runs checks outside it and tags them `(lead-run)`, which are not rechecked.
- DEC-10: integration-verifier keeps today's multi-task condition.

## Open questions

1. Builder tier: keep the `sonnet` default for a whole-spec builder, or default it to opus on the full lane? This spec keeps sonnet.
2. N = 5 and the 6-task threshold are starting values; the AC-12 A/B run and later tagged runs should tune both from catch and overflow data.
