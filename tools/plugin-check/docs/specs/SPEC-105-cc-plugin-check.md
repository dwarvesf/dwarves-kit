# Spec: cc-plugin-check (adopted Claude Code plugin freshness + bump helper)
Generated: 2026-06-20
Status: VALIDATED (revised v2 after 5-lens /spec-validate; see Amendments)

## Problem

Claude Code installs external plugins from marketplaces but offers no "what have I
adopted, and which are outdated" surface. It tracks installed plugins and their
marketplaces, but never compares installed against upstream and never notifies. The
on-disk marketplace clone is stale until manually refreshed.

Han runs 6 marketplaces hosting **12 installed plugins**: single-plugin marketplaces
(`ponytail`, `ouroboros`, `zedra`, `claude-code-warp`), a local `directory` marketplace
(`kit@dwarves-marketplace`, source path the local dwarves-kit checkout), and the big
multi-plugin `claude-plugins-official` (234 plugins; hosts 8 of Han's: playwright,
frontend-design, superpowers, swift-lsp, security-guidance, code-simplifier, telegram,
agent-sdk-dev). Keeping them current means noticing staleness yourself and hand-running
`claude plugin marketplace update` + `claude plugin update <plugin>` per plugin.

cc-plugin-check is the read-only freshness lens: it answers "which adopted CC plugins are
outdated" and emits the exact bump commands. It is the Claude-Code-plugin analogue of the
`mini-agent-update` **skill** (which does the same for the Mini's deployed agents).

## Solution

### Approaches considered

1. **Delegate all resolution to the official `claude plugin` CLI (chosen).** Read installed
   state via `claude plugin list --json` and upstream state via `claude plugin list
   --available --json` (which the CLI resolves across every source type and which exposes a
   per-plugin upstream `ref` + `sha`). Compare installed vs available primarily by **commit
   sha** (the one universal signal), secondarily by version string (for display). Refresh the
   catalog first via `claude plugin marketplace update`. `update` shells the official
   `claude plugin` verbs. No `gh`, no hand-rolled path resolution.
2. **Hand-fetch upstream `plugin.json` via `gh api` (rejected).** This was the v1 design. It
   is broken and unsafe: multi-plugin marketplaces (claude-plugins-official) have no
   repo-root `plugin.json`, so a root fetch 404s for 8 of 12 plugins; each plugin's real path
   lives in `marketplace.json`'s per-plugin `source` (which can be `git-subdir` / `url` /
   subdir-string), and resolving that by hand is exactly the work the official CLI already
   does. It also interpolates third-party repo slugs into a shell `gh` call (injection), and
   adds `gh` as a dependency. Rejected in favor of approach 1.
3. **Curated `cc-plugins.toml` registry (rejected for v1).** A hand-maintained adoption list.
   Duplicates state the CLI already owns; the "what I adopted + why" record lives in
   BACKLOG/LAB_LOG. Re-introducible later if non-marketplace plugins need tracking.
4. **Do nothing; run `claude plugin update` periodically (rejected).** No `--all` verb, no
   freshness visibility; you bump blind.

### Chosen approach + why

