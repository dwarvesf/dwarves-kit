# Implementation notes: ship-gate fail-closed (sub-goal 02 of kit-adopt-enforce)

Spec: SPEC-048. Branch: `feat/kit-adopt-02-gate` off master (post-#22-merge). Built through the
full lane via the lib machinery (cross-repo session; see sub-goal 01 notes for why not /kit:*).

## 2026-06-09, the precise gap + the surgical fix

- Context: the sub-goal framed "ship-gate lane arm fails open on no lane". Reading the code, the
  lane arm (lines 57-78) ALREADY fails closed when a spec has a `Lane:` and gates are missing. The
  real fail-open is **line 61**: a spec exists for the slug but has no `Lane:` header -> `exit 0`.
- Decision: flip ONLY that branch, and only in an adopted repo (proof marker present). So:
  spec-exists + no-Lane + `docs/verification/README.md` present -> BLOCK (exit 2) with a message
  to add a lane; everywhere else stays fail-open. This is the minimal change matching the spec's
  "spec-exists-no-lane" wording without touching the proof arm or the lane-check path.
- Why marker-gated: the quality bar is "fail closed only where safe and intentional". The marker
  is the kit's existing opt-in signal; a non-adopted repo must never be blocked.
- install.sh: replaced the manual `cp $KIT_DIR/AGENTS.md ./AGENTS.md` tip with the
  `bash $KIT_DIR/lib/adopt.sh <repo>` path (the /kit:adopt command from sub-goal 01).
- Lane: lane-classify returned `full` directly this time (the change touches `hooks/`), no
  override needed (contrast sub-goal 01).
- Verification: `tests/test-ship-gate-fail-closed.sh` 5/5 (blocked case + 3 fail-open cases +
  the lane+gates pass case); `tests/test-meta.sh` 392/392.

## Dogfood tie-in

This is the fix for the exact gap the loop hit on its own turn-1 of sub-goal 01: a `review` gate
silently un-recorded, and the fail-open ship-gate let the push through. With this change, in an
adopted repo a spec without a declared lane can no longer ship lane-less.
