# ADR 0005: the curator never deletes (`git mv` archive + restore)

**Date:** 2026-06-19
**Status:** accepted (SPEC-103 TASK-012)

## Context

The curator's job is to consolidate a sprawling skill library: fold narrow siblings into umbrellas
and remove stale/superseded skills. "Remove" is the dangerous word, an LLM-proposed plan deciding to
delete a skill the operator still wanted would be unrecoverable.

## Decision

The maximum destructive action the curator can take is **archive**, implemented as `git mv
skills/<name> skills/_archive/<name>`. Never `rm`. `cc-improve restore <name>` reverses it.
`absorbed_into` is recorded in `_archive/manifest.tsv` so references stay coherent. A wrapper guard
refuses to archive a skill whose frontmatter has `pinned: true` / `cc-si-protected: true`,
independent of what the model's plan says. `tests/test-curate.sh` greps the curate code path and
asserts no `rm` command exists.

## Alternatives considered

- **`rm` of stale skills.** Rejected: unrecoverable; an LLM-proposed deletion is too high-stakes.
- **Trust the model to only propose safe archives.** Rejected: the guard (pinned-skip, never-rm) is
  a wrapper invariant, not a prompt instruction, for the same reason as ADR-0001.

## Trade-offs

`_archive/` grows over time (you periodically prune it by hand if you want). On a non-git
`~/.claude/skills/`, archive falls back to plain `mv` + a manifest line + a WARN: still recoverable
via `restore`, but without git history behind the move. Accepted; RUNBOOK incident 8 covers it.

## Open questions

Whether to add a `cc-improve prune-archive` (operator-confirmed hard delete of long-archived skills)
is deferred; for now `_archive/` is append-only.
