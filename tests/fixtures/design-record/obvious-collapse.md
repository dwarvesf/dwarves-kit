# Spec: fixture -- obvious (non design-bearing) spec, Design block collapses
Generated: 2026-07-03
Status: DRAFT
Lane: normal
Design-bearing (fixture declaration): no

## Problem

Rename the `--dry-run` CLI flag to `--plan` across the `spec-to-cli` tool for consistency with
its sibling tools. No new component, no control-flow change, no schema, no external
integration, no irreversible choice, and only one obvious way to do it.

## Solution

### Approaches considered
Only one viable approach: a find-and-replace of the flag name across the CLI parser, its help
text, and its tests. There is no second reasonable way to rename a flag.

### Chosen approach + why
The only approach: rename in place. Rejected alternatives: none exist, this is a pure rename.

### Extensibility & boundaries
N/A -- a flag rename does not change what happens when any dimension grows.

### Architecture
See `## Design` below.

## Design
obvious: pure rename of an existing CLI flag, no new component/control-flow/schema/
integration/irreversible choice, and no second viable approach -- collapses per ADR-0031 §1.

## Technical Design

### API changes
`--dry-run` -> `--plan` (same behavior, new name; old name kept as a deprecated alias for one
release).

## After state
- [ ] `--plan` is the documented flag name; `--dry-run` still works but warns it is deprecated.

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria

## Verification
`echo fixture-only, no real command`

## Edge Cases
1. A user passes both `--dry-run` and `--plan`: the tool errors, naming the conflict.

## Out of Scope
- Nothing; this is a test fixture for `tests/test-design-record.sh`, not a real spec.

## Decision Log
- DEC-001: fixture only.

## Open questions
(none)
