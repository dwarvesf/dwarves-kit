# Spec: whole-spec dispatch for /kit:execute

Generated: 2026-09-29
Status: DRAFT
Lane: full
Type: spec-feature
File: `docs/specs/SPEC-369-whole-spec-dispatch.md`
References: OpenRig `docs/reference/wave-sdlc.md:22-43` (the builder brief: goal, acceptance, routes, territory, self-navigation grant; a smaller chunk needs a named reason), and `:33-35` ("Detailed sequencing instructions were scaffolding when models were weak; today they are a cage"). Imitate the brief shape and the named-reason rule, nothing else.

Lane note: `lib/classify/lane-classify.sh classify` returns `tiny` on the task text and `normal` with `--files`. The spec takes `full` per the "when in doubt, take the heavier one" rule (`docs/WORKFLOW.md:62`), because the change rewrites the Build-phase HARD stop (`docs/WORKFLOW.md:168-169`) and removes per-task verification, which is a validation-removal change (`AGENTS.md:179`). The operator approved the direction (design D3, `docs/research/2026-09-29-openrig-absorption.md:114-122`).

## Problem

`/kit:execute` runs a per-task spine. For every task it may dispatch a persona meta-agent (`commands/execute.md:150-162`), then a worker (`:167-253`), then `kit:task-verifier` (`:255-292`), then an Opus `kit:recheck-verifier` (`:294-316`), then up to two fix-agent rounds (`:318-369`), then a human phase checkpoint (`:382-405`). The worker template also orders the builder to expand its task into "bite-sized steps" before coding (`:231-236`).

Three facts say this spine costs more than it catches:

1. The recheck-verifier has had its real trial. A recount on 2026-09-29 finds 33 `Re-audit: PASS` lines across 7 verification logs (kit: `docs/verification/precedent-inventory.md`, `dag-wavefront.md`, `kit-wrap.md`, `estate-seams.md`; ops-toolkit: `content-radar`, `vps-mon`, `circle`) and 0 `Re-audit: FAIL` lines in any verification log. The research record counted 29 and 0 (`docs/research/2026-09-29-openrig-absorption.md:60`). Either count gives a zero catch rate.
2. The kit's own audit rule keeps the recheck alive but allows sampling. The operator rejected retire-first in favor of wire-first, "retire reserved for a wire that proves dead after a real trial" (`docs/research/2026-07-04-kit-utilization-audit.md:8-10`), and the planned second trigger for the recheck was already a SAMPLED audit of self-attested rows (`:65`).
3. The estimate for a medium full-lane feature is about 56 dispatches end to end (`docs/research/2026-09-29-openrig-absorption.md:36-42`, marked E). The per-task loop is the largest multiplier in it.

`commands/execute.md` is 36055 bytes and 513 lines at base `c5981b0f`.

## Solution

### Approaches considered

- **A. Keep the per-task spine, trim it.** Drop the persona dispatch and sample the recheck, keep one worker and one task-verifier per task. Tradeoff: cuts about 2 dispatches per task, keeps the sequencing cage and the per-task verifier cost, and execute.md barely shrinks.
- **B. Whole-spec dispatch (chosen).** One builder gets the whole spec as a brief and navigates it. Verification runs once at the end (integration + acceptance). The recheck is sampled. A per-task split happens only when the brief names a reason from a closed list. Tradeoff: a failure is found later (at the end, not after the task that caused it), and one builder context carries the whole spec.
- **C. Opt-in whole-spec mode behind a flag, old spine as default.** Tradeoff: two pipelines in one command file, execute.md grows, and CLAUDE.md:47 ("Replace, don't deprecate") forbids keeping both.

### Chosen approach + why

B. It is the design the operator approved. A trades away most of the saving. C doubles the surface the operator asked to shrink. B's late-failure cost is bounded: the end verifiers name the failed criterion, the fix loop (max 2) still runs, and the negative control still bites.

### Extensibility & boundaries

- The load-bearing dimension is spec size. A spec too big for one builder context is exactly the `fork-risk` split reason; the split path handles it without a second pipeline.
- Units: (1) the brief assembler (the lead, inline prose, no new code), (2) the builder (one dispatch), (3) end verification (integration-verifier + acceptance-verifier), (4) the sampled recheck rule, (5) the PARTIAL rule. Each is one section of execute.md.

## Picture

