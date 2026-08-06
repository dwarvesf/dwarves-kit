# Proof of done: gauntlet scenario pack (SPEC-227 P1-P5)

Journey feature list, reconciled scenario matrix (J1-J11), a card materializer
(`make-card.sh`) with per-row checkers, fixture plants for the bug/drift/review
rows, and a campaign runner note. All additions are additive files plus one
`cleanroom/run.sh` modification (documented in the Rollback note).

## Acceptance criteria -> confirmation

| # | Acceptance criterion | Result |
|---|---|---|
| P1 | `journey.md` committed beside the matrix, nine sections, kit's own terms | PASS (verified against `docs/MANUAL.md` / `docs/guides/spine.md`, no invented commands) |
| P2 | three-move pass run over `journey.md`; matrix reconciled, deltas noted | PASS (J9-J11 added, one candidate folded into J7 with a stated reason; see `scenarios.md` "P2 pass notes") |
| P3 | `make-card.sh <row>` renders a frozen card; J3/J4 checkers pass a hand-built green fixture and fail the untouched one | PASS, all 11 rows |
| P4 | fixture plants for J4 (regression), J8 (empty-input hole), J6 (drift file); inert for J1-J3; `run.sh` takes an optional ROW arg | PASS |
| P5 | README campaign section: run order, per-row budget, ROUNDS.md location, BLOCKER-pause rule | PASS |

## Confirmation run-table

| Run | Command | Exit | Verdict |
|---|---|---|---|
| tier1 (lint gate) | `bash tests/gauntlet/tier1.sh` | 0 | TIER1: GREEN |
| card render x11 | `bash tests/gauntlet/make-card.sh <J1..J11>` | 0 (each) | non-empty stdout, every row |
| negative control x8 (bare repo) | `bash tests/gauntlet/check-submission-user-<J4..J11>.sh <bare-git-repo>` | 1 (each) | SUBMISSION: RED, every row |
| BLOCKED control x8 | `bash tests/gauntlet/check-submission-user-<J4..J11>.sh <repo-with-only-BLOCKED.md>` | 3 (each) | BLOCKED submission reported, contents echoed |
| J4 hand-built green fixture | `bash tests/gauntlet/check-submission-user-J4.sh <hand-fixed-repo>` | 0 | SUBMISSION: GREEN (all 6 checks PASS) |
| J4 untouched fixture (regression still present) | `bash tests/gauntlet/check-submission-user-J4.sh <untouched-regressed-repo>` | 1 | SUBMISSION: RED (all 6 checks FAIL) |

## Run detail

### tier1 (lint gate)

```
Command: bash tests/gauntlet/tier1.sh
Exit: 0
Verdict: TIER1: GREEN
```

T1.5 now shellchecks the whole gauntlet script set via a glob
(`tests/gauntlet/*.sh tests/gauntlet/cleanroom/run.sh`, `-x` to follow the new
`check-lib.sh` source) instead of a hand-maintained file list, so a future new
row's checker is linted automatically. `-x` was required: without it,
shellcheck cannot see `fail` used inside `check-lib.sh`'s `check()` /
`gauntlet_verdict()` and false-flags it as unused (SC2034); with `-x` and the
`source=` directives pointed at the kit-root-relative path
(`tests/gauntlet/check-lib.sh`, matching how tier1.sh invokes shellcheck from
`KIT_ROOT`), the whole set is clean.

### Card render, all 11 rows

```
Command: for r in J1 J2 J3 J4 J5 J6 J7 J8 J9 J10 J11; do bash tests/gauntlet/make-card.sh "$r"; done
Exit: 0 (every row)
Verdict: non-empty stdout every row (1294-1803 bytes)
```

### Negative controls, all 8 new checkers (J4-J11)

```
Command: bash tests/gauntlet/check-submission-user-<row>.sh <fresh `git init` dir, nothing else>
Exit: 1 (every row)
Verdict: SUBMISSION: RED
```

### BLOCKED.md controls, all 8 new checkers (J4-J11)

```
Command: bash tests/gauntlet/check-submission-user-<row>.sh <dir containing only BLOCKED.md>
Exit: 3 (every row)
Verdict: BLOCKED submission: probe stopped honestly. Contents: <echoed>
```

### J4 green/red pair (the spec's own named requirement)

Hand-built green fixture: `cli.js` with the argv index restored to
`process.argv[2]`, `test.js` pinning `--upper hi` -> `HI`, a
`.claude/debug/j4-regression.md` with a filled `## Root cause`, a non-default
branch whose commit message cites the root cause, `PR.md`.

```
Command: bash tests/gauntlet/check-submission-user-J4.sh <hand-built green fixture>
Exit: 0
Verdict: SUBMISSION: GREEN (6/6 PASS)
```

Untouched fixture: same `test.js`/`package.json`, `cli.js` left with the
regression (`process.argv[1]`), no debug ledger, no branch, no PR.md.

```
Command: bash tests/gauntlet/check-submission-user-J4.sh <untouched regressed fixture, no branch/ledger/PR.md>
Exit: 1
Verdict: SUBMISSION: RED (6/6 FAIL)
```

Proves the checker is load-bearing on the actual fix (root cause + passing
tests + traceable commit), not just on file presence.

## Rollback note

Every change is an additive file (`journey.md`, `scenarios.md`'s reconciled
rows, `check-lib.sh`, `make-card.sh`, 8 new `seed-card-user-J*.md` cards, 8 new
`check-submission-user-J*.sh` checkers, this doc) plus one modification each to
`tests/gauntlet/tier1.sh` (the shellcheck glob), `tests/gauntlet/README.md`
(the campaign section), and `tests/gauntlet/cleanroom/run.sh` (the ROW arg +
row-scoped fixture plants). `git revert` of this branch's commit(s) restores
the prior state exactly; nothing outside `tests/gauntlet/` and
`docs/verification/gauntlet-scenario-build.md` is touched.
