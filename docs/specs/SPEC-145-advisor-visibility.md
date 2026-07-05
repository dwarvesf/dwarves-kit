# Spec: Advisor visibility (gate-review-absorptions sub-goal 06)

Generated: 2026-07-04
Status: VALIDATED
Lane: full (classified `full` by `lib/classify/lane-classify.sh` for the phrasing "advisor P5/P6
gate-ledger emit + convergence-gate dispatch step"; touches `commands/mega.md`'s dispatch
convention, so treated as full even though the literal diff is prose/prompt-only, matching
the escalation posture the goal file already sets)
Design: obvious (ADR-0031 sec 1 -- wiring an existing emit convention, `bash
lib/gate/gate-ledger.sh record <rid> <phase> ran "<reason>"`, at two already-existing dispatch
sites; no new table, no new parser, no new architecture)
Depends on: SPEC-143 (stale-adr-inversion) and SPEC-144 (review-findings-memory), both
merged to `master`; this sub-goal is stacked on the same two files (`commands/review-team.md`,
`agents/advisor.md`) those two already touched, per the goal file's `Depends on: 02`.

## Problem

2026-07-04 audit finding (goal file `06-advisor-visibility.md`): the `advisor` agent (ADR-0028
kit-default cross-cutting lens, P5 critique + P6 over-suggest) is reachable ONLY via
`/kit:review-team` Step 2b or a conductor-level convergence-gate dispatch, and neither path
leaves a first-class ledger row. `commands/review-team.md` Step 2b dispatches the advisor and
folds its findings into the merged report's free-text `review ran "<verdict> findings=<K>
suppressed=<S> rejected=<M> actor=<name>"` line, but that line's `findings=<K>` counts the
MERGED report total (3 specialists + advisor combined), so the advisor's own contribution is
invisible in the ledger even when the advisor genuinely ran. `commands/mega.md` has zero
mentions of `advisor` anywhere: the only historical evidence the advisor ran during a mega
chain is a free-text `| ACTION |` line a worker chose to write by convention (e.g.
`~/.local/state/dwarves-kit/logs/runs/kit-telem-05-mergeguard.log`'s "advisor P5=3 doc/board
findings fixed... advisor P6=8 additions surfaced"), never a structured `| GATE |` row a
reader like `kit_gates` (ledger-observatory SPEC-131, PR #683, already merged) can query. A
2026-07-04 scan of the 96 rid logs under `~/.local/state/dwarves-kit/logs/runs/` found the
advisor ledger-invisible in every one: zero `| GATE | advisor |` rows exist anywhere, even on
runs whose free-text `| ACTION |` line describes an advisor pass. In subagent-delegate mega
runs specifically, workers self-record `review ran` per the worker contract instead of an
explicit `/kit:review-team` dispatch, so the advisor had NO invocation path at all in the most
recent runs.

The ops-toolkit `plan-for-mega-goal` skill (dotfiles) is AHEAD of the kit here: its
`references/GUIDE.md` step 6a, `references/invocation-template.md`, and
`references/OPERATE.md` already document a convergence-gate advisor P5+P6 dispatch with the
exact ledger grammar this spec pins (`mode=P5|P6 findings=N actor=`), landed independently
during the harness-observatory mega-goal's dogfooding (2026-07-04, same day). `commands/mega.md`
(the kit-native `/kit:mega`) has an explicit never-diverge contract with that skill (SPEC-142);
this sub-goal is the kit side catching up to a beat the skill already prescribes, not the usual
kit-writes-first direction, see "Never-diverge checklist" below.

## Solution

### Approaches considered

1. **Add the emit to review-team.md Step 2b, add a new convergence-gate step to mega.md, add
   an emit-contract note to agents/advisor.md; reuse `gate-ledger.sh record` verbatim, no new
   verb, no new lib file. CHOSEN.** The grammar (`bash lib/gate/gate-ledger.sh record "$rid" advisor
   ran "mode=P5|P6 findings=N actor=<git user.name>"`) is the exact shape `record()` already
   accepts (phase=`advisor`, state=`ran`, free-text reason carrying the KV pairs) -- the same
   shape `commands/review.md`/`commands/review-team.md`'s own `review ran "... actor=$(git
   config user.name)"` lines already use for the merged verdict. No parser change is needed on
   the read side either: `kit_gates`'s `read_kit_gates()` (ledger-observatory, already merged)
   treats every `| GATE | <phase> | <outcome> | <reason> |` line generically by `phase` name; it
   has never needed a per-phase allowlist, so a NEW phase value (`advisor`) requires zero
   ledger-observatory code change, verified against the live adapter (see Verification below).
2. **A new `gate-ledger.sh advisor` subcommand, distinct from `record`.** Rejected: `record()`
   already accepts an arbitrary phase string (`normalize_phase()` only lowercases and strips
   `(...)`/spaces; it does not validate against a closed enum except the one `grill`+`skipped`
   special case), so a dedicated subcommand would duplicate `record()`'s exact behavior for no
   new capability -- the same "prose+grep is sufficient, don't add a lib surface" discipline
   SPEC-144 already applied to this same file pair.
3. **Fold the advisor emit into the existing `review ran` line's `findings=<K>` instead of a
   separate `| GATE | advisor |` row.** Rejected: `findings=<K>` in that line is explicitly
   documented as "counts main-report findings only" (review-team.md Step 3, item 6, the LATE
   confidence gate) -- a merged, post-dedup, post-suppression count across 3 specialists PLUS
   the advisor. Overloading it to also mean "did the advisor run" would make `kit_gates` unable
   to distinguish "advisor ran with 0 fresh findings" from "advisor never dispatched," exactly
   the honest-zero failure mode NC1 below exists to prevent. A separate `advisor` phase row is
   the only shape that lets a reader tell "zero findings" from "never ran."

### Chosen approach + why

Approach 1. It is the smallest change that produces a first-class, independently-queryable
`advisor` gate row, reuses `record()` unmodified, and needs no ledger-observatory code change
(verified, not assumed -- see Verification).

### Never-diverge checklist (SPEC-142 convention, this sub-goal's entry)

| Beat | Skill-side location | `mega.md` location | Status |
|---|---|---|---|
| Advisor P5/P6 convergence-gate dispatch + ledger emit | `references/GUIDE.md` step 6a ("Advisor pre-launch pass"), `references/invocation-template.md` (the convergence-round bullet list), `references/OPERATE.md` ("The convergence gate is COMPOSED, not improvised") -- all landed 2026-07-04, same grammar `mode=P5|P6 findings=N actor=` | New convergence-gate paragraph before "Close the run visibly" (this spec) | SYNCED (this PR) -- kit catching up to a skill-side beat that landed first; **no dotfiles edit made**, the skill source already carries this content verbatim (grep-verified below), so mirroring here means matching the skill's existing prose, not writing new prose into it |

This resolves the goal file's mirror instruction ("if editing commands/mega.md triggers that
checklist, mirror the change into the dotfiles skill source... If the checklist does NOT
require it, say so in impl-notes and skip"): the checklist DOES apply to this beat, but the
mirror direction is skill -> kit, already satisfied by the skill's pre-existing text. See
`docs/implementation-notes/advisor-visibility.md` for the grep evidence and the discovery note.

## Design

No new component, table, or data model; this is prompt-text wiring at two dispatch sites plus
one documentation note. Design record collapses to one line per ADR-0031 sec 1: **obvious --
the emit reuses `gate-ledger.sh record()` unmodified, at two dispatch sites the goal file
already names, with a grammar the skill side already validated in production use.**

## Quality bar (verbatim from the goal file, binding)

NO gate-requirement change: advisor stays advisory; a missing advisor row never blocks
anything (no lane's `measure-twice` set gains an `advisor` entry; `hooks/ship-gate.sh`'s
required-gate parsing is untouched). Fail-open: an emit failure must not fail the review
or the mega run. Two absolute negative controls:

- **NC1 (honest-zero):** a rid with no advisor dispatch renders zero/absent in `kit_gates`,
  never fabricated coverage.
- **NC2 (emit-failure-never-blocks):** the emit command failing (e.g. a read-only ledger
  directory) never fails the surrounding review/dispatch; a visible warning is printed instead.

## Task Breakdown

### Phase 1: Emit sites
- [x] TASK-001: `commands/review-team.md` Step 2b -- after the advisor critique dispatch
  prompt, add the emit `bash lib/gate/gate-ledger.sh record "$rid" advisor ran "mode=P5
  findings=<N> actor=$(git config user.name)" || echo "WARNING: ..." >&2`, where `<N>` is the
  advisor's own fresh-finding count (post rejected-findings-ledger, SPEC-144), not the merged
  report total. State the RID convention inline (standalone run: current rid; mega/convergence
  context: the FINAL sub-goal's rid). Acceptance: the emit line is present, fail-open (`||`
  fallback that never propagates a nonzero exit into the surrounding flow), and textually
  distinguishes the advisor's own count from the Step 3 merged `findings=<K>`.
- [x] TASK-002: `commands/mega.md` -- new convergence-gate paragraph immediately before "Close
  the run visibly" (Step 5), naming an explicit in-harness dispatch of `advisor` P5 (critique)
  + P6 (over-suggest) over the assembled stack, each emitting its own `mode=P5`/`mode=P6` row
  under the FINAL sub-goal's rid (the de-facto convention the pre-existing free-text
  `kit-telem-05-mergeguard.log` / `kit-clean-05-editmention.log` ACTION lines already used),
  fail-open identically to TASK-001. Acceptance: the paragraph exists, names both modes
  explicitly, states the rid convention, and the emit is fail-open.
