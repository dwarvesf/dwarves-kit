# Spec: fixture -- with a References field, obvious (non design-bearing) spec
Generated: 2026-07-04
Status: DRAFT
Lane: normal
References: `tools/spec-to-cli/bin/api-port` `--format json` flag , imitate its flag-parsing +
the shape of its JSON emitter (one object per record, newline-delimited), not its auth handling.
Design-bearing (fixture declaration): no

## Problem

Add a `--json` output flag to the `witr` CLI so its process-ancestry output can be piped into
`jq`. No new component, no control-flow change, no schema, no external integration, no
irreversible choice, and only one obvious way to do it.

## Solution

### Approaches considered
Only one viable approach: add a `--json` flag that switches the existing table renderer to a
JSON emitter using the same underlying record struct.

### Chosen approach + why
The only approach: reuse the existing record struct, add a second renderer. Rejected
alternatives: none exist, this is additive output-format work.

### Extensibility & boundaries
N/A -- an output-format flag does not change what happens when any dimension grows.

### Architecture
See `## Design` below.

## Design
obvious: pure additive output-format flag, no new component/control-flow/schema/integration/
irreversible choice, and no second viable approach -- collapses per ADR-0031 §1.

## Technical Design

### API changes
`witr <name> --json` emits newline-delimited JSON records instead of the table; the table
format stays the default.

## After state
- [ ] `witr --json` emits valid newline-delimited JSON; `witr` with no flag is unchanged.

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria

## Verification
`echo fixture-only, no real command`

## Edge Cases
1. `--json` combined with `-t`/`--verbose`: the tool errors, naming the conflict.

## Out of Scope
- Nothing; this is a test fixture for `tests/test-references-field.sh`, not a real spec.

## Decision Log
- DEC-001: fixture only.

## Open questions
(none)
