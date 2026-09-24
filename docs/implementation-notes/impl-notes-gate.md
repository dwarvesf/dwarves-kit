# Implementation notes -- impl-notes-gate

Deltas from SPEC-311. Nothing here repeats what the spec states.

## 2026-09-24 Fixture edits take real notes files, not the override
- Context: T1b had to make the existing full-lane pass-path fixtures green again.
- Decision/Change: `test-ship-gate-fail-closed.sh` commits `<slug>.md`; `test-ship-gate-coverage-map.sh` commits `SPEC-001-<slug>.md` through a `notes_for` helper. Both hold the zero-deviation line.
- Why: a real file keeps those suites on the pass path the rule expects, and the coverage-map fixtures exercise the spec-basename name form for free.
- Alternatives considered: recording `override <slug> impl-notes` in each fixture's gate loop (rejected: it would hide a regression in the file check behind the override).

## 2026-09-24 The codex trust pin moved with the hook
- Context: `hooks/codex-hooks.json` pins the sha256 of `hooks/ship-gate.sh`.
- Decision/Change: ran `bash lib/codex/repin.sh`, which rewrote the one pin.
- Impact: not named in the spec's task list; any edit to the hook needs it.

## 2026-09-24 Pre-existing red suite
- `tests/test-advisor.sh` AC3 fails on `commands/mega.md` wording ("convergence gate dispatches advisor"). This branch does not touch `mega.md` or that suite; left alone.

## 2026-09-24 Review warning accepted
- Context: the fresh review noted that the title filter drops only lines starting `# ` with a space.
- Decision/Change: kept. A `#Notes` title with no space counts as content and passes.
- Why: the rule targets a missing or empty file, the SPEC-310 incident; policing title spelling adds a false-block risk for no gain.
