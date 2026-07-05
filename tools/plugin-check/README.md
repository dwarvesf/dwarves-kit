# plugin-check

Which adopted Claude Code plugins are outdated, in one glance. A read-only freshness lens
over every CC plugin you have installed, across all marketplace shapes: single-plugin
marketplaces, the local `directory` marketplace (e.g. a `kit@<marketplace>` dev checkout),
and a big multi-plugin marketplace such as `claude-plugins-official`. It prints the exact
command to bump each stale one.

**Migrated into dwarves-kit (kit-foldin SG-05, 2026-07-05).** This tool moved here verbatim
from `ops-toolkit/tools/cc-plugin-check/` (dropped the `cc-` prefix per the kit naming
rule: kit artifacts are named by function, not by host agent). No functional change: same
verdict logic, same CLI surface, same 27-assertion test suite, unmodified. Full design:
`docs/specs/SPEC-105-cc-plugin-check.md`. Why the data sources differ from the spec's
originally-named JSON shape: `docs/implementation-notes/cc-plugin-check.md`.

## The one contract: a false "current" is unacceptable

It prints `current` for a plugin ONLY when it can prove it: the installed commit sha equals
the upstream commit sha, off a freshly refreshed catalog. Every doubt degrades to `unknown,
go look`, never a false all-clear:

- offline / catalog refresh failed -> the row that would be "current" off a stale catalog is
  marked `unknown` ("catalog stale"), because a stale upstream sha cannot prove freshness.
- a plugin with no installed sha, or a version-less plugin with no sha to compare -> `unknown`.
- a local `directory` marketplace -> `unknown` + `local (dev tree, may be ahead)`; its
  working copy is routinely ahead of the installed snapshot, so no hard verdict is honest.

`OUTDATED` means the shas genuinely differ. `current` means proven equal. `unknown` means go look.

## Install

```bash
ln -s "$(pwd)/tools/plugin-check/bin/plugin-check" ~/.local/bin/plugin-check   # ~/.local/bin is on PATH
```

Needs `claude` (the CLI it delegates to) and `jq`.

## Use

```bash
plugin-check                 # = status (refreshes the catalog first, then the table)
plugin-check status          # same
plugin-check status --no-refresh   # skip the network refresh; an honest offline read
plugin-check update <name>   # print the exact bump command(s) for <name>; runs NOTHING
plugin-check update          # print bump commands for every OUTDATED plugin; runs NOTHING
plugin-check update <name> --apply   # OPERATOR ONLY: actually run the bump (see below)
```

`status` table:

```
# plugin-check  (catalog refreshed)
  PLUGIN             INSTALLED  UPSTREAM   STATUS    MARKETPLACE
  -----------------  ---------  ---------  --------  -----------------------------------------------------
  ponytail           4.7.0      0403c4dd5  current   ponytail
  superpowers        6.0.3      896224c4b  OUTDATED  claude-plugins-official  (sha differs from upstream)
  kit                1.6.0      5c918d15b  unknown   dwarves-marketplace  (local (dev tree, may be ahead))
  swift-lsp          1.0.0      aecd4c852  unknown   claude-plugins-official  (no installed sha)
  ...
  current=1  OUTDATED=8  unknown=3
  bump a stale one:  plugin-check update <plugin>        (dry-run; add --apply to run)
```

`INSTALLED` / `UPSTREAM` show the version when it is a real one, else a short commit sha
(the comparison is sha-primary; the version is display-only and absent for some plugins).

## `update`: dry-run by default

`update` prints the exact commands and runs nothing:

```
$ plugin-check update superpowers
# dry-run (nothing was run). To apply: re-run with --apply.
  # superpowers  (marketplace: claude-plugins-official)
  claude plugin marketplace update -- claude-plugins-official
  claude plugin update -- superpowers@claude-plugins-official

# Restart Claude Code after applying for the new plugin version to load.
```

