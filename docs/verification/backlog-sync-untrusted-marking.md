# Proof of done: backlog_sync Hermes cards marked untrusted (ID-481)

## Acceptance criteria

| AC | Claim | Proof |
|---|---|---|
| AC1 | Hermes card create marks title + body as untrusted (SPEC-147) | `test_apply_marks_untrusted_title_and_body`, `test_apply_never_emits_a_bare_unmarked_title` |
| AC2 | marking runs before shlex quoting, no injection regression | `test_apply_creates_with_idempotency_key_and_quoting` (marked body still one quoted arg, `$var` stays data) |
| AC3 | read() strips markers so title-prefix re-link survives state loss | `test_read_strips_untrusted_markers`, `test_marked_card_relinks_after_state_loss` |
| AC4 | mark helpers are idempotent (no double-wrap) | idempotency guard in cockpit.mark_untrusted_* |
| AC5 | markers are the canonical strings, no divergent copy | byte-identical to board-mirror.sh; defined once in cockpit.py, imported by hermes.py |

## Recorded run

```
Command: uv run --no-project --with pytest -- pytest lib/sync/tests/test_hermes.py -q
Exit: 0
17 passed

Command: uv run --no-project --with pytest -- pytest lib/sync/tests -q
Exit: 0
236 passed
```

NEGATIVE CONTROL: deleting the two `unmark_untrusted_*` lines in
`HermesSource.read()` makes `test_read_strips_untrusted_markers` and
`test_marked_card_relinks_after_state_loss` fail (Exit: non-zero); restoring
them returns Exit: 0. Verdict: PASS.

## Confirmation runs

| Run | Command | Result |
|---|---|---|
| green (hermes) | `uv run --no-project --with pytest -- pytest lib/sync/tests/test_hermes.py -q` | 17 passed, exit 0 |
| green (full sync suite) | `uv run --no-project --with pytest -- pytest lib/sync/tests -q` | 236 passed, exit 0 |
| negative control (marking) | delete the two `mark_untrusted_*` lines in hermes.apply | `test_apply_marks_*` + `test_apply_creates_*` fail; restored -> green |
| negative control (CRITICAL) | delete the two `unmark_untrusted_*` lines in hermes.read | `test_read_strips_*` + `test_marked_card_relinks_after_state_loss` fail; restored -> green |

Verdict: PASS (claim: git-board content reaching a Hermes agent is marked as
DATA-not-instructions, and the marking does not corrupt the sync engine's
state-loss re-link; metric: the pytest suite; threshold: 236/236 with both
negative controls flipping RED).

## Rollback

Single-branch change, no data migration, no deployed state. Revert the branch
commits (or `git revert`) to restore the prior behavior: cards created unmarked,
read() returns raw titles. No cleanup needed. Cards already created while the
change was live carry the `[untrusted] ` title tag; read() strips it on the way
back, so a rollback leaves those cards marked in Hermes but the engine still
re-links them (parse_title tolerates the bare id it now sees). No board
corruption on rollback.

## Reproduce

```
cd lib/sync
uv run --no-project --with pytest -- pytest tests/test_hermes.py -q   # 17 passed
uv run --no-project --with pytest -- pytest tests -q                  # 236 passed
```
