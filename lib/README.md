# `lib/`, kit engine helpers, grouped by subsystem

The kit's `lib/` scripts are call-by-path helpers (`bash "$DIR/x.sh"`, `$DIR`
resolved from the caller's own `BASH_SOURCE`). Claude Code's loader does not
depth-constrain `lib/`, so the files are grouped into subsystem subdirectories.
Each real file lives in exactly ONE place, its subsystem dir; there are **no
alias symlinks** (`find lib -maxdepth 1 -type l` is empty). Single-purpose
orphans with no cluster stay as bare scripts at the root.

## Subsystems

Every `lib/` directory has one row.

| Dir | Purpose |
|---|---|
| `adopt/` | `/kit:adopt` support: the AGENTS pointer template, known old-copy hashes, `onboarding-cost.sh`. The driver is `adopt.sh` at the root. |
| `audit/` | `audit.sh`, the cadence trigger for the audit-loop instances (`bin/audit`). |
| `bench/` | The bench plane: a comparative benchmark runner, its `dashboard.py` control-plane view, and the lens eval. Backs `skills/observe`. |
| `board/` | The kanban cockpit: `board.sh` and its verbs (`work`, `mirror`, `writeback`, `promote`), `backlog.sh`, `parse-board.sh`. Entry: `bin/board`. |
| `classify/` | The classifiers: lane, role, significance, task type and route suggestion. Entry: `bin/classify`. |
| `codex/` | `repin.sh`, a hand-run verb that recomputes the sha256 pins in `hooks/codex-hooks.json`. |
| `config/` | The config layer: `kit-config.sh` resolver (project > operator > kit-root), `modules.tsv` (the one module table), `module-registry.md` (module to stage map). |
| `cosmetic/` | The `cosmetic` module's docs: six session-comfort hooks that sit outside the loop. The hook scripts live in `hooks/`. |
| `decide/` | `flick.sh`, the decide engine: answer a pick-one-of-N question through a decision API, shadow-only and fail-open. Entry: `bin/flick`. |
| `gate/` | The Check stage's engine: gate and proof ledgers, ship rules, dispatch gate, quiz gate, coverage-delta, mutation-smoke, battery and doc-projection checks. Entry: `bin/gate`; see `gate/README.md`. |
| `gauntlet/` | `stats.sh`, a read-only projection over the gauntlet run-record corpus. |
| `goal/` | Goal drafts and the running-goal registry, attempt state, mega-goal merge helpers, the handoff generator. Entry: `bin/goal`. |
| `host/` | `load-warn.sh`, one warning line when the host is too loaded for a heavy run. |
| `intake/` | `intake.sh`, the knowledge-intake dedup gate (`bin/intake`). No command, skill or hook in this kit calls it: the callers are an operator's own intake skills, so a kit-only install never exercises it. |
| `ledger/` | `ledger.sh`, the kit's one append substrate that the gate, proof and telemetry writers share. |
| `lint/` | `scattered-ids.sh`, the lint for spec, task and ADR ids outside their sanctioned homes. Entry: `bin/lint`. |
| `mega/` | The mega-goal engine: `mega.sh` status reconcile against git truth, report, review and runs-dashboard halves. Entry: `bin/mega`. |
| `money-gate/` | The `money_gate` module: a PreToolUse guard that asks before a money-touching edit lands in a repo you named financial. |
| `plugin-check/` | Read-only freshness lens over the installed Claude Code plugins. Entry: `bin/plugin-check`. |
| `precedent/` | "Have we done this before?": the records and inventory surfaces. Entry: `bin/precedent`. |
| `proof/` | `asset.sh`, the proof-asset pipeline behind `bin/proof-asset`. |
| `prose-rag/` | The `prose_rag` module: local semantic search over your own prose corpus, for prompt injection. Entry: `bin/prose-rag`. |
| `queue/` | The overnight queue launcher, the non-LLM orchestrator (`orchestrate.sh`, one fresh session per sub-goal), harness and Orca backends. Entry: `bin/queue`. |
| `reflect/` | The Reflect stage: reads what the harness recorded, proposes work into staging, drains and promotes it. Entry: `bin/reflect`. |
| `registry/` | `feature-registry.sh`, the generator for `docs/FEATURES.md`, plus the id-parenthetical stripper. |
| `repohygiene/` | Tier 1 of the `kit:repo-hygiene` audit: mechanical findings on decayed files in one git repo. |
| `session/` | `session.sh`, the verb dispatcher (`bin/session`), the shared transcript parser, `handoffs.sh`, and the sub-tools `recall/` `observe/` `intel/` `audit/`. |
| `skill-curator/` | The skill half of the self-improvement loop: drafts a SKILL.md from a session, a promote gate, and a consolidating curator (`bin/skill-improve`, `bin/skill-review`). |
| `spec/` | Spec index, depth, find, next and task-done helpers. Entry: `bin/spec`. |
| `stats/` | The read plane: a stateless, read-only projection over the append-only ledgers (Python, run via `uv`). Entry: `bin/stats`. |
| `sync/` | Board sync: two-way sync between `BACKLOG.md` and its spokes (Apple Reminders, Notion, Hermes kanban, Multica). |
| `system-design/` | The UML drawing-set engine behind `skills/system-design`: renders `docs/SYSTEM-DESIGN.md` as HTML with the delta marked (bash + git to build, node optional). |
| `telemetry/` | Lane telemetry, the durable log-dir resolver (`kit-log-dir.sh`), hook-log dir, ledger migration, egress-fail. |
| `webcheck/` | Audits a live public website for agent readiness (stdlib Python, read-only HTTP). |
| `worktree-provision/` | Provisions a fresh git worktree: links the gitignored env and runs the project install. Entry: `bin/worktree-provision`. |
| `wrap/` | The landing step after ship: scan, apply, merge, land, start, rebase, log, adopt and more; verb table in `docs/wrap.md`. Entry: `bin/wrap`. |
| *(root)* | `adopt.sh` (the `/kit:adopt` driver), `explain.sh` (`/kit:explain` engine), `pitch.sh` (`/kit:pitch` engine), `onboard-detect.sh` (install-mode detector for `/kit:onboard`): orphans, no cluster |

