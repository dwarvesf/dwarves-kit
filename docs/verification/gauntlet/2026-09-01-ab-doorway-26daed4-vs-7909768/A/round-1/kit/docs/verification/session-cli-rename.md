# Proof of done: session CLIs adopt kit naming (drop cc-/CC_)

Change under proof: the five session callables and their env knobs finally follow
the kit naming invariant (function-named, never host-agent-prefixed), closing the
inconsistency the 07-05 kit-foldin left (dirs were renamed, callables were not):

| Old | New |
|---|---|
| `cc-intel` | `session-intel` |
| `cc-observe` | `session-observe` |
| `cc-semantic` | `session-semantic` |
| `cc-vps-report` | `session-report` |
| `cc-recall` (+ `cc_recall.py`) | `session-recall` (+ `session_recall.py`) |
| `CC_INTEL_*`, `CC_SEMANTIC_*`, `CC_VPS_*` | `SESSION_INTEL_*`, `SESSION_SEMANTIC_*`, `SESSION_REPORT_*` |

Clean cut, no alias shims (the installer owns every exposure point). Historical
records (docs/, proof-of-done, implementation-notes) keep the old names; the three
live SPEC/README records carry a rename note. Consumer counterparts (the vps-mon
bridge, the cc-observe skill body) update on the ops side.

## Confirmation run-table

```
Command: bash lib/session/tests/test-parse-transcript.sh
Exit:    0  (7/7)
Command: bash lib/session/observe/tests/smoke.sh
Exit:    0  (40/40)
Command: bash lib/session/observe/tests/test-vps-report.sh
Exit:    0  (6/6)
Command: bash lib/session/intel/tests/smoke.sh
Exit:    0  (8/8)
Command: python3 lib/session/recall/tests/test_recall.py
Exit:    0  (OK)
Command: bash tests/test-install-clis.sh
Exit:    0  (28/28)
Command: bash tests/test-meta.sh && bash tests/test-hooks.sh && bash tests/test-install-modules.sh
Exit:    0  (all green: meta, hooks 453, modules 37)
Verdict: PASS
```

## Negative control

Old names are GONE from every live surface:
`rg "cc-intel|cc-observe|cc-semantic|cc-recall|cc-vps-report|CC_INTEL|CC_VPS|CC_SEMANTIC" lib/session/*/bin lib/session/session.sh bin/ install.sh tests/test-install-clis.sh`
-> zero hits (records under docs/ keep them as history). A fresh-HOME install
exposes only the new names; `~/.local/bin/cc-intel` is not written.

## Rollback

`git revert` restores the old names in one commit (pure renames + string
substitutions, no logic change). Consumer shims re-point on the next
`install.sh` run either way.
