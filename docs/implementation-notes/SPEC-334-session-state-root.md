# Implementation notes: session-state-root (SPEC-334)

Delta from the spec only.

| Kind | Note |
|---|---|
| Decision | Validator warning W5 asked for a test of the `git -C "$REAL_CWD"` branch. Added it as case 6c and folded it into TASK-E2 with 6a/6b/7, so E2 carries four cases, not three. NC3's grep widened to `(relative cd resolves\|payload cwd resolves root)` so the mutation must redden 6c as well. |
| Decision | Validator warning W6 split TASK-E into E1 and E2, which collided with the existing TASK-E2 (docs projection). The docs task is renamed TASK-E3; TASK-F now reads "TASK-B through TASK-E3". |
| Decision | `tests/test-hook-anchor.sh` also fails when an EXEMPT entry is wrapped (`exempt-but-wrapped:`), with its own fixture. The spec's After state says secrets-guard stays unanchored in both tables; the lint now pins that direction too, not only "every non-exempt entry is wrapped". |
| Decision | Case 7 substitutes the plugin-root and `$HOME/.claude/dwarves-kit` prefixes textually and runs with `CLAUDE_PLUGIN_ROOT` unset, so hooks that look up kit libs through either variable fail open against the temp HOME instead of reaching the real kit or ledger. |
| Decision | Case 6b runs under `env -u DWARVES_KIT_INVOCATION_CWD` so a value inherited from an outer anchored process can never satisfy the assertion; only the wrapper's own export can. |
| Verified (unscoped) | Case 7 is falsifiable: with `hooks/anchor-root.sh` chmod -x, every hooks.json entry reports `[126]` and the case goes red. The settings.json half cannot catch that mutation (its outer `bash` reads the wrapper without the exec bit); it catches a non-executable INNER hook instead. Not added as a negative control; the spec names three. |
| Deviation | The ship-gate fix is five added lines plus one changed line, not the "three-line" fix the spec text names (the three-tier fallback alone is three lines, plus the CDDIR join and the `git -C` change). Same logic as the spec's code block. |
| Missed constraint | `tests/test-config-registry.sh` lints every `DWARVES_KIT_*` env read under `lib/`, `hooks/`, `bin/` against `lib/config/module-registry.md`. The new `DWARVES_KIT_INVOCATION_CWD` was an orphan until a `gate` row was added there. The spec's Touches list did not name the registry. |
| Pre-existing | `tests/test-meta.sh` takes about 6 minutes alone on this Mac, past `run-all.sh`'s 300s default ceiling, so it TIMES OUT under a default run. It passes in full when run alone or with `RUN_ALL_TIMEOUT_SECS` raised. |
| Pre-existing | `tests/test-no-scattered-ids.sh` fails on clean `origin/master` (`afb52d01`) with the same 2 hits in `lib/gate/proof-ledger.sh:293,415`. This branch does not touch that file. |
