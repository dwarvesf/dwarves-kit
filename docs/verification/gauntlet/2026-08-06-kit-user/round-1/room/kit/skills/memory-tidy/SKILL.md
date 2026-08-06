---
name: memory-tidy
description: Use when auditing, consolidating, or cleaning a repo's .claude/memory store, "dọn memory", "memory tidy", the biweekly memory audit, duplicate or stale memory notes, MEMORY.md index drift (notes missing from the index, index entries with no file), or when a scheduled run asks for the memory-tidy audit of a repository. NOT for the built-in machine-local auto-memory under ~/.claude/projects (not git-tracked, no PR gate) and NOT for editing a single note (just edit it).
disable-model-invocation: false
---

# Memory tidy

## Overview

Audit a repo's git-tracked `.claude/memory/` store and ship the cleanup as a PR. Core principle: **every verdict cites checkable evidence, and deletions reach main only through a PR merge**, the PR is the operator's approval gate, so the audit itself never needs to ask permission.

This is the judgment half of the kit's memory plane. The mechanical half is `stats memory-sweep` (lib/stats, SPEC-136): a read-only scanner that never writes. This skill consumes its output and is the only path that edits a store, always behind a PR.

## Process

1. **Branch in a worktree first** (native worktree tool). All edits and deletions ride this branch. Touching the store on the current branch is the failure this skill exists to prevent.

2. **Mechanical pre-pass.** Run `uv run stats memory-sweep` from the kit's `lib/stats/` and filter its JSON for this repo's store: dead path refs per note, stale index entries. Always also diff both directions: the note files on disk vs the entries in `MEMORY.md` (files not indexed are invisible to sessions; entries with no file are ghosts).

3. **Fan-out judgment.** Split the notes into 2-4 subsystem clusters (roughly one cluster per 40 notes; a tiny store is audited directly) and dispatch parallel read-only agents. Each agent reads every note in its cluster fully and returns, per note: a 1-line gist plus one verdict:

   | Verdict | Required evidence |
   |---|---|
   | KEEP | distinct fact, referents spot-checked alive |
   | MERGE into `<sibling>` | quote the overlapping claim from both notes |
   | STALE | concrete reason: referenced path tested and gone, superseded by a NAMED doc/ADR/newer note, the event concluded (PR merged, tool graduated), or the rule now codified verbatim in an always-loaded file (CLAUDE.md) |
   | UNSURE | what only the operator can answer |

   A verdict with no checkable evidence is not actionable: re-check it or downgrade to UNSURE. UNSURE notes are never deleted; list them in the report.

4. **Danger check.** A note whose recommended fix contradicts current policy is worse than stale, someone may follow it. Fold its still-true diagnostics into the policy-carrying note, then delete it, and say so in the PR body.

5. **Apply.** Merges preserve incident detail and dates. Fix path-drift and dangling `[[wikilinks]]` in surviving notes. Before deleting any note, grep the store for references to its name and rewrite them.

6. **Rebuild the index.** Every remaining note gets one short line in `MEMORY.md` derived from its frontmatter `description`. Verify: entry count equals note count, and a grep for every deleted note's name returns nothing.

7. **Ship.** Follow the repo's own session-close conventions (lab log, backlog rows, proof/gate ledger, whatever that repo's CLAUDE.md requires), commit, push, open a PR whose body lists each removal with its reason. If nothing needed changing, create no branch and report CLEAN.

## Red flags

- Editing or deleting notes without the worktree branch: stop, branch, start over.
- "Obviously stale" with no tested referent.
- Keeping a doubtful note because deleting feels safer: the honest form is UNSURE + operator list.
- Hand-editing index lines instead of deriving them from frontmatter.