Delegate resolution to the official CLI (approach 1). The CLI is the authoritative resolver
for every marketplace shape (single-plugin, multi-plugin monorepo, `git-subdir`, `url`,
local `directory`), so the tool never guesses paths and never touches a third-party repo
slug. The **commit sha is the universal freshness signal**: `claude plugin list --json`
carries the installed `gitCommitSha`, `claude plugin list --available --json` carries the
upstream `source.sha`; equal = current, differ = outdated, works even when no semver exists.
This mirrors `cc-observe` (reads CC's own surfaces read-only) and is ponytail-correct: use
the platform feature instead of reimplementing it. `gh` is not a dependency.

### Extensibility & boundaries

- **The CLI is the resolution oracle.** Any new source type CC adds is resolved by the CLI,
  not by this tool; the tool only consumes `list --json` / `list --available --json`.
- **Read-only on INSTALLED state.** The tool never writes installed-plugin state or cache.
  `status` does run the official `claude plugin marketplace update` (a benign, idempotent
  **catalog** refresh, not an install-state change); `--no-refresh` skips it for a pure
  offline read. Installed-plugin mutation happens ONLY via `update --apply` shelling the
  official CLI.
- **Honest unknown is mandatory.** Offline / catalog-not-refreshed / missing sha both sides /
  version-less with no sha → STATUS=unknown, never a false "current". A false "current" is
  the one unacceptable output.

### Architecture

> **SUPERSEDED in part (v3, 2026-06-20, see Amendments).** The `claude plugin list
> --available --json` join described below returns NOT-installed plugins on the shipped CLI
> (v2.1.183) and exposes no installed-plugin sha, so it resolves zero rows. The shipped data
> sources keep this section's INTENT (CLI-delegation, sha-primary, one `read_state()` boundary,
> refresh-via-`marketplace update`, honest-unknown) but read: installed sha from
> `installed_plugins.json`; upstream sha from `plugin-catalog-cache.json .catalog.plugins[id].source_sha`
> (the file `marketplace update` writes) else the marketplace clone HEAD. See Amendments v3 and
> `docs/implementation-notes/cc-plugin-check.md`. The prose below is retained for design history.

A bash CLI `bin/cc-plugin-check` (no `.sh` extension, `#!/usr/bin/env bash`, `set -euo
pipefail`, `chmod +x`), jq for parsing the CLI's JSON. **No `gh`.** Subcommands:

- `status` (default): refresh catalog (unless `--no-refresh`), read installed + available,
  join, render the freshness table.
- `update [name] [--apply]`: emit (default) or run (`--apply`) the bump commands.

**One `read_state()` boundary** is the only parser of the CLI's JSON shape; everything
downstream consumes a normalized record `{plugin, marketplace, installed_version,
installed_sha, available_ref, available_sha, source_type}`. A CLI schema change is then a
one-place fix. Comparison: if `installed_sha` and `available_sha` both present, equal=current
/ differ=OUTDATED; else if both have a real version, compare versions; else STATUS=unknown.
A sentinel installed version (`unknown`, empty, `0.0.0`) forces the sha path, never a
string-compare against the sentinel.

## Technical Design

### Interfaces (I/O contract)

- `cc-plugin-check` | `cc-plugin-check status [--no-refresh]`: table with columns
  `PLUGIN | INSTALLED | UPSTREAM | STATUS | MARKETPLACE`, STATUS in {current, OUTDATED,
  unknown}. INSTALLED/UPSTREAM show the version when known, else a short sha. Exit 0 always.
  When the catalog refresh failed or was skipped and a row cannot be proven current, that
  row's STATUS is `unknown` (labelled "catalog stale"), never `current`.
- `cc-plugin-check update [name]`: for each outdated plugin (or just `name`), print the exact
  `claude plugin marketplace update <marketplace>` + `claude plugin update <plugin>@<marketplace>`
  (the FULL pluginId; a bare name is "Plugin not found" on the real CLI, see Amendments v4) + the
  "restart Claude Code to apply" note. Default is dry-run (print only, runs nothing).
- `cc-plugin-check update --apply [name]`: run those commands per outdated plugin via the
  official CLI. Iterates per-plugin; echoes each command immediately before running it;
  reports `applied | failed(<reason>) | skipped(already current)` per plugin; one plugin's
  failure does not abort the rest; exits non-zero if any failed; prints the restart reminder
  once after any success. A plugin already current is a no-op.

### Data model (runtime state, NOT in repo)

No repo-side state, no `cc-plugins.toml`. The tool's inputs are the JSON outputs of
`claude plugin list --json` and `claude plugin list --available --json` (the CLI owns reading
`~/.claude/plugins/*`). Freshness is computed live each run; no cache.

### Infrastructure changes

None: on-demand CLI, no daemon, no `gh`. Hard dependencies: `claude` (the CLI it delegates
to) and `jq`. v1 ships NO launchd timer and NO surfacing hook (minimum-infra; both deferred).

## Task Breakdown (single goal, logical steps)

1. Scaffold `tools/cc-plugin-check/` per ops-tool-shape, mirroring `cc-observe`
   (`bin/`, `docs/`, `tests/`, `tool.toml`, `README.md`, `.gitignore`).
