# Proof of done: spec template Picture section (SPEC-214 / ID-454)

Behavioral change: `commands/spec.md`'s spec template gains a `## Picture` section (required
non-empty on full-lane specs, encouraged elsewhere); `commands/spec-validate.md`'s Reviewer 4
(Scope Critic) gains a mechanical presence check plus a lens question (does the picture agree
with `## Task Breakdown`). This is the pre-build twin of ID-395's post-build visual proof.

## Green run

Command: `bash tests/test-picture-section.sh`
Exit: 0
Output (tail):
```
Passed: 21 / 21
All picture-section tests passed.
```

Command: `bash tests/test-design-record.sh` (sibling contract, must stay unaffected)
Exit: 0
Output (tail):
```
Passed: 26 / 26
All design-record tests passed.
```

Command: `bash tests/test-meta.sh`
Exit: 0
Output (tail):
```
Passed: 732 / 732
All meta tests passed.
```

Command: `bash tests/test-hooks.sh`
Exit: 0
Output (tail):
```
Passed: 492 / 492
All tests passed.
```

## The 4 named controls (SPEC-214 Test plan)

1. **NEGATIVE CONTROL** -- `tests/fixtures/picture-section/full-lane-empty.md`: `Lane: full`,
   `## Picture` empty. The presence check (reproduced as a pure function in the test harness)
   returns `FLAG`. Assertion: `Reviewer 4 FLAGS a full-lane spec with an empty Picture section`
   -- PASS (i.e. the flag fires correctly).
2. **POSITIVE** -- `tests/fixtures/picture-section/full-lane-filled.md`: `Lane: full`,
   `## Picture` carries an ASCII diagram. Verdict `PASS`.
3. **PROPORTIONALITY CONTROL** -- `tests/fixtures/picture-section/normal-lane-empty.md`:
   `Lane: normal`, `## Picture` empty. Verdict `PASS` -- Picture is encouraged, not required,
   below full lane.
4. **ID-448 ROUTING CONTROL** -- `tests/fixtures/picture-section/full-lane-prototype-pointer.md`:
   `Lane: full`, `## Picture` names a `prototype/<name>` branch instead of ASCII. Verdict
   `PASS` -- a prototype pointer counts as presence for a UI-shaped spec.

All four, plus the structural wiring greps on both command files, are green (21/21 in
`tests/test-picture-section.sh`).

## NEGATIVE CONTROL (revert -> RED -> restore), run live

Corrupted the negative-control fixture itself by injecting content inside its `## Picture`
section (so it no longer represents "empty"), to prove the check is actually looking at the
content and not passing by construction:

```
$ python3 -c "... inject 'some diagram text landed here now' into full-lane-empty.md's ## Picture ..."
$ bash tests/test-picture-section.sh; echo "exit=$?"
  FAIL fixture 1's Picture section is empty (expected '', got 'some diagram text landed here now')
  FAIL Reviewer 4 FLAGS a full-lane spec with an empty Picture section (expected 'FLAG', got 'PASS')
Passed: 19 / 21
exit=1
```

Restored the fixture (`cp` from a pre-corruption backup):

```
$ bash tests/test-picture-section.sh; echo "exit=$?"
Passed: 21 / 21
exit=0
```

`git status --porcelain tests/fixtures/picture-section/full-lane-empty.md` is empty after
restore -- the fixture is byte-identical to what shipped in the commit, confirming the RED was
a real transient break, not a permanent edit.

## Reproduce

```bash
cd dwarves-kit   # or the spec-picture worktree
bash tests/test-picture-section.sh   # 21/21
bash tests/test-design-record.sh     # 26/26 (sibling contract, unaffected)
bash tests/test-meta.sh              # 732/732
bash tests/test-hooks.sh             # 492/492
```

VERDICT: PASS
