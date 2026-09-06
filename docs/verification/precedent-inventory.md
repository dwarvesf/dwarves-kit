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