```
 TODAY (per task, x N tasks)                      AFTER (once per spec)

 spec                                              spec
  |                                                 |
  v                                                 v
 +-- for each task ---------------------+         brief = goal + acceptance + routes
 | meta-agent Mode C (persona)          |                 + territory + grant
 | worker (bite-sized steps)            |           |   (split only with a named reason)
 | task-verifier                        |           v
 | recheck-verifier (Opus, every PASS)  |         ONE builder (navigates, own order)
 | fix-agent x2                         |           |
 +--------------------------------------+           v
  | phase checkpoint (human) per phase             integration-verifier + acceptance-verifier
  v                                                 |        |
 integration-verifier                              PASS    FAIL:fixable -> fix-agent x2 -> re-verify
  |                                                 |        FAIL:escalate / exhausted -> PARTIAL
 recheck-verifier (every PASS)                      v
  |                                                recheck-verifier: SAMPLED (1 in N runs)
  v                                                 + every (self-attested) row
 negative control -> summary                        |
                                                    v
                                                   negative control -> summary
```

## Design

Design-bearing: yes (it changes the Build-phase control flow and the right-arm re-audit contract of ADR-0028).

### Approaches considered + chosen

See `## Solution` above.

### Diagram

See `## Picture` above (a flowchart of both control flows).

### ADR link(s)

`docs/decisions/0028-autonomous-loop-hardening.md:34` decided "a fresh-context re-audit lens over each right-arm PASS". Sampling changes that decision, so this spec adds an `## Amendment` section to ADR-0028 (the in-place amendment convention already used by ADR-0017, 0025, 0029, 0034). The change is reversible by revert.

### Boundaries & failure modes

Out of bounds: `/kit:next` (manual per-task driving), `/kit:verify`, `/kit:dispatch`, `/kit:battery`, and the agents' own verification logic. See `## Failure modes`.

## Requirements

R1. **Whole-spec brief.** `/kit:execute` dispatches ONE builder by default. Its prompt carries exactly these labeled parts:
- `Goal`: the spec's `## Problem` and `## After state`.
- `Acceptance`: every acceptance criterion, the spec's `## Verification` commands, and the `## Test plan` rows as data (keep the literal `## Test plan` heading reference; `tests/test-meta.sh:616-629` pins it).
- `Routes`: exact paths to read first: the spec, `docs/briefs/CONTEXT-<slug>.md` if present, each `References:` path, and each file the spec names.
- `Territory`: the spec's `## Touches` globs; absent that, the files named in `## Task Breakdown`. A write outside territory is a stop-and-ask.
- The standing grant, verbatim: `Navigate the implementation yourself: derive what you need, decide your own build order; ask when stuck.`
- The kept worker rules: commit format, `docs/implementation-notes/<spec-slug>.md` upkeep, no `EnterWorktree`/`ExitWorktree`, the shell gotchas, stop on a blocker, and the `## When done` return contract.
`## Task Breakdown` stays readable input (a suggested order, not a mandate). The prerequisite at `commands/execute.md:13` relaxes to: the spec has acceptance criteria and a `## Verification` section.

R2. **Named-reason split.** A split into several builders happens only when the lead writes one reason from the closed list `unresolved-decision`, `territory-conflict`, `fork-risk` into the brief and records `bash lib/gate/gate-ledger.sh action "$RID" "split: <reason>: <slices>"`. Slices run one at a time; verification still runs once at the end.

R3. **Drop the persona dispatch.** Remove step 2b-0 (`commands/execute.md:120-165`) and the "bite-sized steps" mandate (`:231-236`). Keep ONE deterministic line: `bash lib/classify/role-classify.sh agent-for <domain>` on the spec text; a non-empty result names the builder's `subagent_type` (keeps `kit:db-migration-worker` and `kit:data-etl-worker` wired, and keeps `tests/test-kit-contract.sh:324-328` green). Remove `### Mode C` from `agents/meta-agent.md:35-76`, its inline-spec clause in the mode chooser (`:15-17`, which becomes "Two modes"), and its exemption note (`:105`), since this change orphans it (CLAUDE.md:47).

