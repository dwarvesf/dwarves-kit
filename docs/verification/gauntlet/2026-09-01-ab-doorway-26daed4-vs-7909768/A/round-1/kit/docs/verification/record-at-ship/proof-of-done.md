# Proof of done: record-at-ship (SPEC-136, understanding-gate ADR-0031 Refinement §4)

## Acceptance criteria -> run-table

| # | Criterion | Result | Evidence |
|---|---|---|---|
| AC1 | `commands/ship.md` Step 8 runs `significance-classify.sh record` BEFORE `quiz-gate.sh tap`, guarded `\|\| true` | PASS | `commands/ship.md` diff; `tests/test-understanding-wiring.sh` AC3 line-order check |
| AC2 | `tests/test-understanding-wiring.sh` AC3 flipped: `record` is WIRED (rc=0), not an honest gap (rc=3) | PASS (3/3) | AC3 block below |
| AC3 | `WORKFLOW.md`, `commands/quiz-gate.md`, `lib/gate/gate-ledger.sh` (~242), `lib/queue/weekend-batch.sh` (~221, ~306) updated to state `record` is wired at Ship, no over-claim | PASS | diffs; no remaining "unwired"/"no live caller" claim for `record` in these 4 files |
| AC4 | End-to-end: `record` (fat line) -> `weekend-batch collect` shows real sig/wor -> human `debt-response` forward-carries -> `mark-paid` exits 0, disposed paid | PASS (7/7) | `tests/test-weekend-batch.sh` AC5 block |
| AC5 | Silent-wave: a `record` producing `verdict=wave` with NO human response is collected as `waved` | PASS (4/4) | `tests/test-weekend-batch.sh` AC6 block |
| AC6 | Grounded NC: the recorded classification derives from the real `--files`/description, not a narrative | PASS | AC5a/AC6a below use `significance-classify.sh`'s own deterministic `explain`/`record` verdict, verified against the actual regex triggers (SPEC-123, unchanged) |
| AC7 | No regression: full CI suite green | PASS (33/33 files) | Regression section below |

**Total: 19/19 PASS in `test-understanding-wiring.sh`, 45/45 PASS in `test-weekend-batch.sh`, 0 FAIL.**

## Implementation

- `commands/ship.md` Step 8: the "Understanding-gate nudge" bullet now runs
  `bash lib/classify/significance-classify.sh record <rid> --files "<files>" "<what changed>" || true`
  immediately before the existing `bash lib/gate/quiz-gate.sh tap ...` call, same files/description.
- `tests/test-understanding-wiring.sh`: AC3 flipped from "record has no live caller" (rc=3, HONEST
  GAP) to "record IS wired via commands/ship.md" (rc=0, WIRED) for the `claim_wired` sweep against
  `WORKFLOW.md`; the old raw "no caller" grep replaced with three real assertions (a caller exists,
  specifically in `commands/ship.md`, and the `record` call's line number precedes the `tap` call's
  line number).
- `WORKFLOW.md`: the "AFTER: the explainer + quiz" paragraph now names the `record` call; the
  "Known wiring gap" bullet replaced with a "wired at Ship (SPEC-136)" bullet stating the practical
  effect (every gate/gated-final ship logs its verdict, including silent-wave) and the honestly-
  scoped remaining limit (gate/gated-final only, never widened).
- `commands/quiz-gate.md` (~line 31): "it was already logged silently ... at Ship" (previously an
  aspirational claim with no wiring behind it) now correctly cites SPEC-136 as the wiring that makes
  it true.
- `lib/gate/gate-ledger.sh` (~242) + `lib/queue/weekend-batch.sh` (~221, ~306): comments describing the
  forward-carry / walk-back fallback logic updated from "record is unwired today" (past-tense
  framing that was becoming stale) to "SPEC-136 wired record into /kit:ship; this fallback stays
  load-bearing for non-gate ships and pre-SPEC-136 rids" -- no behavior change, comments only.
- `tests/test-weekend-batch.sh`: two new sections. AC5 drives the REAL `significance-classify.sh
  record` verb (not a hand-seeded fixture line) through record -> (pending, not yet collectible) ->
  human `debt-response defer` (forward-carry) -> `collect` (shows real sig/wor) -> `mark-paid`
  (exits 0, disposed). AC6 drives `record` to a `verdict=wave` outcome and proves it is collected as
  `waved` with zero human response ever recorded.
- `docs/specs/SPEC-136-record-at-ship.md`, `docs/implementation-notes/record-at-ship.md` (the
  DELTA: 4 decisions not pinned down by the assigning prompt).

## Confirmation run (green)

