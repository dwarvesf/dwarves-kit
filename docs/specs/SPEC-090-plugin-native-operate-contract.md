# SPEC-090: Plugin-native operate-contract (stable kit entrypoint)

Status: DRAFT
Date: 2026-07-01
Lane: full (new entrypoint surface in the kit + a cross-repo doc migration)
Type: feature + migration
Relates-to: the install.sh -> plugin distribution migration (ops-toolkit research/2026-05-22-cc-plugin-local-install.md); the kit's `hooks/hooks.json` (`${CLAUDE_PLUGIN_ROOT}` runtime); SPEC-016 (proof co-location, ops-toolkit)
Board: kit intake ID pending

## Problem

dwarves-kit historically shipped two layers:

1. **Plugin** (`kit@dwarves-marketplace`): `/kit:*` slash commands, verification subagents, and `hooks/hooks.json` wiring every hook type via `${CLAUDE_PLUGIN_ROOT}`.
2. **install.sh layer**: copied `AGENTS.md` + `WORKFLOW.md` + `lib/` into `~/.claude/dwarves-kit/`, symlinked flat commands into `~/.claude/commands/`, merged a hook subset into `~/.claude/settings.json`.

On 2026-07-01 the install.sh layer was removed from both of Han's machines (Air + Mini) via `install.sh --uninstall`, leaving dwarves-kit **plugin-only**. This was deliberate: the plugin's `hooks/hooks.json` already provides the full enforcement runtime via `${CLAUDE_PLUGIN_ROOT}` (SessionStart, PreToolUse, PostToolUse, PreCompact, Stop, SubagentStop, Notification, PermissionRequest). The `${CLAUDE_PLUGIN_ROOT}/hooks/safety-gate.sh` push-gate is confirmed live.

**Nothing about enforcement broke.** But the operate-contract *docs* across 9 adopting repos instruct Claude (and the operator) to invoke kit `lib/` scripts by the now-removed absolute path:

```
bash ~/.claude/dwarves-kit/lib/lane-classify.sh classify "<task>"
bash ~/.claude/dwarves-kit/lib/proof-gate.sh contract "<task>"
bash ~/.claude/dwarves-kit/lib/proof-ledger.sh override '<slug>' "<reason>"
```

Those calls now fail (`No such file or directory`). `WORKFLOW.md` in every adopted repo is a pointer to `~/.claude/dwarves-kit/WORKFLOW.md`, also gone.

### Why there is no drop-in replacement

The kit does not expose a stable entrypoint to `lib/`. Every candidate target path is unstable:

| Candidate | Problem |
|---|---|
| `~/.claude/dwarves-kit/lib/` | removed (was the install.sh location) |
| `~/.claude/plugins/cache/dwarves-marketplace/kit/<VERSION>/lib/` | **version-pinned**; breaks on every plugin update |
| `<checkout>/dwarves-kit/lib/` | machine/checkout-specific; absent for other contributors / hosts without the repo |
| `${CLAUDE_PLUGIN_ROOT}/lib/` | resolves only **inside hook execution**; unset in a doc-instructed Bash tool call |

Root cause: the operate-contract needs a **stable, version-independent, machine-independent entrypoint** to the kit `lib/` scripts, and `plugin.json` has no `bin`.

## API surface (what must keep working)

Distinct `lib/` scripts referenced, by frequency across the 9 adopting repos:

| Script | Refs | Purpose |
|---|---|---|
| `lane-classify.sh` | 52 | classify a task into a lane |
| `proof-gate.sh` | 39 | proof-of-done contract lookup / gate |
| `proof-ledger.sh` | 28 | record / override proof entries |
| `backlog.sh` | 10 | kanban backlog engine |
| `gate-ledger.sh` | 7 | record full-lane gates |
| `spec-next.sh` | 6 | next-spec helper |
| `adopt.sh` | 4 | adopt a repo into the kit |

~146 load-bearing `bash …/lib/*.sh` calls, plus ~34 non-call mentions (WORKFLOW.md pointers, prose) = ~180 references across 9 repos.

## Blast radius (adopting repos)

