# Implementation notes -- significance-classify

Delta from ADR-0031 / SPEC-122. The spec pins the exact regexes and marker format; this logs
decisions the spec left to build time and one deliberate deviation.

## 2026-07-03 Marker name: `DEBT`, not `UNDERSTANDING` or `WORTHINESS`
- Context: ADR-0032 section 3 calls this "the significance/worthiness marker" and "the debt
  ledger" interchangeably; nothing pinned the literal ledger tag before this sub-goal.
- Decision: the gate-ledger subcommand is `debt` and the line tag is `| DEBT |` (not, say,
  `| UNDERSTANDING |` or `| GATE-DEBT |`).
- Why: ADR-0031/0032 both use "the debt ledger" as the noun for this whole concern (cognitive-
  debt budget, debt paydown); `DEBT` is the shortest name that matches the ADRs' own vocabulary
  and reads unambiguously next to the existing `GATE`/`TOKENS`/`START`/`ACTION` tags.
- Alternatives considered: `WORTHINESS` (rejected -- names only one of the two signals, and the
  marker also carries `verdict=`, which is neither signal alone).

## 2026-07-03 `record` requires a rid; no auto-derive from cwd
- Context: `gate-ledger.sh rid` already derives a canonical rid from the current branch, and
  could have been called implicitly inside `significance-classify.sh record` if no rid were
  passed.
- Decision: `record <rid> ...` takes the rid as an explicit first argument; it does not shell
  out to `gate-ledger.sh rid` on the caller's behalf.
- Why: ADR-0032 section 3 splits the debt ledger across conductor/worker under delegation -- the
  worker's rid is not always "the current branch of the process significance-classify.sh happens
  to run in" (a delegated child session's cwd may differ from the conductor's). Forcing the
  caller to pass the rid explicitly (exactly as `gate-ledger.sh record`/`action`/`tokens` already
  require) keeps one calling convention across every ledger writer, and avoids a classifier that
  silently writes to the wrong run's ledger if invoked from an unexpected cwd.
- Impact: none on this sub-goal's own tests (they pass a synthetic rid); a future caller (SG-04)
  must pass the correct rid explicitly, which its own design already implies (it inherits the rid
  the worker recorded under).

## 2026-07-03 Significance's "full lane" leg shells out to lane-classify.sh instead of a copy
- Context: the spec's contract said "sibling to lane-classify.sh" but did not say whether
  significance-classify.sh may call it as a subprocess or must stay hermetic (no cross-lib
  dependency).
- Decision: `classify_core` calls `bash "$LANE_CLASSIFY" classify [--files ...] "$desc"` and
  checks for the literal string `full`, rather than re-implementing the hard/soft flag lists.
