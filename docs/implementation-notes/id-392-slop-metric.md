# Implementation notes, ID-392 review-economics telemetry (the slop metric)

Delta from `docs/briefs/DECISION-BRIEF-review-economics.md` only.

## 2026-08-27 09:40 Built on the existing SPEC-061/SPEC-129/SPEC-062 substrate, no new write side

Context: the brief's build constraint says emit to the existing append-only ledger, stats as a
recomputed projection, no new metrics store. Reading the actual ledger lines commands/review.md
and commands/review-team.md already write (`| GATE | review | ran |` per review round,
`| OUTCOME | review | end | caught=.. dur_s=.. |` per SPEC-129, `| ACTION | ... escaped-from=..`
per SPEC-062), all four counters the brief names were already fully derivable read-side. No new
`gate-ledger.sh` verb was needed.

Decision: added one aggregator, `_review_agg()` in `lib/telemetry/lane-telemetry.sh`, and wired
its output into the existing `report` command as a new "review economics" section. No new
subcommand.

Why: the brief itself frames this as data ALREADY being written with nothing aggregating it
(mirrors SPEC-061's own founding problem for lane routing). Adding a write verb would have
duplicated data the review commands already emit.

Alternatives: a new `gate-ledger.sh review-metric` verb (rejected, duplicate write path); a
separate `docs/verification`-style report script (rejected, the brief explicitly says reuse the
lane-telemetry/gate-ledger pattern).

Impact: ID-393 (canary/planted-defect catch rate) can land the same way, read-side over the
`| ACTION |` / `| GATE |` lines its own future write already needs.

Open questions: none for this increment.

## 2026-08-27 09:55 First-pass acceptance scoped to the `review` phase only, not `design-critique`/`advisor`

Context: `/kit:devs-team` and `/kit:review-team` bracket additional phases
(`design-critique`, `advisor`) with the same OUTCOME start/end shape as `review`.

Decision: `_review_agg()` reads only `phase=review` GATE/OUTCOME lines.

Why: the brief's metric set ("first-pass acceptance", "rework round-trips") is framed around
the primary code-review gate a PR/card goes through, not every advisory lens. Folding
`design-critique`/`advisor` in would conflate distinct gates behind one number.

Alternatives: sum across all review-family phases (rejected: over-broad, harder to read as a
single "did the PR pass review clean" signal).

Impact: a future per-lens breakdown (advisor catch rate, design-critique catch rate) is a
follow-up if a lane wants it; not built here (YAGNI, no ask for it yet).

Open questions: none.

## 2026-08-27 10:05 Time-to-merge not computed as a separate number

Context: the brief lists "time-to-merge" alongside first-pass/rework/reviewer-minutes.
SPEC-061 already deferred exact wall-clock duration math ("Median duration deferred: BSD awk
lacks `mktime`") and lists first..last ISO timestamps per run instead.

Decision: did not add a second duration computation for time-to-merge; the existing per-run
"first..last" window column in `report`'s run listing already carries it for the eyeball read,
same limitation SPEC-061 already named and accepted.

Why: matching an existing, already-accepted deviation is smaller than reintroducing the same
portability problem a second time in the same file.

Alternatives: shell out to `date -d`/`date -j` for a portable epoch diff (rejected: adds a
platform branch to a file that has deliberately stayed pure bash/awk since SPEC-061).

Impact: if a precise duration is later needed, `gate-ledger.sh`'s `outcome` verb already
brackets in epoch seconds (`dur_s`) for phases it covers; a whole-run bracket (START to Ship)
would be the natural follow-up, not a lane-telemetry-side fix.

Open questions: whether a whole-run OUTCOME bracket (not just per-phase) is worth adding for
ID-392's "time-to-merge" specifically; left for whoever picks up the exact number.

## 2026-08-27 10:15 lib/bench/docs/METRICS.md left untouched

Context: the task pointed at `lib/bench/docs/METRICS.md`'s "First-pass yield" / "Defect escape
rate" rows (status `planned`/`join`) as prior art for the vocabulary.

Decision: did not flip either row's status.

Why: METRICS.md is scoped to the bench plane (`bench.py`'s synthetic suite rows/transcripts) --
its "First-pass yield" source is `bench row pass`, not a real PR/card review ledger. This
change lands in lane-telemetry (real work, per the brief's own framing: "first measurement bed
= the Multica pilot cards"), a different subsystem answering a different question. Flipping the
bench-plane rows would claim a status change for work that didn't happen there.

Alternatives: add a cross-reference row in METRICS.md pointing at lane-telemetry (considered,
deferred as scope creep on a bounded increment; the DECISION-BRIEF already documents the
distinction).

Impact: none; a future bench-plane pass on first-pass yield stays a separate piece of work.
