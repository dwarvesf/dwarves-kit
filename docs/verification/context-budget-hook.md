# Proof of Done: context-budget hook (SPEC-255)

**Feature:** a UserPromptSubmit hook in the opt-in `session` module. Once a session's live context passes `CC_CTX_WARN` (200000), it warns once per `CC_CTX_STEP` (100000) band, to the user through `systemMessage` and to the model through `additionalContext`.
**Date:** 2026-09-10 · **Lane:** normal · **Spec:** `docs/specs/SPEC-255-context-budget-hook.md`

## Acceptance criteria

| # | Criterion |
|---|---|
| C1 | Context = input + cache_creation + cache_read of the last main-chain assistant turn |
| C2 | First warning at the budget, then one per band, never twice in a band |
| C3 | A drop below the budget clears the state, so the next crossing warns again |
| C4 | Subagent sidechain usage never sets the number |
| C5 | Thresholds come from `CC_CTX_WARN` and `CC_CTX_STEP` |
| C6 | Fail-open: a missing, unreadable or unparseable transcript exits 0 and prints nothing |
| C7 | Wired on both install paths (plugin `hooks.json`, bash `settings.json`) and in the `session` module list |
| C8 | Bash and jq only, per the Bash-over-binaries rule |

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Hook suite (C1-C6) | `bash tests/test-context-budget.sh` | `Results: 13 passed, 0 failed` | PASS |
| Hook wiring suite | `bash tests/test-hooks.sh` | all pass | PASS, 498 / 498 |
| Module wiring (C7) | `bash tests/test-install-modules.sh` | all pass | PASS, 42 / 42 |
| Lint (C8) | `shellcheck --severity=warning hooks/context-budget.sh` | clean | PASS |
| Registry + meta | `bash tests/test-meta.sh` | `All meta tests passed.` | PASS, 843 / 843 |
| Real transcript | hook against a live 2MB+ transcript, temp HOME | one warning, fast | PASS, `at 330k tokens`, 0.36s |

## Negative control

The sidechain filter and the band check were removed from the hook in a committed tree. The suite returned `10 passed, 3 failed`: the two same-band cases started nagging and the 900k sidechain case set the number. `git checkout` restored the hook and the suite returned `13 passed, 0 failed`.

## Provenance

Ported from a personal dotfiles hook that shipped 2026-09-10 with its own 13-case suite. The kit copy names no operator in its messages. The trigger was measured: several parallel sessions at 300k to 420k context made up most of one hour's token spend, while the statusline showed the number per pane and nobody watched it.

## Reproduce

```bash
bash tests/test-context-budget.sh     # -> Results: 13 passed, 0 failed
bash install.sh --with session        # wires the hook on the bash path
```