- Why: lane-classify.sh's flag lists (auth, data-model, kit-machinery, etc.) already ARE most of
  what "did a lot change" means; copying them would create a second copy that silently drifts the
  next time either file is edited (the exact drift bug class SPEC-098/SPEC-105 exist to prevent
  for lane-classify itself). A cross-lib call has a small fragility cost (noted as an open
  question in the spec) but is bounded: lane-classify's CLI contract (`classify [--files ...]
  "<desc>"` -> one of 5 lane names on stdout) is itself tested by tests/test-lane-classify.sh, so
  a breaking change there fails loudly in CI before it can silently break this classifier.
- Alternatives considered: duplicate a trimmed subset of the hard-gate regexes locally (rejected,
  drift); make `full` detection a THIRD signal orthogonal to significance (rejected -- ADR-0031
  explicitly names "full lane" as one of the three things that make up "did a lot change",
  alongside design-bearing and new-public-surface, not a separate axis).

## 2026-07-03 One tunable knob: `SIGNIFICANCE_WORTHINESS_MIN`, default 1
- Context: the contract required "a defensible, tunable heuristic (one flag), not magic."
- Decision: worthiness is HIGH when the count of fired triggers (5 text regexes +
  `impl-notes-feed`) is `>= ${SIGNIFICANCE_WORTHINESS_MIN:-1}`.
- Why: default 1 means any single worthiness trigger, combined with high significance, taps.
  This is the most sensitive setting; the double-gate (significance AND worthiness both required)
  already absorbs most of the anti-fatigue burden per ADR-0031's own reasoning ("the double gate
  ... already does most of the anti-fatigue work"), so the default is not tuned defensively a
  second time. If the tap rate proves too eager once this runs against real changes,
  `SIGNIFICANCE_WORTHINESS_MIN=2` is the single lever to raise the bar without touching code.
- Not yet measured in production (no live caller wired this sub-goal, see SPEC-122 "Open
  questions"); the default is a reasoned starting point, not an empirically-tuned one.

## 2026-07-03 No live caller wired (matches SPEC-105's precedent, deliberately out of scope)
- Context: the contract's "In scope" list is `lib/significance-classify.sh`, its ledger marker,
  the test file, and one WORKFLOW/AGENTS line -- not wiring a real call site.
- Decision: no command (`/kit:ship`, `/kit:execute`, etc.) actually invokes
  `significance-classify.sh record` yet; the WORKFLOW.md line documents WHERE it fires (at Ship)
  without claiming it dispatches today.
- Why: SPEC-105 (`lib/lane-classify.sh --files`) shipped its discriminator + interface first and
  left wiring to a follow-up once a caller had the touched-file list in hand; this sub-goal
  follows the same shape deliberately, since wiring the call site is SG-04's problem (it decides
  what a `tap` DOES) and premature wiring here would guess at that contract.
- Impact: `docs/decisions/0032-megagoal-execution-hygiene.md`'s wiring-gate lesson ("every new
  artifact must prove a live invocation path") is satisfied at the LIBRARY level (the
  classify/explain/record subcommands are exercised end-to-end by the test suite, which IS a live
  invocation path), not yet at the SHIP-COMMAND level; SG-04/SG-06 are expected to close that gap
  and should flag it if they don't.

## 2026-07-03 Multi-lens review (SPEC-069): one MEDIUM fixed, one MEDIUM test-gap closed
- Context: this sub-goal touches `lib/`, so per SPEC-069 the Review gate ran three lenses
  (security, architecture, test-coverage) instead of a single reviewer.
- Findings: security 9/10 (one LOW, no fix needed -- `debt()`'s enum-`case` validation already
  makes the flagged non-issue a non-issue in practice); architecture 8/10 (one MEDIUM: the
  `lane-classify.sh` subprocess call silently swallowed a nonzero exit, dropping the "full lane"
  significance leg to LOW indistinguishably from a legitimate non-full result -- exactly the
  untracked-debt failure ADR-0031 exists to prevent); test-coverage 7/10 (two MEDIUM: 4 of 7
  pinned regex triggers -- `design-bearing`, `new-public-surface`, `blast-radius`, `must-explain`
  -- had zero dedicated assertions, and the `SIGNIFICANCE_WORTHINESS_MIN` tunable knob, called
  "load-bearing" in this doc, was completely untested).
- Decision/Change: (1) `classify_core` now captures the lane-classify subprocess's exit code and
  emits a named stderr warning on failure before degrading, rather than a bare `|| echo ""`; (2)
  added 5 `explain`-based per-trigger assertions (one per untested regex name) plus a 2-case knob
  test (`SIGNIFICANCE_WORTHINESS_MIN=2` flips a one-trigger case from tap to wave) plus 3 edge-
  case tests (empty description, nonexistent `--impl-notes` path, `record` against a fresh
  nonexistent log dir) to `tests/test-significance-classify.sh` (15 -> 25 assertions).
- Why: the architecture finding directly undercuts ADR-0031's own premise (an untracked failure
  mode inside the classifier that decides what stays untracked); the test gaps left the two
  regex groups most likely to silently break (an unescaped metachar, a typo) with no CI signal.
- Not changed: the one LOW security finding (routing `debt()`'s already-enum-validated
  `significance=`/`worthiness=`/`verdict=` fields through `oneline()` too, for defense-in-depth
  consistency) -- deferred as genuinely optional per the reviewer's own assessment (zero
  behavioral risk today; noted here so a future editor of `gate-ledger.sh` sees it was seen, not
  missed).
