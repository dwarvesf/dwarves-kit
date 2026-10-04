# Spec: gate-ledger inherit, one call that carries a validated spec's gates onto a task branch
Generated: 2026-10-04
Status: DRAFT
Lane: full (kit machinery: `lib/gate/gate-ledger.sh` is the enforcement surface the ship-gate reads; the verb writes lines that satisfy `check()`)
Depth: standard (every ledger shape this spec rests on was sampled live; see ## Grounding)
Type: spec-feature
File: `docs/specs/SPEC-393-task-gate-inherit.md`
References: `lib/gate/gate-ledger.sh` `override()` (lines 451-471: the write path and the distinct-reason guard to reuse unchanged); `check()` (lines 476-500: the `ran|override` predicate the inherited lines must satisfy); `plan_record()` (lines 572-680: refuse-before-write, one printed line per phase written); `hooks/ship-gate.sh` line 474 (the last-state read of a phase, `{s=$4} END{...}`, the semantics this verb copies for the parent)

## Problem

An approved multi-task spec passes the spec-level gates once, on its own rid: think, design,
design-critique, spec, validate, design-record and test-plan. Each task branch built under that
spec is a separate rid, and the ship-gate checks the full lane on it. So each task branch must
show all seven spec-level gates again.

Today the lead hand-writes seven `gate-ledger.sh override` lines per task branch, from a scratch
script. One session did this about 25 times. The live corpus holds 37 run logs with these
hand-written lines (see ## Grounding). Each line is free text, so nothing checks that the parent
spec actually passed the gate the override cites. A task branch can claim "validate ran under
rid watch-hub-spec" while that rid holds no `validate ran` line at all.

The scratch script this replaces (quoted as data):

```
spec="SPEC-003 watch-hub (APPROVED, DEC-48); spec-level gates live under rid watch-hub-spec"
bash "$L" override "$slug" think "$spec: ..." ; ... design, design-critique, spec, validate, design-record, test-plan
bash "$L" record "$slug" build ran "..."; record review ran "..."; record docs ran "..."
bash "$L" override "$slug" ship "..."; override reflect "..."
KIT_PROJECT_ROOT=$PWD bash "$L" check full "$slug" --kit-lanes
```

## Solution

### Approaches considered

1. **A new `inherit` verb that writes `override` lines with a machine-built reason.** The verb
   reads the parent ledger, refuses unless every inherited gate's last state there is `ran`, then
   writes one `| GATE | <phase> | override | inherited from <parent>: ...` line per phase through
   the existing `override()`. Tradeoff: lane telemetry counts the lines as overrides, though
   the reason prefix tells them apart.
2. **A new GATE state `inherited`.** More honest in stats. Tradeoff: every reader that keys on
   the state must learn it: `check()` (line 494), the ship-gate's validate-size read (line 474),
   `lane-telemetry.sh` (line 226-228), and the stats gate-yield rows. Four readers change to save
   one reason prefix.
3. **Extend `plan-record` with a `--from <parent>` flag.** Tradeoff: `plan-record` must dispose
   every plan phase in one call, but build, review and docs happen later on the task branch. The
   two jobs run at different times, so one verb would need a partial mode.

### Chosen approach + why

Approach 1. It adds one verb and changes no reader, so the load-bearing invariant in
`lib/gate/README.md` ("only a `| GATE |` line in state `ran` or `override` satisfies `check()`")
holds as written. An override is already the ledger's word for "this gate did not run on this
rid, and here is the audited why". Inheritance is that, with the why built by the verb from
evidence instead of typed by a human. Approach 2 stays open if stats later need to split
inherited from hand overrides; the fixed reason prefix makes that a read-side change.

### Extensibility & boundaries

- Load-bearing dimension: task branches per spec. The verb reads one parent ledger and writes at
  most seven lines, so cost is constant per branch. A spec with 40 tasks makes 40 calls.
- One unit: `inherit()` in `gate-ledger.sh`. It resolves the parent, judges the parent, and
  writes through `override()`. It owns no new file and no new marker.

### Architecture

See `## Design`.

## Picture

```
  spec branch (rid watch-hub-spec)            task branch (rid wh-t12h)
  +-------------------------------+           +-------------------------------+
  | GATE think          ran       |           |                               |
  | GATE design         ran       |  inherit  | GATE think     override       |
  | GATE design-critique ran      | --------> |   "inherited from             |
  | GATE spec           ran       |  reads    |    watch-hub-spec: think ran  |
  | GATE validate  skipped..ran   |  last     |    there at <ts>"             |
  | GATE design-record  ran       |  state    | ... one line per phase ...    |
  | GATE test-plan      ran       |  per      |                               |
  +-------------------------------+  phase    | GATE build     ran   (per     |
                                              | GATE review    ran    branch, |
          any phase not `ran`                 | GATE docs      ran    never   |
          => refuse, write nothing            |                inherited)     |
                                              +---------------+---------------+
                                                              |
                                                              v
                                              hooks/ship-gate.sh -> check full
```

## Design

### Approaches considered + chosen

See `## Solution`. The design view adds one point: the parent judgment reads the LAST GATE line
per phase, not "any ran". The ship-gate already reads validate that way (line 474). A parent
that ran validate APPROVED and later recorded a NEEDS-REVISION skip has not passed validate now.

### Diagram (flowchart)

```
inherit <rid> <lane> --from <P>
   |
   +-- args bad / rid empty ------------------------------> exit 64
   +-- lane unknown (required() fails) ------------------> exit 1
   |
   +-- P ends in .md? -- yes --> file missing ----------> exit 1
   |        |                    else parent = runid(slug of SPEC-NNN-<slug>.md)
   |        no --> parent = runid(P)
   |
   +-- parent == rid ------------------------------------> exit 64
   +-- S = INHERITABLE in order, kept if required(lane)
   |     S empty ----------------------------------------> exit 64
   +-- parent ledger missing ----------------------------> exit 1
   |
   +-- for each phase in S: last GATE state in parent
   |     none / skipped / override  => collect a failure line
   |     any failure --------------> print all, exit 1, write nothing
   |
   +-- child ledger: an "inherited from Q" line for a phase in S, Q != parent
   |                 --------------------------------------> exit 65, write nothing
   |
   +-- for each phase in S:
   |     child already has "inherited from <parent>" for it => print "already", skip
   |     else override "$rid" "$phase" "inherited from <parent>: <phase> ran there at <ts>[; spec <path>]"
   |
   +-- exit 0
```

### ADR link(s)

None needed. The verb adds no state, no marker and no reader change. ADR-0024 (the gate ledger)
already sanctions `override` as the audited not-run-here path.

### Boundaries & failure modes

Out of bounds: build, review, docs, ship, reflect, grill and ui-design. These stay per branch
(build, review, docs) or belong to the push and the session close (ship, reflect). See
`## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

```
gate-ledger.sh inherit <rid> <lane> --from <parent-rid | path/to/SPEC-NNN-<slug>.md>
```

- Inputs: the parent rid's run ledger `runs/<parent>.log` (read only), the child's run ledger
  (read for the conflict and idempotency checks), the lane data via `required()`. A spec-file
  `--from` must exist on disk. Its basename minus `SPEC-<digits>-` and `.md` is the parent rid,
  the same slug-to-spec match `spec_for_slug` uses in reverse.
- `INHERITABLE`, a fixed ordered list in the script: `think design design-critique spec validate
  design-record test-plan`. The set written is `INHERITABLE` filtered to what `required <lane>`
  prints. For `full` that is all seven; for `normal` it is `spec` alone; for `bug` and `backfill`
  it is empty, so the verb refuses.
- Outputs: one `| GATE | <phase> | override | <reason>` line per phase, written by `override()`.
  Reason, built by the verb, no free text: `inherited from <parent>: <phase> ran there at <ts>`,
  plus `; spec <path>` when `--from` was a file. `<ts>` is the timestamp of the parent's last
  `ran` line for that phase. Stdout: one line per phase, `<phase> inherited from <parent>` or
  `<phase> already inherited from <parent>`.
- Exit codes: 0 written (or all already present); 1 the parent has not passed, or no parent
  ledger, or an unknown lane, or a missing spec file; 64 usage, self-parent, or nothing to
  inherit for the lane; 65 the child already inherited from a different parent.
- Invariants: a refusal writes nothing to any ledger. The verb never writes build, review, docs,
  ship or reflect. The verb never writes a `ran` line, so an inherited gate cannot pass on as
  `ran` to a grandchild.

### Data model changes

None. The written lines are the existing `override()` shape.

### API changes

One new subcommand in the `case` dispatch and the header usage block of `gate-ledger.sh`.

### UI changes

None.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Core

- [ ] TASK-1: `inherit()` in `lib/gate/gate-ledger.sh` plus its dispatch line and header usage
  entry, per the flowchart in `## Design`. Acceptance: AC-1 to AC-9 below pass in
  `tests/test-gate-ledger-inherit.sh`.
- [ ] TASK-2: `tests/test-gate-ledger-inherit.sh`, isolated under a fresh `DWARVES_KIT_LOG_DIR`
  per case (the `test-gate-ledger-plan-record.sh` harness shape), one case per AC and per
  negative control. Add `test-gate-ledger-inherit 60` to `bin/test-affected.timeouts`.
  Acceptance: the suite exits 0 on the built verb, and each NC mutation turns its named case red.

### Phase 2: Docs

- [ ] TASK-3: `lib/gate/README.md` gets the verb in the lane-gate block and one paragraph on
  task branches under a validated spec. `WORKFLOW.md` "## Gate ledger and ship enforcement" gets
  two sentences on multi-task specs pointing at the verb. `docs/CHANGELOG.md` gets an entry.
  Regenerate `docs/FEATURES.md` if the registry freshness pin asks for it. Acceptance:
  `bash tests/run-all.sh --changed --time` green.

## After state

- [ ] `gate-ledger.sh inherit wh-t12h full --from watch-hub-spec` against a parent holding all
  seven gates as `ran` writes seven override lines and nothing else. (Today: seven hand-typed
  `override` calls with free-text reasons.)
- [ ] After that call plus `record build|review|docs ran` and `override ship|reflect`,
  `gate-ledger.sh check full wh-t12h` exits 0.
- [ ] Against the live `watch-hub-spec` ledger as sampled today the verb refuses and names
  think, design, design-critique and spec as not passed. (Today: the hand-written overrides
  cite that rid for gates it never recorded.)

## Acceptance Criteria (global)

- [ ] AC-1 happy path, full lane: the parent holds all seven as last-state `ran`. The call exits
  0 and writes exactly seven GATE lines, all `override`, each reason starting
  `inherited from <parent>: <phase> ran there at <parent-ts>`.
- [ ] AC-2 the per-branch gates stay open: after AC-1, `check full <rid>` exits 1 and lists
  `build`, `review`, `docs`, `ship`, `reflect`, and lists none of the seven. The child ledger
  holds no build, review, docs, ship or reflect line.
- [ ] AC-3 a missing parent gate refuses: drop `think` from the parent. Exit 1, stderr names
  `think`, the child ledger is byte-identical to before (absent stays absent). A second fixture
  drops `test-plan` (last in order) with the same assertions.
- [ ] AC-4 an overridden parent gate refuses: the parent's last `design` line is `override`.
  Exit 1, stderr names `design` as overridden, nothing written.
- [ ] AC-5 last state wins: the parent's `validate` reads `ran` then a later `skipped`. Exit 1,
  stderr names `validate`. The reverse order (`skipped` rounds then `ran`) passes.
- [ ] AC-6 a task-branch parent refuses: the parent itself holds `inherited from G` override
  lines. Exit 1, stderr says the parent inherited and names `G` to inherit from directly.
- [ ] AC-7 a reused slug: the child already holds `inherited from X` lines and the call names
  parent `Y`. Exit 65, nothing written. The same call with parent `X` exits 0, prints
  `already inherited` per phase, and writes no new line.
- [ ] AC-8 spec-file form: `--from <dir>/SPEC-003-watch-hub.md` resolves parent `watch-hub`, and
  each reason ends `; spec <dir>/SPEC-003-watch-hub.md`. A missing file exits 1. A file whose
  slug has no ledger exits 1 and the message says to pass the parent rid.
- [ ] AC-9 lane filter: `normal` writes `spec` alone. `bug` exits 64 with nothing written.
  An unknown lane exits 1.
- [ ] AC-10 usage: no `--from`, a self-parent (`--from <rid>`), or an extra argument exits 64.
- [ ] No regressions: `bash tests/run-all.sh --changed --time` green.

## Verification

```
bash tests/test-gate-ledger-inherit.sh && bash tests/test-gate-ledger-plan-record.sh && bash tests/run-all.sh --changed --time
```

Negative controls (each mutation applied to `inherit()` alone, the named case must go red, then
restore with `git checkout -- lib/gate/gate-ledger.sh`):

| NC | Mutation | Case that goes red |
|---|---|---|
| NC-1 | treat a phase with no parent GATE line as passed | AC-3 |
| NC-2 | accept `override` as a passing parent state | AC-4 and AC-6 |
| NC-3 | judge the parent by "any `ran`" instead of the last line | AC-5 (ran then skipped) |
| NC-4 | add `build` to `INHERITABLE` | AC-2 (child holds a build line; check no longer lists build) |
| NC-5 | drop the different-parent conflict check | AC-7 (exit 0 instead of 65) |
| NC-6 | write each line before judging the next phase | AC-3, second fixture (missing `test-plan`: the child gains six lines) |

## Edge Cases

1. **Parent missing a gate.** Refuse, list every failing phase in one message, write nothing.
   The live `watch-hub-spec` ledger is this case today (## Grounding): it holds no think,
   design, design-critique or spec GATE line. The fix is on the parent: record the gate there
   with its evidence (`record watch-hub-spec think ran "<where it ran>"`), then inherit.
2. **Parent gate overridden.** Refuse. Inheriting an override would stack a second hand-off on
   a gate no one ran. The operator overrides the child by hand if that is truly wanted, which
   keeps the free-text audit trail visible.
3. **Parent is itself a task branch.** Its spec-level lines are `inherited from G` overrides, so
   rule 2 refuses. The message names `G` so the operator points at the real spec rid. No chains.
4. **Reused slug.** A child rid that already inherited from another parent refuses with 65, so
   a recycled branch name cannot carry a stale spec's gates silently. Same parent: idempotent.
5. **Validate rounds.** A parent with `skipped` NEEDS-REVISION rounds then `ran` APPROVED passes
   (last state `ran`), which matches the live watch-hub-spec validate history.
6. **Child already holds a hand override for a phase.** Not a conflict (no `inherited from`
   prefix). The verb appends its line; `override()`'s distinct-reason guard passes because each
   built reason names its phase.
7. **Spec file whose branch rid differs from its slug.** `SPEC-003-watch-hub.md` resolves to
   `watch-hub`, but the spec ran under `watch-hub-spec`. No ledger, exit 1, message says to pass
   the rid. The verb does not guess suffixes.
8. **Project overlay dropped a full-lane phase.** The set follows `required <lane>` with the
   project overlay, like plain `check`. If the hard-path floor (`--kit-lanes`) later demands
   that phase, the ship-gate names it and the operator records it on the child by hand.
9. **Rid normalizing to empty.** `ledger_file()` refuses first; exit 1, nothing written.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| A parent rid typo | exit 1, "no ledger for parent" | re-run with the right rid |
| Parent ledger rewritten after inherit | the child's reason carries the parent ts; `show <parent>` disagrees | audit by comparing timestamps; the ledger is append-only by contract |
| Stats read inherited lines as human overrides | lane-telemetry `ovr` count rises | the `inherited from ` prefix splits them read-side (approach 2 path) |

## Out of Scope

- Inheriting build, review, docs, ship or reflect. Those are per-branch evidence.
- A new GATE state or any reader change (approach 2).
- Auto-detecting the parent from the branch name or spec header. The operator names it.
- Backfilling the live `watch-hub-spec` ledger. That is ops-toolkit work for the lead.

## Touches

- lib/gate/**
- tests/**
- docs/**
- bin/**

## Decision Log

- DEC-1: write `override` lines, not a new state. Zero reader changes; the reason prefix keeps
  them separable. Rejected: an `inherited` state (four readers change).
- DEC-2: the parent must hold `ran`, judged by its LAST GATE line per phase. Matches the
  ship-gate's validate read; refuses a parent whose latest validate failed. Rejected: "any ran"
  like `check()`.
- DEC-3: the set is a fixed list filtered by the lane's required set. A lane that adds a new
  spec-level phase must add it to the list on purpose. Rejected: "every required phase before
  build in the plan", which would inherit any phase a lane overlay inserts.
- DEC-4: no chaining. A parent that inherited is refused, with the grandparent named.

## Grounding

**Ledger line formats, from `lib/gate/gate-ledger.sh` in this worktree.**

`record()`, line 225:
```
append_run_line "$rid" "$(printf '%s | GATE | %s | %s | %s' "$(now)" "$phase" "$state" "$reason")"
```
`override()`, line 470, plus the guard at lines 460-465 that rejects a reason reused on another phase (exit 65):
```
append_run_line "$rid" "$(printf '%s | GATE | %s | override | %s' "$(now)" "$phase" "$reason")"
```
`check()`, line 494, the predicate the inherited lines must satisfy:
```
awk -F' [|] ' -v p="$phase" '$2=="GATE" && $3==p && ($4=="ran"||$4=="override"){f=1} END{exit !f}' "$f"
```
`hooks/ship-gate.sh` line 474, the last-state read DEC-2 copies:
```
awk -F' [|] ' '$2=="GATE" && $3=="validate"{s=$4} END{exit !(s=="ran"||s=="override")}'
```

**Lane sets, live.** `bash lib/gate/gate-ledger.sh required full` prints `think design
design-critique spec validate design-record test-plan build review docs ship reflect`.
`required normal` prints `spec build ship`; `required bug` prints `build debug`; `required
backfill` prints `docs`.

**A real parent ledger.** `~/.local/state/dwarves-kit/logs/runs/watch-hub-spec.log`, GATE lines only:
```
2026-10-03T08:14:22Z | GATE | validate | skipped | NEEDS REVISION round 1: 13 criticals (...)
2026-10-03T08:14:22Z | GATE | design-record | ran | design-bearing=yes pass
2026-10-03T08:31:57Z | GATE | validate | skipped | NEEDS REVISION round 2: ...
2026-10-03T08:39:28Z | GATE | validate | skipped | NEEDS REVISION round 3: ...
2026-10-03T08:42:19Z | GATE | validate | ran | APPROVED critical=0 warnings=see implementation-notes; 4 rounds, fresh agents
2026-10-03T08:42:49Z | GATE | ship | ran | shipping pr=#3866 via=land
2026-10-04T08:07:41Z | GATE | test-plan | ran | matrix rows=155 ... PR #3962
2026-10-04T09:15:55Z | GATE | test-plan | ran | REVISE rounds=3 findings=22 ... PR 3977
```
No think, design, design-critique or spec GATE line exists; spec has only an
`| OUTCOME | spec | start |` bracket. So the verb refuses this parent today (Edge Case 1).

**A real hand-written child.** `runs/wh-t12h.log`, the seven lines this verb replaces:
```
2026-10-04T12:53:08Z | GATE | think | override | SPEC-003 watch-hub (APPROVED, DEC-48); spec-level gates live under rid watch-hub-spec: problem framing in research/2026-10-02-watch-family-unification.md
2026-10-04T12:53:08Z | GATE | design | override | SPEC-003 watch-hub (...): solution design in the SPEC Design and Technical Design sections
... design-critique, spec, validate, design-record, test-plan, same shape ...
2026-10-04T12:53:09Z | GATE | build | ran | Sonnet builder in an isolation worktree; ...
2026-10-04T12:53:09Z | GATE | ship | override | reviewed task branch, pushed by the lead and merged through wrap merge
```
Corpus count: `rg -c 'inherited|spec-level gates live under rid' ~/.local/state/dwarves-kit/logs/runs/*.log | wc -l` printed `37`.

**Spec-file slug.** `tools/watch-hub/docs/specs/SPEC-003-watch-hub.md` in ops-toolkit has header
`Lane: full`; its spec branch rid was `watch-hub-spec`, not `watch-hub`. That is Edge Case 7.

**Negative-control dry traces.** Fixtures are written by the test into a fresh
`DWARVES_KIT_LOG_DIR/runs/`, in the line shapes above.

- NC-1: fixture parent `p` holds six phases as `ran`, no `think` line. The mutated judge loop
  finds no line for think and does not collect a failure. All seven lines get written, exit 0.
  AC-3 asserts exit 1 and an absent child ledger, so it goes red.
- NC-2: fixture parent's last `design` line is `override`. The mutated predicate accepts it,
  exit 0. AC-4 asserts exit 1, red. AC-6's parent holds only `override` lines, so it also
  passes when it must refuse, red.
- NC-3: fixture parent `validate` lines `ran` at T1 then `skipped` at T2. "Any ran" sees T1 and
  passes, exit 0. AC-5 asserts exit 1 naming validate, red.
- NC-4: `build` in the list with a parent holding `build ran`. The child gains a build line, so
  `check full` no longer reports `MISSING-GATE: build`. AC-2 greps for that line and for an
  absent child build line, red.
- NC-5: the child holds `inherited from x` lines and the call names `y`. With the check gone the
  idempotency branch matches no line for `y`, so seven new lines get written, exit 0. AC-7
  asserts exit 65 and an unchanged child, red.
- NC-6: the loop writes as it judges, with the fixture parent missing `think` only. `think` is
  first in `INHERITABLE`, so this fixture would write nothing and stay green. AC-3 therefore
  uses a second fixture missing `test-plan` (last in order). The mutated verb writes six lines
  before it reaches test-plan, the child ledger is no longer absent, red.

## Open questions

(none)
