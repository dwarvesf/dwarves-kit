# SPEC-315: name negctl.sh in the proof-gate negative-control hints

**Status:** VALIDATED
Lane: full
Type: spec-feature
**Proof:** `docs/verification/negctl-hint.md`; `tests/test-hooks.sh`

## Problem

`lib/gate/proof-gate.sh contract "<task>"` prints a `rigor:` hint. For the behavioral class
(`proof_requirement`, around line 86) it says "include a negative control (revert -> RED ->
restore)" but never names the tool that mechanises that exact sequence,
`lib/gate/negctl.sh`. A session read the hint, did not know the tool existed, and hand-rolled
the mutate/test/restore loop by hand instead of running `bash lib/gate/negctl.sh <root>
"<test-cmd>" "<mutate-cmd>"`. The same gap sits in `proof_contract`'s fallback text (line 115,
the `(no registry row ...)` default `proof:` line), which also asks for "a negative control"
with no pointer to the command.

## Contract

- `proof_requirement()`'s `behavioral` case in `lib/gate/proof-gate.sh` names `negctl.sh`
  inline, staying one line: `... and include a negative control (revert -> RED -> restore;
  \`lib/gate/negctl.sh\` runs this).`
- `proof_contract()`'s no-registry-row default `artifact` fallback (currently `"(no registry
  row for type '$type'; default: run the real primary flow + a negative control)"`) gets the
  same pointer, still one line.
- The `stateful` and `inert` cases of `proof_requirement()` do not mention a negative control
  today and are left alone.
- `tests/test-hooks.sh` gains one assertion after the existing "proof req: behavioral names
  negative control" line: the behavioral `requirement` output contains `negctl.sh`.
- No other test pins the exact hint string (checked: `tests/test-hooks.sh`,
  `tests/test-meta.sh`, `tests/test-ship-gate-coverage-map.sh` all use
  `assert_output_contains` substring checks against `rollback` / `negative control` /
  `exempt`, none against the full sentence), so no other test file changes.

## Picture

```
 proof-gate.sh contract "<task>"
       |
       v
 proof_class(desc) --behavioral--> proof_requirement()
       |                                  |
       |                                  v
       |                    "... negative control (revert -> RED -> restore;
       |                     lib/gate/negctl.sh runs this)."
       |
       +--no registry row--> proof_contract() fallback artifact text
                              "... a negative control (lib/gate/negctl.sh runs this)"
```

## Design

obvious: a wording fix to two hint strings that already exist, no new code path, no schema
or control-flow change. The mechanism (`lib/gate/negctl.sh`) already exists and is unmodified.

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: name the tool in both hints | `lib/gate/proof-gate.sh` | behavioral `requirement` output and the no-registry-row `contract` fallback both contain `negctl.sh`; both hints stay one line |
| T2: pin the fix in tests | `tests/test-hooks.sh` | new assertion: behavioral `requirement` output contains `negctl.sh` |
| T3: proof + notes | `docs/verification/negctl-hint.md`, `docs/implementation-notes/negctl-hint.md`, `docs/CHANGELOG.md` | green run + negative control recorded; delta-only implementation note; one CHANGELOG line |

## Test plan

| Case | Setup | Expected |
|---|---|---|
| Behavioral hint names the tool | `bash lib/gate/proof-gate.sh requirement 'add a flag'` | output contains `negctl.sh` |
| Fallback contract text names the tool | `bash lib/gate/proof-gate.sh contract '<task with no registry row>'` | `proof:` line contains `negctl.sh` |
| Existing substring assertions still hold | `bash tests/test-hooks.sh` | the pre-existing `rollback` / `negative control` / `exempt` assertions still pass unchanged |
| Negative control | `bash lib/gate/negctl.sh "$PWD" "bash tests/test-hooks.sh" "<sed removing negctl.sh from the hint>"` | green before, RED under the mutation, green + clean tree after restore |

## Verification

`bash tests/test-hooks.sh` exits 0. `bash tests/run-all.sh --changed` exits 0. The negative
control above is recorded in `docs/verification/negctl-hint.md`.

## After state

`proof-gate.sh contract`/`requirement` on a behavioral task, and the no-registry-row fallback,
both point a reader straight at `lib/gate/negctl.sh` instead of leaving them to reconstruct
the revert/RED/restore loop by hand.

Not covered: the `stateful` hint's rollback wording is untouched (no negative-control language
to begin with); `proof_skeleton`'s generic `## Negative control` section header is untouched
(it is a document skeleton, not a rigor hint).

## Decision Log

- Lane: full, because the change touches `lib/gate/`, per this task's own instruction, even
  though the diff is two one-line string edits.
- Scope held to the two hint strings that actually ask for a negative control; the `stateful`
  and `inert` cases do not, so they are not touched.
