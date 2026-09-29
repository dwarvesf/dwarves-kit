# Implementation notes -- lane-bug-machinery

Deltas from SPEC-362. Nothing here repeats what the spec already states.

## 2026-09-29 One existing test case flips by design
- Context: `tests/test-lane-classify.sh` pins `"fix the parser in lib/gate/gate-ledger.sh"` as `full` under the label "AC6 gate-ledger still full".
- Decision/Change: that case now expects `bug`. The text carries a bug signal ("fix") and no contract signal, so the approved policy routes it to `bug`. A new sibling case, `"add a --json flag to lib/gate/gate-ledger.sh"`, keeps the "gate-ledger still full" guard on a contract change.
- Why: the old expectation encodes the rule this spec retires. Keeping it would pin the policy the operator replaced.
- Impact: the only changed expectation in the suite. Every other existing case keeps its lane.

## 2026-09-29 The bug-lane review and debug gates are advisory without a spec
- Context: `hooks/ship-gate.sh` exits 0 at the spec lookup when no `docs/specs/SPEC-*-<slug>.md` exists. A bug-lane run usually has no spec.
- Decision/Change: none. The diff-keyed proof-of-done gate still blocks an unproven `lib/` or `hooks/` change, so the approved condition holds. The lane-gate check (build, review, debug) is not hook-enforced for a spec-less run; that is true for every bug-lane run today.
- Impact: a machinery bug fix loses the hook-enforced full-lane phases (think, spec, validate, docs, reflect). The proof gate and the lane-independent review-team rule remain.

## 2026-09-29 Side effect during grounding
- Running `lane-classify.sh check bug --files lib/wrap/wrap.sh ...` for the grounding appended one `LANE-CHECK | downgrade` line to the operator's `completeness.log`. That line is a grounding artifact, not a real run. It stays in the log, by the lead's instruction.

## 2026-09-29 Lead decisions on the three open questions (pre-validation)
- (a) Accepted: a spec-less bug-lane machinery fix is held only by the proof gate (green run plus negative control), the same as every other bug-lane fix. The spec's Design section records it as a deliberate tradeoff. Wrap step 10 merges such a fix only through `wrap merge --apply`'s green gate.
- (b) Folded in: a machinery change with a TEXT contract signal sizes `full` even when the tiny rule matches first (Change item 2b). The rename term in the contract regex narrowed to a rename of a flag, verb, knob and the like, so renaming a local variable stays `tiny`. The file contract check stays out of the tiny override; a typo sweep that also touches `docs/WORKFLOW.md` stays `tiny`.
- (c) Folded in: `_files_touch_machinery` also fires on a root `install.sh`, a root `settings.json`, and `adopt.sh` or `hooks.json` at any depth (Change item 2a). The root anchor on `install.sh` and `settings.json` is my call: any-depth would pull a consumer app's `scripts/install.sh` or `config/settings.json` into the machinery surface in every adopted repo. `lib/skill-curator/deploy/install.sh` already fires through `lib/*`.
- Known over-size accepted with (b) and (c): a tiny task whose text names `install.sh`, `adopt`, `hooks.json` or `settings.json` sizes `full`, because those words are text contract signals.