```
$ bash tests/test-understanding-wiring.sh
=== AC2: no-orphan sweep -- each of the 5 artifacts has a live dispatch path ===
  PASS significance-classify: 'record' verb is WIRED via commands/ship.md (SPEC-136)
  ...
=== AC3: wiring check -- commands/ship.md now calls significance-classify.sh record (SPEC-136) ===
  PASS commands/*.md or hooks/*.sh calls significance-classify.sh record (live dispatch path)
  PASS specifically commands/ship.md calls significance-classify.sh record
  PASS the record call precedes the quiz-gate tap call in commands/ship.md (record line=173, tap line=174)
=== Results ===
Passed: 19 / 19
All understanding-wiring tests passed.

$ bash tests/test-weekend-batch.sh
=== AC5 (SPEC-136): the payoff loop -- REAL record -> forward-carry -> collect -> mark-paid ===
  PASS AC5a record's own stdout prints the verdict (tap, per this description's triggers)
  PASS AC5b record wrote a FAT | DEBT | line grounded in the real classification (significance=high worthiness=high verdict=tap)
  PASS AC5c before any human response, ug-30-record-e2e-* is PENDING (not yet collectible)
  PASS AC5d the human's defer response line forward-carries record's significance=high/worthiness=high/verdict=tap
  PASS AC5e collect shows REAL significance/worthiness for ug-30-record-e2e-* (high / high), not blank
  PASS AC5f mark-paid on ug-30-record-e2e-* exits 0 (the record->forward-carry->collect->mark-paid loop closes clean)
  PASS AC5g ug-30-record-e2e-* is disposed paid -- no longer collectible after mark-paid

=== AC6 (SPEC-136): the silent-wave path -- REAL record produces wave, no response ever follows ===
  PASS AC6a record's own stdout prints the verdict (wave: significant full-lane change, no worthiness trigger)
  PASS AC6b record wrote a FAT | DEBT | line (significance=high worthiness=low verdict=wave)
  PASS AC6c [logged-wave path, live] ug-31-record-wave-* IS collected with disposition=waved, with no human response ever recorded
  PASS AC6d the collect digest shows ug-31-record-wave-*'s real significance/worthiness (high / low), grounded in the actual files/desc

  TOTAL: 45   PASS: 45   FAIL: 0   SKIP: 0
```

## Before / after (captured)

**Before this SPEC** (from `docs/verification/docs-wiring/proof-of-done.md`, the prior sub-goal's
own captured run):
```
PASS significance-classify: 'record' verb is an HONEST GAP (no silent over-claim)
PASS no commands/*.md or hooks/*.sh calls significance-classify.sh record (matches the documented gap)
```
`weekend-batch.sh collect`/`list` could only ever show real significance/worthiness by walking back
to a FAT line that a human `debt-response` happened to have inherited from -- and since `record` had
no live caller, that FAT line only ever existed via the sibling test suite's hand-seeded fixtures, or
via `quiz-gate.sh tap`'s OWN transient `classify` call, which never wrote to the ledger. A
significant-but-low-worthiness (`wave`) or `not-significant` change on a `gate`/gated-final PR that
never separately reached a human response was **not logged at all**.

**After this SPEC** (this run, live smoke against a temp `DWARVES_KIT_LOG_DIR`, this branch's own
real changed-files list and an honest description of this actual change):
```
$ bash lib/classify/significance-classify.sh record "$RID" --files "commands/ship.md lib/classify/significance-classify.sh lib/queue/weekend-batch.sh lib/gate/gate-ledger.sh commands/quiz-gate.md tests/test-understanding-wiring.sh tests/test-weekend-batch.sh" \
    "wire significance-classify record into ship.md before the quiz-gate tap, closing the silent-wave-but-logged gap"
wave

$ cat "$DWARVES_KIT_LOG_DIR/runs/$RID.log"
... | START | lane=full classified=full type=spec-feature ctype=spec-feature repo=dwarves-kit
... | DEBT  | significance=high worthiness=low verdict=wave reason=sig:full lane wor:none

$ bash lib/queue/weekend-batch.sh list --repo dwarves-kit --days 400
live-smoke2-*   waved   high   low   ...   <- collected as waved, BEFORE any human response

$ bash lib/gate/gate-ledger.sh debt-response "$RID" defer "live smoke: deferring to weekend batch"
$ tail -n1 "$DWARVES_KIT_LOG_DIR/runs/$RID.log"
... | DEBT | significance=high worthiness=low verdict=wave response=defer reason=live smoke: deferring to weekend batch

$ bash lib/queue/weekend-batch.sh collect --repo dwarves-kit --repo-root "$(pwd)"
## live-smoke2-*
- disposition: deferred
- significance: high / worthiness: low
...

$ bash lib/queue/weekend-batch.sh mark-paid "$RID" --note "live smoke close"
rc=0
$ bash lib/queue/weekend-batch.sh list --repo dwarves-kit --days 400
<empty -- disposed, never re-collected>
```
This run's own real description ("wire significance-classify record into ship.md before the
quiz-gate tap...") happened to classify as significant (full-lane) but low-worthiness -- i.e. this
SPEC's own change is itself an example of the SILENT-WAVE case ADR-0031 Refinement §2 names: a
significant, mechanical, well-tested wiring change that is fine to wave without a quiz, as long as
it is a RECORDED choice. Before this SPEC, that recording would not have happened live.

## Grounded negative control

`significance-classify.sh`'s classification is unchanged by this SPEC (SPEC-123's own deterministic
regex-trigger contract): the same `--files`/description always produces the same verdict, with no
narrative channel. This SPEC only adds a new CALL SITE (`commands/ship.md`); it introduces no new
way for a fabricated story to influence the recorded verdict. AC5a/AC6a above independently verify
two different descriptions produce two different, trigger-consistent verdicts (`tap` for one that
matches a worthiness trigger, `wave` for one that does not), proving the grounding held through the
new wiring.

## Regression

- `bash tests/test-understanding-wiring.sh`: 19/19 PASS.
- `bash tests/test-weekend-batch.sh`: 45/45 PASS.
- `bash tests/test-quiz-gate.sh`: 29/29 PASS.
- `bash tests/test-significance-classify.sh`: 25/25 PASS.
- `bash tests/test-meta.sh`: 667/667 PASS.
- Full CI suite (every `bash tests/test-*.sh` referenced in `.github/workflows/test.yml`, 33
  files): all PASS, run individually.

## Reproduce

```
cd dwarves-kit
bash tests/test-understanding-wiring.sh
bash tests/test-weekend-batch.sh
bash tests/test-quiz-gate.sh
bash tests/test-significance-classify.sh
bash tests/test-meta.sh
```
