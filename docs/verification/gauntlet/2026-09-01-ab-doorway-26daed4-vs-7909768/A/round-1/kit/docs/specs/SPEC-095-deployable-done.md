# SPEC-095: Conditional deployable-done

Status: VALIDATED
Date: 2026-07-02
Lane: full (touches AGENTS.md operate-contract + the shared `lib/gate/proof-ledger.sh` surface
consumed by `hooks/ship-gate.sh`)
Type: feature
Relates-to: ADR-0028 (autonomous-loop hardening, "Conditional deployable-done" property),
ADR-0025 (proof-of-done ship gate, diff-keyed, spec-independent -- the stateful proof shape
reused here verbatim), ADR-0026 (co-located table-first proof)
Board: kit-hardening mega-goal SG-07 (ops-toolkit `_meta/megagoals/kit-hardening`)

## Problem

ADR-0028 names "conditional deployable-done" as one of eight properties of the
autonomous-loop-hardening lane: for DEPLOYABLE work (a service, a daemon, a feature behind
a flag, anything that runs somewhere), `done` should mean a deploy-proof + UAT, enforced at
ship, reusing the ADR-0025 stateful proof shape. Today that intent exists only in the ADR
prose -- there is no explicit AGENTS.md contract naming what "deployable" means or what it
owes, so an autonomous run has no operate-contract line to point at, and the
already-shipped enforcement mechanism (the `stateful` branch of `lib/gate/proof-ledger.sh
check()`, wired into `hooks/ship-gate.sh` per ADR-0025) is not documented as answering this
specific ADR-0028 property.

## Decision (reuse, do not reinvent)

The `stateful` proof class `lib/gate/proof-ledger.sh classify()` already computes (deploy /
rollout / production / migration / schema / database / persistent-state / backup / restore
signals in the diff or commit subjects) **IS** the deployable signal. This spec does not
build a second classifier or tighten the shared `classify()`/`check()` logic (both stay
byte-identical in behavior; other repos consuming this lib via `~/.claude/dwarves-kit` are
unaffected). It makes the existing mapping explicit and contract-level:

1. **AGENTS.md zone-3 clause ("Deployable-done").** `## 3. Done means` gains a clause
   defining DEPLOYABLE work as `lib/gate/proof-ledger.sh classify`'s `stateful` class, and
   stating `done` = a deploy-proof (the existing ADR-0025 stateful shape: a recorded run
   with `Command:`/`Exit:` AND a `rollback` note or `[UNAVAILABLE: reason]`) PLUS a
   UAT/acceptance line, enforced at ship via the same `hooks/ship-gate.sh` ->
   `proof-ledger.sh check` wall every stateful change already passes through. INERT /
   library / refactor / docs work (`inert`/`behavioral` classes) is explicitly unchanged.
2. **A purely-additive `deployable` verb in `lib/gate/proof-ledger.sh`.** `deployable <root>
   <base>` prints `yes`/`no` by calling the existing `classify()` and mapping
   `stateful -> yes`, everything else `-> no`. It does not read or modify `classify()`'s or
   `check()`'s logic -- a thin relabel for call-site readability, not a second classifier.
3. **UAT as a proof-template contract, not a new hard grep.** The deployable proof template
   (fixture + AGENTS.md prose) documents that a deployable proof carries BOTH the ADR-0025
   deploy-proof markers AND a UAT/acceptance line. `check()`'s stateful branch is NOT
   changed to hard-require a `UAT` string match -- doing so would break every existing
   stateful proof in every repo that already adopted ADR-0025 without a UAT line. The test
   asserts the CONTRACT (AGENTS.md states it; the well-formed fixture carries it) and that
   the existing gate still blocks/passes exactly as it did before this spec.

## Acceptance criteria

- AC1 [load-bearing negative control]: a deployable (stateful-classified) diff with NO
  proof-of-done file is BLOCKED by `proof-ledger.sh check` (exit != 0).
