# ADR-0023: Goal-draft store is filesystem-authoritative, with an archive-on-ship lifecycle (supersedes ADR-0011's INDEX.md)

## Status: accepted (2026-05-23). Implements SPEC-037. Supersedes ADR-0011's `INDEX.md` derived-cache.

## Context

ADR-0011 set up the goal-draft store at `.claude/goals/<slug>.md` and specified a derived `INDEX.md` cache (one row per draft, rebuilt from the files). That cache was **never built**: no command writes or rebuilds it, `commands/assign.md` only said "if it exists, rebuild," and the render commands (`/kit:start`, `/kit:next`) read the filesystem directly. A documented-but-absent file is exactly the phantom feature the kit's own code-quality rules reject.

Two further gaps made the store incoherent:

1. **No lifecycle.** A draft's `status:` never advanced past `drafted`, and a shipped draft was never retired. Drafts whose `target_spec` had already SHIPPED (e.g. SPEC-024, SPEC-027, SPEC-028) kept rendering as live candidate work. The directory became a graveyard.
2. **Name collision with the registry.** The goal **draft** store (`.claude/goals/`, ADR-0011) and the cross-session running-goal **registry** (`.git/kit-goals/`, ADR-0022) share the word "goal," and nothing documented them side by side, so they read as accidental duplicates.

## Decision

- **The filesystem is the sole source of truth.** `ls .claude/goals/*.md` is authoritative; there is no derived cache. The `INDEX.md` from ADR-0011 is dropped (it was never implemented). This ADR supersedes that part of ADR-0011; the rest of ADR-0011 (the draft-store-not-a-shadow decision, the never-write-`last-goal.md` rule) stands.
- **Drafts have a lifecycle: drafted -> archived-on-ship.** A draft lives at the top level of `.claude/goals/` while its work is live. Once its `target_spec` resolves to a SHIPPED spec, it is **moved** (never deleted) to `.claude/goals/done/`, with `status:` flipped to `shipped`. The move is performed by `lib/goal-drafts.sh archive`, wired into `/kit:ship`. Because the render commands enumerate top-level `*.md` only (a non-recursive glob), an archived draft drops out of "what's active" with no filter code.
- **Move, never delete.** Archiving relocates a draft; it never removes content. A pre-existing `done/<slug>.md` is not overwritten.
- **Two stores, documented side by side.** `docs/architecture.md` "## State model" carries both the draft store and the registry in one table, with the contrast (draft = candidate work / "what's active"; registry = the cross-session lock / "what's executing now"; the slug is the shared key).

## Alternatives considered

- **Build `INDEX.md` for real.** Honors ADR-0011 literally, but adds helper bash + a test to maintain a cache the filesystem already provides for free. Rejected: the kit values minimalism and the filesystem read is O(few files).
- **Delete shipped drafts.** Smallest directory, but destructive and against the maintainer's standing rule. Rejected in favor of move-to-`done/`.
- **Rewrite ADR-0011 + SPEC-005 in place.** Would leave no trace of the reversal. Rejected: the kit supersedes decisions (ADR-0010 supersedes ADR-0002), it does not erase shipped history. ADR-0011 and SPEC-005 keep their bodies and gain a supersede annotation.

## Consequences

- The phantom `INDEX.md` is gone from the live contract; the only mentions that remain are the annotated historical records in ADR-0011 and SPEC-005.
- `.claude/goals/` reflects only live candidate work; finished drafts live under `done/` for reference.
- A new helper (`lib/goal-drafts.sh`) joins `lib/goal-registry.sh` and `lib/dispatch-gate.sh` as testable command-helper bash. Its archive trigger depends on `/kit:ship` running; if a ship is skipped, drafts simply linger until the next `archive` (idempotent), which is acceptable.
