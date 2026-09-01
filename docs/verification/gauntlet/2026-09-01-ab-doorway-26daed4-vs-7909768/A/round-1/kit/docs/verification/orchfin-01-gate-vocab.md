# Proof of done: gate recording gap closed for build/design-critique/design-record (ID-091)

Behavioral change: `commands/execute.md`, `commands/devs-team.md`, and `commands/spec-validate.md`
each gain a `gate-ledger.sh record` call for a full-lane required matrix row (`build`,
`design-critique`, `design-record`) that previously had no owning command. A command-driven
full-lane run no longer needs any hand-recorded gate to reach `gate-ledger.sh check full <rid>`
exit 0. New test: `tests/test-gate-vocab-recording.sh`.

## Green run

Command: `bash tests/test-gate-vocab-recording.sh`
Exit: 0
Output (tail):
```
=== AC4: a command-driven full-lane run (all 12 gates recorded by literal name) reaches ship ===
  PASS check full <rid> passes with all 12 gates recorded (exit 0)

=== AC5: NEGATIVE CONTROL -- drop just 'build' (execute.md's own gate), the same run re-blocks ===
  PASS check full <rid> FAILS when build is not recorded (exit != 0)
  PASS the check names 'build' as the missing gate

=== Summary: 17/17 passed ===
```

## The dynamic negative control (built into the test, AC4/AC5)

`tests/test-gate-vocab-recording.sh` runs the REAL `gate-ledger.sh check full <rid>` mechanism
twice, isolated via a fresh `DWARVES_KIT_LOG_DIR` per run (never touches the real ledger):

1. **AC4 (positive):** all 12 full-lane required names recorded under a fresh rid, using the
   exact literal strings `execute.md`/`devs-team.md`/`spec-validate.md` (and the other 9
   already-wired commands) now emit. `check full <rid>` exits 0.
2. **AC5 (negative control):** the identical run, with only `build` omitted (simulating
   `execute.md`'s new record call being reverted). `check full <rid>` exits non-zero and names
   `MISSING-GATE: build` -- the same mechanism, same rid shape, the ONE difference being the
   missing `build` line, proves the green in (1) is not vacuous.

## NEGATIVE CONTROL (revert -> RED -> restore, on the real source file)

Beyond the built-in dynamic control above, the fix itself was reverted and restored against the
actual command file to prove the test detects the real regression, not just a simulated one:

1. **Revert:** removed the new `build`-record paragraph from `commands/execute.md` (the exact
   block this PR adds), leaving the file otherwise identical to `HEAD`.
2. **RED:** `bash tests/test-gate-vocab-recording.sh` -> **exit 1**, `15/17 passed`:
   ```
   FAIL 'build' is recorded by commands/execute.md (literal 'build ran')
   ```
   (AC4/AC5 stayed PASS since those two checks exercise the ledger mechanism directly with
   hardcoded literals, not by reading `execute.md`; AC2's per-owner check and AC3's no-orphan
   sweep are what caught the regression -- exactly the two checks whose job is to catch this.)
3. **Restore:** `git checkout -- commands/execute.md` (clean revert of the temp edit; `git status`
   confirmed no diff).
4. **Green again:** `bash tests/test-gate-vocab-recording.sh` -> **exit 0**, `17/17 passed`.

## Regression sweep (no drift in the pre-existing suite)

| Test | Result |
|---|---|
| `tests/test-command-emit-sweep.sh` | 19/19 PASS |
| `tests/test-design-record.sh` | 26/26 PASS |
| `tests/test-references-field.sh` | 15/15 PASS |
| `tests/test-gate-outcome.sh` | 22/22 PASS |
| `tests/test-lane-escalation.sh` | 22/22 PASS |
| `tests/test-right-arm-parity.sh` | 38/38 PASS |
| `tests/test-understanding-wiring.sh` | 17/17 PASS |
| `tests/test-meta.sh` (full kit self-test) | 679/679 PASS |

## Reproduce

```bash
bash tests/test-gate-vocab-recording.sh   # 17/17, exit 0

# reproduce the revert -> RED -> restore control:
cp commands/execute.md /tmp/execute.md.bak
python3 -c "
p='commands/execute.md'; s=open(p).read()
block='''   Record the build gate (closes the recording gap WORKFLOW.md \"## Command emit coverage\"
   used to flag as pre-existing): \`bash lib/gate/gate-ledger.sh record <rid> build ran
   \"tasks=<N>/<N> verified=<N> tests=<pass|fail>\"\`. This is Build's own phase-owner record
   (execute.md IS the Build phase), the same one-line convention every other phase owner
   (\`think.md\`, \`design.md\`, \`spec.md\`, ...) already uses.

'''
open(p,'w').write(s.replace(block,''))
"
bash tests/test-gate-vocab-recording.sh   # expect exit 1, 15/17, FAIL on 'build'
git checkout -- commands/execute.md
bash tests/test-gate-vocab-recording.sh   # back to exit 0, 17/17
```
