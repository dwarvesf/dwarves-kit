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

| Tier | Resolver | Rule |
|---|---|---|
| PROJECT | `CLOUD_<KEY>` env, then `kit_config_get` | the key may only name something INSIDE this repo |
| OPERATOR | `CLOUD_<KEY>` env, then `kit_config_get_root` | anything that reaches outside the repo, runs code, or names a credential |

The two lists are declared once in `provision.sh`
(`CLOUD_PROJECT_KEYS` / `CLOUD_OPERATOR_KEYS`) and the suite fails if a key is
read through the wrong resolver or belongs to neither list, so the next key
cannot silently pick the wrong tier.

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
7. `repos`, `repo_owner`, `plugins`, `hooks_path`, `vault` and `canary_ref`
   resolve at the operator tier only. A project `.kit.toml` cannot set them, and
   `hooks_path` is never inferred from a directory found in the tree.
8. The suite carries its failures into its exit code, proved by a self-check
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
