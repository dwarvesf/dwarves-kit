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

IN: the provisioning engine, the VM-level installers, the `CLAUDE_CODE_REMOTE`
gate, the two cloud hooks, a portable cloud-rules template, the module wiring
(`install.sh`, `lib/adopt.sh`, `kit.toml`), and a suite that carries its verdict
into its exit code.

OUT, and deliberately left with the operator: a personal repo topology map, a
curated skill roster and its sync tool, a private vault or canary item, and any
path naming one operator's machines. Each arrives as consumer config
(`[cloud]` in the project's `.kit.toml`) or not at all.

OUT, deferred: the multi-surface `drift-check` reporter. Four of its five
surfaces audit operator curation (a skill library, a personal repo map, a
copied doc, a hand-written restatement of a personal instruction file). Only the
router-target surface is generic, and it is not worth a module on its own until
a second consumer needs it.

## Design

One subsystem module, `lib/cloud/`, with a verb dispatcher (`cloud.sh`) behind a
stable entrypoint (`bin/cloud`), plus two hooks in `hooks/`. Off by default:
`modules.cloud = false`. The hooks are additionally inert unless
`CLAUDE_CODE_REMOTE=true`, so an enabled module costs a local session two
process spawns that exit immediately.

Consumer config follows the kit's existing seam, not a new one: `--repo-root` /
`REPO_ROOT` for the repo root, `kit_config_get` over the project's `.kit.toml`
for every knob, and a `CLOUD_<KEY>` env override on top for tests and one-off
runs. No new global variable is invented.

## Invariants

Each one is a reproduced live failure. The suite asserts every row.

1. Every path on the cloud startup surface exits 0. Failures degrade to a `!!`
   line and a `CLOUD-PARTIAL` verdict.
2. The cloud gate is `CLAUDE_CODE_REMOTE`, never a directory-existence probe.
3. An installer's Linux gate sits at the point of installation, never at the top
   of the file.
4. No `eval` runs over an environment variable.
5. The dash guard rewrites prose files only, skips fenced and inline code, and
   matches horizontal whitespace (`[ \t]`), never `\s`.
6. The suite carries its failures into its exit code.

## Verification

```bash
bash lib/cloud/tests/smoke.sh
bash tests/test-meta.sh
bash tests/test-bin-forwarders.sh
bash tests/test-kit-contract.sh
bash tests/test-install-modules.sh
bash tests/test-adopt.sh
bash tests/test-config-registry.sh
```

## After state

`bash install.sh --with cloud` wires both hooks and puts `cloud` on PATH.
`bash lib/adopt.sh --with cloud <repo>` records `cloud = true` in that repo's
`.kit.toml` and merges both hook entries into its `.claude/settings.json`, so a
cloud session on that repo provisions itself with nothing typed by a human.