2. `status` read + compare: `read_state()` over the two CLI JSON outputs, sha-primary /
   version-secondary verdict, refresh + `--no-refresh`, table render; exit 0.
3. `update` dry-run + `--apply` (per-plugin, echo-before-run, partial-failure summary,
   idempotent no-op when current).
4a. Test + proof harness: hermetic `tests/smoke.sh` over fixture CLI-JSON (stubbed `claude
    plugin`, never the real binary) covering current / OUTDATED / unknown / sentinel-version /
    injection-defense; capture a real `status` run into `docs/proof-of-done.md`.
4b. Close-out: README + MANUAL + `docs/proof-of-done.md` finalized + MANIFEST row + LAB_LOG,
    then `/review` + `/review-team`, fix findings on-branch.

## After state

`cc-plugin-check` lists all 12 adopted plugins with installed-vs-upstream freshness (sha- or
version-based); outdated rows carry the exact bump command; `update --apply` performs the
bump via the official CLI. It sits in `tools/` as the CC-plugin analogue of the
`mini-agent-update` skill.

## Acceptance Criteria (global)

- **AC1** `cc-plugin-check` prints one row per installed plugin (all 12), each with a
  MARKETPLACE and a STATUS, exit 0. Plugins from the multi-plugin `claude-plugins-official`
  marketplace appear (not just single-plugin marketplaces).
- **AC2** A `claude-plugins-official`-hosted plugin (e.g. superpowers) AND ponytail both
  resolve to a real STATUS (current/OUTDATED), proving multi-plugin + single-plugin paths
  both work; ponytail shows `current` when installed sha == available sha.
- **AC3** A fixture whose installed sha/version is forced older than available shows
  `OUTDATED` with the delta (negative control).
- **AC4** Catalog-refresh failure (offline) or `--no-refresh` yields STATUS=unknown for any
  row not provably current, never a false "current"; exit still 0.
- **AC5** `update <outdated>` prints `claude plugin marketplace update <mp>` then
  `claude plugin update <plugin>@<marketplace>` (the FULL pluginId; bare name is rejected by the
  real CLI, see Amendments v4) + restart note, and runs nothing without `--apply`.
- **AC6** `update --apply` on an already-current plugin is a no-op ("already current"); on a
  set with one failing plugin, the others still apply and the summary names the failure; a
  version-current-but-sha-differing plugin (the CLI says "already at the latest version") is
  reported "already latest (no change)", not a false "applied".
- **AC7** Read-only-on-installed-state holds: no code path writes installed-plugin state or
  cache; the only install mutation is `update --apply` shelling the official CLI; `status`'s
  only side effect is the official catalog refresh (skippable via `--no-refresh`).
- **AC8** A version-less / sentinel plugin (installed `version: "unknown"`, e.g. playwright)
  is compared by sha or marked unknown, and NEVER reported a false `current`/`OUTDATED` from
  string-diffing the sentinel.
- **AC9 (autonomy gate)** `update --apply` is operator-only. The autonomous `/goal` loop MUST
  NOT invoke `--apply` against any plugin; it verifies `--apply` solely via the
  already-current no-op (AC6) and the dry-run print (AC5). `tests/smoke.sh` stubs `claude
  plugin` and asserts the suite never shells the real updater.
- **AC10 (input defense)** Plugin/marketplace names are passed as quoted argv with a `--`
  guard so a name cannot become a flag, and a fixture name containing shell metacharacters or
  a leading `-` runs no injected side effect (canary-file-not-created assertion).
- **AC11** `docs/proof-of-done.md` is committed with a captured real `status` run-table over
  the 12 plugins plus the AC3/AC4/AC8 negative controls, and contains no token, no `op://`,
  and no surprising absolute paths.

## Verification

`tests/smoke.sh` is hermetic: it feeds fixture JSON in the shape of `claude plugin list
--json` / `--available --json` via a **stubbed `claude` on PATH** (the suite must never call
the real `claude plugin ... update`), asserting: one row per fixture plugin (AC1/AC2); an
OUTDATED row for the pinned-old fixture (AC3); an unknown row when refresh is forced to fail
(AC4); a sentinel-version row never false-current (AC8); `update` without `--apply` mutates
nothing (AC5/AC7); the injection canary is not created (AC10). A live `status` run over the
real 12 plugins is captured into `docs/proof-of-done.md` (AC11). Kit-adopted repo: the work
runs its `lane-classify` lane and the ship-gate is the final `Done` check.

