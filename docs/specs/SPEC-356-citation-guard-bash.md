# SPEC-356: citation-guard runs as bash plus jq

**Status:** VALIDATED, revision 3 (round 2 APPROVED; its warnings folded in)
Lane: full
Type: spec-refactor
**Proof:** `docs/verification/citation-guard-bash.md`; `tests/test-citation-guard-parity.sh`, `tests/test-kit-foldin-hooks.sh`.
References: `hooks/citation-guard.py` at `ce08a00b` (the behavior to reproduce); `docs/specs/SPEC-355-money-gate-bash.md` (the sibling port and its round-1 lessons); `hooks/safety-gate.sh` (house style).

## Problem

`hooks/citation-guard.sh` is a shim that runs `hooks/citation-guard.py`. `docs/PHILOSOPHY.md` rules out Python in hooks, and the operator decided on 2026-09-28 to port the six Python hooks to bash plus jq, one PR per hook, enforcement hooks first. citation-guard is the Stop-hook enforcement hook: in strict mode it blocks a stop whose final message cites a `file:line` that does not resolve.

## Contract

`hooks/citation-guard.sh` does the whole job in bash, jq, and POSIX tools. It reproduces the Python hook's observable behavior (exit code, stderr, log line) as its shim surfaced it:

| Observable | Rule |
|---|---|
| Stdin | exactly one JSON object; anything else (malformed, empty, an array or scalar) exits 0 with no output and no log. The Python crashed on a non-object (exit 1, a traceback, never a block); the port exits 0 silently, a deliberate divergence |
| Transcript | `transcript_path` when truthy, else exit 0. A missing or unreadable file exits 0 |
| Final text | the transcript is JSONL, read line by line: a blank line or a line that is not valid JSON (garbage, a truncated last line) is skipped and reading CONTINUES. For each entry with `type == "assistant"` whose `message.content` is an array, collect the `text` (missing key = `""`) of every block with `type == "text"`; when at least one such block exists, their newline join replaces the kept text, even when that join is the empty string. So the kept text is the join from the LAST assistant entry that has a text block. Kept text empty or never set: exit 0. Malformed shapes the Python crashed on (exit 1, never a block): a line that parses to a non-object, an assistant `message` that is not an object, a text block whose `text` is present but not a string (null, a number, a bool, an object, an array). The Python crashed at that line, so nothing after it counts; the port exits 0 silently as soon as it meets one, a deliberate divergence |
| Stripping | remove, in this order, over the whole kept text (not line by line): fenced spans (a triple backtick to the NEXT triple backtick, across newlines, non-greedy; a four-backtick fence is not special), inline spans (a backtick, any run of non-backtick characters including newlines, a backtick), and URLs (`http://` or `https://` plus the run of non-whitespace after it). Whitespace here is Oniguruma's Unicode `\s` (jq's regex engine): it matches Python's on tab, newline, `\v`, `\f`, `\r`, space, U+0085, U+00A0, U+1680, U+2000 to U+200A, U+2028, U+2029, U+202F, U+205F, U+3000, and neither counts U+200B or U+FEFF. Python also counts `\x1c` to `\x1f`; Oniguruma does not (recorded divergence). An unclosed fence is not removed |
| Refs | every match of `([A-Za-z0-9._/-]+\.[A-Za-z0-9_]+):([0-9]+)\b` with Oniguruma's Unicode `\b`, leftmost and greedy like Python's `findall`. On realistic text the two agree: a letter, digit, or `_` after the digits is a word character (`a.md:3é`, `a.md:7_x` are not refs), punctuation is not (`“a.md:9”`, `a.md:8—x`, `a.md:7…`, `a.md:3,` are refs). Rare classes differ (recorded in Failure modes). Refs are deduplicated on (path, INTEGER value of the number), first occurrence order kept (`nope.md:07` and `nope.md:7` are one ref) |
| Root | `CITATION_GUARD_ROOT` when truthy, else the payload's `cwd` when truthy (an empty string is not), else the process's working directory. A path starting with `/` is used as is; any other is joined to the root |
| Resolve | a ref is bad when the target is not a regular file (`no such file`), cannot be read (`unreadable`), or its number is greater than the file's line count (`file has N lines`). The line count is the number of newline bytes plus one when the file is non-empty and does not end in a newline (Python's line iteration; `\r` alone never ends a line). Line 0 is never past EOF, but a missing file at line 0 is still bad (`nope.md:0 (no such file)`). Numbers compare as integers of any size |
| Bad text | `<path>:<number> (<reason>)`, where `<number>` is the decimal integer with leading zeros dropped (`a.md:006` prints `a.md:6`, and `00` prints `0`), joined by `; `. Numbers of any size compare and print as digit strings: jq numbers are doubles, so never run them through `tonumber` |
| Log | on any bad ref: append `<epoch>\t<sid>\t<bad text>` plus a newline, where `<sid>` is `sessionId` when truthy, else `session_id` when truthy, else `?`. The path is `$CITATION_GUARD_LOG` when SET, verbatim, even when empty; `~/.claude/dwarves-kit/logs/citation-guard.log` only when unset. The directory part is created first; when it is empty (an empty value, or a bare name) or cannot be created, no log is written anywhere and the hook carries on |
| Strict | `CITATION_GUARD_STRICT` exactly `1` (no trimming, `true` does not count): print `citation-guard: unresolved citations: <bad text>` to stderr and exit 2. Otherwise exit 0 |
| Latency | a 20 MB transcript, including a multi-MB single line (a large tool result) and non-assistant lines, checks in under 500 ms on an idle machine; stream the transcript line by line, never hold it all in one jq value (the hook timeout is 5 s) |
| Text handling | the hook sets `LC_ALL=C` for any awk, tr, wc, or sort it runs: Claude Code passes the user's locale (often `en_US.UTF-8`), and under it the stock macOS awk dies on a non-ASCII byte (exit 2, which would block a stop in log-only mode). The harness runs every case under `LANG=LC_ALL=en_US.UTF-8`. Text never goes through `awk -v` or argv |
| jq missing | exit 0 and print one line to stderr naming the missing tool (the gate is off) |
| jq version | 1.6 or later with Oniguruma (validation round 2 found 1.6, Apple's 1.7.1, and 1.8.2 agree on the corpus classes). This is the kit's first hook that uses jq's regex |
| Stdout | always empty |

`hooks/citation-guard.py` is deleted. The docs and tests that name it (`tests/test-kit-foldin-hooks.sh` line 807's file list, and any live doc the implementer finds with `git grep citation-guard.py`) say the logic now lives in `hooks/citation-guard.sh`. Dated records stay as written.

## Picture

```
 Stop --> hooks/anchor-root.sh --> hooks/citation-guard.sh
                                        |
            one JSON object with transcript_path? --no--> exit 0
                                        |
                                        v
             jq, streaming: last assistant entry with a text block
                                        |
                          no text --> exit 0
                                        v
           jq regex: strip fences, inline code, URLs; extract refs; dedupe
                                        |
                          no refs --> exit 0
                                        v
           resolve each ref against the root: missing, unreadable, past EOF
                                        |
                           none bad --> exit 0
                                        v
          append log line; strict=1? stderr + exit 2 : exit 0
```

## Design

The diagram is in `## Picture` above.

| Approach | Why not |
|---|---|
| `jq -s` over the transcript | fast enough (121 ms on 20 MB), but it aborts at the first line that is not JSON, where the Python skips it and reads on |
| grep for the regexes | ERE has no non-greedy fence match across lines and no `\b` that treats non-ASCII as a word character |
| one streaming jq pass picks the last text, one awk program strips and extracts | works, but awk is byte-oriented: the Unicode `\s` set and the Unicode `\b` have to be hand-coded, and under a UTF-8 locale the stock macOS awk dies on non-ASCII (validation round 1) |
| jq's own regex engine (Oniguruma) for the strip and the ref scan (chosen) | `gsub("(?s)```.*?```";"") \| gsub("`[^`]*`";"") \| gsub("https?://\\S+";"") \| scan(...)` matches Python's `findall` on the Unicode cases (validation round 1 ran it on jq 1.8.2); no awk, so no locale trap. The shell only counts lines and compares digit strings |

Python's `findall` is leftmost, and each match is greedy: the path run grabs as much as it can, then backtracks to the last `.` that leaves an extension followed by `:` and digits and a boundary. Oniguruma's backtracking gives the same matches. The digits use `[0-9]`, not `\d`: Oniguruma's `\d` may be Unicode, and the port cannot convert a Unicode digit. The corpus pins `v1.2:3`, `1.5:2`, `dash-name_v2.test.js`, and the boundary rows.

## Failure modes

| Class | Mitigation |
|---|---|
| A boundary, greedy-match, or ordering difference from Python | the parity corpus fails |
| Unicode digits (`a.md:٣`) | deliberate divergence: Python's `\d` reads them, the port reads ASCII digits only (a ref with a Unicode digit is not a ref, so it fails open); not in the corpus |
| Invalid UTF-8 in the transcript | deliberate divergence: the Python crashed (exit 1, never a block), jq substitutes U+FFFD and the port may flag a ref; not realistic from Claude Code |
| A 20 MB transcript | streamed; the parity test times it |
| A huge final message full of spans | jq's `gsub` and `scan` cost grows with length times match count (130 KB with 6,000 spans takes 7.5 s and times out, failing open); a final message that size is not realistic, so the ceiling is recorded, not fixed |
| Oniguruma vs Python `\b` and `\s` on rare classes | recorded divergence: after the digits, a combining mark (keycap `3️⃣`), connector punctuation (`‿`), or a circled letter makes a ref in Python and not in the port (fails open); `①`, `⁰`, `₁` make a ref in the port and not in Python; the URL strip differs on `\x1c` to `\x1f`. None appears in realistic agent prose |
| A hook error | never block by accident: only the strict path exits 2 |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: port | `hooks/citation-guard.sh`; delete `hooks/citation-guard.py` | `bash tests/test-citation-guard-parity.sh` passes every case and the latency check; no `python3` in the hook |
| T2: references | `tests/test-kit-foldin-hooks.sh`, live docs naming `citation-guard.py` | `bash tests/test-kit-foldin-hooks.sh` green; no live doc names the `.py` as current code |
| T3: records | `docs/CHANGELOG.md`, `docs/verification/citation-guard-bash.md`, `docs/implementation-notes/citation-guard-bash.md`, `docs/FEATURES.md` (regenerated) | CHANGELOG names the port, the jq 1.6 floor, and every recorded divergence (Unicode digits, the rare `\b`/`\s` classes, invalid UTF-8, the crash classes) |

## Test plan

| # | Check | Expect |
|---|---|---|
| P1 | `bash tests/test-citation-guard-parity.sh` | every case passes, `0 failed`, and the 20 MB line passes |
| P2 | `bash tests/test-kit-foldin-hooks.sh` | exit 0 |
| P3 | P1 under gawk and mawk (PATH shims), in case the port uses awk anywhere | every case passes |
| P4 | `grep -c python3 hooks/citation-guard.sh` | 0 |
| P5 | the 20 MB transcript timed on an idle machine | under 500 ms, recorded in the verification doc |

The harness (`tests/fixtures/citation-guard-parity/run-case.sh`) runs each case from the fixture root with its own HOME, and records any file the hook leaves in the root or HOME other than the log it was told to write.

Negative controls, through `lib/gate/negctl.sh` with P1 as the test command:

| Control | Mutation | Must go red |
|---|---|---|
| NC1 | skip the fence strip | `fenced-ignored` |
| NC2 | keep the first assistant text instead of the last | `all-resolve` (the old turn cites `nope.md:9`) |
| NC3 | treat `true` as strict | `strict-true-is-not-strict` |
| NC4 | count lines with `wc -l` (no final-line rule) | `past-eof` (`noeol.txt`) |
| NC5 | read the transcript with one jq call that stops at the first bad line | `nonjson-before-final` |
| NC6 | strip inline spans line by line | `inline-multiline-a` |

## Verification

P1 to P5 hold and NC1 to NC6 report PASS. `bash tests/run-all.sh --changed` exits 0.

## After state

citation-guard runs with no Python. Its behavior matches the Python hook (as its shim surfaced it) on the parity corpus, except the recorded divergences (Unicode digits, invalid UTF-8, the crash classes), and a 20 MB transcript checks inside the latency budget.

## Decision Log

- Goldens come from the `ce08a00b` shim and `.py`, generated by the orchestrator before the port; the implementer cannot fit the test to the code.
- The corpus pins quirks: strict is the literal `1`; the last assistant entry WITH a text block wins, even an empty one; `v1.2:3` and `1.5:2` are refs; an unclosed fence is not stripped; an empty log path or a bare file name writes no log. A relative path with a directory part (`logs/cg.log`) writes under the hook's working directory, as the Python does; the corpus leaves that case out because it would write into the fixture tree.
- Revision 3 (round 2 APPROVED, critical=0): the rules restated as Oniguruma's `\s` and `\b` with the Python delta recorded; line 0 and `00`; the full crash-class list; the jq floor; the cost ceiling; the harness checks stdout is empty and the log epoch is numeric; two new goldens (`line-zero-missing`, `crash-text-null-before-ref`).
- Revision 2 (validation round 1): jq's regex engine replaces awk (the locale trap, the Unicode `\s` and `\b`); the harness runs under a UTF-8 locale; 16 new goldens (multi-line inline spans, the URL whitespace set, non-JSON lines, empty last text, leading zeros, a four-backtick fence, Unicode punctuation after the digits, `cwd: ""`, three crash classes); the latency fixture gains a multi-MB line.
- The implementer is Devin (`devin -p`, headless, sandboxed) in this worktree; the orchestrator owns the spec, the goldens, verification, review, and ship.
