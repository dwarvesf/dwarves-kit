# SPEC-096: Mega-lane reconcile (/kit:mega mirror + kit-side auto-merge enforcement)

Status: VALIDATED
Date: 2026-07-02
Lane: full (touches the ship-layer surface -- `lib/gate/gate-ledger.sh`'s required-gate
check is the enforcement path a new `lib/goal/mega-merge.sh` rides on, and the new
`commands/mega.md` is a new command surface)
Type: feature
Relates-to: ADR-0028 (autonomous-loop hardening, properties P2 "front-loaded
clarification" + P3 "run-to-final + auto-merge", and the "Where each layer lives"
table), SPEC-034 (mega-goal lane, ID-037 -- the `/kit:mega` roadmap conventions,
single-chain gate, and scaffold-home decision this spec builds the first working
`commands/mega.md` against), SPEC-095 / kit-hardening SG-07 (`lib/gate/proof-ledger.sh
deployable`, reused verbatim for the deploy/UAT terminus), SPEC-032 / ADR-0019/0020
(`/kit:dispatch`, the sibling INDEPENDENT/parallel lane this command mirrors in
shape), `docs/specs/DECISION-BRIEF-kit-hardening.md` (SG-C), ops-toolkit
`plan-for-mega-goal` SKILL.md (the mirror source)
Board: kit-hardening mega-goal SG-08 (ops-toolkit `_meta/megagoals/kit-hardening`)

## Problem

ADR-0028 names the mega lane's kit-side half as two properties that today do not
exist as kit surfaces:

- **P2 (front-loaded clarification) + the per-run merge config** -- authored by the
  ops-toolkit `plan-for-mega-goal` skill, but the kit itself has no command that
  mirrors that shape for a team without the skill installed. `SPEC-034` designed
  `/kit:mega` for a narrower purpose (decompose + roadmap + pointer) and was never
  implemented (no `commands/mega.md` exists on `main`); it also predates ADR-0028,
  so it does not carry the front-load-checkpoint or merge-config framing at all.
- **P3 (run-to-final + auto-merge)** -- "auto-merge each sub-goal once its ship-gate
  passes ... stopping only at the final PR." No ship-layer enforcement exists for
  this: today the only auto-merge-adjacent machinery in the kit is `/kit:dispatch`'s
  explicit refusal ("It NEVER auto-merges") and `lib/gate/gate-ledger.sh check`, which
  answers "is this lane's gate set satisfied" but has no caller that turns that
  answer into a merge action.

Without these, a mega-goal run either has no kit-native planning surface at all
(falls back entirely to the ops-toolkit skill, unavailable to bare-`/kit:*` teams),
or -- worse -- a hand-rolled auto-merge script could plausibly skip the ship-gate
entirely, which ADR-0028 explicitly names as the mis-build risk of this property
("auto-merge escaping the ship-gate").

A 2026-06-29 decision-brief stress test (`DECISION-BRIEF-kit-hardening.md` Q4) first
cut kit-side merge-autonomy from SG-C's scope ("Auto-merge stays a SKILL feature on
operator-owned repos"). ADR-0028 as later Accepted (2026-07-01) revises that: P3 and
the "Where each layer lives" table explicitly assign "Auto-merge enforcement" to the
KIT (ship layer + gate-ledger), with the one team-facing flag (`merge_autonomy`
`gated-final` default, per-run `per-pr-review` opt-out) as the safety valve for
shared repos. This spec builds to the Accepted ADR, not the earlier brief cut; the
supersession is intentional and named here so the two documents are not read as
contradicting each other.

## Decision

Two artifacts, each reusing an existing kit primitive rather than inventing a new
one:

1. **`commands/mega.md`** -- a new command that MIRRORS (never forks) the
   ops-toolkit `plan-for-mega-goal` skill's three authoring beats: decompose (3-8
   dependent sub-goals, single chain, per-sub-goal `Merge policy: auto|gate`,
   deploy/UAT terminus via SG-07's `deployable` classifier), front-load every
   clarification ONCE as the run's only interactive checkpoint, and the per-run
   merge config (`merge_autonomy` `gated-final`|`full-auto` mirroring the skill;
   `MEGA_MERGE_POSTURE` `auto-to-final`|`per-pr-review` as the kit-layer knob
   `lib/goal/mega-merge.sh` reads). It reuses SPEC-034's scaffold conventions (roadmap
   home, `- [ ] SG-NN ... , auto|gate , ...` line shape, single-chain gate) and
   `lib/queue/orchestrate.sh`'s already-shipped directory contract (`ROADMAP.md`,
   `goals/NN-*.md` with `Model:`/`Effort:` headers, `POINTER_PROMPT.md`,
   `HANDOFF.md`, `DECISIONS.md`) so the existing driver needs no changes.

2. **`lib/goal/mega-merge.sh`** -- the ship-layer auto-merge ENFORCEMENT. Two verbs,
   decision separated from action:
   - `gate <rid> <lane>` -- exits 0 iff `lib/gate/gate-ledger.sh check <lane> <rid>`
     passes. No side effects; reuses `gate-ledger.sh` verbatim, never
     re-implements or loosens its required-gate logic.
   - `merge <pr> <rid> <lane> [--execute] [--posture=<val>]` -- runs `gate` FIRST.
     A failing/missing gate REFUSES unconditionally: prints `BLOCKED: ship-gate
     not satisfied, refusing auto-merge`, logs it, exits nonzero, never calls
     `gh`. A passing gate is still DRY-RUN by default (prints the `gh pr merge`
     it would run); only `--execute` calls `gh`. `MEGA_MERGE_POSTURE=per-pr-review`
     forces dry-run regardless of `--execute` or the gate result (the team-review
     opt-out).

Deploy/UAT terminus (the third leg named in the SG-08 goal file) is not a third
artifact -- it is `commands/mega.md` Step 1 documenting that `lib/gate/proof-ledger.sh
deployable <root> <base>` (SG-07, reused verbatim) decides whether the chain's last
two sub-goals are terminal `gate` sub-goals (deploy/wire prep, UAT prep) or whether
build+merge is already the terminus. Enforcement is the SAME ship-time proof-gate
every stateful diff already passes through; no new gate is invented.

## Acceptance criteria

- AC1 [mirror parity]: `commands/mega.md` exists, carries the decompose beat, the
  front-load-checkpoint beat, and the per-run-merge-config beat, and names the
  ops-toolkit `plan-for-mega-goal` skill as the mirror source.
- AC2 [auto-merge past a green gate]: with every required gate for a lane recorded
  in a run's ledger, `lib/goal/mega-merge.sh gate <rid> <lane>` exits 0.
- AC3 [load-bearing negative control]: with one required gate missing,
  `lib/goal/mega-merge.sh gate <rid> <lane>` exits nonzero, AND `lib/goal/mega-merge.sh merge
  <pr> <rid> <lane>` REFUSES -- no merge, exits nonzero, prints a `BLOCKED` message.
  A failing/missing gate never merges, regardless of flags.
- AC4 [dry-run default]: `lib/goal/mega-merge.sh merge <pr> <rid> <lane>` on a PASSING
  gate still does not call `gh` unless `--execute` is given (asserted by a
  PATH-shadowed fake `gh` that would leave a marker file if invoked).
- AC5 [terminus]: `lib/gate/proof-ledger.sh deployable <root> <base>` prints `yes` for a
  deployable fixture (terminus engages) and `no` for an inert one (terminus
  skipped) -- reused verbatim from SG-07, not a new classifier.
- AC6 [per-run config honored]: `MEGA_MERGE_POSTURE=per-pr-review` makes `merge`
  dry-run even with `--execute` on a passing gate; `--posture=` overrides the env;
  the knob is documented in both `lib/goal/mega-merge.sh` and `commands/mega.md`.