The plugin id passed to the real CLI is the full `<plugin>@<marketplace>` form (a bare name
is "Plugin not found" on the official `plugin update` verb), guarded with `--` and
shell-quoted so a hostile plugin/marketplace name is never paste-unsafe.

### `--apply` is operator-only

`update --apply` actually runs the bumps via the official `claude plugin` CLI, per plugin,
echoing each command before it runs, continuing past a failure, and exiting non-zero if any
failed. An already-current plugin is a no-op (`skip: already current`). After any success it
prints the restart reminder once.

This is **operator-only**. An autonomous agent loop must never run `--apply` against a real
plugin (it could pull a breaking upstream change mid-session). The hermetic test suite stubs
`claude` and verifies `--apply` only through the already-current no-op and the dry-run print;
it never shells the real updater (a canary file asserts this).

## How it resolves (no `gh`, delegated to the CLI)

Resolution is delegated to the official `claude plugin` CLI and the state files it owns. There
is no hand-rolled GitHub path resolution and no `gh` dependency.

| What | Source |
|---|---|
| installed roster + display version + scope | `claude plugin list --json` (the authoritative "what is installed") |
| installed commit sha | `$CC_PLUGINS_DIR/installed_plugins.json` -> `.plugins[id][0].gitCommitSha` |
| upstream sha (claude-plugins-official) | `$CC_PLUGINS_DIR/plugin-catalog-cache.json` -> `.catalog.plugins[id].source_sha` (the CLI writes this; `marketplace update` refreshes it) |
| upstream sha (other marketplaces) | the marketplace clone HEAD: `git -C <known_marketplaces installLocation> rev-parse HEAD` (the CLI's own clone; for a `directory` source, the live dev tree) |

`status` refreshes the catalog first via `claude plugin marketplace update` (skippable with
`--no-refresh`); that refresh is what makes the upstream sha trustworthy. The comparison is
**sha-primary**: equal = `current`, differ = `OUTDATED`, missing-or-stale = `unknown`. A
sentinel installed version (`unknown` / `0.0.0` / empty) never gets string-compared; the sha
path governs it.

### Config: `CC_PLUGINS_DIR` (opt-in, defaults to the standard CC plugin dir)

The tool reads Claude Code's own plugin state from `$CC_PLUGINS_DIR`, which defaults to
`$HOME/.claude/plugins` (the standard per-user Claude Code plugin directory). There is no
kit- or consumer-specific path assumption: set `CC_PLUGINS_DIR` only to point the tool at a
non-default location (e.g. a test fixture, per `tests/smoke.sh`).

> Note: SPEC-105 named `claude plugin list --available --json` `source.sha` as the upstream
> signal. On the CLI version it was built against (2.1.183), `--available` lists only
> *not-installed* plugins and carries no installed-plugin sha, so the tool reads the CLI's
> catalog-cache + clone state instead. This is still CLI-delegation (the catalog is the
> CLI's, refreshed by the CLI), and it is isolated to one `read_state()` function, so a
> future CLI that exposes upstream sha via `--available` is a one-place swap. Detail in the
> implementation notes.

## Limits

- `scope: user` plugins only (the common case); other scopes are not read in v1.
- Inside a multi-plugin monorepo marketplace, a moved marketplace HEAD can over-report a
  subdir plugin as possibly-stale. v1 accepts honest over-reporting toward "go look", never a
  false `current`.
- No `status --json`, no launchd/cron timer, no surfacing hook in v1 (on-demand only, or
  wire your own scheduler; the tool never schedules itself).
- Read-only on installed state by contract: the only state mutation is `update --apply`
  shelling the official CLI; `status`'s only side effect is the official catalog refresh.

## Verify

```bash
cd tools/plugin-check
bash tests/smoke.sh             # hermetic: stubbed `claude`, never shells the real updater
bin/plugin-check status         # live, over your real installed plugins
```
