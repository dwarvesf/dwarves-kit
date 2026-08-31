# Proof of done: hermes intake path redacts secret-shaped tokens

## Acceptance criteria

| AC | Claim | Proof |
|---|---|---|
| AC1 | HermesSource.read() redacts high-signal credential shapes in title + body before rows are built | `test_read_redacts_secret_shapes_in_title_and_body` |
| AC2 | redaction reuses the notion-taskboard-pull leg's exact `_SECRETISH` pattern, no divergent copy | `cockpit.redact_secrets`, imported by both `sources/hermes.py` and `sources/notion_taskboard_pull.py` |
| AC3 | notion-taskboard-pull's existing credential-redaction behavior is unchanged after the refactor | `test_credential_shape_is_redacted`, `test_neutralize_is_case_insensitive` (unmodified, still pass) |

## Recorded run

```
Command: uvx pytest tests/test_hermes.py -q
Exit: 0
18 passed

Command: uvx pytest tests -q
Exit: 0
244 passed
```

NEGATIVE CONTROL: reverting the two `redact_secrets(...)` wraps in
`HermesSource.read()` (`lib/sync/sources/hermes.py`) back to plain
`unmark_untrusted_title(...)` / `unmark_untrusted_body(...)` makes
`test_read_redacts_secret_shapes_in_title_and_body` fail:

```
Command: uvx pytest tests/test_hermes.py -q   (with redact_secrets() reverted)
Exit: 1
FAILED tests/test_hermes.py::test_read_redacts_secret_shapes_in_title_and_body
1 failed, 17 passed
```

Restoring the two `redact_secrets(...)` wraps returns to green (18 passed,
244 passed on the full suite). Verdict: PASS.

## Confirmation runs

| Run | Command | Result |
|---|---|---|
| green (hermes) | `uvx pytest tests/test_hermes.py -q` | 18 passed, exit 0 |
| green (full sync suite) | `uvx pytest tests -q` | 244 passed, exit 0 |
| negative control | revert the two `redact_secrets()` wraps in `HermesSource.read()` | `test_read_redacts_secret_shapes_in_title_and_body` fails (1 failed, 17 passed); restored -> 18 passed |

Verdict: PASS (claim: a real credential shape pasted into a hermes kanban
ticket title or body is redacted before the row reaches the git-tracked
board; metric: the pytest suite; threshold: 244/244 with the negative
control flipping RED).

## Rollback

Single-branch change, no data migration, no deployed state, no schema. Revert
the branch commit to restore the prior behavior: `HermesSource.read()` again
commits ticket title/body verbatim (unredacted) and
`notion_taskboard_pull.py` reverts to its own local `_SECRETISH` copy. No
cleanup needed; a card synced while this change was live simply carries the
`[redacted]` placeholder in place of any credential-shaped substring, which a
rollback does not need to undo.

## Reproduce

```
cd lib/sync
uvx pytest tests/test_hermes.py -q   # 18 passed
uvx pytest tests -q                  # 244 passed
```
