# SPEC-103: stop test fixtures polluting the real completeness.log

Status: VALIDATED
Lane: tiny
Type: spec-feature

## Problem

The SPEC-073 eval (bonus finding, ID-087) found leaked `LANE-CHECK downgrade ... "add user
authentication with jwt sessions"` lines in the operator's real durable
`~/.local/state/dwarves-kit/logs/completeness.log`. Root cause: `tests/test-lane-escalation.sh`
invokes `lane-classify check tiny "add user authentication with jwt sessions"` (its AC2
downgrade-guard assertion) at line 67, BEFORE the test sets `DWARVES_KIT_LOG_DIR` (which it only
sets from line ~74, for the gate-ledger portion). `lane-classify check`'s downgrade writer
resolves the log dir via `kit_resolve_log_dir`, so with no env set it writes to the REAL log.
The suite runs repeatedly (CI + local), so each run appended another leaked line.

## Scope (verified sole leak)

Every test `check`-with-downgrade invocation was audited: `test-hooks.sh` (file-wide export at
line 14) and `test-ledger-durability.sh` (its `run`/`new_env` helpers wrap the env, verified by
its own `$DURABLE/completeness.log` assertion) are isolated. `test-lane-escalation.sh:67` was the
sole un-isolated writer.

## Solution

Add a file-wide `export DWARVES_KIT_LOG_DIR="$(mktemp -d ...)"` near the top of
`tests/test-lane-escalation.sh` (mirroring `tests/test-hooks.sh`'s existing convention), so every
`check` in the file writes to a throwaway dir. The per-command `DWARVES_KIT_LOG_DIR="$LOG_DIR"`
prefixes later in the file intentionally override it for the ledger AC. No code-side change to
`lane-classify check` (the goal's smallest-fix preference: isolate the tests, don't add runtime
magic to the writer).

The 12 already-leaked lines are NOT cleaned here (a one-off operator action, out of scope).

## Verification

```bash
cd dwarves-kit
L=~/.local/state/dwarves-kit/logs/completeness.log; a=$(shasum "$L")
for t in tests/test-*.sh; do bash "$t" >/dev/null 2>&1; done
b=$(shasum "$L"); [ "$a" = "$b" ] && echo CLEAN || echo POLLUTED
bash tests/test-lane-escalation.sh   # still 22/22
```

## After state

- `tests/test-lane-escalation.sh` exports an isolated `DWARVES_KIT_LOG_DIR`; the full suite leaves
  the real `completeness.log` byte-unchanged.
- `docs/verification/fixture-isolation.md` carries the shasum-unchanged capture + negative control.

## Open questions

None. (Cleaning the 12 already-leaked lines is a separate one-off operator action.)