## Edge Cases

- Multi-plugin marketplace (claude-plugins-official): resolved by `list --available --json`;
  no per-plugin path math in this tool.
- `url` / `git-subdir` sources (superpowers): the available entry carries `source.sha`;
  compare against installed `gitCommitSha`.
- Subdir-string source (`"./plugins/x"`) with no per-entry sha: fall back to the marketplace
  clone HEAD (`git -C ~/.claude/plugins/marketplaces/<mp> rev-parse HEAD`) vs installed sha;
  if unavailable, unknown.
- Local `directory` source (kit@dwarves-marketplace): the available version reflects the live
  dev working copy, which is routinely ahead of the installed snapshot. Label such rows
  `local (dev tree, may be ahead)` and never assert a hard `current`/`OUTDATED`; this is a
  freshness hint, not a verdict.
- Plugin installed at multiple scopes: v1 reads `scope: user` only (documented narrowing).
- Version strings non-semver / `v`-prefixed: prefer the sha signal; use version only for display.

## Failure modes

- `claude` CLI absent or a verb/flag unrecognized (the tool fully depends on it): probe
  `claude plugin --help` once; on failure print the intended commands + a clear message and
  exit non-zero, never a partial/opaque shell error.
- Catalog refresh fails (offline / DNS / network): fall back to the existing clone, label
  rows "catalog stale", and downgrade any not-provably-current row to unknown (AC4). Never
  false-current off a stale catalog.
- `jq` missing: hard error, one clear line.
- `update --apply` partial failure: per-plugin `applied|failed|skipped`, continue past a
  failure, exit non-zero if any failed (AC6).
- Torn read (CC mid-write): the CLI returns invalid JSON; wrap the parse and emit one clear
  line ("CC plugin state unreadable; re-run in a moment"), exit 0, not a jq trace.
- `~/.claude/plugins/` absent: "no plugins installed", exit 0.

## Out of Scope

- The `gh`-live-fetch resolution (approach 2; rejected).
- A curated `cc-plugins.toml` registry (approach 3; deferred).
- A `status --json` machine-output flag (no consumer in v1; YAGNI).
- Any surfacing wiring (vps-mon honest-link / SessionStart line / launchd timer): v1 is
  pure on-demand; surfacing is a follow-up decision, not the loop's to make.
- Per-plugin commit-diff precision inside a monorepo marketplace (a moved marketplace HEAD
  may over-report a subdir plugin as possibly-stale; v1 accepts honest over-reporting toward
  "go look", never false-current).
- Rollback / pinning (the official CLI owns version management).

## Touches

- New: `tools/cc-plugin-check/**` (bin, docs, tests, tool.toml, README).
- `MANIFEST.md` (new tool row).
- `_meta/LAB_LOG.md` (close-out entry on the feature branch).

## Decision Log

- **CLI-delegation over gh-fetch (approach 1 vs 2).** The official `claude plugin list
  --json` / `--available --json` resolves every source type and exposes installed + upstream
  sha; hand-fetching via `gh` 404s on multi-plugin marketplaces, opens a shell-injection
  surface, and adds a dependency. Verified against live state during /spec-validate.
- **Commit sha is the primary freshness signal.** Versions are absent for ~3 plugins and
  null in 94% of `claude-plugins-official` entries; sha is universal. Version is display-only.
- **`update --apply` is operator-only (autonomy gate).** The `/goal` loop must never bump a
  real plugin; it verifies only the no-op + dry-run paths. (AC9.)
- **Input passed as quoted argv with `--`.** Defense-in-depth even though names now come from
  the trusted CLI, not third-party slugs. (AC10.)
- **Read-only on installed state; catalog refresh is benign.** `status` may refresh the
  catalog (official, idempotent) but never changes what is installed; `--no-refresh` offers a
  pure read.
- **Honest unknown over false current.** Every failure/ambiguous path degrades to unknown.
- **No daemon, no surfacing, no `--json`, no registry in v1.** Minimum-infra + YAGNI.

