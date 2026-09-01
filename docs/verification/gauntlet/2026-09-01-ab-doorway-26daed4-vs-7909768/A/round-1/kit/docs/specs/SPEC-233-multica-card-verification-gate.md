# Spec: refuse Multica cards with no verification command at creation-sync

Generated: 2026-08-27
Status: Draft
Lane: normal (`lane-classify.sh classify` said `normal`)
Relates-to: dfoundation `docs/agent-teamwork-guide.md` §4 (the card-ready template, doc half
shipped 2026-08-11), dfoundation backlog row DF-151, dwarves-kit ID-392 (the review-economics
metric this template is meant to raise)

The card-ready template (agent-teamwork-guide.md §4) says a card is board-ready only when it
carries context, acceptance criteria, a verification command, a size cap, and an optional
`type`. It also says: "a card missing the verification command should be refused at creation,
not merely encouraged to have one," and names this file as where that refusal belongs, because
`lib/sync/sources/multica.py` is the shared sync engine every adopted repo's `#team`-tagged
board rows go through on their way to becoming a Multica card.

## Problem

`MulticaSource.apply()` creates a new Multica issue for every `plan.src_create` entry with no
check on the card body at all. A `#team`-tagged board row with no verification command syncs
into a real Multica card exactly like a well-formed one, so the template is currently
aspirational: a human has to notice and reject it manually, at review time, the most expensive
point to catch it.

## Solution

Add one check inside `MulticaSource.apply()`'s `src_create` loop: before POSTing a new issue,
scan the row's body for a line naming a verification command (`Verify:` or `Verification:`,
case-insensitive, followed by non-blank text, the same labeled-line shape as the kit's own
`Done =` contract for goal drafts, AGENTS.md zone 2 / `commands/assign.md` Step 5). A body
missing that line is refused: no issue is created, and a message naming the missing field and
pointing at the template is printed to stdout.

Scope is deliberately `src_create` only (board row -> new Multica card), not `board_add`
(Multica -> board intake) or any status/body update on an existing linked card: the template
is a **creation-time** gate for cards born from `#team` rows, matching the backlog row's own
framing ("refuse cards without a verification command" at the point they become cards), and it
must never touch an issue a human is already iterating on inside Multica.

Refusal must not raise `SystemExit`: one bad row in a `#team` batch must not abort every other
repo's sync, and `HTTPError`/`URLError` already own `SystemExit` for real transport failures.
Instead, a refused `(bid, ...)` is simply skipped, so it never enters `apply()`'s `created`
dict; `build_state` (sync_core.py, unmodified) then never records it in the sync-state map,
so the row is retried on the next sync the moment its Notes cell gains a verification line.
No new config knob: the check is unconditional for every consumer of this source, the same as
every other rule already hardcoded in this file (the status map, the marker format).

### Architecture

```
plan.src_create: [(bid, title, body, kw), ...]     (from sync_core.plan_sync, unmodified)
        |
        v
MulticaSource.apply()
  for (bid, title, body, kw) in plan.src_create:
    if not _has_verification(body):
        print refusal naming bid + template  -----> skipped, no POST, no `created[bid]`
        continue
    POST /api/issues  -----------------------------> created[bid] = new Multica issue id
        |
        v
  build_state() (sync_core.py): bid absent from `created` -> absent from the state map
        -> next sync run re-plans a `src_create` for the same bid, retried once fixed
```

## Acceptance Criteria

- [ ] AC-1: `MulticaSource.apply()` refuses to POST a `src_create` entry whose body has no
  `Verify:`/`Verification:` line with non-blank content after the colon.
- [ ] AC-2: the refusal message names the missing field ("verification command") and points at
  the card-ready template (agent-teamwork-guide.md §4 / the `Done =` precedent), for the human
  reading `board sync` output to act on.
- [ ] AC-3: a `src_create` entry WITH a verification line still creates the issue exactly as
  before (byte-identical POST body/status), and its `bid` lands in `apply()`'s return value.
- [ ] AC-4: a refused `bid` is absent from `apply()`'s return value, so `build_state` never
  snapshots it and the row is retried on the next sync.
- [ ] AC-5: `board_add` (Multica -> board intake) and every status/body/title update on an
  already-linked card are unaffected: the check only runs inside the `src_create` loop.

## Test plan

Date: 2026-08-27. Dialect: unit tests against the existing `FakeHttp` fixture in
`lib/sync/tests/test_multica.py` (no network, matches every other test in the file).

| # | Case | Covers | Expected |
|---|---|---|---|
| 1 | `src_create` body has `Verify: pytest lib/sync/tests/test_multica.py` | AC-1, AC-3 | POST issued, `created[bid]` set |
| 2 | `src_create` body has no `Verify:`/`Verification:` line (NEGATIVE CONTROL for AC-3) | AC-1, AC-2, AC-4 | no POST for that entry, `bid` absent from `created`, a message naming "verification" is printed |
| 3 | `src_create` body has `Verification:` with nothing after the colon (blank) | AC-1 | treated as missing, same as case 2 |
| 4 | two `src_create` entries in one `plan`, one refused and one valid | AC-4 | the valid one still creates; only the refused one is skipped (a bad row does not block its siblings) |
| 5 | `board_add` entry with no verification line (NEGATIVE CONTROL for AC-5) | AC-5 | unaffected, behaves exactly as `test_apply_adopts_board_add_with_assigned_id` today |

## Verification

```
python3 -m pytest lib/sync/tests/test_multica.py -q
```
Green, including the new cases above; `test_apply_adopts_board_add_with_assigned_id` and every
other pre-existing case in the file stay green unmodified (the negative control for "this gate
did not spread past `src_create`").

## After state

A `#team`-tagged board row with no `Verify:`/`Verification:` line in its Notes cell never
becomes a Multica card: `board sync` skips it, prints why, and leaves it queued for the next
run once fixed. A row that carries the verification line syncs exactly as it did before this
change. The card-ready template (agent-teamwork-guide.md §4) is now enforced at the one point
it named, not merely documented.