## Resolution scheme (the `LIB_ROOT` anchor, no shims)

Every `lib/` script resolves its own dir from `BASH_SOURCE` (`SELF_DIR`) and,
when it needs a cross-subsystem sibling, computes ONE anchor:

```sh
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_ROOT="$(cd "$SELF_DIR/.." && pwd)"   # the lib/ dir
```

- **Same-subsystem** sibling  ->  `"$SELF_DIR/<callee>.sh"` (the real file sits
  right beside the caller).
- **Cross-subsystem** sibling  ->  `"$LIB_ROOT/<callee-subsystem>/<callee>.sh"`
  (e.g. `queue/orchestrate.sh` calls `"$LIB_ROOT/gate/gate-ledger.sh"`).
- **Repo-root** file (WORKFLOW.md, docs/, _meta/)  ->  `"$LIB_ROOT/.."` (two
  levels above a `lib/<subsystem>/` script). A bare root orphan (`pitch.sh`) sets
  `LIB_ROOT="$SELF_DIR"` since its own dir already IS `lib/`.

There are NO alias symlinks and NO dispatcher; the anchor is the whole mechanism.
External callers (hooks, commands, tests, `install.sh`) reference the real
subsystem path `lib/<subsystem>/<name>.sh` directly.

**Adding a file to a subsystem:** drop it in the subsystem dir. If it makes a
cross-subsystem sibling call, reference it as `"$LIB_ROOT/<subsystem>/<name>.sh"`
(add the `LIB_ROOT` line if the script does not have one yet). Nothing else, no
shim to register.
