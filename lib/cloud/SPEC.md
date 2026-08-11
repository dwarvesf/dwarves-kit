# SPEC: cloud-session support

Status: SHIPPED
Lane: full

## Problem

A phone-started Claude Code cloud session on any kit-adopted repo receives
nothing: no provisioning, no rules, no guards, no routing. The machinery that
solves this existed in one operator's personal repo, so exactly one repo had
cloud support and every other tenant repo had none. The kit is already cloned
into every cloud VM and every tenant repo already runs `kit:adopt`, so the kit
is the right home for the generic half.

## Scope

IN: the provisioning engine (`lib/cloud/`), the VM-level installers, the
`CLAUDE_CODE_REMOTE` gate, the two hooks (`hooks/cloud-*.sh`), their
registration in BOTH distribution manifests (`settings.json` for the bash
installer, `hooks/hooks.json` for the plugin), a portable cloud-rules template,
the module wiring (`install.sh`, `lib/adopt.sh`, `kit.toml`,
`lib/config/module-registry.md`), the doc tables, and a suite that carries its
verdict into its exit code.

OUT, and deliberately left with the operator: a personal repo topology map, a
curated skill roster and its sync tool, a private vault or canary item, and any
path naming one operator's machines. Each arrives as consumer config
(`[cloud]` in the project's `.kit.toml`, or a `CLOUD_<KEY>` environment
variable) or not at all.

