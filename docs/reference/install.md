# Install options and modules

How the kit gets onto a machine and which parts it wires. The short path is [`../QUICKSTART.md`](../QUICKSTART.md): install the plugin, run `/kit:onboard`. This page holds the layers, the module table, and the other install routes.

## Install layers and modules

Layered by design: the spine installs unconditionally. It is the hooks that guard push, merge, secrets and commit format, the irreversible boundary. A fresh install also turns on the `core` modules, today just `board`. Everything else is an opt-in module via `--with <a,b,c>`, recorded in your own project's `kit.toml [modules]` (a per-consumer install record, re-runnable; never a runtime registry a hook reads back). Run the installer with no `--with` at all to get the spine plus `board`.

**One table.** Every module's name, hooks (with their event), CLIs and default live in one file, [`lib/config/modules.tsv`](../../lib/config/modules.tsv). `install.sh` and `lib/adopt.sh` both read it; `tests/test-modules-table.sh` pins `settings.json`, `hooks/hooks.json`, `kit.toml` and the registry to it. **Behavior change for new installs and new adopts only:** before, a default `adopt` seeded `session` and `advisor` on; now only `board` starts on, and session, advisor, cosmetic, money_gate and prose_rag are opt-in. An existing install keeps the modules it has, a re-run never adds the core set, and an existing `.kit.toml` is never rewritten.

| Module | What it wires | Kind |
|---|---|---|
| `board` | `backlog-stage` (SessionEnd: stage session work-items to a staging file, opt-in via `BACKLOG_STAGE_AUTO=1`, default off; also wired on SessionStart as `--surface`); that pass also runs `intake-sweep` (consumer-declared deferred-link sources, config-gated); `board-row-gate` (PreToolUse Bash: blocks a commit that adds a new board row without a `board-row-ok: <reason>` line) | hooks |
| `session` | `context-readiness`, `output-offload`, `pre-compact-backup`, `post-compact-reinject`, `harvest`, `citation-guard`, `batch-debt-warn` (advisory PreToolUse: warns on a second PR merge with no lane start in the gate ledger), `context-budget` (warns once at 65% of the model's context window, again at 70%, `KIT_CTX_WARN_PCT`/`KIT_CTX_STRONG_PCT`/`KIT_CTX_WINDOW`); plus a PATH shim for the `session` CLI (`session <intel\|observe\|recall\|report\|semantic>`: the five prefixed CLIs collapsed into one entry) | hooks + CLI |
| `advisor` | `context-hints` (session-elapsed + keyword skill hints) + `tool-policy-guard` (PreToolUse allow/ask/deny per tool domain; inert until a `tool-policy.json` exists) | hooks |
| `cosmetic` | `auto-format`, `notification`, `slop-cleaner`, `statusline`, `codebase-index`, `permission-auto-approve` | hooks |
| `queue` | `/kit:mega` + `/kit:dispatch` machinery (`lib/queue/orchestrate.sh`), the overnight queue launcher (`lib/queue/queue.sh`) | hookless (lib) |
| `stats` | the `stats` CLI, a read-only projection over the run/gate ledgers | hookless (uv CLI) |
| `quiz_gate` | `/kit:quiz-gate` (the understanding-gate nudge) | hookless (command) |
| `weekend_batch` | the debt-paydown reader/closer (`bin/reflect debt`; engine `lib/reflect/weekend-batch.sh`, renamed from `learn`), invoked by a consumer's own skill or directly | hookless (lib) |
| `worktree` | `worktree-provision` on PATH (manual worktree env-symlink + install provisioner, `lib/worktree-provision/`) | hookless (CLI) |
| `money_gate` | `money-gate` (PreToolUse Edit/Write guard for money-touching edits; inert until you set `MONEY_GATE_REPOS`) | hook |
| `prose_rag` | `prose-rag` recall inject (UserPromptSubmit, dormant until `PROSE_RAG_INJECT=1`) + the `prose-rag` CLI alias over context-kit's `ctx` engine verbs (`lib/prose-rag/`) | hook + CLI |
| `sync` | `board sync` two-way spoke mirror (BACKLOG.md ⇄ Apple Reminders / Notion / Hermes kanban; engine `lib/sync/`, per-repo `.kit.toml [sync]` config), inert without `[sync] sources` | hookless (lib) |

`team_mode` is a reserved, not-yet-installable slot (parked, see [`PHILOSOPHY.md`](PHILOSOPHY.md) "Team mode: parked, not absent"); naming it in `--with` errors on purpose.

**Add a module later** (a later module never re-onboards you): edit `.kit.toml`'s `[modules]` section
by hand, then re-run `/kit:adopt --refresh` (or `bash lib/adopt.sh --refresh <repo>`) to re-wire
`settings.json` to match. Full detail: [`commands/adopt.md`](../../commands/adopt.md).

```bash
bash install.sh                         # fresh: spine + board (the core module); a re-run keeps what you have
bash install.sh --with session,stats    # add modules (additive; never un-wires one you already have)
bash install.sh --prune                 # explicit trim: spine only
bash install.sh --prune --with board    # explicit trim: spine + board
```

## Requirements

The bash installer needs `jq` (for the settings merge) and `git`, and refuses to start without them. The plugin path needs neither. `node` is optional: only the `system-design` engine's `--shots` and `test.mjs` use it, and no hook does.

## Option 1: Claude Code plugin (recommended)

In any Claude Code session:

```
/plugin marketplace add dwarvesf/dwarves-kit
/plugin install kit@dwarves-marketplace
```

That's it. Hooks, commands, agents, and the skill all install automatically. No bash, no `jq`, no symlinks. Updates via `/plugin update kit`.

To get the kit listed on Anthropic's official marketplace (`claude-plugins-official`), submit it via [claude.ai/settings/plugins/submit](https://claude.ai/settings/plugins/submit). One-time manual step; not blocking the self-hosted install above.

## Option 2: Codex plugin

```bash
codex plugin marketplace add dwarvesf/dwarves-kit
codex plugin add kit@dwarves-marketplace
```

Codex loads the hard controls through `hooks/codex-hooks.json`: destructive-command safety, secret-file protection, ship completeness, commit format, and premature-completion protection. Open `/hooks` once after installation and trust the exact hook definitions. Each command pins the adapter and policy content hashes, so changed code fails closed before execution and also changes the trust definition when the manifest refreshes.

This first Codex package is a narrow enforcement adapter. It does not inspect prompts, assistant output, hosted tools, or every specialized tool path. The commands, agents, and skills remain Claude Code authoring surfaces until Codex-native loaders ship.

## Option 3: Bash installer (maintainer / power path)

Demoted from the default doc path (the first-run flow is plugin-only). Reach for it
only in environments without Claude Code's plugin system (CI, project templates, older Claude Code
versions), or as a kit maintainer:

```bash
git clone https://github.com/dwarvesf/dwarves-kit.git ~/.claude/dwarves-kit
cd ~/.claude/dwarves-kit && bash install.sh
```

Needs `jq` and `git` (see Requirements above). No root / no package manager (CI images, locked-down containers): drop a static `jq` binary onto PATH instead, e.g. `mkdir -p ~/bin && curl -fsSL -o ~/bin/jq https://github.com/jqlang/jq/releases/latest/download/jq-linux-arm64 && chmod +x ~/bin/jq && export PATH="$HOME/bin:$PATH"` (pick the asset for your arch). Do not hand-copy the kit's files around a missing `jq`: the settings/hooks merge is the step that arms the guardrails, and a partial copy silently ships without them.

**Hooks arm only in a NEW Claude Code session.** The installer registers hooks in `settings.json`, but a session that was already running (and any single-shot headless run: `claude -p`, CI agents) never re-reads them, so every gate is advisory there: gate-ledger calls still work and record, but nothing blocks. Restart the session after installing; treat headless runs as unguarded by design.

Cloning in place is simplest, but `install.sh` also runs from a checkout anywhere. To uninstall: `bash ~/.claude/dwarves-kit/install.sh --uninstall`.

## Pick one (the bash installer is plugin-aware)

The two paths no longer collide. If the plugin is already installed, `install.sh` detects it (the same detector `/kit:onboard` shows, `lib/onboard-detect.sh`), says it **refused** to wire hooks, and does a **compat-only** install: it symlinks the legacy `~/.claude/dwarves-kit/{lib,WORKFLOW.md,AGENTS.md}` paths, so docs that still call `bash ~/.claude/dwarves-kit/lib/<x>.sh` (plain bash, where `${CLAUDE_PLUGIN_ROOT}` is unset) keep resolving, and skips the hook + command registration the plugin already owns. No double-registered hooks. A `--with` on a plugin machine is named as ignored. Wire the bash hooks anyway with `bash install.sh --force-both` (e.g. for the `statusLine` HUD, which the v1 plugin schema does not configure); every hook then fires twice. `lib/adopt.sh` follows the same rule: on a plugin machine it wires no per-repo hooks.

**Invocation differs by path:** installed as the plugin, commands are namespaced `/kit:<name>` (e.g. `/kit:spec`); via the bash installer they resolve bare `/<name>` (e.g. `/spec`). The manual uses the plugin form.

<!-- provenance: ADR-0024 -->
