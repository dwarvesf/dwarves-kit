# Quickstart

Use this when you have never run the kit and want one full lap on your own repo: install, adopt, a tiny change, a specced change, and landing the session. Plan on about an hour.

![What /kit:adopt writes into a repo: an AGENTS.md pointer, a CLAUDE.md loader block, a WORKFLOW.md pointer, the docs/verification/README.md proof marker, and .kit.toml](../figures/adopt.png)

_Figure: adopt adds five small files to your repo and never overwrites one you already have._

## 1. Install

In a Claude Code session:

```
/plugin marketplace add dwarvesf/dwarves-kit
/plugin install kit@dwarves-marketplace
```

The plugin registers every hook, so nothing else needs wiring. Start a new session after you install, so the hooks load.

## 2. Adopt your repo

Open your repo and run `/kit:onboard`. It detects how the kit is installed, previews every write, and asks before it changes anything. A decline changes nothing.

Under the hood it calls the kit's `lib/adopt.sh`. This preview came from a throwaway git repo on a machine with no plugin. With the plugin installed, the last-but-one line says adopt leaves the repo's Claude settings alone, because the plugin already registers the hooks:

```
$ bash lib/adopt.sh --dry-run .
adopt: would create AGENTS.md (pointer)
adopt: would write WORKFLOW.md pointer
adopt: would append the operate-contract block to ./CLAUDE.md
adopt: would create docs/verification/README.md (proof marker)
adopt: would seed a starter .kit.toml (modules: kit-root defaults)
adopt: would wire ./.claude/settings.json for modules: board (hooks:backlog-stage.sh board-row-gate.sh)
adopt: --dry-run for . (changes above)
```

Run for real, adopt prints a wiring line and `adopt: . (updated)`. A second run prints `adopt: . (already adopted, no-op)`, so it is safe to repeat.

What you now have:
- Of the optional modules, only `board` is on. Session capture, advisor hints and the rest are opt-in; `/kit:onboard` lists the choices.
- Two quality gates are on: `proof_of_done` and `lane_gates` in `.kit.toml`. To turn one off, set it to `false` there and commit.

## 3. Start a session

Run `/kit:start` at the top of every session. It reads the repo and names the next command. On a repo with no spec it says:

```
[dwarves-kit] | next: no spec found; state the task (the kit routes it), or /kit:think then /kit:spec
```

## 4. Make a tiny change

Say what you want in plain words: "fix a typo in the README". The kit sizes the work first. The classifier answers:

```
$ bash bin/classify lane explain "fix a typo in the README"
tiny
reason: pure cosmetic
flags: tiny
```

The tiny lane runs two phases, build and review, so a small change stays light. Make the edit on a branch, then run `/kit:review` and `/kit:ship`. Ship checks the review verdict, bumps the version, writes the commit and opens the PR. You never push to the default branch; the `safety-gate` and `ship-gate` hooks refuse it.

## 5. Make a specced change

A change that adds behavior takes the normal lane. The classifier answers `normal` for "add a --version flag to the CLI". Walk the phases:

1. `/kit:think` asks six forcing questions about the idea. Answer them.
2. `/kit:spec` writes the contract to `docs/specs/SPEC-NNN-<slug>.md`, with a `Lane:` line.
3. `/kit:execute` runs one builder against the spec. Read-only verifiers then check every task. A fix-agent retries a fixable failure up to two times, then stops and asks you.
4. `/kit:review` writes a `## Review` verdict into the spec: `SHIP`, `FIX THEN SHIP` or `DO NOT SHIP`.
5. `/kit:ship` refuses `DO NOT SHIP`, then commits and opens the PR.

If a gate has not run, the push stops with a message like this:

```
BLOCKED: ship-gate. The 'normal' lane requires gates that have not run for spec '<slug>':
  ...
Run the missing gate(s), or log an explicit override (recorded for audit):
```

Run the gate it names, or see [`guides/gates-and-proof.md`](guides/gates-and-proof.md).

## 6. Land the session

After the PR is up, run `/kit:wrap`. It flips board rows, merges your own green PRs, checks the deploy, removes finished worktrees and branches, and prints one report that opens with what needs you (shortened here):

```
## Wrap: <session slug>

✅ **Needs you:** NOTHING

**What happened**
**Shipped**
| Repo | PR | Merge | Deploy |
**Left alone:**
```

Detail for every step: [`guides/wrap.md`](guides/wrap.md).

## When it breaks

| You see | Do this |
|---|---|
| A hook does not fire | Start a new Claude Code session; hooks load at session start |
| `BLOCKED: ship-gate.` on push | Run the gate it names, or follow [`guides/gates-and-proof.md`](guides/gates-and-proof.md) |
| `/kit:onboard` says the kit is not installed | Run the two `/plugin` commands in step 1, then onboard again |
| Anything else | Turn on `DWARVES_KIT_DEBUG=1`, then read [`MANUAL.md`](MANUAL.md) "Troubleshooting and recovery" |

## Next

- [`guides/spine.md`](guides/spine.md): the map from "what should I do" to shipped.
- [`MANUAL.md`](MANUAL.md): every command, agent and recovery path.
- [`../AGENTS.md`](../AGENTS.md): the contract an agent follows in an adopted repo.
