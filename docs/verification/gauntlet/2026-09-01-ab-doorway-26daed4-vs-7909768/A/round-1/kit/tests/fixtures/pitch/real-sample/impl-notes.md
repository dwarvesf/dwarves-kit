# Implementation notes: kit-emit-sweep (SPEC-139)

Frozen snapshot of the real implementation-notes, trimmed for `tests/test-pitch.sh` AC1 (a
CI-portable stand-in for the live `kit-emit-sweep` rid -- see
`docs/implementation-notes/kit-emit-sweep.md` for the full, current version).

## 2026-07-04 08:00 the sweep's positive check had to be loosened from a strict regex to a loose substring

**Decision:** the sweep's "does this command emit" check is `grep -qi 'gate-ledger'` (any
mention, case-insensitive), not a stricter invocation-shape regex.

**Why:** the first draft used a stricter phrasing convention and Running it against the real
repo before trusting it surfaced a false negative.

**Impact:** the sweep is deliberately not a strict wiring-shape verifier.