R4. **Verify once at the end.** Remove per-task `kit:task-verifier` dispatch (`:255-292`), per-task spec update loop (`:371-380`), and phase checkpoints (`:382-405`). Step 4 dispatches `kit:acceptance-verifier` on every build and `kit:integration-verifier` when `## Task Breakdown` lists more than one task (today's condition, `:439`). Route FAIL:fixable through the existing fix-agent loop (max 2) and the attempt-state check (`:347-360`). Keep the verifier tier parity sentence (`:182-188`), the Step 4 verification-log entry (`:411-415`), the negative control (`:416-424`), the proof-class gate (`:425-438`), and the build record and outcome bracket (`:484-495`). After an end PASS the lead checks off every task with `lib/spec/spec.sh task-done`. The human checkpoint moves to one point: before the builder dispatch (show the brief, ask to go).

R5. **Sampled recheck.** Replace both recheck sites (`:294-316`, `:444-457`) with one rule:
- `N=$(kit_config_get_root execute.recheck_sample 5)`. `0` turns sampling off; `1` rechecks every PASS (today's behavior).
- The run is sampled when `printf '%s' "$RID" | cksum` yields a first field divisible by N. A sampled run rechecks every end-verifier PASS.
- Every verification-log row whose Verdict line carries the literal tag `(self-attested)` is rechecked on every run. A self-attested row is one whose result came only from the builder's own run and that no end verifier re-executed.
- A PASS not rechecked gets `Re-audit: SKIPPED (sampled out, 1 in N)` so the trust metric keeps an honest denominator.
- A recheck FAIL is recorded as `Re-audit: FAIL -- <finding>` and surfaced in the Step 4 summary. It stays advisory + recorded, never a mid-flight hard block (keep that phrase; `tests/test-right-arm-parity.sh:101-102` pins it).
- The key is root-only (a project `.kit.toml` rides inside an untrusted PR and must not lower verification): a `[execute]` section in `kit.toml`, a row in `lib/config/module-registry.md` plus its `## Root-only keys` table, and a KEYS row in `tests/test-config-registry.sh:339`.

R6. **PARTIAL rule (M6), one paragraph.** When the build cannot meet a criterion after the fix loop: revise the claim down, mark the run `Result: PARTIAL`, name each unmet criterion and where the build stops with `file:line`, and route the gap as a follow-on in the final report. Building the missing capability inside this spec counts as scope creep. The acceptance verdict line stays FAIL and names the criterion; PARTIAL never reads as PASS. The build record says `result=PARTIAL` and the outcome closes `caught=true policy=escalate`.

R7. **Shorter file.** `commands/execute.md` goes from 36055 bytes (base `c5981b0f`) to at most 30000 bytes. The frontmatter description and banner name whole-spec dispatch.

R8. **Pinned tests updated, not deleted wholesale.**
- `tests/test-meta.sh:1131-1135` (bite-sized marker): replace with an assertion on the R1 grant sentence.
- `tests/test-meta.sh:1258`: preflight wording "stops before task 1" becomes "stops before the build"; update the assertion and `commands/execute.md:60,63,65` together.
- `tests/test-meta-agent.sh:45-55`: drop the Mode C and 2b-0 assertions; add a negative assertion that neither `agents/meta-agent.md` nor `commands/execute.md` mentions `Mode C`.
- `tests/test-right-arm-parity.sh:96-102`: assert the sampled rule (`execute.recheck_sample`, `(self-attested)`, `Re-audit: SKIPPED`) in place of "2+ recheck sites".
- `tests/test-role-classify.sh:47,49`: label text only (drop "Mode-C" and "2b-0").
- Must stay green unchanged: `tests/test-lane-escalation.sh:119-124`, `tests/test-outcome-emit-sweep.sh:69`, `tests/test-gate-vocab-recording.sh:72`, `tests/test-kit-contract.sh:320-330`, `tests/test-every-step-review.sh:23`, and the rest of `tests/test-meta.sh` execute pins (`:952-957`, `:1252-1261`, `:1436-1444`, `:2412-2451`, `:2473`, `:2493`, `:3042-3069`).
- New `tests/test-whole-spec-dispatch.sh`: the structural checks in `## Acceptance Criteria` plus the fixture check below.
`tests/test-meta.sh` is a lead-owned hands-off surface (`docs/WORKFLOW.md` "### Hands-off shared-surface list"); under `/kit:dispatch` the lead writes it.

R9. **Docs describing the per-task spine.**
- `docs/WORKFLOW.md`, these sections only: "## The cycle (phase, exit, enforcer)" Build row (`:168-169`); "## The V-model lens" rows (`:241-242`, `:321-322`, `:342-344`); "## Role-specialist roster: two dispatch paths by type" (`:385-395`); "## Completion contract" (`:735`); "### The three bounded loops (engines)" execute pipeline paragraph and diagram (`:1237-1270`); "### The four hard stops (the only blockers)" verification row (`:1350`). SPEC-368 owns "## Size the work first" (`:51-70`, incl. `:62`), "## Lane×phase depth matrix" (`:409+`), and "### Pick a lane" (`:1159+`); this spec does not touch them.
- `docs/MANUAL.md:201-203, 220, 223, 351, 363, 376-377`.
- `docs/architecture.md:21, 44, 104, 116, 121, 178, 462-467, 646, 717`.
- `docs/workflow-paths.md:117-120, 262-264, 381, 414-417, 420`.
- `README.md:3, 69, 210, 225, 247-272, 341, 372, 376`.
- `CLAUDE.md:7`.
- `commands/review-team.md:44` (the "workers dispatch via /kit:execute 2b-0" parenthetical).
- `agents/data-etl-worker.md:3`, `agents/db-migration-worker.md:3` (descriptions name "step 2b-0").
- `lib/classify/role-classify.sh:5, 11, 63` (comments name Mode C and 2b-0), `lib/spec/spec-task-done.sh:4` (comment names step 2e).
- `docs/FEATURES.md`: regenerate with `bash lib/registry/feature-registry.sh generate` (it projects the changed descriptions).
- `docs/decisions/0028-autonomous-loop-hardening.md`: the `## Amendment`.

R10. **Dispatch drop as a hypothesis.** The verification log records the dispatch count of each trial run and states the estimate (about 56 to about 15 for a medium full-lane feature, E) as a hypothesis for SPEC-367's ceremony lens to measure. No doc claims the drop as fact.

## Task Breakdown

### Phase 1: Command and config
- [ ] TASK-A: rewrite `commands/execute.md` per R1 to R7 (brief, split rule, drop 2b-0 and per-task verify, end verification, sampled recheck, PARTIAL, preflight wording). AC-1 to AC-7.
- [ ] TASK-B: `[execute] recheck_sample = 5` in `kit.toml`, its `lib/config/module-registry.md` rows, and the `tests/test-config-registry.sh` KEYS row. AC-6.
- [ ] TASK-C: remove Mode C from `agents/meta-agent.md`; update descriptions in `agents/data-etl-worker.md`, `agents/db-migration-worker.md`; comments in `lib/classify/role-classify.sh`, `lib/spec/spec-task-done.sh`; `commands/review-team.md:44`. AC-4, AC-8.

### Phase 2: Tests and fixture
- [ ] TASK-D: R8 test updates plus `tests/test-whole-spec-dispatch.sh` and `tests/fixtures/whole-spec-dispatch/`. AC-9, T8, T11.

### Phase 3: Docs and trials
- [ ] TASK-E: R9 doc updates, ADR-0028 amendment, `docs/FEATURES.md` regenerate. AC-8.
- [ ] TASK-F: run T9 and T10 trials, log them with dispatch counts in `docs/verification/whole-spec-dispatch.md`. AC-10, AC-11.

## After state

- [ ] `/kit:execute` dispatches one builder with the R1 brief. (Today: one worker per task, `commands/execute.md:190-253`.)
- [ ] No persona meta-agent dispatch exists; `agents/meta-agent.md` has no Mode C. (Today: `commands/execute.md:150-162`, `agents/meta-agent.md:35`.)
- [ ] Verification runs once at the end; recheck is sampled plus every `(self-attested)` row. (Today: per task plus every PASS.)
- [ ] `wc -c < commands/execute.md` prints 30000 or less. (Today: 36055.)
- [ ] A seeded spec with one unmeetable criterion ends FAIL naming it, with `Result: PARTIAL`.

## Acceptance Criteria (global)

Run from the repo root. Each line is its own check.

- [ ] AC-1 shorter: `test "$(wc -c < commands/execute.md)" -le 30000 && test "$(git show c5981b0f:commands/execute.md | wc -c)" -eq 36055`
- [ ] AC-2 brief: `grep -qF 'Navigate the implementation yourself: derive what you need, decide your own build order; ask when stuck.' commands/execute.md && grep -qE 'Goal' commands/execute.md && grep -qE 'Routes' commands/execute.md && grep -qE 'Territory' commands/execute.md`
- [ ] AC-3 named split: `grep -qF 'unresolved-decision' commands/execute.md && grep -qF 'territory-conflict' commands/execute.md && grep -qF 'fork-risk' commands/execute.md && grep -qF 'split: <reason>' commands/execute.md`
- [ ] AC-4 no persona dispatch: `! grep -qE 'Mode C|2b-0|kit:meta-agent|bite-sized' commands/execute.md && ! grep -q 'Mode C' agents/meta-agent.md && grep -qF 'role-classify.sh agent-for' commands/execute.md`
- [ ] AC-5 end verification: `! grep -q 'kit:task-verifier' commands/execute.md && grep -q 'kit:acceptance-verifier' commands/execute.md && grep -q 'kit:integration-verifier' commands/execute.md && grep -qi 'NEGATIVE CONTROL' commands/execute.md`
- [ ] AC-6 sampled recheck: `grep -qF 'kit_config_get_root execute.recheck_sample 5' commands/execute.md && grep -qF '(self-attested)' commands/execute.md && grep -qF 'Re-audit: SKIPPED (sampled out' commands/execute.md && bash tests/test-config-registry.sh`
- [ ] AC-7 PARTIAL: `grep -qF 'Result: PARTIAL' commands/execute.md && grep -qi 'scope creep' commands/execute.md && grep -qF 'file:line' commands/execute.md`
- [ ] AC-8 docs: `! grep -nE '2b-0|Mode C' docs/WORKFLOW.md docs/MANUAL.md docs/architecture.md docs/workflow-paths.md README.md CLAUDE.md commands/review-team.md agents/*.md lib/classify/role-classify.sh && bash lib/registry/feature-registry.sh check && grep -q '^## Amendment' docs/decisions/0028-autonomous-loop-hardening.md`
- [ ] AC-9 suites: `bash tests/test-meta.sh && bash tests/test-hooks.sh && bash tests/test-meta-agent.sh && bash tests/test-right-arm-parity.sh && bash tests/test-role-classify.sh && bash tests/test-kit-contract.sh && bash tests/test-lane-escalation.sh && bash tests/test-outcome-emit-sweep.sh && bash tests/test-gate-vocab-recording.sh && bash tests/test-every-step-review.sh && bash tests/test-whole-spec-dispatch.sh`
- [ ] AC-10 negative control trial: `grep -A12 '^## NEGATIVE CONTROL' docs/verification/whole-spec-dispatch.md | grep -q 'Verdict: FAIL' && grep -A12 '^## NEGATIVE CONTROL' docs/verification/whole-spec-dispatch.md | grep -q 'AC-3' && grep -A12 '^## NEGATIVE CONTROL' docs/verification/whole-spec-dispatch.md | grep -qF 'Result: PARTIAL'`
- [ ] AC-11 dispatch hypothesis recorded: `grep -q 'Dispatches:' docs/verification/whole-spec-dispatch.md && grep -qi 'hypothesis' docs/verification/whole-spec-dispatch.md`

## Verification

```bash
bash tests/test-whole-spec-dispatch.sh && bash tests/test-meta.sh && bash tests/test-hooks.sh \
  && bash tests/test-meta-agent.sh && bash tests/test-right-arm-parity.sh \
  && bash tests/test-config-registry.sh && bash lib/registry/feature-registry.sh check
```

## Test plan

| # | Case | Covers (AC) | Proof |
|---|---|---|---|
| T1 | execute.md byte count at or under 30000; base is 36055 | AC-1 | `bash tests/test-whole-spec-dispatch.sh` (asserts both numbers) |
| T2 | brief labels and the grant sentence present | AC-2 | same script |
| T3 | split closed list and the ledger action line present | AC-3 | same script |
| T4 | no Mode C, 2b-0, meta-agent, bite-sized in execute.md; agent-for kept | AC-4 | same script + `bash tests/test-kit-contract.sh` |
| T5 | no per-task task-verifier; acceptance + integration + negative control present | AC-5 | same script |
| T6 | recheck key resolves 5 by default, honors operator toml, ignores project toml | AC-6 | `bash tests/test-config-registry.sh` |
| T7 | PARTIAL rule wording | AC-7 | same script |
| T8 | fixture is genuinely unmeetable: `bash tests/fixtures/whole-spec-dispatch/check.sh unmeetable` exits non-zero and prints `AC-3: FAIL`; `check.sh meetable` exits 0 on a tree where `hello.txt` holds `hello` | AC-10 | same script (runs both on a temp copy) |
| T9 | NEGATIVE CONTROL trial: `/kit:execute` on the unmeetable fixture ends `Verdict: FAIL` naming AC-3 and `Result: PARTIAL`; `git diff --quiet <base> -- tests/` shows the builder never edited the check | AC-10 | recorded run in `docs/verification/whole-spec-dispatch.md` |
| T10 | positive trial: the meetable fixture ends PASS (proves T9 is not an always-FAIL pipeline) | AC-10 | recorded run, same log |
| T11 | structural negative control: restore `c5981b0f:commands/execute.md` into a temp tree, run `tests/test-whole-spec-dispatch.sh` against it, expect red on T1-T7 | AC-1..AC-7 | `t=$(mktemp -d) && git archive HEAD | tar -x -C "$t" && git show c5981b0f:commands/execute.md >| "$t/commands/execute.md" && ! bash "$t/tests/test-whole-spec-dispatch.sh"` |
| T12 | docs sweep and FEATURES freshness | AC-8 | the AC-8 command |
| T13 | trial dispatch counts logged with the hypothesis wording | AC-11 | the AC-11 command |

Fixture (new, `tests/fixtures/whole-spec-dispatch/`): `SPEC-900-unmeetable.md` (Lane: tiny, Status: VALIDATED; AC-1 `hello.txt` contains `hello`; AC-2 `README.md` names `hello.txt`; AC-3 `[ $((2+2)) -eq 5 ]`; `## Touches` excludes `tests/**`; `## Verification`: `bash tests/fixtures/whole-spec-dispatch/check.sh unmeetable`), `SPEC-901-meetable.md` (same without AC-3), and `check.sh`. The trial copies the fixture into a `mktemp -d` git repo, so the acceptance-verifier's `Bash(bash tests/*)` grant (`agents/acceptance-verifier.md:4-12`) can run the check. Lane tiny keeps the validation preflight out of the trial (`commands/execute.md:65`).

## Grounding

- No external data shape is asserted. Local samples: `wc -c commands/execute.md` printed `36055`; `wc -l` printed `513`. `grep -rhoE 'Re-audit: PASS' --include='*.md'` over kit `docs/` and ops-toolkit `docs/ tools/` found 33 lines in 7 verification logs; the only `Re-audit: FAIL` hit is prose in the research record itself. `lane-classify.sh classify` printed `tiny` (text) and `normal` (with `--files`).
- Negative control dry trace (T9): mutation = none to the kit; the fixture's AC-3 is false by arithmetic. The builder reads the brief, builds `hello.txt` and the README line, and cannot make `$((2+2))` equal 5. Step 4 dispatches `kit:acceptance-verifier`, which runs `bash tests/fixtures/whole-spec-dispatch/check.sh unmeetable`; `check.sh` prints `AC-3: FAIL` and exits 1. The verifier returns FAIL naming AC-3. The fix loop runs at most twice and cannot change arithmetic, so the run exits the loop, applies the PARTIAL rule, and logs `Verdict: FAIL` + `AC-3` + `Result: PARTIAL`. If the builder instead edits `check.sh`, `git diff --quiet <base> -- tests/` goes non-zero and the trial is recorded as a failure of the territory rule.
- Structural negative control (T11): at `c5981b0f`, execute.md is 36055 bytes, carries `2b-0`, `Mode C`, `bite-sized`, `kit:task-verifier`, and lacks the grant sentence, so T1, T2, T4, T5 go red.

## Edge Cases

1. Spec with no `## Touches`: territory falls back to `## Task Breakdown` files; neither present means the builder asks before its first write.
2. Spec with one task: integration-verifier skipped (today's rule); acceptance-verifier still runs.
3. `execute.recheck_sample = 0`: no sampled rechecks, but `(self-attested)` rows are still rechecked.
4. `execute.recheck_sample = 1`: every PASS rechecked (today's behavior).
5. A project `.kit.toml` sets `recheck_sample = 0`: ignored (root-only); T6 proves it.
6. Builder goes silent: attempt-state resume via `SendMessage`, no retry spent (kept from `commands/execute.md:347-360`).
7. Builder reports a spec contradiction: stop and ask (kept from `:501`); a scope addition takes the mid-flight amend path.
8. A `Model: opus` spec: builder and end verifiers dispatch at opus (kept parity rule).
9. Split with a reason outside the closed list: not a split; the lead dispatches one builder.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| A defect found late (end, not per task) costs a bigger fix | fix loop exhausts on a large diff | PARTIAL rule names the gap; follow-on routes it; `fork-risk` split for big specs |
| Builder context overflows on a big spec | builder stops or compacts mid-build | `fork-risk` split; the post-compact re-inject (D4, shipped) restores the spec |
| Sampling misses a fabricated PASS | a later run or review finds it | `(self-attested)` rows always rechecked; `recheck_sample = 1` restores full coverage; SPEC-367 lens tracks catches |
| Builder edits the check to make it pass | `git diff <base> -- <check path>` non-empty | territory rule; acceptance-verifier re-reads the spec's AC, not only the script |

## Out of Scope

- `/kit:next`, `/kit:verify`, `/kit:dispatch`, `/kit:battery`, `/kit:mega`: they keep their own verifier use; `kit:task-verifier` stays dispatched by them, so it is not orphaned.
- Agent verification logic and `agents/task-verifier.md`, `agents/integration-verifier.md`, `agents/acceptance-verifier.md` bodies.
- The worker model tier policy (`commands/execute.md:174-180`); see Open questions.
- Lane classification and the `when in doubt, heavier` rule (SPEC-368, D1).
- Building the ceremony lens that measures dispatches (SPEC-367).
- `commands/spec.md` template (`## Task Breakdown` stays in the template).

## Touches

A file path is not a `dir/**` prefix, so `lib/gate/dispatch-gate.sh` treats each one as unprovable and serializes this spec against every sibling. That is intended: the spec edits central surfaces shared with SPEC-368 (`docs/WORKFLOW.md`, `kit.toml`).
- commands/execute.md
- commands/review-team.md
- agents/meta-agent.md
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
- tests/test-whole-spec-dispatch.sh
- tests/fixtures/whole-spec-dispatch/**
- docs/WORKFLOW.md
- docs/MANUAL.md
- docs/architecture.md
- docs/workflow-paths.md
- docs/FEATURES.md
- docs/decisions/0028-autonomous-loop-hardening.md
- docs/verification/whole-spec-dispatch.md
- docs/implementation-notes/whole-spec-dispatch.md
- README.md
- CLAUDE.md

Overlap notes: `docs/WORKFLOW.md` sections are listed in R9 and are disjoint from SPEC-368's sections. `kit.toml` gets a new `[execute]` section only; SPEC-368 adds `[lane.*]`.

## Siblings

| Spec | Relation | Shared file |
|---|---|---|
| SPEC-366 execution-view | reads the run ledger; this spec adds `split:` action lines and `result=PARTIAL` to the build record it may render | none expected |
| SPEC-367 ceremony-lens | measures R10's dispatch hypothesis | none expected |
| SPEC-368 lanes-as-data | owns lane-classify, `kit.toml` lanes, WORKFLOW.md lane table | `docs/WORKFLOW.md` (disjoint sections, R9), `kit.toml` (different sections) |
| SPEC-370 orca-mega-backend | dispatches mega sub-goals; unaffected by execute's inner shape | none expected |
| SPEC-371 adopt-pointer-onboarding | adopted-repo AGENTS.md pointer | none expected |

## Decision Log

- DEC-1: whole-spec dispatch over trimming the per-task spine; trimming keeps most of the cost (Solution A).
- DEC-2: sample the recheck, do not delete it; stays inside the wire-first rule (`docs/research/2026-07-04-kit-utilization-audit.md:8-10`).
- DEC-3: sampling keys on the rid hash, so the decision is reproducible per run and needs no counter state.
- DEC-4: the sample key is root-only, since a project `.kit.toml` rides inside an untrusted PR (`lib/config/module-registry.md` "## Root-only keys").
- DEC-5: keep `role-classify.sh agent-for` as a zero-dispatch builder lookup; remove only the meta-agent synthesis hop and Mode C.
- DEC-6: amend ADR-0028 in place rather than mint a new ADR number, to avoid a number race with the sibling specs.
- DEC-7: integration-verifier keeps today's multi-task condition; acceptance-verifier runs on every build.

## Open questions

1. Builder tier: a whole-spec builder reasons more than a per-task worker. Keep the `sonnet` default (`commands/execute.md:174-180`) or default the builder to opus on the full lane? This spec keeps sonnet.
2. Default N = 5 is a guess. SPEC-367's lens should tune it from catch data.
