# Implementation notes: cc-plugin-check

**Migrated into dwarves-kit (kit-foldin SG-05, 2026-07-05).** This tool moved here verbatim
from `ops-toolkit/tools/cc-plugin-check/`, renamed `plugin-check` (kit naming rule: drop
the host-agent prefix on entry). No functional or test change; kept below for continuity,
predating the move.

Delta-from-spec log. The spec (`docs/specs/SPEC-105-cc-plugin-check.md`) holds the design;
this file holds ONLY what the spec did not pin down, what I changed against it, and host
quirks discovered while building. Not a restatement of the spec.

## 2026-06-20 11:50 The spec's `--available --json` join mechanism does not exist in CLI 2.1.183

- Context: spec §Architecture mandates `read_state()` join installed `gitCommitSha`
  (from `claude plugin list --json`) against available `source.sha`
  (from `claude plugin list --available --json`). I probed the live CLI (v2.1.183)
  before writing any code.
- Discovery (the load-bearing host quirk):
  1. `claude plugin list --json` carries NO `gitCommitSha`. Its per-plugin keys are
     `id, version, scope, enabled, installPath, installedAt, lastUpdated[, mcpServers]`.
     The installed sha lives instead in `~/.claude/plugins/installed_plugins.json` at
     `.plugins["<id>"][0].gitCommitSha`.
  2. `claude plugin list --available --json` returns `{available:[...], installed:[...]}`.
     `.available` is the catalog of NOT-installed plugins and contains ONLY
     `claude-plugins-official` entries (227). My 12 installed plugins are EXCLUDED from
     `.available` (it lists what you *could* install, the opposite of what the spec
     assumed), so the installed->available sha join the spec describes returns zero rows.
  3. The real upstream truth the CLI keeps is `~/.claude/plugins/plugin-catalog-cache.json`
     at `.catalog.plugins["<id>"]`, an object keyed by pluginId. Per entry the upstream
     sha is `.source_sha` (ALWAYS present for official plugins); `.sha` is populated only
     for url / git-subdir sources (external repos, e.g. superpowers) and is `null` for
     subdir-string sources (`./plugins/x`, the plugins that live inside the official
     monorepo). So the universal upstream-sha field is **`source_sha`** (fall back to
     `sha`). The catalog cache holds `claude-plugins-official` only.
  4. The single-plugin marketplaces (ponytail, ouroboros, zedra, claude-code-warp) and the
     local `directory` marketplace (kit@dwarves-marketplace) are NOT in the catalog cache.
     Their upstream sha is the marketplace clone HEAD:
     `git -C <known_marketplaces.json[mp].installLocation> rev-parse HEAD`. For the
     `directory` source that installLocation is the live dev working tree
     (the local dwarves-kit checkout).
