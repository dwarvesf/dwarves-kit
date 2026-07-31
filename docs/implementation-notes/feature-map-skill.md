# Implementation notes: feature-map-skill (SPEC-218)

Delta log only; the spec carries the design.

## 2026-07-31 SPEC-217 number collision resolved by renumbering Phase A to SPEC-219

Context: two standalone sessions both drew 217 from `spec-next.sh next` the same day (this program's Phase A, merged PR #323, and self-grill-watcher, merged PR #322). SPEC-128's reservation mutex only guards orchestrate.sh waves, not concurrent standalone sessions.
Decision: renumber the registry spec to SPEC-219 (file + all references in registry-owned files); self-grill keeps 217.
Why: self-grill's number is baked into another session's merged lib code (`lib/queue/queue.sh`, `watch-board.sh`, `commands/grill.md`, its test, CHANGELOG); every SPEC-217 reference on the registry side was under this program's control. Ship-gate keys on the spec SLUG, so the ledger and gates were unaffected.
Impact: `docs/FEATURES.md` refs self-heal on regeneration (they derive from spec filenames).

## 2026-07-31 the freshness pin caught real concurrent-merge drift before Phase B started

Context: first act on the Phase B branch, the staleness gate (skill step 1) reported STALE: #322 merged between Phase A's base and merge, moving spec/test ref counts in FEATURES.md.
Decision: regenerate + commit as the branch's first commit; also fixed a latent bug the regeneration exposed (the review-round EXIT trap referenced a function-local var after scope, exit 1 under `set -u`; masked in test-meta, which never checks the generator's exit code).
Why: exactly the drift class the pin exists for; the skill's refusal rule got its first real exercise before the skill even shipped.

## 2026-07-31 BSD sed delimiter trap pinned into the skill body

Context: the first cross-check draft used `|` as the sed delimiter with `\|` in the pattern; BSD sed cannot escape the delimiter, so extraction silently passed whole lines through. A second silent failure: zsh noclobber kept stale temp files across the retry.
Decision: the skill's recipes use `/` delimiters with `\/` escapes, and the body carries a one-line warning.
Why: the recipe is the skill's load-bearing artifact; shipping the trap that bit its own author would ship a broken loop.
