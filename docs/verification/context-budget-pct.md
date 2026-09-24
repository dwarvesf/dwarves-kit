# Proof of Done: context-budget hook, percentage rewrite (SPEC-255)

**Feature:** the `context-budget.sh` UserPromptSubmit hook now warns on a percentage of the model's context window instead of a raw token count. `KIT_CTX_WARN`/`KIT_CTX_STEP` (absolute tokens, repeating bands) are replaced by `KIT_CTX_WARN_PCT` (default 65, advisory) and `KIT_CTX_STRONG_PCT` (default 70, directive), each firing once per session. The window defaults to 200000, auto-bumps to 1000000 for a model id carrying a `1m` marker, and `KIT_CTX_WINDOW` overrides either.
**Date:** 2026-09-25 · **Lane:** normal · **Spec:** `docs/specs/SPEC-255-context-budget-hook.md`

## Acceptance criteria

| # | Criterion |
|---|---|
| C1 | Context = input + cache_creation + cache_read of the last main-chain (non-sidechain) assistant turn |
| C2 | Silent under 65% of the window |
| C3 | Fires once (advisory) on crossing 65%, stays silent on a second prompt at the same threshold |
| C4 | Fires once more (directive) on crossing 70%, stays silent on a second prompt at the same threshold |
| C5 | A drop below the 65% threshold clears the state, so the next crossing warns again |
| C6 | Subagent sidechain usage never sets the number |
| C7 | Window comes from the last turn's model id (a `1m` marker bumps to 1,000,000), or `KIT_CTX_WINDOW` overrides it outright |
| C8 | Thresholds come from `KIT_CTX_WARN_PCT` and `KIT_CTX_STRONG_PCT` |
| C9 | Fail-open: a missing, unreadable, or unparseable transcript exits 0 and prints nothing |
| C10 | Bash and jq only, per the Bash-over-binaries rule |

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Hook suite (C1-C9) | `bash tests/test-context-budget.sh` | `Results: 19 passed, 0 failed` | PASS |
| Hook wiring suite | `bash tests/test-hooks.sh` | all pass | PASS, 491 / 491 |
| Module wiring | `bash tests/test-install-modules.sh` | all pass | PASS, 42 / 42 |
| Lint (C10) | `shellcheck --severity=warning hooks/context-budget.sh` | clean | PASS |
| Registry + meta | `bash tests/test-meta.sh` | `All meta tests passed.` | PASS, 854 / 854 |

## Fixture matrix (50 / 66 / 71 percent, default 200k window)

| Fixture | Tokens | Percent | First call | Second call (same threshold) |
|---|---|---|---|---|
| 50% | 100000 | 50 | silent | - |
| 66% | 132000 | 66 | speaks (advisory, `CONTEXT BUDGET`) | silent |
| 71% | 142000 | 71 | speaks (directive, `CONTEXT CEILING`) | silent |

## Negative control

The threshold comparison was broken in a committed tree (`if [ "$CTX100" -lt ... ]` reverted to compare the raw `$CTX` against `$(( WARN_PCT * WINDOW ))` instead of `$(( CTX * 100 ))`, so the crossing math no longer matched the fixtures). The suite returned `9 passed, 10 failed`: cases 1.2, 1.4, 2.2, 4.1, 6.1, 7.1, 7.3, 7.4, 8.1, and 8.2 all failed to speak or tone correctly. The file was restored (byte-identical to the committed version) and the suite returned `19 passed, 0 failed` again.

## Provenance

Percentage rewrite of the hook this repo already ships (ported 2026-09-10 from the operator's dotfiles, tested 13-case suite). The operator's dotfiles copy had set `KIT_CTX_WARN`/`KIT_CTX_STEP` past any real context to silence it (2026-09-24), leaving the per-prompt session-age nudge in `context-hints.sh` as the only mid-session cache-hygiene signal, which fires on wall-clock elapsed time, not on how full the context actually is. This rewrite restores a context-size-based signal, expressed as a percentage of window so it holds across models with different window sizes, and the operator's dotfiles override is being removed in the same round so the hook is live again by default.

## Reproduce

```bash
bash tests/test-context-budget.sh     # -> Results: 19 passed, 0 failed
bash install.sh --with session        # wires the hook on the bash path
```