- Decision / Change: keep the spec's INTENT (delegate to the CLI, sha-primary compare,
  one `read_state()` boundary, refresh via `claude plugin marketplace update`, honest
  unknown) but change the DATA SOURCES `read_state()` reads, because the spec's named
  JSON shape does not exist in this CLI version:
  - installed sha + version <- `installed_plugins.json` (the CLI's own state file).
  - upstream sha <- `plugin-catalog-cache.json` `.catalog.plugins[id].source_sha`
    (official) ELSE the marketplace clone HEAD (non-official, from
    `known_marketplaces.json`).
  - `claude plugin marketplace update` still drives the catalog refresh at `status` start;
    it is what rewrites `plugin-catalog-cache.json`, so refreshing via the CLI then reading
    the file it wrote is still "delegate resolution to the CLI", just async through its
    state file rather than a synchronous `--available` call.
  - `claude plugin list --json` is still called once, as the authoritative roster of which
    plugins are installed + their display version + scope filter (`scope == user`), per
    the spec's "list --json is the installed roster" intent.
- Why: a false "current" is the spec's one unacceptable output (§Solution). The
  `--available` join the spec names would silently return no matching rows -> every plugin
  would fall through to a non-sha path. Using the CLI's real upstream state file is the
  only way to get a *provable* installed-sha == upstream-sha equality, which is the whole
  honest-current contract.
- Alternatives considered:
  - `gh api` upstream fetch: explicitly rejected by the spec (approach 2; injection + 404
    on multi-plugin marketplaces). Not revived.
  - Parse `--available --json` `.installed[]`: it carries the same shape as `list --json`
    (no sha, no source), so it adds nothing.
  - `claude plugin details <name>`: shows installed version + component inventory, no
    upstream sha. Useless for freshness.
- Impact: `read_state()` reads three CLI-owned JSON files + (for non-official mp) one
  `git rev-parse` per marketplace. Still no `gh`, still no hand-rolled GitHub path math
  (the clone is the CLI's, the catalog is the CLI's). A future CLI that DOES expose
  upstream sha via `--available` would be a one-place swap inside `read_state()`.
  Documented in README + MANUAL as the resolution path.

## 2026-06-20 Live resolution result for the real 12 (recorded for proof-of-done)

current (sha match): ouroboros, ponytail, warp, zedra.
OUTDATED (sha differs): code-simplifier, frontend-design, kit, playwright,
  security-guidance, superpowers.
unknown (no installed gitCommitSha in installed_plugins.json): swift-lsp, telegram.
kit@dwarves-marketplace is `directory` source -> labelled `local (dev tree, may be ahead)`,
  no hard verdict asserted (its dev-tree HEAD is routinely ahead of the installed snapshot),
  per spec Edge Cases. It is reported under STATUS=unknown with the dev-tree note, never a
  hard current/OUTDATED.

## 2026-06-20 Review-round fixes (3-lens /review-team on the PR; no criticals, warnings folded)

Lead-applied after the build, on this branch. Each is a delta from the as-built code; the spec
got a v3 Amendment for the data-source supersede (already logged above) + these:

- **Hex-sha guard in `verdict()`** (`is_real_sha`, `^[0-9a-f]{7,40}$`). The `current` arm now
  requires both shas to be hex-shaped, not merely `!= "-"`. This makes a false `current`
  *structurally* impossible even if a future CLI wrote a non-hex sentinel (e.g. the literal
  string `"null"`) into the sha field. Defense-in-depth behind read_state's `-` rule; the one
  unacceptable output (false `current`) is now excluded by shape, not by trusting the input.
- **Paste-safe dry-run** (`emit_bump_commands`). The printed bump commands now `printf %q` the
  name and carry the `--` end-of-options guard, mirroring the `--apply` exec path. Reason: the
  dry-run output exists to be copy-pasted, and a hostile plugin/marketplace name (the `evil`
  fixture) previously printed a runnable injection. `--` is valid for the commander.js-style
  `claude plugin update [options] <plugin>` (verified `--help`).
- **Named `update <name> --apply` verdict gate.** A named `--apply` now refuses an
  `unknown`/`directory`-dev-tree row (it cannot be verdicted OUTDATED) with a non-zero exit and
  a "run the official CLI yourself" hint, instead of attempting a bump on something the tool
  labelled `unknown`. The bulk `--apply` already excluded those; this closes the named-path
  asymmetry both review lenses flagged. (Operator-driven; the AC9 autonomy gate, loop never runs
  `--apply`, was already intact.)
- **Tests (+4, smoke now 26).** Added: AC6 `--apply` applied-summary + exit 0 ([23]); AC6
  partial-failure failed-summary + non-zero exit ([24]); the named-apply refusal + no-canary
  ([25]); dry-run paste-safety on the `evil` row ([26]). Stub gained a `STUB_ALLOW_UPDATE` mode
  so the apply/summary path can run without firing the autonomy canary (still the stub, never the
  real CLI). AC3 control de-dead-claused (the old `(A && B) || A` collapsed to `A`).
- **MANUAL freshness caveat.** Documented that a single-plugin-marketplace `current` is only as
  fresh as what `marketplace update` pulled into the clone (it is the CLI's fetch, not ours).

## 2026-06-20 Real-CLI dogfood: bump-form was WRONG; tests stubbed the contract away

First live `update --apply` (operator ran it on the real 8 OUTDATED) failed ALL 8. Root cause
found by running the real CLI directly (the suite only ever stubbed it, so it shipped):

- **Bump-command form bug (the merged tool was broken).** The tool emitted/ran
  `claude plugin update -- <bare-name>`. The real CLI rejects a bare name: `Plugin "ouroboros"
  not found`. The correct form is the full pluginId `claude plugin update -- <plugin>@<marketplace>`
  (verified live: `ouroboros@ouroboros` updated 0.29.1 -> 0.42.4). The `--` guard itself is fine
  (`claude plugin update -- ouroboros@ouroboros` works); only the bare-vs-full-id was wrong. The
  spec's AC5 + the build + the solution-design review lens all asserted "bare name, NOT @mp" by
  reading `claude plugin update --help` (`<plugin>`), never running it. Fix: emit/run the full id.
- **Why no test caught it (the lesson).** `tests/fixtures/stub-claude` accepted ANY name shape,
  so the stub validated an imagined contract, not the real CLI's. Fix: the stub now mimics the
  real CLI , a bare name (no `@`) returns "Plugin not found" + non-zero, so a regression to the
  bare form fails the suite. This is the durable guard.
- **`--apply` honesty.** The real CLI exits 0 with "already at the latest version" for a plugin
  that is version-current even when its sha differs (the accepted over-report). Without parsing
  that, `--apply` would report "applied" for an unchanged plugin. Fix: capture the CLI output and
  classify `already (at the latest|up to date)` as a no-op ("already latest"), distinct from a
  real "applied". Stub gained `STUB_ALREADY_LATEST` to test this.
- **version-primary was investigated and REJECTED (no data).** The over-report (sha differs but
  version unchanged) cannot be fixed by comparing versions: the CLI's state exposes no upstream
  VERSION (`list --available --json` has `version: null`; only `source.ref` carries a tag, and
  single-plugin marketplaces have no catalog entry at all). So sha-primary stays; the over-report
  is documented as "sha moved, run `update` and the CLI is the version authority", and `--apply`'s
  new already-latest handling makes it harmless in practice.
