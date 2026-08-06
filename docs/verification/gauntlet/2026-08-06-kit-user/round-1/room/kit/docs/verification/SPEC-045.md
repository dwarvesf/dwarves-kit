# Proof of done: SPEC-045 (gate resolves lib from the install path)

Class: behavioral. Verified 2026-06-08. The bug: the proof-of-done gate failed open in
every consumer repo. The fix: ship-gate resolves its lib from the kit's install path, and
install.sh deploys lib there.

## GREEN (real run)

Command: `bash tests/test-meta.sh`
Exit: 0
VERDICT: PASS
Output excerpt:

```
  PASS install.sh materializes lib/gate/proof-ledger.sh (SPEC-045)
Passed: 390 / 390
All meta tests passed.
```

## Primary flow: consumer-repo gate, end to end (the real repro)

Setup: `install.sh` into a throwaway `HOME` (deploys `lib/` to `$HOME/.claude/dwarves-kit/lib`), then a consumer-style git repo with `docs/verification/README.md` (opt-in) and a behavioral diff (`app.sh` logic change) on `feat/thing`. Drive the actual `hooks/ship-gate.sh` with a `git push` tool-input JSON.

```
A1  lib NOT reachable (empty HOME)   -> exit 0   FAIL OPEN   <- the bug (consumer unguarded)
A2  lib reachable via install        -> exit 2   BLOCKED     <- the fix
      "BLOCKED: proof of done. This is a 'behavioral' change; ...
       Type-specific shape (SPEC-044): run 'bash lib/gate/proof-gate.sh contract ...'"
B   proof-of-done entry added        -> exit 0   PASS
```

So a consumer repo is now actually gated (A2), the gate still names the type-specific
artifact (SPEC-044 message live), and a valid proof lets it through (B).

## NEGATIVE CONTROL (falsifiable)

Two independent controls, both recorded:
1. **A1 vs A2** above: with the lib unreachable the gate does NOT block (exit 0); with the
   fix's install-path lib it blocks (exit 2). The block is caused by the fix, not trivially.
2. `tests/test-meta.sh` pin `install.sh materializes lib/gate/proof-ledger.sh`: removing the
   install.sh lib-deploy block makes this assertion go RED.

VERDICT: PASS. Exit: 0 on the suite; the gate blocks exactly when it should.

## Reproducible

Re-run `bash tests/test-meta.sh` (Exit 0). Re-run the A1/A2/B sequence (install into a temp
HOME, consumer repo with README + a behavioral diff, invoke `hooks/ship-gate.sh` with a
`git push` JSON) to reproduce fail-open -> block -> pass.