## Tasks

- T1: `commands/mega.md` -- the mirror command (decompose, front-load, merge
  config, scaffold shape, hand-off, enforcement wiring, refusal list).
- T2: `lib/goal/mega-merge.sh` -- `gate` + `merge` verbs, dry-run default, posture knob.
- T3: `tests/test-mega-reconcile.sh` -- AC1-AC6.
- T4: `docs/verification/mega-reconcile.md` -- table-first proof-of-done.
- T5: `docs/implementation-notes/mega-reconcile.md` -- deltas from this spec.
- T6: Roster: README.md command table + summary count + Project structure `lib/`
  listing; MANUAL.md command reference entry; `docs/architecture.md` cross-phase
  row; `_meta/BACKLOG.md` ID-037 status note.

## Verification

```
bash tests/test-mega-reconcile.sh   # AC1-AC6
bash tests/test-meta.sh             # roster cross-refs stay green (new command + new lib)
bash tests/test-hooks.sh            # unaffected by this change; stays green
```

## Out of Scope

- The activator loop itself (`/goal`, `ralph-loop`) -- ADR-0017 activator-agnostic
  stands; `commands/mega.md` hands off, it does not become a runtime.
- `lib/queue/orchestrate.sh` -- already exists (SPEC-087); this spec's scaffold shape is
  written to be compatible with it, but the driver itself is untouched.
- The dynamic-injection skill SPEC-034 TASK-004 proposed. `lib/queue/orchestrate.sh`
  already re-reads `ROADMAP.md` fresh every turn by construction (it is a non-LLM
  bash driver, not a `/goal`-loop text re-injection), so the injection skill's
  reason for existing (working around `/goal`'s literal-text-only re-injection) does
  not apply to the `orchestrate.sh` path; a team running under bare `/goal` still
  needs it and can install the ops-toolkit skill for that.
- Rewriting `lib/gate/gate-ledger.sh` or `hooks/ship-gate.sh` -- `mega-merge.sh` is a
  caller, not a change to either.
- A DAG / dependency-graph scheduler (ADR-0028 Out of Scope; GSD v2).
- Actually merging, deploying, or UAT-ing anything as part of running this spec's
  own tests -- the tests exercise `mega-merge.sh` against fixture ledgers only.

## Decision Log

- DEC-001: `commands/mega.md` reuses SPEC-034's scaffold conventions (roadmap home,
  line shape, single-chain gate) rather than inventing a second convention --
  SPEC-034 is `Status: VALIDATED` and its DEC-002/DEC-007/DEC-008 are maintainer
  confirmed; only its DEC-009 ("auto-merge stays human") is superseded, per ADR-0028
  P3 below.
- DEC-002 [supersession, explicit]: SPEC-034 DEC-009 ("Auto-merge. Merge stays
  human, at `/kit:ship`") is superseded for `auto`-tagged sub-goals by ADR-0028 P3.
  `gate`-tagged sub-goals and the final PR under `gated-final` still merge only by
  human hand, exactly as SPEC-034 intended -- the supersession is scoped to the
  `auto` case ADR-0028 adds, not a reversal of SPEC-034's human-ship default.
- DEC-003: `gate` and `merge` are separate verbs (not one `merge` that silently
  gate-checks) so the decision is unit-testable with zero side effects -- the same
  decision/action split `lib/gate/dispatch-gate.sh` uses for `plan` vs the drift `check`.
- DEC-004: dry-run is the DEFAULT action, not an opt-in flag -- inverting this
  (execute-by-default, `--dry-run` to opt out) would make the safe path the one
  easiest to forget under time pressure, exactly the failure ADR-0028 flags.
- DEC-005: the deploy/UAT terminus reuses SG-07's `deployable` verb verbatim rather
  than adding a mega-lane-specific classifier -- per the SG-08 goal file's explicit
  "reuse, do not reinvent" instruction and DEC-001 of SPEC-095 itself.
