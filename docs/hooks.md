# Hooks: which hook prints which message

One row per hook wired in `hooks/hooks.json` and `settings.json`. Find the hook behind a message you see, the knobs that tune it, and its source file.

Searching the installed kit with plain `rg` or `fd` finds nothing, because every entry under `~/.claude/dwarves-kit` is a symlink. Follow links, or name the `hooks` directory as the search root:

```
rg -L "Context ceiling" ~/.claude/dwarves-kit
rg "Context ceiling" ~/.claude/dwarves-kit/hooks
```

The plugin `hooks.json` runs every hook except secrets-guard through `hooks/anchor-root.sh`, which changes to the repo root first.

Two env vars apply to groups of hooks, not all of them:

- `DWARVES_KIT_DEBUG=1` prints a `[dwarves-kit:<name>]` trace line to stderr. These hooks honor it: anti-rationalization, auto-format, codebase-index, context-readiness, permission-auto-approve, safety-gate, session-state-save, slop-cleaner, spec-drift-guard.
- `DWARVES_KIT_LOG_DIR` moves the log directory (default `~/.claude/dwarves-kit/logs`). These hooks honor it: anti-rationalization, board-row-gate, commit-format, safety-gate, secrets-guard, ship-gate, slop-cleaner, spec-drift-guard.

A `[gate]` key in the committed project kit config switches a gate off. `lib/gate/gate-policy.sh` reads it. See `lib/gate/README.md`.

## Hook table

Module is the `install.sh --with` group that enables the hook. Spine hooks always install.

