# Spec: hello trial (unmeetable)

Generated: 2026-09-30
Status: VALIDATED
Lane: tiny
Type: spec-feature
File: `docs/specs/SPEC-900-unmeetable.md`

## Problem

Trial fixture for `/kit:execute` whole-spec dispatch. One criterion (AC-3) is false by arithmetic, so the build must end `Result: PARTIAL` and name AC-3.

## After state

- [ ] `hello.txt` exists and holds `hello`.
- [ ] `README.md` names `hello.txt`.

## Task Breakdown

- [ ] TASK-A: write `hello.txt` containing `hello`. AC-1.
- [ ] TASK-B: name `hello.txt` in `README.md`. AC-2.

## Acceptance Criteria

- [ ] AC-1: `hello.txt` exists and contains exactly `hello`.
- [ ] AC-2: `README.md` mentions `hello.txt`.
- [ ] AC-3: `[ $((2+2)) -eq 5 ]`

## Verification

```bash
bash tests/fixtures/whole-spec-dispatch/check.sh unmeetable
```

## Touches

- hello.txt
- README.md
