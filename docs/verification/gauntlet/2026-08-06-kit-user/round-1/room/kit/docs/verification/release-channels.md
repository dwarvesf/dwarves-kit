# Proof of done: two-channel release path (ID-437)

2026-07-25. Acceptance: one command prepares both channels; the paid channel is
key-gated with the lifecycle's grace semantics; negative controls hold.

## Green run

Command: `bin/release 2.0.1 --dry-run`
Exit: 0
Output: bumps VERSION+plugin.json+CHANGELOG (rolled v1.7.0..HEAD skeleton), builds
forge-stream-2.0.1.tar.gz (4186 bytes, sha256 c30516...), restores files, commits nothing.
Verdict: PASS

Command: staging round-trip (env-token proof script; statuses only, token never printed)
Exit: 0
Output: PUT /admin/release 200 (4188 bytes stored) - mint craft key 201 -
GET /stream/latest?key=... 200 v2.0.1 - bundle download 200, sha256 MATCH -
worker deploy version 71c93f3c, node --check clean.
Verdict: PASS

## NEGATIVE CONTROL (revert -> RED -> restore)

Command: GET /stream/latest with no key
Exit: HTTP 401 (RED as designed)
Verdict: PASS

Command: revoke the test key (the revert), then GET /stream/latest?key=...
Exit: HTTP 403 after revoke; was 200 before (RED on revert). Restore path exists:
POST /admin/licenses/(key)/restore returns the key to active.
Verdict: PASS

Command: `bin/release 1.0.0` (backward version guard)
Exit: 1 ("version must move forward: current 2.0.0, asked 1.0.0")
Verdict: PASS

## Reproduce

`bin/release <ver> --dry-run`; the staging proof script shape lives in the session
scratchpad (stream-proof.py: token via env, prints statuses only). Human release
steps (git push --tags, gh release) intentionally excluded per ID-295.

## Addendum (2026-07-25): public-repo guard + STREAM_SRC

The repo is PUBLIC; paid sources must never enter it (private dwarves-kit-stream repo
is created when the first paid module ships).

Command: `mkdir stream && bin/release 9.9.9 --dry-run`
Exit: 1, BEFORE any file mutation (guard moved above channel 1; tree stays clean)
Output: "REFUSED: stream/ exists inside this (public) repo..."
Verdict: PASS

NEGATIVE CONTROL is the guard itself (revert = create stream/ -> RED refuse -> restore
= remove it); the accept path:

Command: `STREAM_SRC=<private checkout> bin/release 2.0.2 --dry-run`
Exit: 0
Output: "paid sources from <path>", 4361-byte bundle with sha256.
Verdict: PASS
