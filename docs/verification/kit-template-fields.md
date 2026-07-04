# Proof of done: kit-template-fields
Profile: feature   Proof class: behavioral

## Hypothesis / assumptions
- The three prose absorptions (spec `References:` field, Design-section likelihood-to-tweak
  ordering, meta-agent Mode C `Post-condition:` line) land as OPTIONAL additions with no new
  gate and no new required field in `/kit:spec-validate`.
- What would prove this false: a fixture spec WITH the `References:` field getting a different
  `/kit:spec-validate` Reviewer 6 verdict than the byte-identical fixture WITHOUT it. If they
  differ, the field silently became load-bearing to the gate, contradicting the sub-goal
  contract.

## Test design
- `tests/test-references-field.sh` runs Reviewer 6's structural contract (reproduced as a pure
  function, same pattern as `tests/test-design-record.sh`) against
  `tests/fixtures/references-field/{with,without}-references.md`, two specs identical except
  for the `References:` line, and asserts both verdicts are `PASS` and equal to each other.
- Negative control: revert `commands/spec.md` to its pre-change state (no `References:` field,
  no ordering instruction) and re-run the same test , the 3 assertions that grep for the new
  template text must fail RED, proving the test is actually exercising the change and not
  vacuously green.
- Full regression: `tests/test-design-record.sh` (Reviewer 6 fixtures unaffected),
  `tests/test-meta-agent.sh` (Mode A/B/C fixtures unaffected), `tests/test-meta.sh` (the whole
  spec-authoring depth contract, 667 assertions).

## How to re-run
```
bash tests/test-references-field.sh
bash tests/test-design-record.sh
bash tests/test-meta-agent.sh
bash tests/test-meta.sh
```

## Runs

### 2026-07-04 06:40 GREEN -- kit-template-fields [green]
- Command: `bash tests/test-references-field.sh`
- Exit: 0
- Output (excerpt):
  ```
  --- WITH a References: field ---
    PASS fixture carries a 'References:' field
    PASS Reviewer 6 verdict WITH References: GREEN
  --- WITHOUT a References: field (byte-identical otherwise) ---
    PASS fixture carries NO 'References:' field
    PASS Reviewer 6 verdict WITHOUT References: GREEN
  --- No-new-gate proof: both verdicts equal (presence of References is inert) ---
    PASS verdict is identical with and without the field
  Passed: 15 / 15
  All references-field tests passed.
  ```
- Verdict: PASS
- Note: covers the "no new gate" acceptance criterion in SPEC-137's After state.

### 2026-07-04 06:41 RED-as-expected -- kit-template-fields [negative-control]
- Command: `bash tests/test-references-field.sh` (run against `commands/spec.md` temporarily
  reverted to its pre-change content, via `git show HEAD~1:commands/spec.md`, in the same
  working tree; restored immediately after, confirmed clean by `git status --short` /
  `git diff --stat` showing no diff)
- Exit: 1
- Output (excerpt):
  ```
  --- Structural wiring: References is OPTIONAL, not a new required field ---
    FAIL commands/spec.md template has a 'References:' field (expected '0', got '1')
    FAIL commands/spec.md marks References as optional (expected '0', got '1')
    FAIL commands/spec.md states source-beats-description (expected '0', got '1')
  Passed: 12 / 15
  Failed: 3
  ```
- Verdict: RED-as-expected
- Note: the 3 failing assertions are exactly the ones asserting the new template text exists;
  everything reviewer-6-verdict-related (the no-new-gate assertions) stayed PASS even on the
  reverted file, which is itself further evidence those assertions are not coupled to this
  specific field's presence, i.e. they are testing the right thing (Reviewer 6's own logic, not
  a tautology). Working tree restored to the green state immediately after this run.

### 2026-07-04 06:41 PASS -- kit-template-fields [restore-confirm]
- Command: `bash tests/test-references-field.sh` (after restoring `commands/spec.md`)
- Exit: 0
- Output (excerpt): `Passed: 15 / 15` / `All references-field tests passed.`
- Verdict: PASS
- Note: confirms the revert-and-restore cycle left the working tree byte-identical to the
  committed state (`git status --short` empty, `git diff --stat` empty).

### 2026-07-04 06:42 PASS -- kit-template-fields [regression]
- Command: `bash tests/test-design-record.sh && bash tests/test-meta-agent.sh && bash tests/test-meta.sh`
- Exit: 0
- Output (excerpt):
  ```
  test-design-record.sh:  Passed: 26 / 26  -- All design-record tests passed.
  test-meta-agent.sh:     72/72 passed, 0 failed
  test-meta.sh:           Passed: 667 / 667 -- All meta tests passed.
  ```
- Verdict: PASS
- Note: no regressions in the two other suites that exercise `commands/spec.md`,
  `commands/spec-validate.md`, `commands/design.md`, and `agents/meta-agent.md`.

## Reversibility
Pure documentation/template-prose change (no runtime code, no schema, no migration): `git
revert` of the single commit fully undoes it. No stateful component to roll back.
