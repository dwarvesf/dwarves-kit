# SPEC-356: citation-guard runs as bash plus jq

**Status:** DRAFT
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
| Stdin | exactly one JSON object; anything else (malformed, empty, an array or scalar) exits 0 with no output and no log. The Python crashed on a non-object (exit 1, a traceback); the port exits 0 silently, a deliberate divergence |
| Transcript | `transcript_path` when truthy, else exit 0. A missing or unreadable file exits 0 |
| Final text | the transcript is JSONL; lines that are blank or not JSON are skipped. For each entry with `type == "assistant"` whose `message.content` is an array, the `text` of every block with `type == "text"` is joined with a newline; when that join is non-empty (at least one text block), it replaces the kept text. So the kept text is the LAST assistant entry that HAS a text block, even when a later assistant entry has none. No kept text: exit 0 |
| Stripping | remove, in this order: fenced spans (a triple backtick to the NEXT triple backtick, across newlines, non-greedy), inline spans (a backtick, any run of non-backtick characters including newlines, a backtick), and URLs (`http://` or `https://` plus the run of non-whitespace after it). An unclosed fence is not removed |
| Refs | every match of `[A-Za-z0-9._/-]+` then `.` then `[A-Za-z0-9_]+`, a `:`, then ASCII digits, where the character after the digits is not a word character. A word character is `[A-Za-z0-9_]` or any non-ASCII byte (so `a.md:3é` and `a.md:7_x` are not refs, `a.md:3,` and `(a.md:99)` are). The regex is leftmost and greedy like Python's `findall`. Refs are deduplicated on (path, number), first occurrence order kept |
| Root | `CITATION_GUARD_ROOT` when truthy, else the payload's `cwd` when truthy, else the process's working directory. A path starting with `/` is used as is; any other is joined to the root |
| Resolve | a ref is bad when the target is not a regular file (`no such file`), cannot be read (`unreadable`), or its number is greater than the file's line count (`file has N lines`). The line count is the number of newline bytes plus one when the file is non-empty and does not end in a newline (Python's line iteration; `\r` alone never ends a line). Line 0 is never bad. Numbers compare as integers of any size |
| Bad text | `<path>:<number> (<reason>)`, where `<number>` is the decimal integer (leading zeros dropped), joined by `; ` |
| Log | on any bad ref: append `<epoch>\t<sid>\t<bad text>` plus a newline, where `<sid>` is `sessionId` when truthy, else `session_id` when truthy, else `?`. The path is `$CITATION_GUARD_LOG` when SET, verbatim, even when empty; `~/.claude/dwarves-kit/logs/citation-guard.log` only when unset. The directory part is created first; when it is empty (an empty value, or a bare name) or cannot be created, no log is written anywhere and the hook carries on |
| Strict | `CITATION_GUARD_STRICT` exactly `1` (no trimming, `true` does not count): print `citation-guard: unresolved citations: <bad text>` to stderr and exit 2. Otherwise exit 0 |
| Latency | a 20 MB transcript checks in under 500 ms on an idle machine under the stock macOS awk, gawk, and mawk; stream the transcript, never hold it all in one jq value (the hook timeout is 5 s) |
| Text handling | all text is handled as bytes; pass it to awk on stdin or in a file, never through `awk -v` or argv |
| jq missing | exit 0 and print one line to stderr naming the missing tool (the gate is off) |

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
           awk: strip fences, inline code, URLs; extract refs; dedupe
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
| `jq -s` over the transcript | holds a 20 MB file in one value; slow and memory-heavy |
| grep for the regexes | ERE has no non-greedy fence match across lines and no `\b` that treats non-ASCII as a word character |
| one streaming jq pass picks the last text, one awk program strips and extracts (chosen) | jq keeps the transcript streamed; awk handles the fence and inline stripping with an explicit scan and does the ref walk byte by byte |

The ref walk: Python's `findall` is leftmost, and each match is greedy: the path run grabs as much as it can, then backtracks to the last `.` that leaves an extension followed by `:` and digits and a boundary. The port reproduces that: at each start position, try the longest path run and back off. The corpus pins `v1.2:3`, `1.5:2`, `dash-name_v2.test.js`, and the boundary rows.

## Failure modes

| Class | Mitigation |
|---|---|
| A boundary, greedy-match, or ordering difference from Python | the parity corpus fails |
| Unicode digits (`a.md:٣`) | deliberate divergence: Python's `\d` reads them, the port reads ASCII digits only; not in the corpus |
| A Unicode non-word character right after the digits (`a.md:3—`) | deliberate divergence: Python matches (not a word character), the port does not (any non-ASCII byte counts as one); not in the corpus |
| A 20 MB transcript | streamed; the parity test times it |
| A hook error | never block by accident: only the strict path exits 2 |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: port | `hooks/citation-guard.sh`; delete `hooks/citation-guard.py` | `bash tests/test-citation-guard-parity.sh` passes every case and the latency check; no `python3` in the hook |
| T2: references | `tests/test-kit-foldin-hooks.sh`, live docs naming `citation-guard.py` | `bash tests/test-kit-foldin-hooks.sh` green; no live doc names the `.py` as current code |
| T3: records | `docs/CHANGELOG.md`, `docs/verification/citation-guard-bash.md`, `docs/implementation-notes/citation-guard-bash.md`, `docs/FEATURES.md` (regenerated) | CHANGELOG names the port and both divergences |

## Test plan

| # | Check | Expect |
|---|---|---|
| P1 | `bash tests/test-citation-guard-parity.sh` | every case passes, `0 failed`, and the 20 MB line passes |
| P2 | `bash tests/test-kit-foldin-hooks.sh` | exit 0 |
| P3 | P1 under gawk and mawk (PATH shims) | every case passes |
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

## Verification

P1 to P5 hold and NC1 to NC4 report PASS. `bash tests/run-all.sh --changed` exits 0.

## After state

citation-guard runs with no Python. Its behavior matches the Python hook (as its shim surfaced it) on the parity corpus, except the two recorded Unicode divergences and the non-object crash, and a 20 MB transcript checks inside the latency budget.

## Decision Log

- Goldens come from the `ce08a00b` shim and `.py`, generated by the orchestrator before the port; the implementer cannot fit the test to the code.
- The corpus pins quirks: strict is the literal `1`; the last assistant entry WITH a text block wins; `v1.2:3` and `1.5:2` are refs; an unclosed fence is not stripped; an empty or relative log path writes no log.
- The implementer is Devin (`devin -p`, headless, sandboxed) in this worktree; the orchestrator owns the spec, the goldens, verification, review, and ship.
