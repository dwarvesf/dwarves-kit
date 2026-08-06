# Implementation notes: loop-02-outcome-emit (SPEC-193)

Delta from the spec/goal file only; the spec carries the inventory and the proof-of-done carries the evidence.

## 2026-07-12 03:50 ship.md excluded from the literal inventory by its own prose

Context: the goal's inventory command (`rg ... | rg -v outcome`) silently dropped `commands/ship.md`'s `record <rid> Ship ran` site because the line's unrelated prose contains the word "outcome".
Decision: documented exemption, no new bracket.
Why: `hooks/ship-gate.sh` already emits the `ship` OUTCOME pair (SPEC-129's original live emit) and `normalize_phase()` folds `Ship`/`ship` to one key, so a command-side bracket would double-emit.
Alternatives: bracket it anyway (double emit, corrupts durations); widen the inventory regex (churns the goal file mid-loop).
Impact: the standing lint carries an explicit `ship` exemption with a load-bearing NC (removing the exemption must flag ship.md).

## 2026-07-12 03:50 caught= omitted at 8 verdict-less sites

Context: SPEC-129's `caught=` needs a verdict/count to derive from.
Decision: at 8 of 22 sites (test-plan authoring, pitch, docs, explain, spec approval, design) `caught=` is omitted; the verb's documented `false` default stands.
Why: deriving a verdict where the phase records none would invent gate-decision logic, which the goal's quality bar forbids (zero behavior change to gate decisions).
Impact: uniform, predictable rule recorded in the spec's inventory table.

## 2026-07-12 03:50 lane normal, not full

Context: `bin/classify lane classify` returned `normal`; the goal header says only `Design: obvious`, no lane override.
Decision: honored the classifier; gates recorded per the normal lane plan.
Impact: none on scope; recorded for telemetry honesty.
