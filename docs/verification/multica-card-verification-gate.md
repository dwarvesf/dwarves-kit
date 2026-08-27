# Proof of done: multica-card-verification-gate

Scope: SPEC-233. `MulticaSource.apply()` (`lib/sync/sources/multica.py`) refuses to POST a new
Multica issue for a `plan.src_create` entry whose body carries no `Verify:`/`Verification:`
line, per the card-ready template (dfoundation `docs/agent-teamwork-guide.md` §4, DF-151). A
refused entry is skipped, not raised: it stays absent from `apply()`'s `created` dict so the
next sync retries it once the row is fixed, and it never blocks any sibling entry in the same
batch.

## Green run

Command: bash tests/test-sync.sh
Exit: 0
Verdict: PASS, 243 passed, 0 failed. Includes the 6 new cases in `lib/sync/tests/test_multica.py`:
a card with a `Verify:` line still creates the issue byte-identically; a card with no
verification line is refused (no POST, absent from `created`, refusal message names the row and
the template); a `Verification:` line with nothing after the colon is treated as missing; two
`src_create` entries in one plan, one refused and one valid, only the refused one is skipped; and
a `board_add` (Multica -> board intake) entry with no verification line is unaffected (the gate
is scoped to `src_create` only).

## Negative control

Command: temporarily short-circuit the gate (`if False and not _has_verification(body):` in
`MulticaSource.apply()`), rerun bash tests/test-sync.sh
Exit: 1 (pytest reports failures)
Verdict: RED as expected, 3 of the 6 new cases fail (`test_apply_refuses_card_with_no_verification_line`,
`test_apply_refuses_card_with_blank_verification_line`, `test_apply_refused_card_does_not_block_its_siblings`):
with the gate disabled every `src_create` entry POSTs regardless of body content.

Command: restore the real gate (`if not _has_verification(body):`), rerun bash tests/test-sync.sh
Exit: 0
Verdict: PASS, 243/243 green again.

## Rationale

The check lives only inside the `src_create` loop, matching the backlog row's own framing: the
template gates a card at the moment a `#team`-tagged board row is ABOUT to become a Multica
card, not an existing card someone is iterating on. `HTTPError`/`URLError` already own
`SystemExit` in this module for transport failures, so the validation refusal deliberately does
not raise: one malformed row in a batch must not abort every other repo's sync. Skipping the
`bid` from `apply()`'s return value is what makes the refusal self-healing, `build_state`
(sync_core.py, unmodified) never records an unset bid, so `plan_sync` re-proposes the same
`src_create` on the next run, and the row succeeds the moment its Notes cell gains a
`Verify:`/`Verification:` line, no separate retry mechanism needed.
