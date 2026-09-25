# Proof of Done: context-budget hook (SPEC-255)

**Feature:** a UserPromptSubmit hook in the opt-in `session` module. Once a session's live context passes `KIT_CTX_WARN` (200000), it warns once per `KIT_CTX_STEP` (100000) band, to the user through `systemMessage` and to the model through `additionalContext`.
**Date:** 2026-09-10 · **Lane:** normal · **Spec:** `docs/specs/SPEC-255-context-budget-hook.md`

## Acceptance criteria

| # | Criterion |
|---|---|
| C1 | Context = input + cache_creation + cache_read of the last main-chain assistant turn |
| C2 | First warning at the budget, then one per band, never twice in a band |
| C3 | A drop below the budget clears the state, so the next crossing warns again |
| C4 | Subagent sidechain usage never sets the number |
| C5 | Thresholds come from `KIT_CTX_WARN` and `KIT_CTX_STEP` |
| C6 | Fail-open: a missing, unreadable or unparseable transcript exits 0 and prints nothing |
| C7 | Wired on both install paths (plugin `hooks.json`, bash `settings.json`) and in the `session` module list |
| C8 | Bash and jq only, per the Bash-over-binaries rule |

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Hook suite (C1-C6, C9) | `bash tests/test-context-budget.sh` | `Results: 22 passed, 0 failed` | PASS |
| Hook wiring suite | `bash tests/test-hooks.sh` | all pass | PASS, 498 / 498 |
| Module wiring (C7) | `bash tests/test-install-modules.sh` | all pass | PASS, 42 / 42 |
| Lint (C8) | `shellcheck --severity=warning hooks/context-budget.sh` | clean | PASS |
| Registry + meta | `bash tests/test-meta.sh` | `All meta tests passed.` | PASS, 854 / 854 |
| Real transcript | hook against a live 2MB+ transcript, temp HOME | one warning, fast | PASS, `at 330k tokens`, 0.36s |

### C9: 1M window detection reads the identity attachment, not just `.message.model`

A live 2.8MB session transcript surfaced this: `.message.model` on every assistant
turn is the bare model id (`claude-opus-5-5`), never the `[1m]` marker. That marker
sits only on an earlier `{"type":"attachment","attachment":{"type":"model","identity":{"modelId":"...[1m]",...}}}`
line, which the `tail -c 2000000` window used for the context-size read could miss
entirely on a transcript bigger than 2MB. The hook fell back silently to a 200k
window and warned "65%"/"CONTEXT CEILING 85%" on a session that was really at
13%/17% of its true 1M window.

Fix: scan the whole transcript for the latest `modelId` identity marker (case-insensitive
`1m` check) before falling back to `.message.model`; add a guard that live context
already past 200000 tokens cannot be a 200k-window model. `KIT_CTX_WINDOW` still
overrides both. Added cases 9.1-9.3 (bare model + `[1m]` identity at 130k -> silent;
bare model, no identity, 130k -> speaks; bare model, no identity, 250k -> guard
treats it as 1M -> silent) to `tests/test-context-budget.sh`; both 9.1 and 9.3
failed against the pre-fix code (`speak` instead of `silent`).

## Negative control

**C1-C8 (existing):** the sidechain filter and the band check were removed from the hook in a committed tree. The suite returned `10 passed, 3 failed`: the two same-band cases started nagging and the 900k sidechain case set the number. `git checkout` restored the hook and the suite returned `13 passed, 0 failed`.

**C9 (this fix), via `lib/gate/negctl.sh`:** mutated the identity scan so it never sets `IDENTITY_MODEL` (`IDENTITY_MODEL=$(false && grep ...)`). Suite went RED (`Exit: 1`). Restore via `git checkout HEAD --` returned it GREEN. `Verdict: PASS`.

## Provenance

Ported from a personal dotfiles hook that shipped 2026-09-10 with its own 13-case suite. The kit copy names no operator in its messages. The trigger was measured: several parallel sessions at 300k to 420k context made up most of one hour's token spend, while the statusline showed the number per pane and nobody watched it. The C9 fix traces to a live 1M-context session that warned at the wrong percentage because the `[1m]` marker lives on a transcript attachment, not `.message.model`.

## Reproduce

```bash
bash tests/test-context-budget.sh     # -> Results: 22 passed, 0 failed
bash install.sh --with session        # wires the hook on the bash path
```
