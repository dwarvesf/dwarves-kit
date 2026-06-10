# SPEC-071: Gate and ledger defect fixes (4 live misses)

Status: SHIPPED
Date: 2026-06-11
Lane: full (classified: full, kit-machinery hard-gate; build discipline = the bug
loop, failing-test-first per defect)
Type: bug-fix / behavioral
Board: ID-061, ID-063, ID-062, ID-050

## Problem

Four defects found live, each with a recorded miss:

1. **ID-061**: `proof-gate.sh contract` returned `class=behavioral` for a doc task
   whose registry default is `inert`. Root cause confirmed by repro: `proof_class`
   falls through to a blanket `behavioral` default and NEVER consults the
   task-type registry's `default class` column; the board row's "behavior keyword"
   hypothesis was wrong (there is no keyword trigger, just the fall-through).
2. **ID-063**: ship-gate's SPEC-069 boardless advisory sits BELOW
   `[ -n "$SPEC" ] || exit 0`, so every spec-less (freeform) push exits before the
   nudge fires: exactly the work most likely to be un-boarded (live miss: PR #184
   economics-track shipped un-boarded, advisory silent).
3. **ID-062**: a behavioral-shaped RUN can ship with no committable verification
   record when the proof-gate's diff classifier fails open (non-adopted repo, or a
   tests/CI-only diff classifying inert). The session ledger (`.claude/debug/`,
   `$DWARVES_KIT_LOG_DIR`) is gitignored by design, so acceptance evidence dies
   with the session. Live miss: the CI-fix bug lane shipped green runs + negative
   control that existed only in chat until the operator asked.
4. **ID-050**: `gate-ledger.sh progress` can render ✓ marks PAST the ▶ pointer
   (faithful to the ledger: a later phase was disposed before an earlier gap).
   Faithful but misleading at a glance.

## Decision