- [x] TASK-003: `agents/advisor.md` -- a short "Ledger emit" note (in the agent's own doc, not
  its dispatch instructions -- the agent itself never runs bash) recording that every dispatch
  site is EXPECTED to emit `mode=<P5|P6> findings=N actor=` so a future third dispatch site
  inherits the convention by reading this file. Acceptance: the note exists and names the exact
  grammar.

### Phase 2: Proof
- [x] TASK-004: a fixture rid ledger log exercising the new grammar (`mode=P5 findings=N
  actor=...` and `mode=P6 findings=N actor=...`), parsed by the merged `ledger-observatory`
  `kit_gates` reader (`uv run ledger gate-yield`) against a `DWARVES_KIT_LOG_DIR` pointed at a
  scratch dir containing only the fixture -- proving the new phase value needs zero
  ledger-observatory code change. Acceptance: the command's output shows an `advisor` row with
  the fixture's exact ran-count.
- [x] TASK-005: NC1 capture -- a second fixture rid with NO advisor row, same `gate-yield`
  query, showing `advisor` absent/zero for that rid (never fabricated). Acceptance: captured
  output distinguishing the two rids.
- [x] TASK-006: NC2 capture -- point `DWARVES_KIT_LOG_DIR` (or the ledger file itself) at a
  read-only path and run the emit line from TASK-001/002 verbatim, showing the surrounding
  review flow completing with a printed warning, never a hard failure. Acceptance: captured
  exit code 0 (or explicitly non-fatal) plus the warning text.
