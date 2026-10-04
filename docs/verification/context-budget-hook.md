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
| Hook suite (C1-C6, C9) | `bash tests/test-context-budget.sh` | `Results: 24 passed, 0 failed` | PASS |
| Hook wiring suite | `bash tests/test-hooks.sh` | all pass | PASS, 498 / 498 |
| Module wiring (C7) | `bash tests/test-install-modules.sh` | all pass | PASS, 42 / 42 |
| Lint (C8) | `shellcheck --severity=warning hooks/context-budget.sh` | clean | PASS |
| Registry + meta | `bash tests/test-meta.sh` | `All meta tests passed.` | PASS, 854 / 854 |
| Real transcript | hook against a live 2MB+ transcript, temp HOME | one warning, fast | PASS, `at 330k tokens`, 0.36s |

### C9: the `1m`-window check needed three inputs, not one, plus one guard

`.message.model` alone (the original check) misses the "1m" marker on every path
Claude Code actually uses to pick a 1M window. Three fixes landed together:

- **#761** (`655858a`, merged to master first): the transcript records the bare
  API model id (`claude-opus-5-5`), which drops the `[1m]` suffix Claude Code
  used to pick the window. #761 added a second input, the *configured* model
  (`ANTHROPIC_MODEL`, then `.claude/settings.local.json` / `settings.json` at
  the request's `cwd`, then `~/.claude/settings.json`), plus the guard: live
  context already past 200000 tokens cannot be a 200k-window model. Tests
  7.5-7.7. Live probe on a 173k `opus[1m]` session: old hook 86%, fixed hook
  silent.
- **This branch** (pre-merge): a live 2.8MB session transcript surfaced a case
  #761 doesn't cover: no `ANTHROPIC_MODEL`, no `.model` in any settings file
  (model picked via `/model` mid-session), so #761 alone still warned "95% of
  its window (191k tokens)" on a real 1M session (191k is under #761's >200k
  guard). The real marker sits only on an earlier
  `{"type":"attachment","attachment":{"type":"model","identity":{"modelId":"...[1m]",...}}}`
  line -- which the `tail -c 2000000` window used for the context-size read
  can miss entirely once the transcript passes ~2MB, since that marker is
  typically written once, early, near session start. Added a third input: scan
  the whole transcript for the latest `modelId` identity marker. Cases
  9.1-9.2 (bare model + `[1m]` identity at 130k -> silent; bare model, no
  identity, 130k -> speaks); both failed against pre-fix code (`speak` instead
  of `silent`). Case 9.3 (bare model, no identity, 250k, guard forces 1M) was
  dropped as a duplicate of #761's 7.7.
- **Merge:** one case-insensitive `1m` match now runs across all three inputs
  (`.message.model`, the configured model, the transcript identity marker), and
  there is exactly one `>200000` guard (#761's). `KIT_CTX_WINDOW` still
  overrides all of it.

Re-verified live: firing the merged hook against the same 2.8MB transcript
(fresh `HOME`, `cwd` set in the input JSON, `ANTHROPIC_MODEL` unset, no
`.model` in any settings file) is silent, exit 0 -- the case #761 alone still
missed.

## Negative control

**C1-C8 (existing):** the sidechain filter and the band check were removed from the hook in a committed tree. The suite returned `10 passed, 3 failed`: the two same-band cases started nagging and the 900k sidechain case set the number. `git checkout` restored the hook and the suite returned `13 passed, 0 failed`.

**C9 (this fix + #761, merged), via `lib/gate/negctl.sh`:** mutated the identity scan so it never sets `IDENTITY_MODEL` (`IDENTITY_MODEL=$(false && grep ...)`). Suite went RED (`Exit: 1`). Restore via `git checkout HEAD --` returned it GREEN. `Verdict: PASS`. Re-ran after the merge with master to confirm the combined hook still holds the same negative control.

## Provenance

Ported from a personal dotfiles hook that shipped 2026-09-10 with its own 13-case suite. The kit copy names no operator in its messages. The trigger was measured: several parallel sessions at 300k to 420k context made up most of one hour's token spend, while the statusline showed the number per pane and nobody watched it. The C9 fix is two sessions' work merged together: #761 added the configured-model input and the `>200k` guard; this branch added the transcript identity-attachment input, needed because neither `.message.model` nor a configured model exists when the model was picked with `/model` mid-session and live context stays under #761's guard.

## Reproduce

```bash
bash tests/test-context-budget.sh     # -> Results: 24 passed, 0 failed
bash install.sh --with session        # wires the hook on the bash path
```
