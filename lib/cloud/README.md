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
   |        [gate: CLOUD_PROVISION=1 AND CLAUDE_CODE_REMOTE=true AND Linux]
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
            [gate: CLOUD_DASH_GUARD=1 AND CLAUDE_CODE_REMOTE=true AND Linux]
            prose files only, fenced and inline code skipped
```

## Install and use

Opt-in, off by default, in two independent steps.

```bash
bash install.sh --with cloud                 # wire the hooks + the PATH CLI
bash lib/adopt.sh --with cloud <repo>        # or via /kit:adopt for a consumer repo
```

Then arm each hook on the repo's cloud environment, as an environment variable:

| Switch | Arms |
|---|---|
| `CLOUD_PROVISION=1` | the SessionStart provisioner |
| `CLOUD_DASH_GUARD=1` | the prose dash guard |

Both switches are mandatory and both default to off. `hooks/hooks.json` is the
PLUGIN manifest and is NOT filtered by the enabled module set, so on the
plugin-install path both hooks are registered for every consumer of the kit.
`CLAUDE_CODE_REMOTE` answers "is this a cloud session", never "did this project
ask for provisioning". Without the switches, a consumer who never enabled this
module would get binaries installed and prose rewritten in their cloud sessions.
Same pattern as `money-gate` (`MONEY_GATE_REPOS`) and `prose-rag`
(`PROSE_RAG_INJECT`). They are separate switches because a team can reasonably
want the provisioning and not one project's punctuation rule.

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

Both `|| true` guards are load-bearing, not decoration. A non-zero exit anywhere
in the Setup script aborts the environment build. Every `cloud` VERB exits 0 by
design, but an UNKNOWN verb exits 1, so a typo in this field would otherwise
abort the session with no session to read the error in.

## Consumer config

A project's `.kit.toml` rides inside the repo, so a pull request can change it.
Config therefore resolves in two tiers.

| Tier | Resolution | Why |
|---|---|---|
| PROJECT | `CLOUD_<KEY>` env, then the project's `.kit.toml` `[cloud]`, then the kit-root default | the value is inert data naming something INSIDE this repo, and `repo_path` enforces that |
| OPERATOR | `CLOUD_<KEY>` env, then the kit-root `kit.toml` only. A project `.kit.toml` is IGNORED | the value reaches outside the repo, selects code to run, or names a credential, so a branch under review must not be able to set it |

| Key | Tier | Default | What it drives |
|---|---|---|---|
| `map` | project | none | repo-relative routing map printed by `cloud map` |
| `rules` | project | `lib/cloud/CLOUD-RULES.md` | repo-relative cloud-rules file for this repo |
| `workspace` | operator | `$HOME/workspace` | where the session repo is linked and siblings are cloned |
| `op_version` | operator | `v2.31.1` | pinned 1Password CLI release |
| `repos` | operator | none | comma-separated sibling repos to clone: `<name>` or `<owner>/<name>` |
| `repo_owner` | operator | none | default owner for a bare name in `repos` |
| `plugins` | operator | none | behavioral plugins to install: comma-separated `<id>\|<marketplace-slug>` |
| `hooks_path` | operator | none, never auto-detected | repo-relative `core.hooksPath` to arm |
| `vault` | operator | none | vault name, reported in the canary verdict |
| `canary_ref` | operator | `op://<vault>/cloud-canary/credential` | reference proving the vault is reachable |

Example, in a consumer repo's `.kit.toml`:

```toml
[cloud]
map   = "docs/REPO-MAP.md"
rules = "docs/CLOUD-RULES.md"
```

Both project keys are PATHS, and both are resolved against the repo root by
`repo_path`, which refuses an absolute path, a leading `~`, a `..` segment, a
directory that resolves outside the repo, and a final component that is a
symlink. A refused value is reported as a `!!` line and dropped: `map` prints
nothing, `rules` falls back to the kit's own template. Naming a key "project
tier" is a comment; this check is the control.

