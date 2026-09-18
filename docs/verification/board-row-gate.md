# Verification -- board-row-gate

A PreToolUse Bash hook blocks a `git commit` that adds a new board row unless the message carries a `board-row-ok: <reason>` line. It covers every repo whose root has `_meta/BACKLOG.md` or `BACKLOG.md`, with no per-repo install.

Verdict: PASS

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | A new first-cell ID with no marker blocks | cases 2.1, 3.2, 9.4; live CC runs 1 and 3 | PASS |
| AC2 | The marker passes, as its own `-m`, `--message=`, `$'...'`, heredoc body, or `-F` file | cases 2.2, 2.3, 2.5, 3.1, 3.3, 4.2; live CC run 2 | PASS |
| AC3 | IDs are prefix-agnostic | cases 6.1 to 6.4 (DF-, FO-, TR- on a root `BACKLOG.md`) | PASS |
| AC4 | Status flips, moved rows, and IDs cited in Notes never count | cases 5.1, 5.2, 5.3 | PASS |
| AC5 | An unreadable message blocks only when new IDs exist | cases 4.1, 4.4 block; 4.5 allows | PASS |
| AC6 | `git -C` and `cd` chains resolve the target repo; an ambiguous `cd` checks the cwd repo | cases 7.1 to 7.8 | PASS |
| AC7 | Non-commit commands and board-less repos never engage | cases 1.1 to 1.5, 11.7 | PASS |
| AC8 | Merge, rebase, cherry-pick states and a first commit skip | cases 9.1, 9.2, 9.3, 9.6 | PASS |
| AC9 | The session kill switch turns the hook off | case 9.5 | PASS |
| AC9b | Default ON; a committed `[gate] board_row_gate = false` passes a new row with no marker; an uncommitted or dirty opt-out does not apply; a default repo still blocks; the operator overlay can switch it off | cases 12.1 to 12.7 | PASS |
| AC10 | What the commit takes is what is checked: index, `-a`, a `git add` earlier in the same call, covering and non-covering pathspecs, `--amend` | cases 8.1 to 8.4, 11.1 to 11.6, 11.17, 11.18; live CC run 3 | PASS |
| AC11 | Only the commit's own segment is its message; shell syntax is never a pathspec | cases 2.7, 11.10 to 11.14 | PASS |
| AC12 | The hook fires in a real Claude Code session | headless `claude -p` runs 1 to 3 below | PASS |
| AC13 | bash 3.2 compatible, fast on unrelated commands, no hang on `-F /dev/zero` | `HOOK_BASH=/bin/bash` run, timing below, cases 11.15, 11.16 | PASS |
| NEGATIVE CONTROL | Forcing the new-ID set empty turns every blocking case red | run below | PASS |
| NEGATIVE CONTROL (opt-out) | Ignoring the policy verdict turns the opt-out cases red | run below | PASS |

