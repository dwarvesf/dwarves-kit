# ab-medium (wordstat)

Empty-skeleton fixture for an A/B measurement of the `/kit:execute` spine. A run builds `src/wordstat.py` from `docs/specs/SPEC-001-wordstat.md` (4 tasks, full lane). Public and neutral: no client data.

## Starting state

| Path | Role |
|---|---|
| `docs/specs/SPEC-001-wordstat.md` | VALIDATED spec, the input to `/kit:execute` |
| `tests/run.sh` | test entry point (stdlib unittest discovery) |
| `tests/data/sample.txt` | known input: 3 lines, 11 words, 52 bytes |
| `src/wordstat.py`, `tests/test_*.py`, `docs/usage.md` | absent on purpose: the build writes them |

## Reset

Never work in place and never reuse a built copy. Copy this directory to a fresh scratch dir, then `git init -b main`, commit everything, and adopt the kit there.
