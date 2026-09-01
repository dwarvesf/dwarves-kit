# Proof of done: hermes spoke instance reach (target, board, assignee, workspace)

Change under proof: `HermesSource` gains `board`, `assignee`, and `workspace`,
and `--hermes-target` accepts `local` and `sudo:<user>` beside an ssh host.
The board flag rides reads as well as writes; the workspace is a template whose
`{id}` is the board id. Every knob is off by default.

Driver: SPEC-004 phase 2 relays hub rows onto a shared ops board owned by a
daemon account on the runner's own host. Without these four, the relay writes
to the wrong board, leaves tasks unassigned, loses deliverables on completion,
and cannot reach the instance at all.

## Confirmation run-table

| # | Check | Command | Result | Verdict |
|---|---|---|---|---|
| 1 | Whole sync suite, new cases included | `bash tests/test-sync.sh` | 230 passed in 0.20s | PASS |
| 2 | Config registry still consistent | `bash tests/test-config-registry.sh` | exit 0 | PASS |
| 3 | Config resolution unchanged | `bash tests/test-config.sh` | 19/19 passed | PASS |
| 4 | Reserved-key guard unchanged | `bash tests/test-reserved-config-guard.sh` | exit 0 | PASS |
| 5 | `board sync` dispatch unchanged | `bash tests/test-sync-dispatch.sh` | exit 0 | PASS |
| 6 | Board CLI unchanged | `bash tests/test-board.sh` | exit 0 | PASS |
| 7 | Stable-interface contract holds | `bash tests/test-stable-interface.sh` | exit 0 | PASS |
| 8 | `sudo:` form reaches a real foreign-uid instance | `printf 'export HERMES_HOME=/Users/server/hermes-dfoundation\nset -e\nhermes kanban --board dw-ops list --json\n' \| sudo -n -u server -H bash -s` | exit 0; stdout starts `[` and parses as a 17-task array; stderr empty | PASS |

Row 8 ran on the Mini ops account against the dfoundation instance, and
is the one check a fake transport cannot make: it proves the uid hop works
unattended (`-n`, no TTY) and that `-H` is what stops the CLI reading the
caller's dotenv.

## Negative controls

| Control | What was reverted | Result |
|---|---|---|
| A | `lib/sync/sources/hermes.py` restored to `HEAD~1` | collection error, `cannot import name '_target_cmd'`; 0 tests run | RED |
| B | Only the board flag dropped from `_kanban()` (prose and every other line kept) | `test_board_flag_rides_reads_and_writes` FAILED, 12 passed | RED |
| restore | `git checkout HEAD -- lib/sync/sources/hermes.py` | 230 passed | GREEN |

Control B is the one that matters: it changes a single returned string, leaves
every docstring claiming the board rides both paths, and the suite still turns
red. The test is sensitive to the code, not to the prose about it.

## Reproduce

```
git checkout feat/hermes-spoke-instance-reach
bash tests/test-sync.sh                       # 230 passed

# negative control B
python3 - <<'PY'
import pathlib
p = pathlib.Path("lib/sync/sources/hermes.py")
p.write_text(p.read_text().replace(
    '        return f"hermes kanban --board {shlex.quote(self.board)}"',
    '        return "hermes kanban"'))
PY
uv run --no-project --with pytest -- pytest lib/sync/tests/test_hermes.py -q   # 1 failed
git checkout HEAD -- lib/sync/sources/hermes.py
```

## Residual

The spoke still has no per-item workspace: every relayed task takes the same
template. That is enough for the consumer this unblocks, whose tasks differ
only by board id, and a per-item override would need the planner to carry one.
