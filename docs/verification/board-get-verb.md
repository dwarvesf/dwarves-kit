# Proof of done: `board get <ID>` single-row status verb

Change: `lib/board/backlog.sh` gains a `get <ID-NNN>` verb that prints one Active-queue row's status cell; `lib/board/board.sh` usage line documents it (positional forwarding already carried it).

## Green run

Fixture `/tmp/bg-fixture.md`: one row `ID-001` with status `shipped [PR #700]`.

| Command | Exit | Verdict |
|---|---|---|
| `BACKLOG_FILE=/tmp/bg-fixture.md bash lib/board/backlog.sh get ID-001` | 0, prints `shipped [PR #700]` | PASS |
| `bash bin/board get ID-001 --backlog-file /tmp/bg-fixture.md` | 0, prints `shipped [PR #700]` | PASS (wrapper path) |
| `backlog.sh get ID-999` (absent) | 1, `no Active-queue row for ID-999` | PASS |
| `backlog.sh get ID-009` (duplicated ID) | 1, `matches 2 rows ... dedupe first` | PASS |
| `backlog.sh get` (no arg) | 64, usage | PASS |
| `bash tests/test-hooks.sh` | 498/498 | PASS |
| `bash tests/test-board.sh` | 50 pass, 1 skip | PASS |

## Negative control (revert -> RED -> restore)

| Step | Command | Exit | Result |
|---|---|---|---|
| revert | `bash lib/board/backlog.sh get ID-001` on master checkout | 64 | RED: `get` is an unknown verb, usage prints |
| restore | same command on `feat/board-get-verb` | 0 | GREEN: `shipped [PR #700]` |

## Repro

`cd <repo> && bash lib/board/backlog.sh get <ID>` (kit's own board), or `bash bin/board get <ID> --backlog-file <path>` for any adopting repo.
