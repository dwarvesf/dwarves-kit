# Implementation notes: fixture-isolation (SPEC-103)

Delta from the spec. Reference, do not restate.

## 2026-07-02 sole leak, test-side fix

**Context:** the goal named `test-lane-escalation.sh`, `test-hooks.sh`, `test-lane-classify.sh`
as candidates.
**Decision:** the ONLY un-isolated `check`-with-downgrade writer is `test-lane-escalation.sh:67`;
fixed with a file-wide `DWARVES_KIT_LOG_DIR` export.
**Why:** audited every `check` invocation across the suite: `test-hooks.sh` exports at line 14;
`test-ledger-durability.sh`'s `run`/`new_env` helpers wrap the env (its own `$DURABLE` assertion
proves it); `test-lane-classify.sh` calls `classify` (which does not write completeness), not the
downgrade writer. Verified by an isolated probe: only `test-lane-escalation` reached the writer
before setting the env.
**Alternatives:** a code-side guard in `lane-classify check` (rejected per the goal's smallest-fix
preference: isolate the tests, don't add runtime magic to the writer).
**Impact:** tiny lane; no runtime behavior change. The 12 already-leaked lines are left for a
one-off operator cleanup (out of scope).
