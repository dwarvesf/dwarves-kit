# ADR-0003: User-level install with symlinks

## Status: accepted

## Context
Kit can be installed globally (~/.claude/) or per-project (.claude/). Global means available everywhere. Per-project means committed to git, shared with team.

## Decision
Default install is user-level (~/.claude/dwarves-kit/) with symlinks to ~/.claude/commands/ and copies to ~/.claude/skills/. The kit itself is a standalone directory, not scattered across ~/.claude/.

## Alternatives considered
- Per-project install: better for team sharing but requires copying to every repo. Can add later.
- Plugin marketplace format: requires packaging as a plugin. Shipped in v1.4 as the recommended path; see ADR-0009.
- npx installer (like GSD): nice UX but adds npm dependency for installation. Bash is simpler.

## Consequences
- Commands appear as /user:think, /user:spec, etc. (not /project:think).
- Kit updates are a git pull in one directory.
- Team members must each install individually (no auto-sharing via repo).
- Can add project-level install mode later without breaking user-level installs.