Operator-tier keys go in the kit-root `kit.toml`, or in the cloud environment as
`CLOUD_WORKSPACE`, `CLOUD_REPOS`, `CLOUD_PLUGINS`, `CLOUD_HOOKS_PATH` and so on.
The kit-root path is pinned to the kit install the hook runs from, so
`KIT_CONFIG_ROOT` cannot redirect the operator half at a file inside the repo.

`workspace` is operator-tier because it names a directory OUTSIDE the repo and
the assemble step creates a symlink in it. A project-settable value pointed it
at `$HOME/.claude/skills`, which made a PR-authored root `SKILL.md` a live skill
in the same session, loaded immediately because the hook emits `reloadSkills`.
Constraining it to "under the home" would not have helped: that path IS under
the home. `op_version` is operator-tier because it selects a binary that is
downloaded, `chmod +x`, prepended to PATH and persisted into `CLAUDE_ENV_FILE`;
it is validated against `^v?[0-9]+(\.[0-9]+)*$` on top, because operator-tier is
not a reason to skip validating a value that lands in a URL.

Why the operator tier exists, plainly. Installing a plugin normally requires a
human on the machine to approve a project-declared plugin from an external
marketplace. A cloud VM has no human, so this module installs it non
interactively, which means that one approval step does not happen. Arming
`core.hooksPath` is the same shape from the other direction: scripts a plain
clone leaves inert become code every later git command runs. Neither may be
reachable from a file a pull request can edit, so both resolve from the
operator-owned kit-root config or the environment, and `hooks_path` is never
inferred from a `.githooks` directory found in the tree.

`repos` and `repo_owner` are operator-tier for a quieter reason: a clone runs no
code, but provisioning then NAMES the clone's `AGENTS.md` and `CLAUDE.md` to the
model as files to read, so a project-settable clone target is a prompt-injection
path into every later turn.

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
| each hook checks its own switch FIRST | the plugin manifest is not filtered by the enabled module set, so `modules.cloud = false` alone does not turn the hooks off for a plugin consumer |
| operator-tier keys skip the project overlay | a project `.kit.toml` rides inside the repo, so a branch under review could otherwise arm `core.hooksPath`, install a plugin, redirect the secret probe, choose the workspace, or clone a repo whose instruction files are then named to the model |
| a project-tier PATH resolves inside the repo or is refused | `map` and `rules` both took an absolute path, so a project value printed a file from outside the repo into model context |
| `op_version` is validated as a version | the value is interpolated into a download URL; `vEVIL/../../../../attacker-path` produced a traversal-shaped URL |
| the kit-root config path is pinned to the kit install | `KIT_CONFIG_ROOT` otherwise redirects the operator-owned half of the tier split at a file inside the repo |
| the `safe.directory` write is gated to a Linux cloud session | it writes the operator's GLOBAL `~/.gitconfig`, and a hand-run on a workstation did |
| the sibling-clone loop carries a total budget | the 60s cap bounds ONE clone; three unreachable siblings plus the gh install exceeded the SessionStart budget, which kills the whole hook |
| a `~` in a config value is expanded | a tilde read out of a file is a literal character, so `mkdir -p` silently created a directory named `~` under the repo |

## Test

```bash
bash lib/cloud/tests/smoke.sh    # "smoke: all N passed"
```

Each hook has THREE gates: its own switch, `CLAUDE_CODE_REMOTE`, and Linux. The
suite proves each one INDIVIDUALLY: neutering any single gate turns it red. An
earlier version proved only that SOME gate fired, because the OFF cases ran
without the `uname` stub, so on macOS the Linux gate short-circuited before the
cloud gate was ever read, and the suite stayed fully green with the cloud gate
deleted.

The suite runs on macOS with a stubbed `uname`, which proves which BRANCH the
code takes, never that the branch works. The CI workflow includes an
`ubuntu-latest` leg; that leg is what proves the install paths, and the workflow
is `workflow_dispatch` only, so it proves nothing until someone dispatches it.
Neither leg proves the real cloud GitHub proxy or the real network allowlist.
