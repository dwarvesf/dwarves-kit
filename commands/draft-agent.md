---
description: "Meta-agent agent-builder. From a one-line description, generates a new subagent definition OR a mega-goal sub-goal file and (by default) installs the subagent so it is dispatchable next session. --draft stops at a staged draft for review."
---

Dispatch the `meta-agent` to generate a new subagent definition (or a mega-goal sub-goal file) from a description, then INSTALL it by default so it is runnable at runtime. Installing is local: the agent goes live in your `~/.claude/agents/` on the next session and lands in the repo working tree; it only reaches teammates if you commit + merge it (that stays PR-gated). `--draft` keeps the old behavior: stop at a staged draft, install nothing.

A sub-goal file (Mode B) is NOT installable (it is project content, not an agent); for Mode B this command always behaves as `--draft` and just writes the file to the goals staging path.

## Usage

`$ARGUMENTS` is the description, optionally prefixed with `--draft` and/or a mode:

- `/kit:draft-agent agent: <one-line role>` , generate + INSTALL a subagent (default).
- `/kit:draft-agent --draft agent: <one-line role>` , generate a staged draft only, no install.
- `/kit:draft-agent subgoal: <one-line unit of work>` , draft a mega-goal sub-goal file (never installed).
- `/kit:draft-agent <description>` , no mode prefix: the meta-agent infers the mode and says which it picked.

## Steps

1. Parse `--draft` (if present), the mode (or let the agent infer it), and the description from `$ARGUMENTS`.

2. Dispatch ONE `meta-agent` subagent. Give it the mode, the description, and a staging write-path (default `drafts/` at the repo root; create it if missing). It writes the artifact there with the DRAFT marker on line 1 and returns a bounded summary (mode, path, name/tools/model or the sub-goal `Done =`).

3. **If `--draft`, or the mode is `subgoal`:** show the summary, open the staged file for review, and STOP. Nothing is installed.

4. **Otherwise (default, mode `agent`): INSTALL it so it is dispatchable.** Do this as the main agent (you have the tools the subagent does not):
   1. Read the staged draft. Strip the first-line DRAFT marker.
   2. Write it to `agents/<name>.md` (the repo source of truth), where `<name>` is the frontmatter `name:`.
   3. Roster sync (REQUIRED , `test-meta.sh` fails closed otherwise): add a `| \`<name>\` | ... |` row to `MANUAL.md`'s agent table, a row to the `docs/architecture.md` "Command and agent V-phase inventory" table, and (only if you also added a command) the `README.md` command rows. Match the existing row formats.
   4. Run `bash tests/test-meta.sh`. It MUST pass (it lints the new agent's frontmatter + the cross-refs). If it fails, fix the roster rows until green; do not leave a half-installed agent.
   5. Activate it for runtime: `cp agents/<name>.md ~/.claude/agents/<name>.md` (the dir Claude Code scans at session start). It is dispatchable on your **next session / reload**, not mid-conversation (CC discovers agents at startup).
   6. **Print, loudly:** the agent `name`, its **granted tools** and `model`, "live next session", and "undo: `rm ~/.claude/agents/<name>.md` (+ revert the repo rows)". The granted tools are the one thing to eyeball, since default-install skips the read-before-live gate.

5. **Team propagation is still gated:** the repo changes from step 4 are uncommitted working-tree edits. They only reach teammates when you commit + open a PR, which is reviewed normally. Local immediacy, git-gated sharing.

## When NOT to use

- Writing a skill (use `superpowers:writing-skills` / `extract-workflow`); this builds kit subagents + sub-goal files, not skills.
- Unattended fleet generation: each run installs a live agent locally, so run it deliberately, not in a loop.

## Cleanup

`--draft` / `subgoal`: the only artifact is the staged file; delete it to undo. Default install: undo with `rm ~/.claude/agents/<name>.md` (runtime copy) and revert the `agents/<name>.md` + roster rows in the repo working tree (nothing is committed until you choose to).
