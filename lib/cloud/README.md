# cloud

Cloud-session support for any adopted repo. A Claude Code cloud VM clones ONE
repo and nothing else: no user `CLAUDE.md`, no user skills, no plugins, no
sibling checkouts, no secrets, no `/kit:*` slash commands. This module rebuilds
the generic half of that, and states the rules for the half it cannot rebuild.

Folded in from the ops-toolkit `cloud-cockpit` tool, which proved the shapes
live and paid for them in aborted sessions. The operator-specific half (a
personal repo map, a curated skill roster, a private vault) stayed there and
arrives here as CONSUMER CONFIG.

```
Environment "Setup script" field  (once per environment cache generation, ROOT)
   |  clone dwarves-kit into ~/.claude/dwarves-kit
   +--> bash ~/.claude/dwarves-kit/bin/cloud vm-setup
          +-- lib/cloud/install-gh.sh   gh: release tarball first, apt fallback
          +-- op (1Password CLI)        only useful when the env carries a token

Consumer repo .claude/settings.json  (rides in the clone; written by /kit:adopt)
   |
   +-- SessionStart (startup|resume) --> hooks/cloud-session-start.sh
   |        [gate: CLAUDE_CODE_REMOTE=true AND Linux]
   |        +--> lib/cloud/provision.sh
   |               +-- workspace dir + a symlink for the session repo
   |               +-- sibling repos declared in [cloud] repos
   |               +-- toolchain report (git, jq, python3) + a gh fallback install
   |               +-- arm the repo's core.hooksPath
   |               +-- board render smoke, when the repo keeps a kit kanban
   |               +-- background layer: MEMORY.md / AGENTS.md / CLAUDE.md
   |               +-- behavioral plugins declared in [cloud] plugins
   |               +-- secrets canary, when OP_SERVICE_ACCOUNT_TOKEN is set
   |        +--> additionalContext + reloadSkills back to the session
   |
   +-- PostToolUse (Write|Edit|MultiEdit) --> hooks/cloud-dash-guard.sh
            [same gate] prose files only, fenced and inline code skipped
```

## Install and use

Opt-in module, off by default. Enable it per project:

```bash
bash install.sh --with cloud                 # wire the hooks + the PATH CLI
bash lib/adopt.sh --with cloud <repo>        # or via /kit:adopt for a consumer repo
```

Stable entrypoint `bin/cloud`:

```bash
cloud provision [--repo-root <p>]   # assemble the layout (what the hook runs)
cloud vm-setup                      # VM-level installs (the Setup script body)
cloud install-gh                    # just the gh installer
cloud rules                         # print the cloud rules this session follows
cloud map                           # print the consumer's routing map
cloud repo <name>                   # clone one more repo into the workspace
cloud secrets                       # just the secrets step
cloud plugins                       # just the behavioral-plugin step
```

The environment's Setup script field holds a short locator, never a pasted
install blob (a blob is an untestable second copy that drifts):

```sh
git clone --depth 1 https://github.com/dwarvesf/dwarves-kit.git \
  "$HOME/.claude/dwarves-kit" 2>/dev/null || true
bash "$HOME/.claude/dwarves-kit/bin/cloud" vm-setup || true
```

## Consumer config

Every knob resolves env-first (`CLOUD_<KEY>`), then the PROJECT's `.kit.toml`
`[cloud]` section, then a neutral default. With no config at all the module
still does the generic work. Nothing operator-specific is baked into the kit.

| Key | Default | What it drives |
|---|---|---|
| `workspace` | `$HOME/workspace` | where the session repo is linked and siblings are cloned |
| `repos` | none | comma-separated sibling repos to clone: `<name>` or `<owner>/<name>` |
| `repo_owner` | none | default owner for a bare name in `repos` |
| `plugins` | none | behavioral plugins to install: comma-separated `<id>\|<marketplace-slug>` |
| `vault` | none | vault name, reported in the canary verdict |
| `canary_ref` | `op://<vault>/cloud-canary/credential` | reference proving the vault is reachable |
| `hooks_path` | `.githooks` when present | repo-relative `core.hooksPath` to arm |
| `map` | none | repo-relative routing map printed by `cloud map` |
| `rules` | `lib/cloud/CLOUD-RULES.md` | repo-relative cloud-rules file for this repo |
| `op_version` | `v2.31.1` | pinned 1Password CLI release |

Example, in a consumer repo's `.kit.toml`:

```toml
[cloud]
workspace  = "~/workspace/acme"
repos      = "billing,acme/infra"
repo_owner = "acme"
plugins    = "superpowers@claude-plugins-official|anthropics/claude-plugins-official"
map        = "docs/REPO-MAP.md"
rules      = "docs/CLOUD-RULES.md"
```

Trust note: `.kit.toml` rides inside the repo, so a pull request can change
these values. That is the same trust level the repo's own
`.claude/settings.json` hooks already carry, and it is why `plugins` is empty by
default. Do not point `plugins` at a marketplace the repo's contributors are not
trusted to control.

## Invariants (each one is a live failure, not a preference)

| Invariant | The failure it prevents |
|---|---|
| every path exits 0 | a non-zero exit on the cloud startup path aborts the session before Claude Code starts |
| the cloud gate is `CLAUDE_CODE_REMOTE` | a "does directory X exist" gate self-disabled the moment the session cloned that directory |
| installers gate on Linux AT the install point | a top-of-file gate makes the portable branches untestable; no gate at all installs Linux binaries into a Mac system dir with `sudo -n` |
| no `eval` over an environment variable | `eval echo ~$SUDO_USER` in a root context was a reproduced command injection |
| the dash guard uses `[ \t]`, never `\s` | `\s` crosses newlines: a dash at end of paragraph swallowed the blank line and the next heading |
| `getent passwd`, not `~$SUDO_USER` | same injection, and root's `$HOME` is not the session user's home |
| `CLAUDE_ENV_FILE` append-once | an in-process `export` dies with the hook, so an installed `op` was invisible to the next command |
| the SessionStart matcher is `startup\|resume` | without it the whole assembly re-ran on every `clear` and every compaction |
| plugins are installed imperatively | declaring them in a project's settings duplicates the record in the operator's shared per-user plugin registry |

## Test

```bash
bash lib/cloud/tests/smoke.sh    # "smoke: all N passed"
```

The suite runs on macOS with a stubbed `uname`, which proves which BRANCH the
code takes, never that the branch works. The CI matrix runs it on
`ubuntu-latest` too; that leg is what proves the install paths. Neither proves
the real cloud GitHub proxy or the real network allowlist.
