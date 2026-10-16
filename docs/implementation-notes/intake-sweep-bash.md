# Implementation notes -- intake-sweep-bash

Deltas from SPEC-407. Nothing here repeats what the spec already states.

## 2026-10-16 One jq program for the dedup, bash for the reading

- Context: the Python reads each source, then dedups and renders per candidate in one loop, and a crash anywhere stops the run before the append.
- Decision/Change: bash reads each source into a JSON array of mapped items and keeps going; one jq program takes every source's items plus the board, staging, and swept-keys text and returns the blocks, the keys, and the per-source counts. A crash shape in any source makes the read return 1, and the hook exits before that program runs.
- Why: the order that matters (every source read, then one atomic decision, then the append) falls out of the shape, and the Python's "known titles grow as items stage" is a `reduce` over the items.

## 2026-10-16 Case folding by table, not by `ascii_downcase`

- Context: `norm` is `str.casefold` plus `[^\W_]+`. The operator writes Vietnamese titles, and `ascii_downcase` would call `ĐÀ NẴNG` and `đà nẵng` two different titles.
- Decision/Change: `staging-format.jq` carries Python 3.12's casefold as 195 `[first, last, step, delta]` ranges and 104 multi-character entries, generated once from Python and pinned by `tests/test-staging-format-jq.sh` (every changed code point plus 400 unchanged ones). `[\p{L}\p{N}]+` equals Python's word class on every code point Python 3.12 knows; Oniguruma also knows the newer ones.
- Impact: dedup keys agree with the Python on every title, accented or not.

## 2026-10-16 A bare staging heading borrows the next line, in both

- Context: `staging-format.py` reads a block from its heading to the next heading and applies `##\s*\[([^\]]+)\]\s*(.+)` to it. A heading with no title (`## [staged]` then `- Intent: x`) lets `\s*` eat the newline and `(.+)` take the next line as the title, so `intent x` becomes a known title.
- Decision/Change: the twin splits the text at heading starts and applies the same pattern to each block alone, so it borrows the same line. A corpus case pins it (`dup-staging-heading-without-title`).
- Why: parity includes the quirks; fixing it is a separate behavior change with its own spec.

## 2026-10-16 The command source runs in the background, with a watchdog

- Context: the Python used `subprocess.run(..., timeout=)`; bash has no `timeout` on macOS.
- Decision/Change: `run_capture` starts the command in the background with its stdout to a file and a subshell that sleeps and then `kill -9`s it. Bash gives a background command `/dev/null` for stdin, where the Python inherited the hook's stdin; no source command reads it.

## 2026-10-16 What the fresh review changed

- Context: one Opus reviewer ran 690 cases (600 random) and found two critical issues and twelve warnings. The random cases all matched; the findings came from classes nobody had written down.
- Decision/Change: `hu_mtime` reads GNU `stat -c %Y` first (BSD `stat -f %m` on Linux prints several lines and exits 1, which killed the throttle after its first stamp); the command source's output file lives in a temp dir the hook removes on exit, and the watchdog's `sleep` is reaped; items and the batch go to jq through files (`--slurpfile`), not arguments, because a 6,000-row ledger overran the argument limit; `include`, `kind`, `name`, and the map keys crash where Python crashes (an `include` typo on an empty file does not); a BOM and invalid UTF-8 are read as Python reads them; the board, staging, and swept-keys files follow universal newlines and `splitlines`; a joined root path is not doubled; an unset `HOME` no longer stops the hook (the same bug is fixed in context-hints).
- Why: each is a way the port could stage nothing, or stage differently, on a host or a file the corpus did not cover. 27 corpus cases and `tests/test-hook-util.sh` pin them.

## 2026-10-16 Real data

- The real digest ledger, board, and staging file on this machine (148 ledger rows, 536 board lines, 970 staging lines) went through the Python and the port in three scenarios (real files, empty board and staging, board only): identical stdout, staging bytes, and swept keys. See `docs/verification/intake-sweep-bash.md`.