OUT, deferred: the multi-surface `drift-check` reporter. Its five surfaces are
SKILLS (a curated skill roster against a personal skill library), COPIED DOC (a
copy of one chezmoi-managed reference file), ROUTER TARGETS (the rules file's
implementation-playbook table against the playbook directory), REPO MAP (a
hand-maintained personal repo topology against one workstation's disk), and
RULES FRESHNESS (a sha marker over one operator's personal instruction file).
Four of the five audit operator curation and cannot exist in the kit. Only
ROUTER TARGETS is generic, and a single-surface checker is not worth a module
until a second consumer needs it. `cloud rules` and `cloud map` already fail
loudly when their target file is absent, which is the cheap half of that
surface.

## Design

One subsystem module, `lib/cloud/`, with a verb dispatcher (`cloud.sh`) behind a
stable entrypoint (`bin/cloud`), plus two hooks in `hooks/`.

A module is the only shape that works. A command is unreachable: a cloud VM
receives no `/kit:*` slash commands, because the plugin that supplies them is
enabled in user settings that never reach the VM. A skill has no automatic
SessionStart or PostToolUse trigger, and both jobs here must fire without a
human or a model deciding to invoke them.

### Two distribution paths, two different off-switches

| Path | How the hooks arrive | What gates them |
|---|---|---|
| `install.sh` / `lib/adopt.sh` | `settings.json`, FILTERED by the enabled module set | `modules.cloud`, then the switches below |
| Claude Code plugin | `hooks/hooks.json`, a static manifest that is NOT filtered | the switches below only |

`modules.cloud = false` is therefore only half an off-switch, and only on the
installer path. Each hook additionally requires its own environment switch,
checked FIRST, the same shape `money-gate.sh` and `prose-rag.sh` already use:

| Hook | Switch | Why it is separate |
|---|---|---|
| `cloud-session-start.sh` | `CLOUD_PROVISION=1` | it installs binaries and clones repos; no VM should get that unasked |
| `cloud-dash-guard.sh` | `CLOUD_DASH_GUARD=1` | it REWRITES files to a house punctuation style, which is taste, not correctness |

### Consumer config

Config follows the kit's existing seam, not a new one: `--repo-root` /
`REPO_ROOT` / `CLAUDE_PROJECT_DIR` for the repo root, and the `lib/config`
resolver for values. It resolves in two tiers, because a project's `.kit.toml`
rides inside the repo and a pull request can therefore set it.

| Tier | Keys | Resolver | Rule |
|---|---|---|---|
| PROJECT | `map`, `rules` | `CLOUD_<KEY>` env, then `kit_config_get` | the key may only name something INSIDE this repo, and `repo_path` enforces it |
| OPERATOR | `workspace`, `op_version`, `repos`, `repo_owner`, `plugins`, `hooks_path`, `vault`, `canary_ref` | `CLOUD_<KEY>` env, then `kit_config_get_root` | anything that reaches outside the repo, runs code, or names a credential |

The two lists are declared once in `provision.sh`
(`CLOUD_PROJECT_KEYS` / `CLOUD_OPERATOR_KEYS`) and the suite fails if a key is
read through the wrong resolver or belongs to neither list.

**That lint checks CONSISTENCY, not CORRECTNESS**, and the earlier claim that it
stops the next key picking the wrong tier was wrong. It proves each key is read
through the resolver its own list names; it cannot know whether the list is the
right one. Three keys sat in the PROJECT list, passed the lint on every run of
this branch, and each reached outside the repo: `workspace` accepted any
absolute path and pointed the assemble symlink at `$HOME/.claude/skills`, which
turned a PR-authored root `SKILL.md` into a live skill in the same session;
`map` and `rules` accepted any absolute path and printed a file from outside the
repo into model context; `op_version` selected a downloaded binary.

The correctness half is therefore enforced in code, per key class:

| Enforcement | Applies to | What it does |
|---|---|---|
| tier | every key | operator keys skip the project overlay entirely |
| `repo_path` | every PROJECT-tier PATH | resolves against the repo root and REFUSES an absolute path, a leading `~`, a `..` segment, a directory that resolves outside the repo, or a final component that is a symlink |
| shape validation | `op_version` | must match `^v?[0-9]+(\.[0-9]+)*$` before it is interpolated into a download URL |

The kit-root config path is PINNED to the kit install `provision.sh` belongs to.
`kit-config.sh` otherwise takes it from `KIT_CONFIG_ROOT`/`DWARVES_KIT`, so the
operator-owned half of the split could be redirected at a file inside the repo,
which would have made the tier split decorative.

### What the operator tier trusts

The environment. `CLOUD_<KEY>` sits ABOVE both config tiers for operator keys,
and `CLOUD_PROVISION` (the master switch for the whole module) is env-only with
no config channel at all. The environment is therefore the trust anchor, not
just an override.

That is deliberate. In a cloud VM the kit-root `kit.toml` arrives inside the git
clone, so the environment's variables are the only per-environment operator
channel that exists. Removing the env tier for operator keys while the master
switch stays env-read would close nothing: an actor who can set environment
variables sets `CLOUD_PROVISION=1` and owns the module regardless of where the
individual keys resolve.

UNVERIFIED, and it decides whether this trust holds: whether a repo-committed
`.claude/settings.json` `env` block reaches a hook subprocess in a cloud VM. If
it does, the environment is repo-writable and this whole layer needs a
kit-wide env-hardening pass, not a cloud-local one. Only a real cloud VM answers
it. Recorded in `docs/proof-of-done.md` under "Not proved here".

## Invariants

Each one is a reproduced live failure or a review finding. The suite asserts
every row.

1. Every path on the cloud startup surface exits 0. Failures degrade to a `!!`
   line and a `CLOUD-PARTIAL` verdict.
2. The cloud gate is `CLAUDE_CODE_REMOTE`, never a directory-existence probe.
3. Each hook's own master switch is checked BEFORE the cloud gate, because the
   plugin manifest is not filtered by the enabled module set.
4. An installer's Linux gate sits at the point of installation, never at the top
   of the file.
5. No `eval` runs over an environment variable.
6. The dash guard rewrites prose files only, skips fenced and inline code, skips
   a file with unbalanced fences whole, and matches horizontal whitespace
   (`[ \t]`), never `\s`.
7. `workspace`, `op_version`, `repos`, `repo_owner`, `plugins`, `hooks_path`,
   `vault` and `canary_ref` resolve at the operator tier only. A project
   `.kit.toml` cannot set them, and `hooks_path` is never inferred from a
   directory found in the tree.
8. A PROJECT-tier path resolves INSIDE the repo root or it is refused, and the
   refusal is explained. Naming the tier is not the control; `repo_path` is.
9. `op_version` matches a version shape before it reaches a download URL.
10. Each hook's THREE gates (its switch, `CLAUDE_CODE_REMOTE`, Linux) is proved
    individually. Neutering any one of them turns the suite red. The suite used
    to prove only that SOME gate fired.
11. The suite carries its failures into its exit code, proved by a self-check
    that re-invokes the suite with one planted failure.

## Verification

```bash
bash lib/cloud/tests/smoke.sh
bash tests/test-meta.sh
bash tests/test-hooks.sh
bash tests/test-bin-forwarders.sh
bash tests/test-kit-contract.sh
bash tests/test-install-modules.sh
bash tests/test-adopt.sh
bash tests/test-config-registry.sh
shellcheck -S warning lib/cloud/*.sh lib/cloud/tests/smoke.sh hooks/cloud-*.sh bin/cloud
```

Recorded runs, pinned to a commit: `docs/verification/cloud-session-support.md`.

## After state

`bash install.sh --with cloud` wires both hooks and puts `cloud` on PATH.
`bash lib/adopt.sh --with cloud <repo>` records `cloud = true` in that repo's
`.kit.toml` and merges both hook entries into its `.claude/settings.json`. With
`CLOUD_PROVISION=1` set on the repo's cloud environment, a cloud session then
provisions itself with nothing typed by a human.