- [x] TASK-007: `tests/test-advisor-ledger-emit.sh` -- grep-based regression pins (mirrors
  `tests/test-advisor.sh`'s style) so a future edit cannot silently drop the emit, the
  fail-open fallback, or the rid-convention statement from either dispatch site.

### Phase 3: Close
- [x] TASK-008: `docs/verification/advisor-visibility.md` (proof, per `docs/verification/README.md`
  flat-shape convention) + `docs/implementation-notes/advisor-visibility.md` (delta log,
  including the never-diverge discovery note). Commit, push, PR against `master`, CI green on
  both runners.

## After state

- [x] `commands/review-team.md` Step 2b emits a first-class `| GATE | advisor | ran | mode=P5
  findings=<N> actor=<name> |` row per dispatch. (Today: the advisor's own count is folded
  invisibly into the merged `review ran` line.)
- [x] `commands/mega.md` names an explicit convergence-gate dispatch of advisor P5+P6 at the
  assembled-stack close, each emitting its own row under the final sub-goal's rid. (Today:
  zero mentions of `advisor` in `commands/mega.md`.)
- [x] `agents/advisor.md` documents the emit contract for future dispatch sites.
- [x] Both NCs captured and committed.
- [x] No lane's required-gate set changed; `hooks/ship-gate.sh` behavior is unchanged
  (verified by the existing `tests/test-*.sh` suite staying green).

