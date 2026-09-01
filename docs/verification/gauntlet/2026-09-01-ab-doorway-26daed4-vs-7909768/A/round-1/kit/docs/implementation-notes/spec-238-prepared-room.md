# Implementation notes: SPEC-238 prepared gauntlet room

Delta from the spec only.

## 2026-09-01 build + verification

Version pins: no lockfile or prior-run record named an exact version used on
2026-08-31, so both packages pin to the current latest stable at build time,
`bun@1.4.0` and `@oh-my-pi/pi-coding-agent@18.0.11` (spec's own fallback
instruction: "or just pin the latest stable at build time and RECORD the
pinned version"). Recorded in the Dockerfile comment and here.

TASK-004 (persist-check leg E, the binary canary) scoped out of this pass on
explicit direction; left as an owed item in the proof (`docs/verification/prepared-room.md`),
not implemented. `tests/gauntlet/cleanroom/persist-check.sh` is unchanged.

TASK-003's live-round framing ("a live NW round on the baked image") was
satisfied with the direct `-u node` binary-resolution command instead of a
spend-incurring NW round: it is the load-bearing claim under validation W2
(binaries must resolve for the round's real user, not root) and needs no
model spend to prove.

No other deviations; TASK-001 and TASK-002 match the spec's Interfaces
section verbatim (allowlist by `*.log`/`*.jsonl` extension, `models.yml`/
`config.yml` never copied, binaries deleted rather than persisted).
