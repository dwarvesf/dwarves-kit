# ADR-0011: Goal-draft store beside the built-in /goal (not a shadow)

## Status: accepted (2026-05-21).

## Context
The Claude Code built-in `/goal` writes a single `.claude/last-goal.md` and installs a Stop hook from it. It is single-slot by design: brainstorming a second goal overwrites the first. There is no way to hold several candidate goals while the kit's orchestration spine (SPEC-006) picks one to activate. The user-level `goal-craft` skill crafts the text but explicitly does not shadow `/goal`.

The kit needs a place to accumulate goal *drafts* without fighting the built-in's single active slot, and without pretending to own an undocumented built-in internal (`last-goal.md`).

## Decision
A draft store at `.claude/goals/`, beside (not replacing) the built-in's single active slot:

```
.claude/goals/
  <slug>.md    one goal draft. Frontmatter: slug, id, target_spec, status, created
               (all five pinned by SPEC-006 DEC-020).
               Body = the goal text to run through an activator.
  INDEX.md     a DERIVED cache (one row per draft), rebuilt from the *.md files.
               The filesystem (ls .claude/goals/*.md) is the source of truth.
.claude/last-goal.md   the built-in /goal's single active slot. The kit NEVER
                       writes, parses, or rewrites this file.
```

Rules:
- **The kit owns the draft store, not activation.** It writes `.claude/goals/<slug>.md` and the derived `INDEX.md`. It never writes `last-goal.md`. "Activating" a draft means the maintainer runs a goal-loop *activator* (the built-in `/goal` if present, else the `ralph-loop` plugin or the `goal-craft` skill) with the draft's body; the activator writes `last-goal.md` and installs the Stop hook.
- **The activator is a precondition with graceful degradation.** The kit detects which activator is available and feeds it the draft. If none is present, the drafts still work as plain reusable files (paste the body anywhere); the kit loses only one-step activation, not the store.
- **Brainstorm many, one active.** Drafts accumulate; the built-in's single active slot is respected, not fought. Each draft carries a `target_spec`/`id`, the seam SPEC-006 uses.
- **Gitignored.** `.claude/` is already ignored (`.gitignore:10`), so drafts are per-machine and never shared (half-baked goals are not artifacts).

The `/user:goals` command (list/new/switch) and the `/user:start`/`/user:next` rendering of the queue + drafts are NOT part of this ADR; their consumer (the orchestration spine) lives in SPEC-006.

## Alternatives considered
- **Reimplement / shadow `/goal`:** breaks the no-shadow rule; the kit would own a Stop-hook loop duplicating the built-in. Rejected.
- **Make the kit write `last-goal.md`:** treats an undocumented built-in internal as a public API the kit cannot version. Rejected (the kit never touches it).
- **A single draft file:** same single-slot clobber the built-in already has. Rejected (a directory holds many).
- **Commit drafts to git:** half-baked goals are not shared artifacts; per-machine is correct. Rejected.

## Consequences
- The kit gains a multi-draft store without fighting or shadowing the built-in.
- Activation depends on an external activator the kit cannot version (built-in `/goal` / `ralph-loop` / `goal-craft`); if that contract changes, activation degrades to manual and the drafts still work as files. Mitigated by never reading/writing `last-goal.md`.
- `INDEX.md` can diverge from the files (a slash command is not transactional); it self-heals on the next rebuild because the filesystem is authoritative.
- `switch` semantics (SPEC-006) are unsafe mid-loop: re-running `/goal` while a Stop-hook goal is iterating re-points the active slot; the prior goal's progress is not migrated, only its draft is preserved. SPEC-006 must warn.

## Source
SPEC-005 Part 2 (the draft-store contract; DEC-003 + DEC-004 the no-`last-goal.md` rule, DEC-016 INDEX derived cache, DEC-005 gitignore). The built-in `/goal` + the user-level `goal-craft` skill it wraps. Activator detection: SPEC-005 DEC-018 / SPEC-006.