| Hook | Event (matcher) | Message prefix it prints | Env knobs and config | Module | Source |
|---|---|---|---|---|---|
| safety-gate | PreToolUse (Bash) | `BLOCKED:` plus a reason such as "Destructive delete detected", "Do not push directly to main/master", "Force push is dangerous", "'git reset --hard' discards uncommitted work". Exits 2. | none beyond the globals | spine | `hooks/safety-gate.sh` |
| ship-gate | PreToolUse (Bash) | `BLOCKED: ship-gate.` (missing lane gates), `BLOCKED: doc-projection drift.`, `BLOCKED: registry freshness.`, plus `[advisory]` lines on stderr. Exits 2 on a block. | `DWARVES_KIT_SKIP_DOC_PROJECTION=1`, `DWARVES_KIT_SKIP_REGISTRY_FRESHNESS=1`; config `lane_gates`, `proof_of_done` | spine | `hooks/ship-gate.sh` |
| spec-drift-guard | PreToolUse (Write) | `[dwarves-kit] '<file>' is not in any active spec`. Context only, never blocks. | none | spine | `hooks/spec-drift-guard.sh` |
| secrets-guard | PreToolUse (Read\|Edit\|Bash) | `secrets-guard:` plus "targets a secret file" or "appears to read a secret file". Exits 2. | none | spine | `hooks/secrets-guard.sh` |
| commit-format | PreToolUse (Bash) | `commit-format:` plus the failed rule (length over 72, spec marker, not a Conventional Commit). Exits 2. | config `commit_format` | spine | `hooks/commit-format.sh` |
| anti-rationalization | Stop | `Rationalization detected:`, `Guess-fix detected during an open debug session`, `Completion claimed but the diff still adds an unimplemented stub`. Exits 2. | config `understanding_gate` | spine | `hooks/anti-rationalization.sh` |
| board-row-gate | PreToolUse (Bash) | `BLOCKED: board-row-gate.` when a commit adds a board row with no `board-row-ok:` line. Exits 2. | `DWARVES_KIT_SKIP_BOARD_ROW_GATE=1`; config `board_row_gate` | board | `hooks/board-row-gate.sh` |
| backlog-stage | SessionEnd | `backlog-stage: fired detached` on stderr. A no-op unless enabled. | `BACKLOG_STAGE_AUTO=1` (opt-in), `BACKLOG_STAGE_STAGING`, `BACKLOG_STAGE_BACKLOG`, `BACKLOG_STAGE_MIN_INTERVAL`, `BACKLOG_STAGE_MAXCHARS`, `BACKLOG_STAGE_PREFILTER`, `BACKLOG_STAGE_EXTRACTOR`, `BACKLOG_STAGE_SYNC`, `BACKLOG_STAGE_STATE_DIR`, `REPO_ROOT` | board | `hooks/backlog-stage.sh`, `hooks/backlog-stage.py` |
| context-readiness | SessionStart | `[dwarves-kit]` then `<state> \| next: <suggestion> \| warn: <warnings>`. | none | session | `hooks/context-readiness.sh` |
| post-compact-reinject | SessionStart (compact) | `[dwarves-kit post-compaction] Context was compacted. Critical rules re-injected:` | none | session | `hooks/post-compact-reinject.sh` |
| codebase-index | SessionStart | Silent. Debug trace `[dwarves-kit:index]`. Starts a background index when `codebase-memory-mcp` is on PATH. | none | cosmetic | `hooks/codebase-index.sh` |
| output-offload | PostToolUse (all tools) | `[dwarves-kit] <tool> output was large (~N tokens, over the N-token offload threshold). Full payload saved to <file>.` | `OFFLOAD_MAX_TOKENS` (default 2000), `XDG_CACHE_HOME` | session | `hooks/output-offload.sh` |
| pre-compact-backup | PreCompact | `Backup saved: <file>` on stderr. Writes `.claude/backups/`. | none | session | `hooks/pre-compact-backup.sh` |
| harvest | PreCompact; SessionEnd (`--lab-log`) | `harvest: staged N new ...`, `harvest: staged a LAB_LOG draft ...`, `harvest: fired detached ...` on stderr. | `HARVEST_LEDGER`, `HARVEST_GLOSSARIES`, `HARVEST_EXTRACTOR`, `HARVEST_FUZZY_THRESHOLD`, `HARVEST_MAXCHARS`, `HARVEST_LABLOG_DRAFT`, `HARVEST_STOP_TRIGGER`, `HARVEST_STOP_N`, `HARVEST_STATE_DIR`, `HARVEST_MIN_INTERVAL`, `HARVEST_SYNC`, `HARVEST_SWEEP_CHILD`, `REPO_ROOT` | session | `hooks/harvest.sh`, `hooks/harvest.py` |
| session-state-save | Stop; SubagentStop | Silent. Writes `.claude/session-state/last-state.md`. | `DWARVES_KIT_SESSION_MARKER` | session | `hooks/session-state-save.sh` |
| citation-guard | Stop | `citation-guard: unresolved citations:` on stderr, only in strict mode. Otherwise it logs. | `CITATION_GUARD_STRICT=1`, `CITATION_GUARD_ROOT`, `CITATION_GUARD_LOG` | session | `hooks/citation-guard.sh` |
| context-budget | UserPromptSubmit | User line: `Context budget: this session is at N% of its window`, then `Context ceiling: this session is at N% of its window`. Model line: `CONTEXT BUDGET:` and `CONTEXT CEILING:`. | `KIT_CTX_WARN_PCT` (default 65), `KIT_CTX_STRONG_PCT` (default 70), `KIT_CTX_WINDOW` | session | `hooks/context-budget.sh` |
| batch-debt-warn | PreToolUse (Bash) | `Batch-debt warning:` on the second `gh pr merge` of a session with no lane START in the ledger. Once per session. | none | session | `hooks/batch-debt-warn.sh` |
| context-hints | UserPromptSubmit | `Session time: <elapsed> elapsed, <idle> since your last prompt.` and `Maybe-relevant skills:`. | `CONTEXT_HINTS_SKILLMAP`, `CONTEXT_HINTS_STATE`, `CONTEXT_HINTS_NOW`, `CONTEXT_HINTS_TEMPORAL=0` | advisor | `hooks/context-hints.sh`, `hooks/context-hints.py` |
| tool-policy-guard | PreToolUse (all tools) | `tool-policy-guard: <tool> is DENIED by policy` (exit 2) or `is policy-controlled` (warning). Silent without a policy file. | `KIT_TOOL_POLICY` (default `~/.claude/dwarves-kit/tool-policy.json`) | advisor | `hooks/tool-policy-guard.sh` |
| auto-format | PostToolUse (Write\|Edit) | Silent. Runs prettier, gofmt, ruff or black, or rustfmt by file type. | `RUSTFMT_TOOLCHAIN` (default `stable`) | cosmetic | `hooks/auto-format.sh` |
| slop-cleaner | Stop | `[dwarves-kit:slop-check] These recently modified files may have unnecessary complexity:`. Context only. | `DWARVES_KIT_SESSION_MARKER` | cosmetic | `hooks/slop-cleaner.sh` |
| notification | Notification | A desktop notice titled `dwarves-kit`: "Claude needs permission to proceed", "Claude is waiting for your input", or "Claude needs your attention". | none | cosmetic | `hooks/notification.sh` |
| permission-auto-approve | PermissionRequest | Silent. Approves a Bash command only when it is single, simple and read-only. Debug trace `[dwarves-kit:permission]`. | none | cosmetic | `hooks/permission-auto-approve.sh` |
| money-gate | PreToolUse (Edit\|Write\|MultiEdit) | `money-gate: edit in a financial repo touches <terms>: confirm before applying.` Inert unless `MONEY_GATE_REPOS` is set. | `MONEY_GATE_REPOS`, `MONEY_GATE_STRICT`, `MONEY_GATE_LOG` | money_gate | `hooks/money-gate.sh` |
| prose-rag | UserPromptSubmit | Prior-note recall from `bin/prose-rag hook`. Dormant unless enabled. | `PROSE_RAG_INJECT=1` | prose_rag | `hooks/prose-rag.sh` |

## Files in `hooks/` that are not hook events

| File | Role |
|---|---|
| `hooks/anchor-root.sh` | Wrapper every wired hook runs through. Changes to the repo root and exports `DWARVES_KIT_INVOCATION_CWD`. Prints nothing. |
| `hooks/statusline.sh` | The `statusLine` command, not a hook. Prints `[<model>] <branch> \| ctx:N% \| $<cost> \| think:<on or off>`. Ships with the cosmetic module. |
| `hooks/codex-hook-adapter.sh`, `hooks/codex-hooks.json` | Codex runtime adapter. It supports five hooks: safety-gate, ship-gate, commit-format, secrets-guard, anti-rationalization. |
| `hooks/intake-sweep.sh`, `hooks/intake-sweep.py` | Run by `backlog-stage.sh --surface`. Not wired as an event. |
| `hooks/harvest_sweep.py` | Loaded by `harvest.py` for its sweep verbs. Not wired as an event. |