## Acceptance Criteria (global)
- [x] All tasks pass their individual acceptance criteria.
- [x] `bash tests/test-advisor.sh && bash tests/test-review-team-plants.sh && bash
  tests/test-command-emit-sweep.sh && bash tests/test-advisor-ledger-emit.sh` all exit 0.
- [x] `bash tests/test-meta.sh` and `bash tests/test-hooks.sh` show no new failures (no
  gate-requirement or ship-gate behavior changed).

## Verification

```bash
cd /Users/tieubao/workspace/tieubao/dwarves-kit/.claude/worktrees/advisor-visibility
bash tests/test-advisor.sh
bash tests/test-review-team-plants.sh
bash tests/test-command-emit-sweep.sh
bash tests/test-advisor-ledger-emit.sh
bash tests/test-meta.sh
bash tests/test-hooks.sh
```

## Edge Cases
1. A dispatch site runs the advisor but the emit command itself fails (read-only ledger dir,
   disk full): the review/mega output must complete unaffected, with a visible warning (NC2).
2. A rid genuinely never dispatches the advisor (a lane that never reaches Step 2b, or a mega
   run that halts before the convergence-gate step): `kit_gates` must show zero/absent for that
   rid's `advisor` phase, never a fabricated row (NC1).
3. Two advisor dispatches in one rid (critique P5 then over-suggest P6, or a re-run): each is
   its own `| GATE | advisor | ran |` row (never deduped, matching the existing FIFO-tolerant
   `kit_gates` reader behavior for any repeated phase name, SPEC-131 edge case 4).
