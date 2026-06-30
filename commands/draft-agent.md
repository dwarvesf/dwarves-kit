---
description: "Gated meta-agent drafter. From a one-line description, drafts a new subagent definition OR a mega-goal sub-goal file as a DRAFT for review. Never installs."
---

Dispatch the `meta-agent` to draft a new agent definition or a mega-goal sub-goal file from a description. The output is always a DRAFT, written to a staging path, marked "review before use", and never installed into `agents/` or a live `goals/` dir. Installing (moving the file + adding the MANUAL.md row) is your gated step afterward, not the agent's.

## Usage

`$ARGUMENTS` is the description, optionally prefixed with a mode:

- `/kit:draft-agent agent: <one-line role>` , draft a subagent definition.
- `/kit:draft-agent subgoal: <one-line unit of work>` , draft a mega-goal sub-goal file.
- `/kit:draft-agent <description>` , no prefix: the meta-agent infers the mode and tells you which it picked.

## Steps

1. Parse the mode (or let the agent infer it) and the description from `$ARGUMENTS`.

2. Dispatch ONE `meta-agent` subagent. Give it: the mode, the description, and an explicit staging write-path (default `drafts/` at the repo root; create it if missing). Tell it NOT to write into `agents/`, `commands/`, or any live `goals/` dir.

3. When it returns, show its bounded summary: mode, draft path, the frontmatter it produced (name/tools/model) or the sub-goal's `Done =`, and the "review before installing" line. Then open the draft for the user to read.

4. **Stop at the draft.** Do not install. If the user then says "install it", that is a separate, explicit action: move the file into `agents/` (or `goals/`), add the `MANUAL.md` row for an agent (the `test-meta.sh` MANUAL cross-ref requires it), strip the DRAFT marker, and run `bash tests/test-meta.sh` to confirm the lint passes.

## When NOT to use

- Writing a skill (use `superpowers:writing-skills` / `extract-workflow`); this drafts kit subagents + sub-goal files, not skills.
- Auto-generating a fleet of agents unattended; the review gate is the point.

## Cleanup

The only artifact is the draft file under `drafts/` (or the staging path you gave). Delete it to undo. Nothing is installed, no registry is touched, until you take the explicit install step.
