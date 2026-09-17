# SPEC-295: the auth hard-gate regex stops matching the bare word "session"

**Status:** BUILT (the regex and its fixtures land in this PR; this spec records the contract)
Lane: full
**Board:** ID-906. **Proof:** `tests/test-lane-classify.sh`, the SPEC-295 block.

## Problem

`lib/classify/lane-classify.sh` escalates any task to `full` when its auth hard-gate regex hits. That regex carried `\bsession(s)?\b`, so every task that mentions a Claude session, a wrap session, or a handoff session went `full`. Two report-prose edits to `commands/wrap.md` hit it on 2026-09-17 and were hand-routed to `tiny` with the misclassification noted.

## Contract

- The auth entry matches `sessions? (token|cookie|id|hijack|fixation|store|management|expiry)` and `(login|auth|user) sessions?`, in place of the bare word.
- Every other alternative in the auth entry is unchanged: `auth[a-z]*`, `login`, `logout`, `password`, `jwt`, `refresh token`, `permission`, `role(s)`, `tenant`.
- A task about session tokens, session hijacking, or login sessions still classifies `full` with reason `auth`.
- A task that mentions the session in the wrap or handoff sense classifies by its remaining flags.

## Verification

`bash tests/test-lane-classify.sh` runs the SPEC-295 block: the two recorded misfire strings and their `--files commands/wrap.md` form classify `normal`; `rotate the session token on login`, `fix session hijacking in the cookie store`, and `expire login sessions after an hour` classify `full`. Negative control: restore the old alternative and the first three fixtures fail with `full`.

## Out of scope

No new flag, lane, or config key. The `docs(...)` prefix and markdown-only anchors are not touched; the misfire strings land `normal`, not `tiny`, and that is the classifier's existing default for a bounded change.
