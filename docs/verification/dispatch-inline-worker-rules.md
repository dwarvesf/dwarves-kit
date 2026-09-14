# Proof of done: inline standing worker rules in `commands/dispatch.md`

Branch `feat/wrap-retry-and-dispatch`. Docs-only change: `commands/dispatch.md`'s worker
prompt template now carries a "Standing rules (carried inline, not by file reference)"
section directly in the text every dispatched worker receives, plus an explicit
missing-referenced-brief stop rule, instead of depending on a dispatching session's own
shared brief file (which can vanish, as it did overnight when macOS cleanup wiped a
`/private/tmp` scratchpad a dispatch had pointed six workers at, and only one of the six
said so).

No executable code changed; `commands/dispatch.md` is a prompt/instruction file with no
`bash -n` surface.

## Scope of this check

This is a docs-only prompt-template edit to one file: `commands/dispatch.md`. The full
`bash tests/run-all.sh` suite is the wrong check for a change this narrow, it takes 20+
minutes under concurrent sessions on this host and exercises hundreds of unrelated
behaviors. It was started in the background; see "Background full-suite status" below.
**It was not waited on and its result does not gate this proof.**

The targeted check is every test under `tests/` whose own source references
`commands/*.md`, `COMMANDS_DIR`, or `commands/dispatch.md` by name (found via
`grep -rl "commands/\*\.md\|commands/\$\|COMMANDS_DIR\|commands/dispatch" tests/*.sh`):
`test-boundary-lint.sh`, `test-command-triggers.sh`, `test-command-emit-sweep.sh`,
`test-gate-vocab-recording.sh`, `test-no-scattered-ids.sh`, `test-outcome-emit-sweep.sh`,
`test-understanding-wiring.sh`, plus `test-docs-wiring.sh` and `test-goal-dispatch.sh`
(dispatch's own worker-forwarding tests) for coverage of the file dispatch.md documents
and drives.

## Runs

| # | Command | Exit | Verdict |
|---|---|---|---|
| 1 | `bash tests/test-command-emit-sweep.sh` | 0 | PASS `18 / 18`, incl. AC5: `dispatch.md has ZERO gate-ledger mentions of its own (the exemption entry is the ONLY thing keeping it non-orphan)` -- confirms the new text did not accidentally trip the gate-ledger orphan sweep |
| 2 | `bash tests/test-docs-wiring.sh` | 0 | PASS `25/25 passed` |
| 3 | `bash tests/test-boundary-lint.sh` | 0 | PASS `5/5 passed` (incl. its own negative controls, AC2/AC3) |
| 4 | `bash tests/test-command-triggers.sh` | 0 | PASS `9/9 passed` |
| 5 | `bash tests/test-goal-dispatch.sh` | 0 | PASS `TOTAL: 20   PASS: 20   FAIL: 0   SKIP: 0` |
| 6 | `bash tests/test-gate-vocab-recording.sh` | 0 | PASS `Summary: 20/20 passed` |
| 7 | `bash tests/test-no-scattered-ids.sh` | 0 | PASS `all 9 passed`, incl. `Zone 7: no id anywhere in commands/*.md` -- confirms the new prose carries no spec/ticket ID |
| 8 | `bash tests/test-outcome-emit-sweep.sh` | 0 | PASS `51 / 51` |
| 9 | `bash tests/test-understanding-wiring.sh` | 0 | PASS `19 / 19` |

Total across the nine targeted files: 176/176 passing, 0 failures.

## Negative control

None of the above tests assert the literal content of the new "Standing rules" block
(none existed to break before this change, so there is nothing for a revert to turn red
against). A revert of this change would not fail any of runs 1-9; that is expected and is
stated here plainly rather than manufacturing a negative control against an assertion
that does not exist. The closest thing to a control this change already carries is run 1's
AC5: it proves the gate-ledger orphan sweep still treats `dispatch.md` correctly (via its
existing exemption-table mechanism) after the new text was added, i.e. the addition did
not silently break an *existing* assertion.

## Manual read-check

Re-read the edited block in `commands/dispatch.md` (inside the worker-prompt template, the
part sent verbatim to every dispatched worker): confirms it carries, inline, all eight
required rules (premise-check-before-editing, worktree not branch-switch, never merge your
own PR, commit before the negative control, no em/en dash, never `git add -A`, mask
secret-shaped strings in reports, and the missing-referenced-brief stop-and-say-so rule),
and that no other section of the file was restructured.

## Background full-suite status

`bash tests/run-all.sh` was launched in the background before this proof was written; it
had not produced output after several minutes (consistent with the 20+ minute runtime
under concurrent sessions this host is known for) and was not waited on. If it finishes
with a result worth recording, it will be appended to this file or noted separately; its
absence here does not weaken this proof, which rests on the nine targeted runs above.
