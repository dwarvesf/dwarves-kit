# Proof of Done: plugin-check

**Feature:** read-only freshness lens over installed Claude Code plugins (which are outdated, and the exact bump command).
**Date:** 2026-07-14 (packaged; the suite predates this and rode in with the kit-foldin migration, 2026-07-05) · **Lane:** normal · **Host:** Hans-Air-M4 (macOS 26.5) · **Spec:** `docs/specs/SPEC-105-cc-plugin-check.md`

Written to close a real gap the SPEC-200 contract lint found: the tool shipped with a
27-assertion suite and no proof-of-done, so the kit's own done-gate had nothing to read.
The evidence existed; the artifact did not.

## Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| A1 | Detects a stale plugin (installed sha != upstream sha) across all three marketplace shapes: single-plugin, local `directory`, multi-plugin (`claude-plugins-official`) | SPEC-105 |
| A2 | Reports a current plugin as current (no false "outdated") | NEGATIVE CONTROL |
| A3 | Read-only: never mutates installed plugin state | SPEC-105 |
| A4 | Prints the exact bump command per stale plugin | SPEC-105 |
| A5 | Degrades on missing/malformed catalog files rather than crashing | robustness |
| A6 | Reachable from the operator surface (`bin/plugin-check`) | SPEC-200 C2 |

## Implementation

| Piece | What | Where |
|---|---|---|
| Verdict logic | installed `gitCommitSha` vs catalog `source_sha` per marketplace shape | `bin/plugin-check` |
| Sources | `$CC_PLUGINS_DIR/installed_plugins.json`, `plugin-catalog-cache.json` (host-provided path; the kit reads it, does not own its name) | same |
| Operator entry | stable `bin/plugin-check` shim | `bin/plugin-check` (added 2026-07-14) |
| Tests | 27 assertions over fixtures for all three marketplace shapes + degrade cases | `tests/smoke.sh` |

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Full suite (A1-A5) | `bash lib/plugin-check/tests/smoke.sh` | `smoke: all 27 passed` | PASS |
| Operator entry (A6) | `bash bin/plugin-check --help` | usage banner | PASS |
| Contract lint (A6) | `bash tests/test-kit-contract.sh` | C2 wiring green | PASS |

## Run detail

```
$ bash lib/plugin-check/tests/smoke.sh | tail -1
smoke: all 27 passed
Exit: 0

$ bash bin/plugin-check --help | head -1
plugin-check , which adopted Claude Code plugins are outdated, in one glance.
Exit: 0
```

## Reproduce

```bash
cd <dwarves-kit>
bash lib/plugin-check/tests/smoke.sh
bash bin/plugin-check --help
```
