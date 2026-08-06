# Implementation notes: review-yield-lens (SPEC-137)

Deltas only; reference SPEC-137 / `verification/review-yield-lens.md` for anything already
pinned there.

## 2026-07-04 21:40 kit_gates real-corpus count changed mid-run

Context: while building the review-gate fixture, I re-checked the live
`~/.local/state/dwarves-kit/logs/runs/` corpus for real `findings=`/`rejected=` grammar hits
(none existed as of the earlier harness-observatory SG-01 capture). Decision: found exactly 2
real lines carrying the grammar (`SHIP findings=0` and `FIX THEN SHIP findings=4 rejected=0
actor=Han Ngo`), the second matching 02's shipped `review.md` grammar exactly. Why: this
confirmed the query design (regex-extract at query time) works against genuinely live data,
not just the fixture, before I finished the fixture itself. Impact: none on the design (SPEC-137
already specified query-time extraction); it just gave me the real numbers pinned in the "Real
corpus" section of the verification doc (`raised=4`, `low_n=true` on the only real
`rejected_findings` row).

## 2026-07-04 22:10 `LEDGER_OBS_REPOS` command-substitution bug in the test's Z/H sections

Context: my first draft of `tests/test-review-yield.sh`'s division-by-zero (`Z-div-by-zero`) and
honest-zero (`H-nc`) sections used `env VAR=... uv run ledger rebuild ... && uv run ledger
review-yield ...` as ONE line. Decision: `env`'s var assignments apply ONLY to the first command
in a `&&` chain, not the second -- the second `review-yield` call silently ran against the
OUTER test's already-exported `LEDGER_OBSERVATORY_DB` (the fully-populated golden-fixture db),
not the intended empty one. Fixed by wrapping the whole compound command in `bash -c '...'`
under the single `env` prefix (matching the pattern the `H-nc` section already used correctly).
Why this belongs here: it is not a SPEC-137 design decision, it is a shell-scripting gotcha that
cost real debugging time and will recur in any future test that composes `env VAR=... cmd1 &&
cmd2` in one line. Impact: no source change; test-file-only fix, caught before any assertion was
trusted.

## 2026-07-04 22:30 `rejected_findings`'s row-count env-var listing order affects nothing, verified

Context: `LEDGER_OBS_REPOS`'s comma-separated order (`repo-a,repo-b,repo-empty,repo-missing`)
does not need to match the alphabetical output order, because `read_rejected_findings` sorts
its own output by `(repo, lens)` before returning (same convention every other adapter uses).
No deviation; confirmed via the golden fixture's exact-row assertions rather than assumed.
