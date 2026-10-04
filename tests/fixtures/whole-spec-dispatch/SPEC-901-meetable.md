# Spec: hello trial (meetable)

Generated: 2026-09-30
Status: VALIDATED
Lane: tiny
Type: spec-feature
File: `docs/specs/SPEC-901-meetable.md`

## Problem

Trial fixture for `/kit:execute` whole-spec dispatch. Every criterion is meetable, so the build must end PASS. It proves the unmeetable trial is not an always-FAIL pipeline.

## After state

- [ ] `hello.txt` exists and holds `hello`.
- [ ] `README.md` names `hello.txt`.

## Task Breakdown

- [ ] TASK-A: write `hello.txt` containing `hello`. AC-1.
- [ ] TASK-B: name `hello.txt` in `README.md`. AC-2.

## Acceptance Criteria

- [ ] AC-1: `hello.txt` exists and contains exactly `hello`.
- [ ] AC-2: `README.md` mentions `hello.txt`.

## Verification

```bash
bash tests/fixtures/whole-spec-dispatch/check.sh meetable
```

## Touches

- hello.txt
- README.md
