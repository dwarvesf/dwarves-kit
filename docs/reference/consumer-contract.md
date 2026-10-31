# Consumer contract

What a project or machine needs so an adopted repo works with the dwarves-kit. This is the
onboarding page, not a tutorial: read `AGENTS.md` (the operate-contract itself) and
`WORKFLOW.md` (the lane x phase gate matrix) for how to work once adopted.

## What `/kit:adopt` injects

`lib/adopt.sh` (driven by `/kit:adopt`) runs the numbered steps below against the target repo,
idempotently. The step numbers match the `# N.` comments in `lib/adopt.sh`.

| Step | Target | What it is | Refreshed? |
|---|---|---|---|
| 1 | `AGENTS.md` | A small pointer (`lib/adopt/AGENTS.pointer.md`) to the installed kit's operate-contract | Never. A local file is never rewritten, merged or deleted. Only an unmodified old kit copy is swapped, and only on `--refresh --swap-agents` |
| 2 | `WORKFLOW.md` | Pointer to the installed kit's lane x phase gate matrix | Yes, on `--refresh` (written atomically) |
| 3 | `CLAUDE.md` (managed block) | `@AGENTS.md` import + the classify/gate one-liners, inside `<!-- kit:adopt --> ... <!-- /kit:adopt -->` markers | Yes, on `--refresh` (block replaced; rest of the file untouched) |
| 4 | `docs/verification/README.md` | The proof-of-done marker; its presence opts the repo into the ship-gate | Never |
| 5 | `.kit.toml` | Opt-in per-project starter, seeded once (see below) | Never; an existing file is not touched |
| 6 | `.claude/settings.json` | Hook wiring for the enabled modules, a targeted `jq` merge | Every run, from the current `.kit.toml` |
| 6b | `.claude/settings.json`, `.claude/output-styles/` | The `[output] style` pick, when set | Every run, when a style is set |

Only `AGENTS.md` (bar the opt-in old-copy swap), the proof marker and an existing `.kit.toml` are never overwritten. The
`WORKFLOW.md` pointer and the `CLAUDE.md` block are replaced on `--refresh`. Step 6 leaves
the project `settings.json` alone on a plugin machine, because the plugin already registers every
hook. `--single-source` folds the block into `AGENTS.md` and skips step 1.

Claude Code auto-loads `CLAUDE.md`, not `AGENTS.md`, which is why the loader block exists: it
`@AGENTS.md`-imports the real contract so an agent session actually reads it.

## The `KIT_LEDGER_DIR` knob

One root, shared by the write-side ledger and the read-side `stats` projection. Precedence
(`lib/telemetry/kit-log-dir.sh`):

1. `$KIT_LEDGER_DIR` env var, explicit (empty is a fatal error, never silent fall-through).
2. `$DWARVES_KIT_LOG_DIR` env var, back-compat alias.
3. `[ledger].location` in `.kit.toml` (project) / `kit.toml` (kit-root): `"isolated"` ->
   `$PWD/.kit/logs`, `"shared"`/unset -> the XDG default, anything else -> that literal path.
4. `${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs` -- the hardcoded default, outside
   `~/.claude` so a plugin reinstall can never wipe the corpus.

Pick **shared** (default) when several adopted projects should feed one run corpus for
`/kit:retro` and the effectiveness eval. Pick **isolated** (or an explicit path) when a
project's ledger must not mix with anything else on the machine.

## The optional `<project>/.kit.toml` override

Seeded once by `/kit:adopt` (opt-in; never overwritten after creation; `--with a,b,c` seeds
those modules `true` instead of inheriting the kit-root default). A fresh seed also writes
`[gate] lane_gates = true` and `proof_of_done = true`, so an adopted repo enforces both gates;
a raw install keeps the `kit.toml` defaults, both off. Only the keys you set win;
everything you omit inherits the operator `kit.toml`, then the kit-root `kit.toml` default
(`lib/config/kit-config.sh` resolves project > operator > kit-root > default; a missing file
at any layer is skipped).

