# Implementation notes -- lane-bug-machinery

Deltas from SPEC-362. Nothing here repeats what the spec already states.

## 2026-09-29 The bug-lane review and debug gates are advisory without a spec
- Context: `hooks/ship-gate.sh` exits 0 at the spec lookup when no `docs/specs/SPEC-*-<slug>.md` exists. A bug-lane run usually has no spec.
- Decision/Change: none. The diff-keyed proof-of-done gate still blocks an unproven `lib/` or `hooks/` change, so the approved condition holds. The lane-gate check (build, review, debug) is not hook-enforced for a spec-less run; that is true for every bug-lane run today.
- Impact: a demoted machinery bug fix loses the hook-enforced full-lane phases (think, spec, validate, docs, reflect). The proof gate and the lane-independent review-team rule remain.

## 2026-09-29 Side effect during grounding
- Running `lane-classify.sh check bug --files lib/wrap/wrap.sh ...` for the round-0 grounding appended one `LANE-CHECK | downgrade` line to the operator's `completeness.log`. That line is a grounding artifact, not a real run. It stays in the log, by the lead's instruction. Round-2 grounding ran through a scratch prototype and wrote no log.

## 2026-09-29 Lead decisions, round 0 (pre-validation)
- (a) Accepted: a spec-less bug-lane machinery fix is held only by the proof gate (green run plus negative control), the same as every other bug-lane fix. Recorded as a deliberate tradeoff under Design. Wrap step 10 merges such a fix only through `wrap merge --apply`'s green gate.
- (b) Folded in: a machinery change with a TEXT contract signal sizes `full` even when the tiny rule matches first (Change item 7). The rename term narrowed to a rename of a flag, verb, knob and the like, so renaming a local variable stays `tiny`. The file contract check stays out of the tiny override.
- (c) Folded in, then narrowed in round 2 (below).

## 2026-09-29 Lead decisions, round 1 (NEEDS REVISION, one critical)
- Enforcement-file guard (lead ruling, primary defence): a change to an enforcement file never demotes; on the text-only path, a text naming an enforcement file or gate word never demotes. The set lives once in `_ENFORCEMENT_GLOBS` and `_ENFORCEMENT_WORDS_RE` (Change item 5).
- Consequence stated in the spec's Problem: `lib/wrap/wrap.sh` is enforcement, so the SPEC-360 wrap-merge fix, the motivating example, still sizes `full` (G3). The demotion reaches telemetry, board, session, queue, goal libraries and non-blocking hooks.
- Item 2a scope (lead ruling): a root `install.sh` or `settings.json` counts as machinery only in the kit repo (`lib/classify/lane-classify.sh` at the git toplevel). The round-0 any-depth `adopt.sh`/`hooks.json` pattern is dropped; the real kit paths already fire through `lib/*` and `hooks/*`.
- The round-0 flip of the existing "fix the parser in lib/gate/gate-ledger.sh" case is gone: the enforcement word `gate-ledger` keeps it `full`. No existing expectation in the suite changes.

## 2026-09-29 My calls inside the round-1 fold
- Added `lib/goal/mega-merge.sh` and `lib/goal/stack-merge.sh` to the enforcement set: they are merge automation in the same class as `wrap.sh`'s merge gate. Over-size direction only.
- Added `hooks/anchor-root.sh` to the set: it relays the exit codes of the hooks it wraps.
- Added `(wrong(ly)?|incorrectly|falsely) (block|refus|reject|den)` to the contract vocabulary so the vocabulary alone also holds the "wrongly blocking/refusing" round-1 texts. Left out `fail`: "wrongly failing on an empty board" is an ordinary defect.
- `_ENFORCEMENT_WORDS_RE` starts with `-gate`, which BSD `grep` parses as an option. The prototype hit this; the build uses `grep -qE -e` for every such regex.
- Added NC2F (file check only) and NC6 (both defences off). The round-1 texts are held by both defences, so NC5 alone cannot redden them; NC6 is their control.