- AC2: the same deployable diff WITH a well-formed proof (rollback/`[UNAVAILABLE` +
  `Command:`/`Exit:` + a UAT/acceptance line) PASSES `proof-ledger.sh check` (exit 0).
- AC3 [inert unaffected]: a docs-only diff classifies `inert` and ships with no proof
  required, unchanged from pre-spec behavior.
- AC4 [override logs]: `proof-ledger.sh override <slug> "<reason>"` on a deployable diff
  with no proof makes `check` PASS, and the override is written to the audit log
  (`proof-overrides.log`) with the slug and reason.
- AC5 [contract]: `AGENTS.md` `## 3. Done means` carries a "Deployable-done" clause that
  (a) defines deployable via the `stateful` class, (b) states done = deploy-proof + UAT,
  (c) states inert/library/refactor work is unchanged.
- AC6 [shared-path safety]: `lib/gate/proof-ledger.sh classify()` and `check()` are
  byte-unchanged in logic (only a new, separately-dispatched `deployable` function and
  case-arm are added); every previously-green test in `tests/test-proof-*.sh`,
  `tests/test-ship-gate-*.sh`, `tests/test-meta.sh`, and `tests/test-hooks.sh` stays green.

## Tasks

- T1: `AGENTS.md` -- add the "Deployable-done" clause to `## 3. Done means`.
- T2: `lib/gate/proof-ledger.sh` -- add the additive `deployable <root> <base>` verb + dispatch
  case; `classify()`/`check()` untouched.
- T3: `tests/fixtures/deployable-done/` -- a deployable-change fixture (a `deploy/`-path
  script + a "deploy:" commit subject), an inert-change fixture (docs-only), and a
  well-formed proof fixture (rollback + `Command:`/`Exit:` + UAT line).
- T4: `tests/test-deployable-done.sh` -- AC1-AC5, mirroring the `test-ship-gate-*.sh` /
  `test-lane-escalation.sh` temp-repo harness shape.
- T5: `docs/verification/deployable-done.md` -- table-first proof-of-done.
- T6: `docs/implementation-notes/deployable-done.md` -- deltas from this spec.

## Verification

```
bash tests/test-deployable-done.sh       # AC1-AC5
bash tests/test-proof-dir-layout.sh      # shared-path safety: proof-ledger.sh unaffected
bash tests/test-proof-visual-evidence.sh # shared-path safety
bash tests/test-ship-gate-fail-closed.sh # shared-path safety
bash tests/test-ship-gate-profiles.sh    # shared-path safety (requires kit installed at
                                          # ~/.claude/dwarves-kit; else NO EXECUTABLE CHECK,
                                          # a pre-existing environment gap, not this change)
bash tests/test-meta.sh                  # shared-path safety
bash tests/test-hooks.sh                 # shared-path safety
```

## Out of Scope

- Modifying `classify()`'s or `check()`'s existing logic/output in any way (would tighten
  the shared path every consumer repo relies on).
- A hard-required `UAT` grep inside `check()`'s stateful branch (would break existing
  stateful proofs in every already-adopted repo that predates this spec).
- Actually deploying or UAT-ing any real service -- this spec BUILDS the contract + gate
  affordance; it does not deploy anything (per the SG-07 goal file's Scope edges).
- Per-repo deployability definitions -- the classifier stays the general one
  `lib/gate/proof-ledger.sh classify()` already uses.

## Decision Log

- DEC-001: `deployable` is a NEW verb, not a change to `classify`'s output vocabulary
  (`inert`/`behavioral`/`stateful` stays exactly as-is) -- callers that already parse
  `classify`'s three-way output are unaffected; `deployable` is an opt-in convenience layer
  on top.
- DEC-002: UAT is documented (AGENTS.md + the well-formed fixture), not gated by a new
  `grep -qi UAT` in `check()` -- per the SG-07 goal contract's "CONSERVATIVE -- reuse, do
  not reinvent or tighten the shared path" instruction; the fixture and AC2/AC5 assert the
  contract without touching the enforcement code other consumers depend on.