4. The rid at emit time is a mega-chain's in-progress sub-goal, not yet the final one: per the
   pinned convention, the convergence-gate emit (mega.md path only; review-team.md's own
   Step 2b emit always uses ITS OWN run's rid) records under the FINAL sub-goal's rid, since the
   convergence gate runs once, at the assembled-stack close, after every sub-goal's own rid
   already exists.

## Out of Scope
- The ops-side self-attested-row split (cockpit ID-270).
- Any new advisor capability or change to P5/P6 content.
- Auto-dispatch of the advisor anywhere beyond `/kit:review-team` Step 2b and the new
  `mega.md` convergence-gate step.
- Any `lib/gate/gate-ledger.sh` or `ledger-observatory` code change (verified unnecessary, TASK-004).
- **Known pre-existing gap, NOT closed by this pass, flagged honestly (multi-lens review
  finding, 2026-07-04):** `commands/mega.md` still names no `/kit:verify` or
  `/kit:review-team` dispatch of its own at the assembled-stack close. The ops-toolkit
  `plan-for-mega-goal` skill's convergence gate is COMPOSED of `/kit:verify` +
  `/kit:review-team` + advisor P5/P6 together (`references/OPERATE.md` "The convergence gate
  is COMPOSED, not improvised"); this sub-goal wires only the advisor third of that
  composition into `commands/mega.md`, per the goal file's own scope edges (`## Scope edges`
  names `commands/mega.md` convergence-gate step" for the advisor only). The mega.md prose
  says explicitly it is mirroring "the ADVISOR SLICE," not claiming full parity with the
  skill's composed gate -- a future sub-goal owns wiring `/kit:verify`/`/kit:review-team`
  into `commands/mega.md`'s own convergence-gate step, if that gap is worth closing.

## Touches
`commands/review-team.md`, `commands/mega.md`, `agents/advisor.md`, `tests/test-advisor-ledger-emit.sh`,
`docs/specs/SPEC-145-advisor-visibility.md`, `docs/verification/advisor-visibility.md`,
`docs/implementation-notes/advisor-visibility.md`.

## Decision Log
- DEC-001: the advisor's own `findings=<N>` count (TASK-001) is read off the advisor's OWN
  `ADVISORY: <N findings>` output line, distinct from Step 3's merged `findings=<K>` (which
  spans all 3 specialists + advisor post-dedup). Conflating the two would make `kit_gates`
  unable to answer "how many of the advisor's OWN findings survived," the exact per-lens
  signal a future `gate-yield`-style query over `kit_gates` would want.
- DEC-002: the rid convention (final sub-goal's rid for convergence-gate rows) is PINNED, not
  invented here -- it is the de-facto pattern the pre-existing `kit-telem-05-mergeguard.log` /
  `kit-clean-05-editmention.log` free-text ACTION lines already followed before this spec
  existed; this spec makes it a structured `| GATE |` row instead of prose, without changing
  which rid it lands under.
- DEC-003: the never-diverge checklist mirror direction for this beat is skill -> kit (the
  opposite of SPEC-142's three knobs, which were kit-and-skill-both). No dotfiles edit is made;
  the skill's `GUIDE.md`/`OPERATE.md`/`invocation-template.md` already carry the exact grammar
  this spec pins, verified by direct grep (see impl-notes).

- DEC-004: spec-validate self-review (2026-07-04, 6-reviewer pass): Reviewer 6 (Design Record
  Auditor, blocking) confirmed the `obvious:` one-liner is warranted -- no new table, parser,
  schema, or component; two prose emit sites plus a doc note. Reviewers 1-5 found no blocking
  issues: no auth/secret/injection surface (the emit is a documented bash invocation inside a
  markdown command's own instructions, `$rid`/`$(git config user.name)` both already pass
  through `gate-ledger.sh`'s `oneline()` newline-stripping at the existing `record()` call, no
  new interpolation path); the two NCs (honest-zero, emit-failure-never-blocks) are the
  explicit failure-mode contract, not an afterthought; the "final sub-goal's rid" assumption is
  named and pinned (DEC-002), not hidden; scope matches the goal file's edges exactly (no drift
  into P5/P6 content or a required-gate change); solution reuses `record()` verbatim, no second
  verb invented.

## Amendments
(none)

## Review
Self-review via `/kit:spec-validate`-equivalent (6-reviewer pass), 2026-07-04. Verdict:
APPROVED. Status flipped DRAFT -> VALIDATED.

Multi-lens `/kit:review-team`-equivalent pass (4 real subagent dispatches: security,
architecture, test-coverage, advisor critique P5), 2026-07-04, over
`git diff master -- commands/review-team.md commands/mega.md agents/advisor.md
tests/test-advisor-ledger-emit.sh docs/specs/SPEC-145-advisor-visibility.md`:

- **Security: SECURE, 0 findings.** `$rid`/`$(git config user.name)` interpolation is
  sanitized upstream by `runid()`; the fail-open `||` cannot hide a real security-gate
  failure since nothing gate-worthy depends on this row; no secrets in the diff.
- **Architecture: 1 LOW.** The advisor emit is the first `gate-ledger.sh record` call site to
  wrap itself in an explicit `|| WARNING` fallback, unreconciled with ~15 bare sibling sites,
  with no doc anchor explaining the asymmetry. FIXED: added a note to `WORKFLOW.md`'s "Gate
  ledger and ship enforcement" section naming this fail-open behavior as SPEC-145-specific
  (NC2), not a new ledger-wide default.
- **Test-coverage: 3 findings (1 HIGH, 1 MEDIUM, 1 LOW-MEDIUM), all FIXED and re-verified.**
  (1) HIGH, empirically reproduced: `fail_open_call()`'s awk used sticky global `found`/`ok`
  flags, so stripping the fallback from ONLY `mega.md`'s second (P6) call site still passed
  AC3 -- the earlier P5 match's `ok=1` masked it. Fixed: rewrote the check to test each match
  independently (grep -n each call site, slice its own +2 lines, no shared state); reproduced
  the original bug against the mutated file first, confirmed the rewrite catches it. (2)
  MEDIUM: no test exercised the real `lib/gate/gate-ledger.sh record` write path, only prose
  describing it. Fixed: added AC8, which invokes the real script against a scratch log dir and
  asserts the exact written line. (3) LOW-MEDIUM: AC5 didn't pin the "FINAL sub-goal" rid
  convention text in `agents/advisor.md` itself, even though that file frames itself as the
  convention's canonical home. Fixed: added the grep. Suite now 27/27 (was 23/23).
- **Advisor critique (P5): 2 findings, both FIXED.** (1) The convergence-gate paragraph told
  the reader to reuse "the SAME `RID`" a per-sub-goal loop computes, but that variable is
  scoped to one loop iteration (and, under the default subagent/delegate run modes, a
  different process entirely) -- not guaranteed to exist at convergence-gate time. Fixed:
  reworded to name the final sub-goal's rid as a STATIC, already-known value (its `**Branch:**`
  header, `type/` stripped -- the same transform Step 4's own comment already named), never a
  live variable re-derivation. (2) The "mirrors... catching up" framing risked implying full
  parity with the skill's COMPOSED convergence gate (`/kit:verify` + `/kit:review-team` +
  advisor), when this sub-goal wires only the advisor third. Fixed: reworded to say "the
  ADVISOR SLICE" explicitly, and added an honest Out of Scope bullet naming the
  `/kit:verify`/`/kit:review-team` gap as pre-existing and unclosed by this pass. Previously
  rejected: 0 (checked against `docs/verification/rejected-findings.md`).

**Verdict: SHIP.** All 6 findings across 4 lenses addressed and re-verified (full suite green:
`tests/test-advisor-ledger-emit.sh` 27/27, `tests/test-advisor.sh` 15/15,
`tests/test-review-team-plants.sh` 8/8, `tests/test-command-emit-sweep.sh` 19/19,
`tests/test-mega-reconcile.sh` 35/35, `tests/test-meta.sh` 669/669, `tests/test-hooks.sh`
452/452). Ledger recorded: `bash lib/gate/gate-ledger.sh record advisor-visibility review ran
"SHIP findings=6 suppressed=0 rejected=0 actor=Han Ngo"` and, dogfooding this very sub-goal's
own convention, `bash lib/gate/gate-ledger.sh record advisor-visibility advisor ran "mode=P5
findings=2 actor=Han Ngo"` -- this rid now itself carries a real `advisor` gate row.
Full detail: `docs/verification/advisor-visibility.md`.

## Test plan
Date: 2026-07-04
Source: this spec's ## Acceptance Criteria

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|-------------|----------|-------|
| 1 | review-team Step 2b emits `advisor` row after critique dispatch | happy-path | AC-1 | `| GATE | advisor | ran | mode=P5 findings=<N> actor=<name> |` appended | `tests/test-advisor-ledger-emit.sh` + fixture run (TASK-004) |
| 2 | mega.md convergence-gate step dispatches P5+P6 with emits | happy-path | AC-1 | paragraph names both modes, each with its own emit | `tests/test-advisor-ledger-emit.sh` grep pins |
| 3 | agents/advisor.md documents the emit contract | happy-path | AC-1 | note present, exact grammar named | `tests/test-advisor-ledger-emit.sh` grep pin |
| 4 | a rid with zero advisor dispatch | boundary/edge | NC1 | `kit_gates`/`gate-yield` shows zero/absent for `advisor`, never fabricated | fixture run, TASK-005 |
| 5 | two advisor dispatches in one rid (P5 then P6) | boundary/edge | Edge Case 3 | two independent `| GATE | advisor |` rows, never deduped | fixture run (TASK-004, both modes in one rid) |
| 6 | emit command fails (read-only ledger dir) | failure-injection | NC2 | review/mega flow completes, a visible warning prints, no propagated failure | TASK-006 capture |
| 7 | malformed `$rid` or `$(git config user.name)` (embedded newline, empty) | security/abuse | Edge Case 1 (adjacent) | `oneline()` (existing, unmodified) collapses newlines before the line is written; empty actor is written as empty text, never a crash | inspection of `gate-ledger.sh record()`/`oneline()` (unmodified in this diff) + TASK-004 fixture using a realistic actor string |
| 8 | existing lane-required-gate sets are unchanged | regression | AC (global) #3 | `bash tests/test-meta.sh && bash tests/test-hooks.sh` show no new failures; no lane gains an `advisor` `measure-twice` entry | `tests/test-meta.sh`, `tests/test-hooks.sh` |
| 9 | existing advisor/review-team/emit-sweep suites still pass | regression | AC (global) #2 | `tests/test-advisor.sh`, `tests/test-review-team-plants.sh`, `tests/test-command-emit-sweep.sh` all green | direct run |

### Coverage notes
- Categories skipped: none -- all 5 categories apply (happy-path, boundary/edge, failure-injection, security/abuse, regression).
- Case 7's "security/abuse" coverage is intentionally light: this spec adds no new parsing or interpolation code (it only adds two bash invocations of the EXISTING, unmodified `record()`), so the abuse surface is whatever `record()`/`oneline()` already defend, not new surface this spec must independently prove.

## Open questions
(none)