1. **proof_class consults the registry** (ID-061): after the stateful keyword pass,
   look up the classified type's `default class` via `_registry_field "$type" 5`
   (awk `-F'|'` makes $2=task-type, $3=artifact, $4=skill, $5=default class; the
   table's own header note confirms 3/4/5). If the registry names a class, use it;
   blanket `behavioral` remains only for types with no registry row. Stateful
   keywords still upgrade first (a doc task that says "migrate the schema" stays
   stateful).
2. **Advisory moves above the spec check** (ID-063): the SPEC-069 boardless advisory
   block relocates above `[ -n "$SPEC" ] || exit 0` in hooks/ship-gate.sh, RETAINING
   its `$ROOT/_meta/BACKLOG.md` existence guard + grep (both `$ROOT` and `$SLUG` are
   in scope there, set ~30 lines earlier); still advisory, never blocks.
3. **Evidence-dies-with-the-session warn** (ID-062): in ship-gate, when the rid's
   run ledger shows a `build` gate `ran` under lane normal/full/bug AND the branch
   diff carries no `docs/verification/` (or `proof-of-done.md`) file, print ONE
   advisory line (never block). SCOPE (validator F2): `$BASE` is currently computed
   only inside the adopted-repo proof block, and `$LANE` only for spec-driven runs,
   so the warn computes its OWN base (same three-way origin/main -> main -> master
   fallback) and reads the lane from the ledger's START line via `$LEDGER show
   "$SLUG"` , never from the spec. Reads the ledger via `$LEDGER show` (no third
   copy of the runid transform). This covers the fail-open seams the proof-gate
   deliberately leaves; in adopted repos with behavioral diffs the proof-gate still
   BLOCKS as before.
4. **Out-of-order ✓ gets its own marker** (ID-050): a disposed phase rendering
   AFTER the ▶ pointer renders as `*<phase>` (done-out-of-order) instead of
   `✓<phase>`, plus one dim legend line, exactly `  (* = disposed out of order)`,
   when any such mark exists. DEVIATION from
   the board row's "sort-by-plan-order display option" sketch: re-sorting would lie
   about plan position; a distinct marker keeps the glance honest with zero flags.

## Acceptance criteria

- AC1: `proof-gate.sh contract "<the live doc phrasing>"` -> `class=inert`
  (registry default for type=doc); a stateful-keyword doc task stays `stateful`;
  a type with no registry row still defaults `behavioral`.
- AC2: a spec-less push whose branch slug is not on the board prints the boardless
  advisory (exit still 0); a boarded spec-less push prints nothing.
- AC3: a push whose run ledger has `build ran` under lane bug/normal/full and no
  fresh verification file prints the ID-062 advisory; adding the verification file
  silences it; a tiny-lane or no-ledger push prints nothing.
- AC4: a ledger with `review ran` but `build` undisposed renders `▶build` and
  `*review` (not `✓review`) + the legend line; an in-order ledger renders no `*`
  and no legend.
- AC5: all three suites green; every fix carries its failing-test-first pin
  (test written against the pre-fix behavior, RED, then fix, GREEN).

## Test plan

| # | Case | Proof | Expected |
|---|------|-------|----------|
| 1 | ID-061 repro pin | `contract` on the live doc phrasing | `class=inert` |
| 2 | ID-061 stateful guard | doc phrasing + "migrate the schema" | `class=stateful` |
| 3 | ID-061 no-registry fallback | phrasing classifying a rowless type | `class=behavioral` |
| 4 | ID-063 spec-less boardless | fixture repo, no spec, slug off-board, push | advisory on stderr, exit 0 |
| 5 | ID-063 boarded negative | same fixture WITH `_meta/BACKLOG.md` present + slug on a board row (file-existence guard must be reachable, validator F4) | no advisory |
| 6 | ID-062 warn | fixture ledger build-ran lane=bug, diff without verification | advisory on stderr, exit 0 |
| 7 | ID-062 silenced | same + verification file in diff | no ID-062 advisory |
| 8 | ID-050 out-of-order | ledger review-ran build-gap, `progress` | `*review` + the exact legend line, piped plain (quote the `*` pattern in asserts: glob trap) |
| 9 | ID-050 in-order negative | sequential ledger | no `*`, no legend; the pre-existing in-order pin (test-hooks "progress: checklist marks") doubles as this regression guard |

Negative controls: each fix reverted in isolation flips its pin RED (run live at
build); the SPEC-069/070 suites stay green throughout (no regression).

## Verification

- Failing-test-first: 12 assertions written against the PRE-fix tree -> 5 RED (one
  per defect surface), fixes applied -> GREEN. Review fixes added 4 more assertions
  (operate/planning registry floors, rowless-fallback source pin) -> 345/345.
- `tests/test-hooks.sh` 345/345; `tests/test-meta.sh` 432/432; `tests/test-e2e.sh`
  20/20.
- Deliberate side effect documented in code + here: migration/incident/operate now
  floor at registry `stateful`, planning/learning at `inert`, even without step-2
  keywords; spec-feature/eval/research/data-tool/reconcile unchanged.

## Review

Date: 2026-06-11. Multi-lens (3 parallel reviewers). Pre-fix: security 7/10,
architecture 7/10, test-coverage 7/10. Fixed in-branch:

- Security F2: the lane= sed extraction anchored to the START field separator
  (`\| lane=`), closing the contrived repo-named-lane-full spoof.
- Architecture F1: `_classify_type` helper, one classify fork shared by
  proof_class + proof_contract; F2: `_resolve_base` helper, the three-way
  default-branch fallback now has ONE copy in ship-gate; F3: ordering comment on
  the ID-062 block (deliberately after the proof block); F4: silent registry-floor
  side effects documented in code + spec + 2 new tests; F5: the ID-062 evidence
  grep aligned byte-level with proof-ledger's `_fresh_proof_files` (md anchor +
  README exclusion).
- Test F1: row 3 (rowless fallback) confirmed unreachable via classify today;
  covered by a source-text pin + the AC note. F2 (boarded-negative trivially green
  pre-fix) accepted: its purpose is post-fix regression guarding.

Post-fix: hooks 345/345, meta 432/432, e2e 20/20. Verdict: SHIP.

Test-authoring note (validator F5): AC2/AC3 fixtures reuse the existing ship-gate
fixture pattern (mktemp git repo + `CLAUDE_PLUGIN_ROOT=$KIT_DIR` +
`DWARVES_KIT_LOG_DIR` isolation + JSON piped to the hook); AC2 fixtures add
`_meta/BACKLOG.md`.
