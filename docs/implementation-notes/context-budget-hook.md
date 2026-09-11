# Implementation notes: context-budget hook (SPEC-255)

## 2026-09-10 Lane chosen below the classifier

Context: `lane-classify.sh classify` returned `full` for the task text.
Decision: ran the `normal` lane; the ledger `start` records chosen `normal`, classified `full`.
Why: same precedent as SPEC-254, porting an already-tested, already-shipped operator hook into an existing module, no new subsystem, no schema change.
Alternatives: `full` lane ceremony for a straight port with a pre-existing 13-case reference suite.
Impact: none on behavior; grill skipped as home-turf, design-record and test-plan satisfied inline in the spec rather than as separate command runs.
Open questions: none.

## 2026-09-10 CLAUDE.md gets no hooks-list edit

Context: the task brief asked for the hook documented "wherever the kit lists hooks (MANUAL.md hooks table, docs/architecture.md hook layer, CLAUDE.md hooks list, module docs)".
Decision: `CLAUDE.md` carries no hooks list at all (it explicitly points to `MANUAL.md`/`docs/architecture.md`/README and says "do not duplicate the inventory here"); `docs/MANUAL.md`'s own Hooks section is BLOCKERS-only by stated design ("What to remember here: the blocking hooks, everything else advises or warns"), and `context-budget` is advisory, not a blocker.
Why: adding rows to either file would violate an existing single-source-of-truth rule stated in the files themselves.
Alternatives: add a row to MANUAL.md's blockers table anyway.
Impact: `context-budget` is documented in `README.md` (Hooks table + `session` module row) and `docs/architecture.md` (Hook fallback layer table, class `advisory`), which is where every other advisory hook already lives.
Open questions: none.

## 2026-09-10 Classified advisory, not convenience

Context: the Hook fallback layer's placement test distinguishes "no judgment involved" (convenience) from "warns, human may override" (advisory).
Decision: `advisory`, same tier as `output-offload` and `context-readiness`.
Why: the hook makes a judgment call ("this session's cache-read cost is now large enough to act on") and recommends a specific next action (handoff + `/clear`), unlike a pure state-save or formatter.
Alternatives: `convenience` (the dotfiles original never blocks either, but framing it as "no judgment" undersells what it is telling the operator to do).
Impact: the Hook fallback layer table row states this explicitly; no test pins the classification itself (the table is prose, parity-checked only on row COUNT).
Open questions: none.

## 2026-09-10 Real-transcript smoke found a trailing zero-usage entry

Context: the smoke ran the hook against a 14.85MB real transcript. Its second-to-last main-chain assistant usage entries carried ~449k-466k combined tokens, but the very last one in file order was an all-zero usage block (`input_tokens:0, cache_creation_input_tokens:0, cache_read_input_tokens:0`), so `ctx` computed as 0 and the hook stayed silent.
Decision: left unchanged. The "take the LAST main-chain assistant usage entry" rule is inherited verbatim from the tested dotfiles source; a trailing zero-usage entry is a real-world transcript shape (likely a stop/interrupt metadata line) the synthetic 13-case suite does not cover.
Why: this port's contract is behavioral parity with the shipped reference, not a new heuristic; changing the selection rule (e.g. "last NONZERO entry") would diverge from the tested original with no reference test to validate the new rule against.
Alternatives: skip zero-usage entries when picking the last one.
Impact: on a session whose most recent turn happens to log zero usage, the hook under-reports for that one prompt; the next turn's own usage entry corrects it.
Open questions: whether the dotfiles original should also adopt a skip-zero-usage rule; flagged for the operator, not fixed here (out of this spec's scope).
