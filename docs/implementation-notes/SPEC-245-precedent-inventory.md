# Implementation notes: SPEC-245 precedent inventory surface

Delta from the spec only. Decisions already in the spec's Decision Log are referenced, not repeated.

## 2026-09-06 Before build

- The four research files under `docs/research/` are session scratch. `architecture.md` was tracked from an earlier spec and got overwritten by the research agent; restored with `git checkout --`, and the three untracked reports stay out of the commit.
- `tests/test-meta.sh` pin at 2079-2087 (SPEC-068) reads `precedent.sh find` and `-x lib/precedent.sh`. Rewritten in TASK-001 to `precedent find` and `-x bin/precedent`; the SPEC-068 label in the message is kept so the test history stays greppable.
