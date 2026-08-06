## 2026-07-04 04:01 Wired significance-classify record into /kit:ship (SPEC-136)

Context: ADR-0031 Refinement §4 + the understanding-gate mega-goal's TIER-4 close both named the
same open hole: `significance-classify.sh record` (SPEC-123) has existed since the classifier
shipped, but nothing ever called it. `tests/test-understanding-wiring.sh` AC3 made this an honest,
asserted gap (rc=3) rather than a silent over-claim -- correct SG-06 discipline, but it left the
"silent wave, but LOGGED" half of ADR-0031 Refinement §2 inert: a significant-but-low-worthiness
change was only ever recorded as a side effect of `quiz-gate.sh tap` running, and `tap` itself only
calls `classify` (transient), never `record` (persists). This entry is the DELTA from SPEC-136, not
a restatement of it (see `docs/specs/SPEC-136-record-at-ship.md` for the full Problem/Solution/
Design).

Decisions not pinned down by the assigning prompt, made here:

1. **Where in ship.md, exactly.** The assigning prompt said "before the `quiz-gate.sh tap` call,
   using the SAME change description + files the tap already uses." I placed `record` as bullet
   sub-step 1 and `tap` as sub-step 2 under the SAME "Understanding-gate nudge" bullet (rather than
   two separate top-level bullets), so the two calls read as one coherent beat with one shared
   file/desc input, not two independently-timed steps that could drift apart if someone edits one
   without the other.
2. **Fire-on-every-gate-ship vs fire-only-when-tap-would-nudge (SPEC-136 Design, Approach C).**
   Chose unconditional: `record` runs on every `gate`/gated-final ship regardless of what verdict
   `tap` will compute a moment later. Gating `record` on `tap`'s own verdict would just move the
   silent-wave hole one line down (a `wave` verdict, by definition, never triggers `tap`'s nudge
   branch -- so gating record on "tap would nudge" makes `wave` unloggable again, the exact bug this
   SPEC closes). `record` and `tap` compute the SAME classification independently (both call
   `significance-classify` with identical inputs) rather than one feeding the other a cached
   verdict -- kept them decoupled per Approach B's rejection (a future non-ship caller of `tap`
   should not silently start writing to the ledger as a side effect of asking `tap` a yes/no
   question).
3. **The exit-0 guard.** The assigning prompt said "a `record` failure must never block the ship
   (guard it, exit-0 posture like the rest of the axis)." Implemented as a literal `|| true` on the
   prose command in `commands/ship.md` (this is a markdown-instruction file executed by an agent,
   not a real shell script, so the guard is documentation of intent + a copy-pasteable safe form,
   not an enforced trap). `significance-classify.sh record` itself already exits 0 in the success
   path (SPEC-123); the only realistic failure mode is a `gate-ledger.sh debt` write error (e.g. a
   read-only log dir), which `|| true` absorbs.
4. **Widening the scope was explicitly rejected.** Considered (Approach D) firing `record` on every
   ship, not only gate/gated-final. Rejected: the Understanding-gate nudge bullet this wiring
   extends has always been scoped to `gate`/gated-final PRs (SPEC-125); this SPEC fills a gap
   INSIDE that existing scope, it does not widen it. A non-gate ship still writes zero debt-ledger
   markers after this change -- documented plainly in WORKFLOW.md's updated bullet so a future
   reader does not assume otherwise.

Deviation from a literal reading of the assigning prompt: none functionally, but note the AC3 flip
in `tests/test-understanding-wiring.sh` needed a THIRD assertion beyond "a caller exists somewhere"
(the prompt's own wording): I added an explicit line-order check (`record`'s line number precedes
`tap`'s line number in `commands/ship.md`) so the test proves the ORDERING the whole SPEC depends
on, not just that both strings happen to appear in the file. A grep-only "both exist" check would
have passed even if I had (incorrectly) put `record` after `tap`.

Impact: every `/kit:ship` run on a `gate`/gated-final PR now writes a FAT `| DEBT |` line
(`significance=`/`worthiness=`/`verdict=`) to the debt ledger before the quiz-gate tap decision.
`weekend-batch.sh collect`/`list` show real significance/worthiness for these rids directly (the
TIER-4-close walk-back logic stays load-bearing only for pre-SPEC-136 rids and non-gate ships). A
live smoke run (temp `DWARVES_KIT_LOG_DIR`, this branch's real changed-files list) reproduced the
full loop: `record` (verdict=wave, grounded in the real files/description, full-lane significant but
no worthiness trigger fired) -> `list` shows it collectible as `waved` with NO human response yet
recorded (the silent-wave path, live) -> `debt-response defer` forward-carries `significance=high
worthiness=low verdict=wave` onto the response line -> `collect` digest shows the real values, not
blanks -> `mark-paid` exits 0, disposed paid, no longer collectible.

New/flipped test coverage: `tests/test-understanding-wiring.sh` AC3 (3 checks: a caller exists,
specifically in `commands/ship.md`, and precedes the `tap` call by line number) plus AC2's
`claim_wired` check for `record` now expects rc=0 (WIRED) instead of rc=3 (HONEST GAP).
`tests/test-weekend-batch.sh` gained AC5 (7 checks: the full record -> forward-carry -> collect ->
mark-paid payoff loop, driven through the REAL `significance-classify.sh record` verb, not a
hand-seeded fixture line) and AC6 (4 checks: the silent-wave path, a `record` producing `verdict=wave`
with no human response ever collected as `waved`).
