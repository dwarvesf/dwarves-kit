# Verification log: SPEC-245 precedent inventory surface

Spec: `docs/specs/SPEC-245-precedent-inventory.md`. Branch `feat/precedent-inventory`, base `e7f5fee`.

## Phase 1 checkpoint (TASK-001 e07bc30, TASK-002 975b9bd)

Command: `bash tests/test-precedent.sh && bash tests/test-meta.sh && bash tests/test-bin-forwarders.sh`
Exit: 0 / 0 / 0
Output (excerpt): `6/6 passed`; `Passed: 829 / 829`; `test-bin-forwarders: all 36 passed, 0 skipped`
Verdict: PASS

TASK-001 task-verifier: PASS 5/5. Byte parity of `bin/precedent find "spec drift" --surface records` and of the positional `find "spec drift" 3` against the e7f5fee script (diff empty); default `all` prints the records then `precedent: 5 record matches, 0 inventory hits in 0 sections; top: -`; `--surface bogus` exits 64; `grep -rn 'precedent.sh find' commands/` empty.
Re-audit: PASS (recheck-verifier, fresh context, re-executed every command). Observation: the records surface exits 141 (SIGPIPE from its own `head`), identical to the pre-move script; the `all` path exits 0.

TASK-002: acceptance re-run by the lead after the dispatched verifier record was lost by the harness: `bash tests/test-precedent.sh` 6/6, step at `.github/workflows/test.yml:257`, zero em or en dashes in the file, `make_fixture` exports `FIX_HOME FIX_REPO FIX_SCRIPTS FIX_CRONS FIX_MEMORY FIX_LEDGER FIX_REGISTRY`, commit subject `test(precedent): fixture and records-surface cases`.

## Phase 2, TASK-003 (964f1a1)

Command: `bash tests/test-precedent.sh`
Exit: 0
Output (excerpt): `19/19 passed`; `python3 -m py_compile lib/precedent/inventory.py` exit 0; `bash tests/test-meta.sh` 829/829; `bash tests/test-bin-forwarders.sh` 36/36
Verdict: PASS (task-verifier 8/8: edge cases 2 to 8, 11, 12 probed on scratch fixtures; a `ghp_` token in a memory note prints as `[redacted]` in text and JSON; a 400-char line caps at 240; an unwritable ledger root still exits 0; a binary file in a `scripts` dir is skipped; an empty repo as ROOT still lists the kit verbs)
Re-audit: PASS (recheck-verifier, fresh context; `bin/precedent find "board set" --surface inventory` lists `kit lib/board/board.sh` under `## kit verbs`, third hit after `backlog.sh` and `board-mirror.sh`)
Known delta: the After-state bullet names `bin/board`; the AND scorer gives the 13-line forwarder 0 for `set`, so the hit is the lib entry. Intent satisfied; wording corrected at TASK-005.

## Phase 2 checkpoint, TASK-004 (0f8d25a)

Command: `bash tests/test-precedent.sh && bash tests/test-meta.sh && bash tests/test-bin-forwarders.sh`
Exit: 0 / 0 / 0
Output (excerpt): `23/23 passed`; `Passed: 829 / 829`; `all 36 passed, 0 skipped`
Verdict: PASS (task-verifier 9/9: `bin/precedent find "board set"` prints `## records` first, `## kit verbs` at line 16, last line `precedent: 5 record matches, 22 inventory hits in 3 sections; top: kit verbs`; `--json` is one object with `records` and `total_hits`; records surface byte-equal to the e7f5fee script; five runs leave no `precedent-records.*` temp files)
Re-audit: PASS (recheck-verifier, fresh context; parity confirmed by cmp and sha256, 520 bytes both sides)

## NEGATIVE CONTROL (lead, throwaway worktree at 1c23d91)

Command: `bash lib/gate/negctl.sh <throwaway> "bash tests/test-precedent.sh" "sed -i '' 's/^    if not terms:$/    if True:/' lib/precedent/inventory.py"` (the scorer returns 0 for every entry)
Exit: 0 green before mutation; 1 under mutation; 0 after `git checkout HEAD -- lib/precedent/inventory.py`
Output (excerpt, under mutation): `17/23 passed`; RED cases: default (all) surface nonzero summary line, kit.toml registry fallthrough scans the scripts row, name-over-body ranking, `~` expansion row scanned, secret redaction reaches a hit line, crons section lists both expressions
Verdict: RED-as-expected (negctl `Verdict: PASS`); the throwaway worktree was removed afterwards, the shared checkout was never mutated
