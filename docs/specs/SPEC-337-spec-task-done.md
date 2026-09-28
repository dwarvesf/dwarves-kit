# SPEC-337: a `spec task-done` verb for the step 2e edits

**Status:** VALIDATED
Lane: normal
Type: spec-feature
**Proof:** `docs/verification/spec-task-done.md`; `tests/test-spec-task-done.sh`.

## Problem

After each PASS verdict, `/kit:execute` step 2e checks the task off in the spec and appends a verification-log entry to `docs/verification/<slug>.md`. No tool makes these edits. One session made them eight times by hand with python heredocs, and the checked-off lines in `docs/specs/` already carry four different shapes.

## Contract

- `spec.sh task-done <spec-path> <TASK-ID> --commit <sha>` rewrites the one unchecked line `- [ ] <TASK-ID>...` as `- [x] <TASK-ID> (DONE, commit <sha>, verified)...` and keeps its indent and trailing text.
- The ID match is exact: `TASK-1` never matches `TASK-10`.
- A missing ID, an already-checked ID, or two unchecked lines for one ID exits 1 with a named error, and neither file changes.
- `--verify-log <path>` with `--command`, `--exit`, `--excerpt`, `--verdict`, and optional `--reaudit` appends a `## <TASK-ID> <title>` entry with the Command, Exit, Output (excerpt), and Verdict fields of the `docs/verification/README.md` run shape, plus an optional Re-audit field. The verb creates the file with a `# Verification log` header when it is absent.
- The verb never commits. The caller commits both paths.
- `commands/execute.md` step 2e names the verb in one sentence.

## Design

obvious: `spec.sh` stays a pure forwarder; a sibling `spec-task-done.sh` owns the logic, like `spec-next.sh` and `spec-index.sh`. One awk pass counts and flips the line by a prefix compare, so an ID needs no regex escaping. The script validates every argument before it writes either file, and replaces the spec by an atomic rename of a mode-preserving copy.

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1 | `lib/spec/spec-task-done.sh`, `lib/spec/spec.sh`, `tests/test-spec-task-done.sh`, `commands/execute.md`, `lib/README.md` | the test suite is green; a negative control on the ID match turns it red |

## Test plan

| Case | Expected |
|---|---|
| flip among several | only the named line changes; `TASK-10` and an indented `TASK-3` stay unchecked |
| missing ID | exit 1, `not found`, spec unchanged |
| already checked | exit 1, `is already checked`, spec unchanged |
| log created | header plus one entry with Command, Exit, Output (excerpt), Verdict, Re-audit |
| log appended | a second entry, header once, Re-audit only when given |
| log fields missing | exit 1 before any write |
| two unchecked lines for one ID | exit 1, `more than one unchecked line`, spec unchanged |
| file mode | the flip keeps the spec's mode and leaves no temp file |
| fence in excerpt | a four-backtick fence wraps the excerpt |

## Verification

`bash tests/test-spec-task-done.sh` exits 0.

## After state

`/kit:execute` step 2e runs one command per task instead of hand edits, and every checked-off line has one shape.

## Decision Log

- The step 2e example line now shows `- [x] TASK-A (DONE, commit abc1234, verified): ...`, the shape the verb writes and the most common shape in recent specs. The old example `-- DONE (commit: ...)` matched no line in `docs/specs/`.
- No existing test covered `spec.sh` itself (`test-spec-index.sh` and `test-spec-reserve.sh` each pin one sibling script), so the cases live in a new `tests/test-spec-task-done.sh` in the same harness.