## Amendments

- **v2 (2026-06-20), after 5-lens /spec-validate.** Critical fixes: (1) replaced the broken
  `gh`-root-fetch resolution with official-CLI delegation, fixing the 8-of-12 multi-plugin
  miss and removing the gh-injection surface [assumption + solution-design + failure-mode +
  security lenses]; (2) sha-primary comparison + sentinel-version handling, fixing false
  current/OUTDATED on version-less plugins [assumption + solution-design + failure-mode]; (3)
  corrected bump command form to bare `<plugin>` [solution-design]; (4) added the autonomy
  gate AC9 so the loop cannot run `--apply` [scope]; (5) added input-defense AC10
  [security]. Warnings folded: single `read_state()` boundary; directory-source dev-tree
  staleness label; `--apply` partial-failure semantics; `claude`-absent failure mode;
  torn-read guard; secrets check on the committed proof; step 5 split into 4a/4b; dropped
  `--json` and surfacing to Out of Scope; corrected marketplace names. PASS (kept): read-only
  + shell-out boundary, honest-unknown invariant, minimum-infra framing, dry-run-by-default.

- **v3 (2026-06-20), during build + post-build review round.** (a) **Data-source correction
  (the §Architecture supersede above):** the v2 `claude plugin list --available --json`
  `source.sha` join does not exist on the shipped CLI (v2.1.183) , `--available` lists
  NOT-installed plugins. Shipped resolution keeps the v2 intent but reads installed sha from
  `installed_plugins.json` and upstream sha from `plugin-catalog-cache.json
  .catalog.plugins[id].source_sha` (the file `marketplace update` writes) else the marketplace
  clone HEAD; detail in `docs/implementation-notes/cc-plugin-check.md`. (b) **Review-round
  hardening (3 lenses, no criticals; warnings folded):** a hex-sha guard so a non-hex sentinel
  can never reach `current` (defense-in-depth behind the honest-unknown contract); the dry-run
  bump commands are now paste-safe (`printf %q` + `--` guard, mirroring `--apply`); a named
  `update <name> --apply` now refuses an `unknown`/dev-tree row instead of attempting a bump it
  cannot verdict; tests added for the `--apply` applied/failed summary (AC6), the named-apply
  refusal, the dry-run paste-safety, and the AC3 control was de-dead-claused (smoke now 26).
  (c) **MANUAL note:** single-plugin-marketplace freshness is only as fresh as what
  `marketplace update` pulls into the clone.

- **v4 (2026-06-20), after the first real `update --apply` (operator-run, exposed a shipped bug).**
  The stubbed suite hid a wrong command form; running the real CLI broke all 8 bumps. Fixes:
  (1) **bump-form correction (the bug):** the update verb needs the FULL `<plugin>@<marketplace>`
  pluginId, NOT the bare name v2/v3 asserted (read from `--help`, never run). `claude plugin
  update -- <bare>` returns "Plugin not found"; `-- <plugin>@<marketplace>` works (the `--`
  injection guard is fine). Corrected in `emit_bump_commands`, the `--apply` exec, and the
  named-refusal hint, and in AC5/Interfaces above. (2) **`--apply` honesty:** the CLI exits 0 with
  "already at the latest version" for a version-current plugin whose sha differs (the accepted
  over-report); the tool now classifies that as "already latest (no change)", not "applied" (AC6).
  (3) **the lesson-fix:** `tests/fixtures/stub-claude` now mimics the real CLI contract , a bare
  name (no `@`) returns "Plugin not found" + non-zero , so a regression to the bare form fails the
  suite. New tests: AC5 full-id assertion, `STUB_ALREADY_LATEST` no-op classification (smoke now
  27). (4) **version-primary stays REJECTED:** investigated again; the CLI exposes no upstream
  VERSION (`list --available --json` `version: null`; only `source.ref` carries a tag; single-plugin
  marketplaces have no catalog entry), so sha-primary remains and the over-report is documented,
  with `--apply`'s already-latest handling making it harmless in practice.

## Open questions

(none material; surfacing choice is explicitly deferred to a follow-up, not v1.)
