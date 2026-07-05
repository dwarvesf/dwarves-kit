# cc-elevation: wiring runbook (activate the tools)

The 8 tools are built + merged, but **inert until wired**. This is the post-merge
activation guide. Do it at a keyboard (it changes live Claude Code behavior).

**Where hooks live:** `~/.claude/settings.json` is chezmoi-managed. Edit the dotfiles
source (`dotfiles/home/dot_claude/modify_settings.json`), then `chezmoi apply`. Do NOT
hand-edit `~/.claude/settings.json` (the watcher reverts it). Symlink each tool's bin
into `~/.local/bin` (already on PATH) first.

## Install bins

```bash
cd ~/workspace/tieubao/ops-toolkit
for t in cc-observe cc-citation-guard cc-harvest repo-sweep verify-claim cc-money-gate; do
  ln -sf "$PWD/tools/$t/bin/$t" ~/.local/bin/$t
done
ln -sf "$PWD/tools/cc-context-hooks/bin/cc-context" ~/.local/bin/cc-context
cd tools/prose-rag && uv sync   # prose-rag runs via its own .venv (see the hooks table)
```

## Hooks to add (start safe: log-only / cheap first)

| Tool | Event | settings.json entry | Mode to start |
|---|---|---|---|
| cc-citation-guard | `Stop` | `~/.local/bin/cc-citation-guard` | log-only (no env) |
| cc-money-gate | `PreToolUse` matcher `Edit\|Write\|MultiEdit` | `~/.local/bin/cc-money-gate` | log-only |
| cc-context | `UserPromptSubmit` | `~/.local/bin/cc-context` | on (cheap, ~ms) |
| cc-harvest | `PreCompact` + `SessionEnd` | `~/.local/bin/cc-harvest` | on (Haiku, infrequent) |
| prose-rag | `UserPromptSubmit` | `<abs>/tools/prose-rag/.venv/bin/python <abs>/tools/prose-rag/bin/prose-rag hook` | **opt-in** (~250ms/prompt) |

Promote cc-citation-guard / cc-money-gate to blocking later: set `CC_CITATION_STRICT=1` /
`CC_MONEY_STRICT=1` in the hook's env once the logs (`~/.claude/logs/*.log`) show the
false-positive rate is acceptable.

**prose-rag** also needs its index built first and refreshed when the corpus changes:
```bash
tools/prose-rag/.venv/bin/python tools/prose-rag/bin/prose-rag index   # ~8 min
```

## Scheduled digests (launchd) + monitoring

Two read-only weekly digests. Per the `job-monitoring-onboarding` rule, register each new
launchd job with vps-mon (reconcile kind = scheduled) before calling it done.

| Job | Command | Cadence |
|---|---|---|
| cc-observe weekly | `cc-observe report --days 7 --json >> <log>` | weekly |
| repo-sweep weekly | `repo-sweep run >> <digest>` (+ `triage`, `learning-flush`) | weekly |

Author the plists under each tool's `deploy/macos/` following the repo's BTM-friendly rule
(ProgramArguments[0] = the script, no `.sh` on the launcher). Then wire vps-mon.

## On-demand (no wiring)

- `verify-claim "<claim>" --n 3`, run on a load-bearing claim (or from a `/verify` flow).
- `repo-sweep triage` / `learning-flush`, run when you want the board / ledger reconciled.

## Safety order

1. Wire the cheap/log-only ones first (cc-context, cc-citation-guard log-only, cc-money-gate log-only, cc-harvest).
2. Watch `~/.claude/logs/` for a week.
3. Promote citation-guard + money-gate to strict.
4. Add prose-rag's hook last, only if you accept ~250ms/prompt (else keep it CLI-only).
5. Schedule the two digests + register them in vps-mon.
