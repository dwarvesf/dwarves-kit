# SPEC-408: backlog-stage runs as bash plus jq

**Status:** VALIDATED, revision 2 (round 1 NEEDS REVISION folded; see Decision Log)
Lane: full
Type: spec-refactor
**Proof:** `docs/verification/backlog-stage-bash.md`; `tests/test-backlog-stage-parity.sh`, `tests/test-kit-foldin-hooks.sh`, `tests/test-intake-sweep.sh`, `tests/test-hook-util.sh`.
References: `hooks/backlog-stage.py` and its shim at `b9306b37` (the behavior to reproduce); `docs/specs/SPEC-407-intake-sweep-bash.md` (the grammar twin and the shlex splitter this port reuses); `docs/specs/SPEC-406-context-hints-bash.md`; `tests/lib/hook-parity.sh`.

## Problem

`hooks/backlog-stage.sh` is a shim that gates on `BACKLOG_STAGE_AUTO`, runs `hooks/intake-sweep.py` on the surface pass, and runs `hooks/backlog-stage.py`. `docs/PHILOSOPHY.md` rules out Python in hooks, and the operator decided on 2026-09-28 to port the Python hooks to bash plus jq, one PR per hook. intake-sweep (SPEC-407) already landed with the staging-grammar jq twin; this port reuses it. backlog-stage is opt-in (`BACKLOG_STAGE_AUTO`), so the cost it removes is the python3 starts on a consumer that turned it on: one at SessionStart, one at SessionEnd, and a third for the detached child.

## Contract

`hooks/backlog-stage.sh` does the whole job in bash and jq. It reproduces the Python hook's observable behavior: stdout, stderr, exit code, the staging file, the throttle stamp, and the exact prompt the model receives.