| Repo | Files referencing `~/.claude/dwarves-kit` |
|---|---|
| ops-toolkit | 125 (96 load-bearing) |
| dwarves-kit (this repo) | 35 (self-referential; owns the entrypoint fix) |
| console-labs | 5 |
| dfoundation | 5 |
| hidden | 5 |
| screenpipe-menubar | 3 |
| claude-skills | 1 |
| event-bridge | 1 |
| family-office | 1 |

## Design decision: the stable entrypoint

### Option A: `kit` CLI dispatcher shipped by the kit (recommended)

Add `bin/kit` to dwarves-kit and register it (a `bin` entry the plugin exposes, or a one-line PATH installer). The dispatcher resolves the installed kit `lib/` at runtime, priority: newest plugin cache (`~/.claude/plugins/cache/dwarves-marketplace/kit/*/lib`) -> local repo checkout -> clear error. Docs become version- and location-independent:

```
kit lane-classify classify "<task>"     # was bash ~/.claude/dwarves-kit/lib/lane-classify.sh classify "<task>"
kit proof-gate contract "<task>"
kit proof-ledger override '<slug>' "<reason>"
```

- Pros: stable across plugin updates and machines; shared-repo-safe; cleanest plugin-native shape; the fix lives in the kit (this repo), which is where the migration is owned.
- Cons: one upstream kit change (dispatcher + distribution) + a one-time rewrite of ~146 call sites.

### Option B: stable symlink `~/.claude/dwarves-kit/lib` maintained by a hook

Recreate `~/.claude/dwarves-kit` as a symlink to the current plugin-cache `lib/`, re-pointed on update by a kit SessionStart hook. Zero doc churn.

- Pros: near-zero doc changes; keeps existing refs valid.
- Cons: reintroduces the `~/.claude/dwarves-kit` dependency just removed; needs an upkeep hook; brittle if the plugin is absent.

### Option C: repo-path find/replace, REJECTED for shared repos

Rewrite to a checkout path. Hardcodes a personal workspace path into shared repos (dwarvesf/hidden, dfoundation, console-labs); breaks for other contributors/hosts.

### Recommendation

**Option A**, dispatcher shipped by this repo. Only option that is simultaneously version-stable, machine-stable, and shared-repo-safe. Option B is the low-effort fallback if the dispatcher is deferred.

## Plan (phased)

1. **Entrypoint (this repo)**: add `bin/kit` dispatcher + distribution + tests; tag a kit release. Verify `kit lane-classify …` resolves on a plugin-only machine.
2. **ops-toolkit (reference rollout)**: rewrite the 96 load-bearing call sites + the CLAUDE.md operate-contract section + `WORKFLOW.md` pointer to the `kit` CLI; verify clean.
3. **Consumer repos (7)**: one PR each: console-labs, dfoundation, hidden, screenpipe-menubar, claude-skills, event-bridge, family-office.
4. **Non-call mentions + AGENTS.md** naming the old path.

Historical records (shipped SPECs, past proof-of-done) that merely *mention* the old path as a record of what ran are NOT rewritten (accurate history). Triage per file: only load-bearing instructions and live pointers change.

## Verification (per repo)

- `git grep -P "(?<![/A-Za-z0-9_-])\.claude/dwarves-kit/lib"` returns only historical-record hits.
- One representative gate command runs end-to-end via the new entrypoint (`kit lane-classify classify "add validation"` returns a lane).
- Plugin ship-gate still blocks a direct `main` push (sanity; unchanged).
- Each `WORKFLOW.md` pointer resolves.

## Rollback

Per-repo doc PRs, reverted individually. The dispatcher is additive (does not remove the plugin). Rollback is doc-only; running enforcement is unaffected either way.

## Open questions

1. Ship `bin/kit` in this repo now (Option A) or a local shim first, upstream later?
2. Leave historical SPEC/proof mentions verbatim (recommended) or annotate "path since migrated"?
3. Shared `dwarvesf/*` + tenant repos: assume the `kit` CLI on PATH, or vendor a copy?
4. Tooling-assisted cross-repo rewrite (one pass over the adopting-repo list) vs 9 hand-reviewed PRs? Blast radius argues for tool-assisted rewrite with per-repo human review.