The operator file lives at `${XDG_CONFIG_HOME:-$HOME/.config}/dwarves-kit/kit.toml`
(`KIT_CONFIG_OPERATOR` overrides the directory). It holds the keys that name per-operator
paths, such as `wrap.activity_log` and `precedent.registry`, so they survive a kit upgrade
instead of living in the kit checkout. It carries the same trust as the kit root: it sits on
the operator's machine and never rides inside a pull request, so `kit_config_get_root` reads
it and still skips the project `.kit.toml`.

Re-run `/kit:adopt` (or `lib/adopt.sh --refresh`) after hand-editing `[modules]` to re-wire
`.claude/settings.json` -- adopt reads `.kit.toml` at adopt time; no hook reads it at
hook-fire time. A module's hooks are added to or removed from the project's `settings.json` via
a targeted `jq` merge (every other entry in that file is preserved). Which modules carry hooks,
and which only expose commands or skills, is the `hooks` column of `lib/config/modules.tsv`, the
one module table. Modules with no hook there never touch `settings.json`.

## The stable entrypoint

Reference `$DWARVES_KIT/bin/<name>`, never a deep `lib/<subsystem>/<file>.sh` path.
The adopt-injected `CLAUDE.md` block already does this for you:

| Stable entrypoint | Forwards to |
|---|---|
| `bin/board` | `lib/board/board.sh` (incl. `board promote`, the staged-candidate human gate, ex `add-backlog`) |
| `bin/classify` | `lib/classify/classify.sh` |
| `bin/gate` | `lib/gate/gate.sh` |
| `bin/goal` | `lib/goal/goal.sh` |
| `bin/mega` | `lib/mega/mega.sh` |
| `bin/precedent` | `lib/precedent/precedent.sh` (`find "<words>" --surface records\|inventory\|all`, `--quiet` the close-out form, `--explain <label>`; registry rows are `<kind> <path> [label=NAME] [depth=N]` for `repo\|scripts\|skills\|crons\|memory\|learnings\|exec\|commands\|agents` (`learnings` = a browser-harness per-site recipe dir, one `manifest.json` per site; `exec` = executables under a dir to `depth` levels; `skills` walks category dirs; `commands` and `agents` read `<dir>/*.md`; the last four take a glob and `label` names the source harness or tenant), `find` takes `--layer\|--cluster\|--kind` filters and prints a query equal to an item name (or `kit:<name>`) first in an `exact` section, `index [--layer\|--cluster\|--kind] [--out <file>]` prints a markdown page of every item grouped by cluster, layer and kind with the declared `estate` fields (SKILL.md/agent/command `metadata.estate`, tool.toml `[estate]`, script header `# estate: k=v`), resolved `--registry` > `PRECEDENT_REGISTRY` > `kit.toml [precedent] registry` (operator or kit-root only, never a project `.kit.toml`) > `${XDG_CONFIG_HOME:-$HOME/.config}/dwarves-kit/inventory.txt`) |
| `bin/queue` | `lib/queue/queue.sh` |
| `bin/reflect` | `lib/reflect/reflect.sh` (`reflect debt <list\|collect\|mark-paid>`, `reflect propose`, `reflect drain`; renamed from `learn` by ADR-0036) |
| `bin/session` | `lib/session/session.sh` (`session <intel\|observe\|recall\|report\|semantic>`, ex the five `bin/session-*`) |
| `bin/spec` | `lib/spec/spec.sh` |
| `bin/stats` | `lib/stats/` (via `uv run --project`) |
| `bin/wrap` | `lib/wrap/wrap.sh` (`scan` report-only; `apply [--apply] [--worktrees]` branch delete + worktree remove + `--ff-only` pull, plus the origin delete of branches whose same-repo PR merged at their exact tip (`[wrap] delete_merged_remote_branches`, root-only, default `true`), plus opt-in `--archive-unmerged` (never under `--own`): pushes every local branch not current/default/worktree-held with a commit `git cherry origin/<default>` marks unique to `origin archive/<slug>-<date>` (no force), deletes the local branch only once that push lands, dry-run by default; plus opt-in `--archive-worktrees` (never under `--own` or `--no-pull`, needs `lsof`): a stale (`[wrap] archive_worktree_min_age_hours`, root-only, default `72`) worktree whose branch is unmerged, whose detached HEAD carries a commit origin lacks, or that is dirty goes to `origin archive/<slug>-<date>` through a create-only lease, uncommitted files as a temp-index snapshot commit, then the worktree is removed and its branch deleted, leased to the HEAD it read; `--no-pull` (a step 0 stop) skips the pull and the stray-commits move (`SKIP pull: --no-pull`, `SKIP stray commits: --no-pull`), pushes nothing for stray lines (`SKIP stray lines: --no-pull (N lines in <file> stay local)`), skips the worktree and all-branches sweeps unless `--own` names the session's worktrees, still runs the `--own` tidy and the origin sweep, and refuses `--pull-only` (exit 64); `--pull-only` runs exactly `fetch --prune` + default-branch resolution + the pull section (union carry, `wrap.pull_past_dirty`) alone, no worktree/branch/archive/origin-branch/stray-line/stray-commit write; refuses to combine with `--worktrees`, `--archive-unmerged`, `--own`, or `--tips-file` (exit 64); a default branch ahead of origin prints `NOTE: <default> is N commits ahead of origin/<default>` and is never carried: merely ahead of un-moved origin the pull is a no-op (exit 0), diverged it still fails (`FAILED pull --ff-only`, exit 2); an unresolved default branch exits 2, and under `--apply` so does a pull skipped by a held `index.lock` (plain `apply` exits 0 on both); the tip snapshot and `gh auth status` probe do not run; `land <worktree> [--no-pull]` (`--no-pull` skips the closing fast-forward, `SKIP pull: --no-pull`, and writes nothing in the main checkout); `merge [--apply] [--no-pull] [--pr N] [--verify C]` one own green PR per call (`--no-pull`, a step 0 stop, skips any PR whose head branch the main checkout holds, whatever its state: `SKIP #<n>: head <branch> is checked out in the main checkout (--no-pull)`) (`--pr` names exactly one own open PR, marking a draft ready first), base = default branch, mergeable, checks green, no unresolved threads, no open dependents, a draft is a SKIP line; a CONFLICTING own PR runs the shared merge cycle first (`origin/<default>` merged into the branch, a generated file resolved through its generator, a pure-addition CHANGELOG union kept, anything else refused and left for the squash-equivalent fallback; `--verify C` runs once between the merge commit and the fast-forward push, and a re-merge that cannot restore cleanly keeps its checkout for a human); `log` prepends a dated line to `[wrap] activity_log (from a worktree of the log's repo, the worktree's copy is written)`, operator or kit-root `kit.toml` only, path must resolve under `$HOME`; `default-branch` prints the detected name; `deploy-wait <owner>/<name> <sha> [--check <substr>]... [--timeout <secs>]` reads a SHA's check runs until every match is completed, highest id per name, exit 0 only when all concluded `success`, 1 a failure (names printed), 2 a gh or read error, 124 timeout, writes nothing; `rebase <worktree>` rebases a worktree's branch onto `origin/<default>` (never the main checkout), regenerating `docs/reference/FEATURES.md` when the worktree carries `lib/registry/feature-registry.sh` and keeping both sides of a `CHANGELOG.md` conflict only when both sides purely added lines, else `git rebase --abort` and exit 1 naming the paths; the stage set is marker-scanned before `git add`, the only commit is one regeneration after the rebase, never pushes, exit 64 usage or a non-worktree path; `follow-mode [lanes\|all]` prints step 10's mode and lanes from `[wrap] follow_through` (`off`, `lanes`, `all`; root-only, default `off`; any other value prints one line and runs as `off`)) |

`bin/learn` is a deprecated forwarder to `bin/reflect` (same verbs, a stderr notice); point
callers at `bin/reflect`. The table above lists the main entrypoints, not every file in `bin/`;
`ls bin` is the full set.

Module CLIs keep their module names (ADR-0034 two-class rule): `bin/prose-rag`,
`bin/worktree-provision`.

A consumer that points at `bin/<name>` survives an internal `lib/` reorg unchanged; a consumer
that reaches a deep lib path does not.