## Green run
```
Command: bash tests/test-board-row-gate.sh
Exit: 0
Verdict: PASS=73 FAIL=0
```

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-board-row-gate.sh` (hook under Homebrew bash 5) | 0 | PASS=73 FAIL=0 |
| `HOOK_BASH=/bin/bash bash tests/test-board-row-gate.sh` (hook under macOS bash 3.2) | 0 | PASS=73 FAIL=0 |
| `bash tests/test-gate-opt-out.sh` | 0 | ALL PASS (incl. the no-hook-names-the-config-file lint) |
| `bash tests/test-gate-opt-in.sh` | 0 | all pass |
| `bash tests/test-adopt.sh` | 0 | all pass |
| `bash tests/test-install-modules.sh` | 0 | 42 passed, 0 failed |
| `bash tests/test-config-registry.sh` | 0 | 50/50 passed |
| `bash tests/test-meta.sh` | 0 | all meta tests passed |
| `bash tests/test-kit-foldin-hooks.sh` | 0 | all passed |
| `bash tests/test-no-scattered-ids.sh` | 0 | 9/9 passed |
| `bash bin/lint --zone hooks --count` | 0 | 0 scattered ids |
| `shellcheck hooks/board-row-gate.sh tests/test-board-row-gate.sh` | 0 | clean |

## Negative control
```
Command: bash tests/test-board-row-gate.sh   (hook edited: NEW="" before the new-ID check)
Exit: 1
Verdict: PASS=33 FAIL=40
```
Run on top of the committed opt-out change (`d1b88f2`). Every blocking case flipped to allow, plus the two block-text checks and the log check. The edit was reverted with `git checkout -- hooks/board-row-gate.sh`, and the suite returned to PASS=73 FAIL=0, exit 0. Earlier rounds ran the same control: PASS=25 FAIL=23 on `e6f3a20`, PASS=30 FAIL=36 on `74307e9`.

Opt-out control, same commit: the hook edited to ignore the policy verdict (`PRC=0`).
```
Command: bash tests/test-board-row-gate.sh   (hook edited: policy exit 1 ignored)
Exit: 1
Verdict: PASS=70 FAIL=3
```
Cases 12.3 (committed opt-out), 12.4 (OFF-BY-CONFIG log), and 12.7 (operator overlay) went red; restored, PASS=73 FAIL=0.

## Review round

A fresh-context Opus review of `e6f3a20` returned FAIL with one critical, two high, and three medium or low findings. Each one is now a regression case:

| Finding | Severity | Fix | Case |
|---|---|---|---|
| `git add -A && git commit` in one call slipped through: the hook runs before the add | critical | read the working-tree board when an earlier `git add`/`rm`/`mv`/`stage` reaches it | 11.1, 11.2, 11.3, live run 3 |
| `echo 'remember to git commit later'` blocked | high | the commit must sit at command position | 11.7 |
| `git commit -- other` blocked on a staged board it leaves out | high | parse pathspecs; a non-covering one passes | 11.6 |
| marker in a later `echo -m` or heredoc counted | medium | message comes from the commit's own segment only | 11.10, 11.11 |
| `.` or `_meta` pathspec over an unstaged row missed | medium | covering pathspecs read the working tree | 11.4, 11.5 |
| `/usr/bin/git commit` not matched | medium | optional path prefix and env assignments | 11.8, 11.9 |
| `-F /dev/zero` hung | low | regular files only, read after the new-ID check | 11.15, 11.16 |
| `<<<` here-string read as a heredoc | low | here-strings skipped | 11.12 |
| `--amend` compared with HEAD | low | compare with `HEAD^` | 11.17, 11.18 |

Two review findings stay open, listed under Not proven.

## Real flow: headless Claude Code

A scratch repo with `DF-001` in HEAD's `_meta/BACKLOG.md`. The hook was wired through `--settings` only (`--setting-sources project`), so no other hook ran. Each run asked Haiku to run one command verbatim.

| Run | Command | Result |
|---|---|---|
| 1 | `git commit -m 'docs(board): file DF-002'`, DF-002 staged | blocked; commit count stayed 1; log `BLOCKED ... DF-002` |
| 2 | heredoc commit whose body carries `board-row-ok: blocked on a vendor reply outside the session` | commit landed (count 2) with the marker in its body; log `MARKER ... DF-002` |
| 3 (fixed hook) | `git add -A && git commit -m 'docs(board): file DF-003'`, DF-003 unstaged | blocked before the add ran; row still unstaged, count 2; log `BLOCKED ... DF-003` |

Run 1 tool result, trimmed:

```
BLOCKED: board-row-gate. This commit adds new board row(s) to _meta/BACKLOG.md in .../e2e/repo:
  DF-002
The commit message has no 'board-row-ok: <reason>' line.
```

## Latency

Payloads against ops-toolkit (a 576-line board), fixed hook:

| Command in payload | bash 5 | bash 3.2 |
|---|---|---|
| `ls -la` | 0.013s | 0.010s |
| `git status` | 0.013s | 0.010s |
| `git commit -m 'feat: x'`, board unchanged | 0.071s | 0.065s |
| heredoc commit, 1.5k-char message, board unchanged | 0.073s | 0.065s |

## Not proven
- Only the first `git commit` of a command is checked. `git commit ... ; git -C <board repo> commit ...` passes the second one unchecked (review finding, left open: agents rarely chain two commits in one call).
- A `git restore --staged <board>` or `git reset` earlier in the same call still blocks, because the hook sees the row staged. This fails in the safe direction; splitting the call clears it.
- The plugin path end to end: the live runs wired the hook through `--settings`, not `hooks/hooks.json`. The hooks.json entry is pinned by `tests/test-meta.sh` parity and the install tests, and goes live once the main checkout pulls the merge (next session).
- `bash -c '...'` wrappers, `--git-dir`/`--work-tree`, and `-C <commit>` message reuse. The last blocks when new IDs exist, as designed.