| Observable | Rule |
|---|---|
| Exit code | always 0. A shape the Python crashed on stages nothing and prints nothing; the throttle stamp it had already written stays |
| Opt-in | unless `$BACKLOG_STAGE_AUTO` is exactly `1`, `true`, `yes`, or `on` (lowercase, not trimmed), exit 0 with no output, whatever the arguments. The detached child inherits the variable from its parent, so it passes the gate too |
| Surface | with `--surface` anywhere in the arguments: run `hooks/intake-sweep.sh` first (its output comes first), then, when `$BACKLOG_STAGE_STAGING` (default `<root>/_meta/backlog-staging.md`) is a valid UTF-8 file (an invalid one prints nothing), count its lines (a lone `\r` ends a line) that start with `## [staged]` and print `📋 N backlog candidate(s) staged in <staging>.` when N is not zero. Nothing else runs |
| Root | `$REPO_ROOT` when non-empty, else `git rev-parse --show-toplevel`, else the physical cwd |
| Stdin | exactly one JSON object with a truthy `transcript_path`; anything else (empty, malformed, trailing data, a BOM, a list, a missing or falsy path) exits 0 with no throttle stamp. A truthy `transcript_path` that is not a string passes the throttle (the stamp is written) and then ends the run. A lone high surrogate escape is accepted, as in Python |
| Throttle | `$BACKLOG_STAGE_MIN_INTERVAL` as an integer (blanks and a sign allowed), default 3600 when unset or not an integer; zero or negative turns it off. Otherwise the stamp `<state dir>/last-run`: when it exists and is younger than the interval, exit 0; else create it and go on. State dir `$BACKLOG_STAGE_STATE_DIR` when SET (empty means the cwd and the directory cannot be created), else `~/.claude/dwarves-kit/state/backlog-stage`. The stamp is written before the transcript is read |
| Transcript text | `$BACKLOG_STAGE_MAXCHARS` (default 12000; an integer with blanks and a sign allowed, clamped past 18 digits; any other value ends the run). From the file at `transcript_path` (a missing or unreadable file is empty text; a file that is not valid UTF-8 ends the run): every non-blank line that parses as JSON (a first line that starts with a BOM does not); a line that does not parse is skipped, a line that parses to a non-object ends the run. An entry whose `type` is `user` or `assistant` contributes the `text` of each block in `message.content` that is an object with `type` `text` and a truthy `text`, in order, newline-joined; a `message` that is truthy and not an object, a `content` that is a number or `true`, or a non-string `text` ends the run. A `content` that is a string or an object contributes nothing. The last MAXCHARS characters are kept when the text is longer (zero keeps everything; a negative value drops that many from the front). A text with no non-blank character ends the run |
| Pre-filter | unless `$BACKLOG_STAGE_PREFILTER` is exactly `0`, a text with none of the forward-intent phrases (`todo`, `to-do`, `backlog`, `we should`, `i should`, `should we`, `let's`, `lets`, `next time`, `follow up`, `follow-up`, `followup`, `remind me`, `reminder`, `need to`, `have to`, `going to`, `gonna`, `plan to`, `want to`, `in the future`, `revisit`, `circle back`, `action item`, `down the line`, `later on`, `come back to`, `for later`, as whole words, case-insensitive) ends the run before the model call |
| Date | `_today` from the payload when truthy (Python's `str()` of a scalar: `None`, `True`, a decimal integer), else today's local date |
| Run | `$BACKLOG_STAGE_SYNC` truthy (`1`, `true`, `yes`, `on`, trimmed, any case): stage inline. Otherwise write `{text, date, backlog, staging}` to `<state dir>/payload-<pid>.json`, start `--staged-run <file>` in the background in its own process group, print `backlog-stage: fired detached (candidates land in <staging> after this hook returns)` on stderr, and return. A state dir that cannot be created means nothing runs and nothing prints |
| `--staged-run` | `--staged-run` anywhere in the arguments; the file is the next argument. It reads the payload file, stages from it, and always removes the file (a missing, corrupt, or incomplete file included). The file must be valid UTF-8 without a BOM and an object with all four keys (`text`, `backlog`, `staging` strings, `date` any value, printed as `str()` does), else nothing is staged and no model call is made. No file argument or a missing file does nothing |
| Extractor | `$BACKLOG_STAGE_EXTRACTOR` when non-empty, else `claude -p --model haiku --setting-sources project`, split like Python's `shlex.split` and run with the prompt on stdin and a 120 s timeout. Its stdout is kept whatever its exit status, except that a run that times out is killed and its stdout is thrown away. A command string shlex refuses, or one with no words in it, ends the run; so does output that is not valid UTF-8 |
| Prompt | the fixed head (`You extract FORWARD-LOOKING work-items ...Transcript follows:` and a blank line) followed by the transcript text, byte for byte |
| Model output | the first balanced `[...]` of the output, counting brackets with no regard for strings, parsed as JSON; no `[`, no balance, a parse error, or a non-list means no candidates. No candidates ends the run |
| Dedup | against `$BACKLOG_STAGE_BACKLOG` (default `<root>/_meta/BACKLOG.md`) rows `\| ID-N \| Item \|` and the headings `## [state] title` of `$BACKLOG_STAGE_STAGING`, matched line by line; a set-but-empty path is the empty path. A candidate that is not an object, has an empty normalized title, or whose normalized title is known is skipped; each staged title joins the known set |
| Block | the shared grammar: title, intent, approach, `#u-` and `#f-` (`hi`, `mid`, `lo`, else `lo` and `mid`), home, `Source: session <date>`, whitespace collapsed |
| Append | a four-line header when the staging file is new, then the blocks, appended. A staging path with no directory part, or one that cannot be written, stages nothing |
| jq missing | exit 0 and print one line to stderr naming the missing tool (the harvest is off) |

`hooks/backlog-stage.py` is deleted. `docs/hooks.md`, the test headers, and the module docs stop naming it.

## Picture

```
 SessionStart --> backlog-stage.sh --surface --> intake-sweep.sh --> count "## [staged]" --> one line
 SessionEnd   --> backlog-stage.sh
                    |  AUTO knob? throttle stamp, transcript text, pre-filter   (cheap, inline)
                    v
         payload-<pid>.json --> detached child: backlog-stage.sh --staged-run <file>
                                   |  extractor (stdin prompt, 120 s) --> first [...] --> candidates
                                   |  dedup (board rows + staging headings) --> render (staging-format.jq)
                                   v
                              append to _meta/backlog-staging.md
```

## Design

The cheap half stays inline and the slow half moves to a detached child, as in the Python. The child is the same script with `--staged-run`, started with job control on so it has its own process group, and with `nohup` so a hangup does not reach it. The Python used `start_new_session`, a new session; bash has no `setsid` on macOS, so this is the closest portable equivalent and the one recorded divergence of the design.

The transcript walk is one jq program over the raw lines that mirrors the Python's crash points with a flag, as the citation-guard port does, so a bad shape stops the run before the extractor is called. The bracket scan is a `reduce` over code points, not a regex, because the Python counts brackets without regard for JSON strings and the port must keep that quirk.

## Failure modes

| Class | Mitigation |
|---|---|
| A rule differs from Python | the parity corpus (goldens from Python, including the exact prompt) fails |
| Not a new session | the detached child shares the hook's session, with its own process group. A harness that kills the whole session rather than the group would take it down; Claude Code's hook timeout kills the process it started |
| Out of parity, no realistic input | invalid UTF-8 in the transcript or the model output; `NaN` in a JSON line; a candidate field that is a list or object (Python prints its repr); a `\r` alone as a line break in the transcript; a `transcript_path` that is not a string; `str.strip()` whitespace that Oniguruma's `\s` omits (`\x1c` to `\x1f`, folded in by hand); a pre-filter boundary next to a combining mark |
| Concurrent hooks | no lock on the staging file, as in Python; the hourly throttle makes two writers rare |
| jq missing | exits 0 and names the missing tool on stderr |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: harness | `tests/lib/hook-parity.sh`, `tests/test-hook-parity-lib.sh` | `settle`, `@HOME@`/`@CWD@` in seeds and args, `@PATH@` in env values, and `base64:` seeds work and are self-tested |
| T2: goldens | `tests/fixtures/backlog-stage-parity/` | cases and goldens generated from the Python at `b9306b37` before the port |
| T3: port | `hooks/backlog-stage.sh`; delete `hooks/backlog-stage.py` | `bash tests/test-backlog-stage-parity.sh` passes; no `python` in the hook |
| T4: references | `docs/hooks.md`, `docs/test-value-audit.md`, `tests/test-kit-foldin-hooks.sh`, the install and adopt lists | no live doc or test names `backlog-stage.py` as current code |
| T5: records | `docs/CHANGELOG.md`, `docs/verification/backlog-stage-bash.md`, `docs/implementation-notes/backlog-stage-bash.md`, `docs/retro/`, `docs/FEATURES.md` (regenerated) | CHANGELOG names the port |

## Test plan

| # | Check | Expect |
|---|---|---|
| P1 | `bash tests/test-backlog-stage-parity.sh` | every case passes, `0 failed` |
| P2 | `bash tests/test-kit-foldin-hooks.sh`, `bash tests/test-intake-sweep.sh`, `bash tests/test-hook-parity-lib.sh`, `bash tests/test-staging-format-jq.sh` | exit 0 |
| P3 | P1 under `/bin/bash` (3.2) and `/usr/bin/jq` (1.7.1) | pass |
| P4 | 500 real session transcripts through the Python and the port, extractor stubbed to a fixed answer | identical prompt, staging, stderr |
| P5 | `grep -c python hooks/backlog-stage.sh` | 0 |

Negative controls, through `lib/gate/negctl.sh` with P1 as the test command:

| Control | Mutation | Must go red |
|---|---|---|
| NC1 | count brackets to the last `]`, not the matching one | `stage-two-arrays-first-only` |
| NC2 | read a string `content` as text | `transcript-string-content-ignored`, `transcript-only-string-content` |
| NC3 | never write the throttle stamp (in `lib/reflect/hook-util.sh`) | `throttle-first-run-creates-stamp`, `crash-maxchars-invalid`, `throttle-before-transcript-read` |
| NC4 | drop the board dedup | `dedup-board`, `dedup-board-case-and-punctuation` |
| NC5 | keep the payload file after `--staged-run` | the `staged-run-*` and `detached-*` cases |
| NC6 | exempt `--staged-run` from the `BACKLOG_STAGE_AUTO` gate | `staged-run-without-auto` |
| NC7 | skip the forward-intent pre-filter | the `prefilter-miss*` cases |
| NC8 | hand the extractor the transcript text plus a trailing newline | every case that stages, through the prompt's byte count |

## Verification

P1 to P5 hold and NC1 to NC8 report PASS. `bash tests/run-all.sh --changed` exits 0.

## After state

backlog-stage runs with no Python, on the staging grammar twin. Its prompt, staging file, and state match the Python on the parity corpus and on real transcripts. One Python hook remains (harvest).

## Decision Log

- Goldens come from the Python hook at `b9306b37`, run through that revision's shim, before the port was written. They include the exact prompt the model was sent, so the transcript walk is pinned byte for byte.
- The Python swallowed every crash (`|| true`), so a crash case's golden is a silent exit 0 plus whatever the Python had already written.
- The detached child cannot be a new session without `setsid`; a new process group is the recorded substitute.
- Revision 2 (round 1 of the fresh review, NEEDS REVISION, 2 critical): the detached payload carried the transcript text through `jq --arg` and split its fields on a control byte, so a U+0001 in the text, or a text past the argument limit, staged nothing or staged to a junk path; the payload is now built from files, each field is read on its own, and the file is moved into place whole. A timed-out extractor's stdout is discarded as `subprocess.run` does (the timeout marker lives in `hook-util.sh`); a blank extractor command, an invalid-UTF-8 transcript, model output, staging file, or payload, a truthy non-string `transcript_path`, a `--staged-run` that is not the first argument, and a `null` or `true` date all follow the Python. The corpus gained the cases (invalid UTF-8 through `base64:` seeds the harness now supports) and the string-content gap is recorded, not fixed.
