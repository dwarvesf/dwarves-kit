# SPEC-406: context-hints runs as bash plus jq

**Status:** VALIDATED, revision 3 (round 1 NEEDS REVISION folded; see Decision Log)
Lane: full
Type: spec-refactor
**Proof:** `docs/verification/context-hints-bash.md`; `tests/test-context-hints-parity.sh`, `tests/test-kit-foldin-hooks.sh`.
References: `hooks/context-hints.py` at `b9306b37` (the behavior to reproduce); `docs/specs/SPEC-355-money-gate-bash.md` and `docs/specs/SPEC-356-citation-guard-bash.md` (the two ports this one follows); `tests/lib/hook-parity.sh` (the shared harness, SPEC-373).

## Problem

`hooks/context-hints.sh` is a shim that runs `hooks/context-hints.py`. `docs/PHILOSOPHY.md` rules out Python in hooks: every prompt pays a python3 start, and the operator decided on 2026-09-28 to port the Python hooks to bash plus jq, one PR per hook. money-gate (#822) and citation-guard (#823) landed. context-hints is the smallest of the four that remain and the only one with no shared library behind it, so it goes first.

## Contract

`hooks/context-hints.sh` does the whole job in bash and jq. It reproduces the Python hook's observable behavior: stdout, exit code, and the per-session state file.

| Observable | Rule |
|---|---|
| Exit code | always 0 |
| Stdin | exactly one JSON object. Anything else (empty, malformed, trailing data, two values, an array, a string, a number, `null`, or a BOM before the JSON) prints nothing and writes no state. A lone high surrogate escape (`\ud83d` with no low half, what a client sends when it cuts an emoji in half) is accepted, as Python accepts it, and read as U+FFFD |
| Prompt | `prompt` when truthy in Python's sense (not null, `""`, `false`, `0`, `[]`, `{}`), else `lastPrompt` when truthy, else `""` |
| Session id | `session_id` when truthy, else `sessionId` when truthy, else `default`. Python's `str()` of it must match `^[A-Za-z0-9_-]{1,64}$` (a trailing newline is allowed, as `$` allows it in Python), else `default`. A number is its decimal text (`123`, `-5`), `true` is `True`, and a float, list, or object falls to `default` |
| State file | `<state dir>/<session id>.json`, state dir `$CONTEXT_HINTS_STATE` when SET (even empty: then the path is relative to the cwd and the directory cannot be created), else `~/.claude/dwarves-kit/state/context-hints` |
| Now | read only when the temporal line is on. `$CONTEXT_HINTS_NOW` as a number (surrounding blanks allowed) when set and non-empty, else the real clock. A non-empty value that is not a number, a blank-only one included, prints nothing and writes no state |
| Temporal | skipped when `$CONTEXT_HINTS_TEMPORAL` is exactly `0`. Otherwise: read `{start, last}` from the state file (a missing, unreadable, or non-JSON file means start = last = now); a JSON value that is not an object prints nothing and writes nothing; a missing `start` or `last` means now. `start` is converted first: a string that does not parse as a number (surrounding blanks allowed) resets both to now without looking at `last`; null, a list, or an object prints nothing and writes nothing. Then `last` goes the same way. A string that parses, and `true`/`false`, count as numbers. A BOM before the JSON makes the file invalid (reset). Write `{start, last: now}` (silently skipped when the directory or file cannot be written). Elapsed = now - start, idle = now - last. Under 1 s elapsed: no line. Otherwise `Session time: <elapsed> elapsed, <idle> since your last prompt.`, plus a second line `consider /clear or /dcompact (cache-hygiene rule)` when elapsed is above 21600 s |
| Humanize | whole seconds, truncated toward zero. Under 60: `<n>s` (a negative idle prints as `-500s`). Under 3600: `<m>m<ss>s`. Otherwise `<h>h<mm>m` |
| Skill hints | only when the prompt has a non-blank character. The map is `$CONTEXT_HINTS_SKILLMAP` when SET (even empty: no map), else `context-hints-skills-map.json` beside the real hook file (symlinks resolved). A missing, BOM-prefixed, or non-JSON map gives no hints. A map that is JSON but not an object prints nothing at all (the temporal line is lost too; the state write stays). For each key in file order, when the key occurs in the prompt as a whole word, case-insensitively (the key is a literal, never a pattern; a word character is a letter, a digit, or `_`, so a combining accent is not one), add `<value> (keyword: <key>)`. A non-string value prints as Python's `str()`: `5`, `None`, `True`, `False` |
| Output | the temporal line(s), then `Maybe-relevant skills: ` plus the hints joined by `; `, one per line, newline-terminated. Nothing when there is nothing to say |
| Prompt not a string | a truthy prompt that is not a string (number, `true`, list, object) prints nothing; the state write stays |
| jq missing | exit 0 and print one line to stderr naming the missing tool (the hints are off) |

`hooks/context-hints.py` is deleted. `docs/hooks.md` and `tests/test-kit-foldin-hooks.sh` stop naming it. `hooks/context-hints-skills-map.json` stays: the bash hook reads it.

## Picture

```
 UserPromptSubmit --> hooks/anchor-root.sh --> hooks/context-hints.sh
                                                   |
                          jq: one JSON object? session id (validated)
                                                   |
        state file  <--- read ---+                 |
        (start, last)            v                 v
                          jq: now, elapsed, idle, line, nudge ----> map: keyword whole-word match
                                   |                                       |
                       write {start, last: now}                            v
                                   +------------> stdout: temporal line, hints line
```

## Design

One jq program takes the payload, the state text, the map text, and the two env values, and prints the state to write, a separator, and the text to print. Bash only reads the files, writes the state, and prints. This keeps every Python crash point in one place: the program returns "print nothing" for each, and returns the state write alongside it where Python had already written.

The keyword test finds every place the escaped key occurs, with a zero-width case-insensitive jq match (so overlapping hits count), then checks the characters on either side by hand with Python's word-character rule. Python lowercased both and ran `\b<key>\b`. The first draft used Oniguruma's own `\b`, which counts a combining accent as a word character and so differs on decomposed text (a Finder-pasted `cà phê`); Oniguruma also refuses a lookbehind under a case-insensitive match, so the boundary test cannot live in the pattern. The two agree on every realistic input, including Vietnamese, accents, Greek, and CJK (the corpus pins these).

Approaches considered:

| Approach | Why not |
|---|---|
| `ascii_downcase` on both sides, then `test` | leaves `ĐÀ NẴNG` against `đà nẵng` unmatched; the operator writes Vietnamese prompts |
| `awk tolower` | the stock macOS awk dies on a non-ASCII byte under UTF-8 (the SPEC-355 finding) |

## Failure modes

| Class | Mitigation |
|---|---|
| A rule differs from Python | the parity corpus (goldens from Python) fails |
| Out of parity, no realistic payload | invalid UTF-8; `NaN` or `Infinity` in the payload, state, or map (jq reads them as null); `CONTEXT_HINTS_NOW` spellings only Python's `float()` accepts (`1_000`, `inf`, `nan`); a Unicode character that Python's `lower()` folds differently from Oniguruma's case folding (the Kelvin sign, dotted `İ`, the long s); a map value that is a list or object (Python prints its repr); `str.strip()` whitespace that Oniguruma's `\s` omits (`\x1c` to `\x1f`) |
| The state file is written without a lock | as in Python; two concurrent prompts of one session can lose one `last` update, which only shifts an idle figure |
| jq missing | the hook exits 0 and names the missing tool on stderr (the Python shim failed with `exec: python3: not found`, exit 127; this fails open and says why) |
| A hook error | never block: every path exits 0 |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: harness | `tests/lib/hook-parity.sh`, `tests/test-hook-parity-lib.sh` | `seed`, `read`, and `@HOME@`/`@CWD@` work and are self-tested; the library runs under bash 3.2 (a `case` inside `$(...)` broke it) |
| T2: goldens | `tests/fixtures/context-hints-parity/` | cases and goldens generated from the Python at `b9306b37` before the port |
| T3: port | `hooks/context-hints.sh`; delete `hooks/context-hints.py` | `bash tests/test-context-hints-parity.sh` passes; no `python` in the hook |
| T4: references | `docs/hooks.md`, `docs/architecture.md`, `tests/test-kit-foldin-hooks.sh` | no live doc or test names `context-hints.py` |
| T5: records | `docs/CHANGELOG.md`, `docs/verification/context-hints-bash.md`, `docs/implementation-notes/context-hints-bash.md`, `docs/retro/`, `docs/FEATURES.md` (regenerated) | CHANGELOG names the port |

## Test plan

| # | Check | Expect |
|---|---|---|
| P1 | `bash tests/test-context-hints-parity.sh` | every case passes, `0 failed`; the 1 MB prompt, jq-missing, no-python, and symlink checks pass |
| P2 | P1 under `/bin/bash` (3.2) and under `/usr/bin/jq` (1.7.1) | every case passes |
| P3 | `bash tests/test-kit-foldin-hooks.sh` | exit 0 |
| P4 | real captured prompts and state files through the Python and the port | identical stdout, exit code, and state |
| P5 | `bash tests/test-hook-parity-lib.sh` | exit 0 |
| P6 | `grep -c python hooks/context-hints.sh` | 0 |

Negative controls, through `lib/gate/negctl.sh` with P1 as the test command:

| Control | Mutation | Must go red |
|---|---|---|
| NC1 | drop the state write that precedes a crash (the prompt is not a string, the map is not an object) | `crash-prompt-number`, `crash-prompt-list`, `crash-prompt-true`, `crash-map-list`, `crash-map-string`, `crash-map-null` |
| NC2 | treat a map that is not an object as no map | `crash-map-list`, `crash-map-string`, `crash-map-null` |
| NC3 | compare the nudge with `>=` instead of `>` | `nudge-at-threshold` |
| NC4 | drop the boundary test on the character after the key | `map-digit-is-word`, `map-keyword-with-plus`, `map-non-ascii-adjacent` |
| NC5 | drop the case-insensitive flag | `map-key-uppercase`, `map-prompt-uppercase`, `map-vietnamese`, `map-accent-case`, `map-greek-case` |

## Verification

P1 to P6 hold and NC1 to NC5 report PASS. `bash tests/run-all.sh --changed` exits 0.

## After state

context-hints runs with no Python. Its stdout, exit code, and state file match the Python hook on the parity corpus and on real captured prompts. Three Python hooks remain (backlog-stage, harvest, intake-sweep).

## Decision Log

- Goldens come from the Python hook at `b9306b37`, run through that revision's shim, before the port was written.
- The Python swallowed every crash itself (it catches `Exception` and exits 0), so no golden needs a recorded divergence: every crash class in the corpus is a real Python result.
- Parity includes the quirks: a crash after the state write keeps the write; a map that is not an object silences the temporal line too.
- The harness gains `seed`, `read`, and the `@HOME@`/`@CWD@` tokens here because this is the first port with state to seed and read back. The three following ports reuse them.
- Revision 2: a trailing newline in a session id is allowed, as Python's `$` allows it; `CONTEXT_HINTS_STATE` and `CONTEXT_HINTS_SKILLMAP` use set-versus-empty semantics; the bash 3.2 syntax error in the shared harness is fixed in this PR.
- Revision 3 (round 1 of the fresh review, NEEDS REVISION, no critical finding on Claude Code's real payload shape): the port now accepts a lone high surrogate, rejects a BOM, treats a blank `CONTEXT_HINTS_NOW` as a crash, trims state strings before reading them as numbers, and tests word boundaries by hand so decomposed accents behave as in Python. The Now, Temporal, and Session id rows were wrong and are rewritten; the Failure modes table gained the classes the review listed. The 17 corpus cases that pin these were added and the goldens regenerated from the Python.
