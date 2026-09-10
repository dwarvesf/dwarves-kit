# Spec: context-budget hook, warn on live context past budget

Generated: 2026-09-10
Status: VALIDATED
Lane: normal (classifier said full; chosen normal, same de-escalation precedent as SPEC-254: porting a tested, shipped operator hook into an existing module, no new subsystem, no schema change)
References: the operator's personal dotfiles hook `home/dot_claude/hooks/context-budget/executable_context-budget.sh` (tieubao/dotfiles) + its 13-case test suite `tests/context-budget.sh`; `docs/architecture.md` "Hook fallback layer"; `hooks/context-hints.sh` (sibling UserPromptSubmit hook, header-comment convention).

**Scope:** one new hook file in the existing `session` module, wired into `hooks/hooks.json` + `settings.json` + `install.sh`. No new module, no new CLI, no new dependency.

## Problem

Every turn in a Claude Code session re-reads the whole context from cache. Parallel sessions sitting at 300k to 420k context burned most of an hour's spend, and the statusline shows the number but nobody watches it across panes. The operator already carries a tested personal hook that solves this in dotfiles; it never reaches anyone who installs the kit without also installing the operator's dotfiles.

## Solution

### Approaches considered

1. **Port the hook verbatim into `hooks/context-budget.sh`, wired into the `session` module** (chosen). The logic is already tested (13 cases); the module already exists and already owns session-lifecycle hooks (`context-readiness`, `session-state-save`, `harvest`).
2. **A new `context` module.** Rejected: one hook does not justify a new opt-in module category; `session` already owns "state about the running session".
3. **Fold into `context-hints.sh`.** Rejected: different event purpose (context-hints is temporal + keyword skill-hint injection, python-backed with an explicit "coexists, not merged" note against the SessionStart `context-readiness` hook); mixing a budget alarm into it would violate "each hook does one thing, described in one sentence" (PHILOSOPHY NO-list).

### Chosen approach + why

Copy the dotfiles hook's logic unchanged (band math, state file, fail-open contract) into `hooks/context-budget.sh`, strip the operator's name from the model-facing message (kit ships to any adopter, never assumes who is reading), and wire it as a fourth `UserPromptSubmit` entry alongside `context-hints` and `prose-rag`. Classified `advisory` in the Hook fallback layer table: it never blocks, only nudges via `systemMessage` + `additionalContext`, so a human or the model can act at the next boundary.

## Picture

```
UserPromptSubmit event
  { session_id, transcript_path }
        |
        v
context-budget.sh
  read transcript tail (2MB)
  -> last main-chain (isSidechain != true) assistant usage
  -> ctx = input + cache_creation + cache_read
        |
   ctx < CC_CTX_WARN (200k)?  --yes--> clear state, exit 0 (silent)
        | no
   band = (ctx - WARN) / CC_CTX_STEP (100k)
   band > last-warned-band (~/.cache/claude-context-budget/<session_id>)?
        | no --> exit 0 (silent, already warned this band)
        | yes
   write band to state file
   emit {systemMessage, hookSpecificOutput.additionalContext}
```

## Technical Design

### Interfaces (I/O contract)

- Event: `UserPromptSubmit`. Stdin: the standard hook payload (`session_id`, `transcript_path`, `prompt`).
- Env knobs: `CC_CTX_WARN` (default 200000, first warning threshold) and `CC_CTX_STEP` (default 100000, band width for repeat warnings). Non-numeric or a non-positive `CC_CTX_STEP` disables the hook for that invocation (fail-open).
- State: `~/.cache/claude-context-budget/<session_id>`, one line holding the last-warned band index (an integer, or absent). Removed when context drops back under `CC_CTX_WARN`.
- Output on warn: `{"systemMessage": "<operator-facing text>", "hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": "<model-facing text>"}}`. No output (empty stdout) when silent. Exit code is always 0.
- Context computation: the LAST JSONL line in the transcript tail (2MB) whose `type == "assistant"` and `isSidechain != true` and carries `message.usage`; `ctx = input_tokens + cache_creation_input_tokens + cache_read_input_tokens` (missing fields treated as 0).

### Data model changes

None. State is a single-line file per session under `~/.cache/`, not tracked by the kit.

### API / UI / Infrastructure changes

- `hooks/hooks.json`: new `UserPromptSubmit` entry, `${CLAUDE_PLUGIN_ROOT}/hooks/context-budget.sh`, timeout 5s.
- `settings.json`: same event, `bash $HOME/.claude/dwarves-kit/hooks/context-budget.sh`, timeout 5s (parity with hooks.json is a standing test-meta assertion).
- `install.sh`: `context-budget.sh` appended to the `session` module's hook list (`kit_module_hooks session`), so `--with session` wires it and a spine-only or non-session install never sees it.
- Docs: README.md Hooks table + `session` module row, `docs/architecture.md` Hook fallback layer table (class: advisory).

## Task Breakdown

### Phase 1

- TASK-001: `hooks/context-budget.sh` (ported logic, operator name stripped, header-comment convention for `feature-registry.sh`).
- TASK-002: wire into `hooks/hooks.json`, `settings.json`, `install.sh` session module list, `tests/test-install-modules.sh` session HOOKS list + UNWANTED negative-control list.
- TASK-003: `tests/test-context-budget.sh`, the 13-case dotfiles suite ported to the kit's hermetic-HOME test style (auto-discovered by `tests/run-all.sh`'s `test-*.sh` glob).
- TASK-004: docs, README.md + docs/architecture.md rows, implementation notes, changelog, `docs/FEATURES.md` regeneration.

## Verification

Run `bash tests/test-context-budget.sh`. All 13 cases pass:

1. Under budget (150k) stays silent.
2. Crossing 200k speaks once.
3. Staying in the same band (290k) stays silent (no nag).
4. Crossing into the next band (310k) speaks again.
5. Staying in that band (320k) stays silent.
6. Dropping to 90k (e.g. after `/compact`) clears state, stays silent.
7. Re-crossing 200k after the drop speaks again (state was cleared).
8. Sidechain-only usage (main chain 50k, sidechain 900k) stays silent: sidechain is excluded from `ctx`.
9. A second session (`s4`) at 250k warns independently of `s1`'s state (per-session state file).
10. A missing transcript path stays silent (fail-open).
11. An unparseable transcript stays silent (fail-open).
12. A transcript with no assistant turn yet stays silent.
13. `CC_CTX_WARN` overridden via env (100000) warns at 120k, below the hardcoded default.

Negative control: revert the sidechain filter (`isSidechain != true` -> drop the clause) and the band-comparison guard (`$BAND -gt $LAST` -> always true) in a committed tree; cases 3, 5, and 8 must fail; restore and confirm green again.

Real-transcript smoke: run the hook against the largest transcript under `~/.claude/projects` touched in the last hour, with `HOME` pointed at a throwaway temp dir (so the state file never touches real `~/.cache`), and report the `systemMessage` (or "silent, under budget") plus wall time.

Also run `bash tests/test-hooks.sh` (unaffected, regression check) and `bash tests/test-meta.sh` (hook-count parity, README/architecture row-count parity, executability, install materialization).

## After state

- Any adopter running `install.sh --with session` gets the context-budget warning without needing the operator's personal dotfiles.
- `docs/architecture.md` and `README.md` carry the hook in the standard inventory, parity-pinned by `tests/test-meta.sh`.
- The dotfiles copy stays the tested reference; nothing in dotfiles changes.
