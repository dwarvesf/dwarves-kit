# SPEC-355: money-gate runs as bash plus jq

**Status:** DRAFT, revision 2 (validation round 1 folded in)
Lane: full
Type: spec-refactor
**Proof:** `docs/verification/money-gate-bash.md`; `tests/test-money-gate-parity.sh`, `tests/test-money-gate.sh`.
References: `hooks/money-gate.py` at `ce08a00b` (the behavior to reproduce); `lib/money-gate/SPEC.md` (the module contract, unchanged); `hooks/safety-gate.sh` (house style for a bash + jq + awk hook).

## Problem

`hooks/money-gate.sh` is a shim that runs `hooks/money-gate.py`. `docs/PHILOSOPHY.md` rules out Python in hooks: every hook call pays a python3 start, and the operator decided on 2026-09-28 to port the six Python hooks to bash plus jq, one PR per hook, enforcement hooks first. money-gate is one of the two enforcement hooks.

## Contract

`hooks/money-gate.sh` does the whole job in bash, jq, and POSIX tools (awk, grep, sed, sort). It reproduces the Python hook's observable behavior exactly:

| Observable | Rule |
|---|---|
| Exit code | always 0 |
| Inert | `MONEY_GATE_REPOS` unset or empty: exit 0 with no output and no log |
| Stdin | must be exactly one JSON object; anything else (malformed, empty, two concatenated values, an array or scalar) exits 0 with no output and no log |
| Other shapes | a `tool_input` that is truthy but not an object, or a truthy `file_path`/`path` that is not a string: exit 0, no output, no log (the Python crashed there and its shim swallowed the crash) |
| Location match | `haystack = file_path + "\n" + cwd`, where `file_path` is the first of `tool_input.file_path`, `tool_input.path` that is truthy in Python's sense (not null, `""`, `false`, `0`, `[]`, `{}`), else `""`, and `cwd` is `.cwd` when truthy, else `""`. Strings are used byte for byte: a trailing newline or a tab stays in. A repo name `r` (a non-empty `:`-separated entry of `MONEY_GATE_REPOS`) matches when `haystack` contains `/r/` or ends with `/r`. Literal substring match, no regex |
| Scanned text | `file_path`, then every string value anywhere under `tool_input` (recursive over objects and arrays, in document order), joined by newlines. Keys, numbers, booleans, and null are never scanned |
| Money terms | Python's `MONEY_RE`, case-insensitive: a term from the list, optional trailing `s`, where the character before is not `[A-Za-z0-9]` (or is the start) and the character after is not `[A-Za-z0-9]` (or is the end). `_`, `-`, blanks, and punctuation count as separators. The term list and the `[_-]?` variants are exactly those in `money-gate.py` |
| Hits | every match, lowercased, deduplicated, sorted by byte order (`LC_ALL=C`) |
| Log | on any hit: append `<epoch>\t<file_path>\t<hits joined by ",">` plus a newline. The path is `$MONEY_GATE_LOG` when the variable is SET, verbatim, even when empty; `~/.claude/logs/money-gate.log` only when it is unset. The directory part is created first; when it is empty (an empty value, or a bare name like `rel.log`) or cannot be created, no log is written anywhere and the hook carries on (Python's `os.makedirs("")` failure, caught) |
| Strict | `MONEY_GATE_STRICT`, trimmed of blanks (spaces, tabs, newlines) and lowercased, in `1 true yes on`; the ask prints even when the log could not be written: print one JSON object `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":<reason>}}` |
| Reason | `money-gate: edit in a financial repo touches <first 6 hits joined by ", ">: confirm before applying.` |
| Text handling | the scanned text is handled as bytes: a NUL, a literal backslash sequence (`\\n` in source code), or any non-ASCII byte is data, never an escape or a terminator. Pass it to awk on stdin or in a file, never through `awk -v` or argv (escape processing, and Linux caps one argument at 128 KB) |
| Latency | a 1 MB payload finishes in under 500 ms on an idle machine under the stock macOS awk, gawk, and mawk (the hook timeout is 5 s, and a timed-out hook does not fire) |
| jq missing | exit 0 and print one line to stderr naming the missing tool (the gate is off) |

`hooks/money-gate.py` is deleted. The docs that name it (`lib/money-gate/README.md`, `lib/money-gate/SPEC.md` "Where the code lives", `lib/config/module-registry.md`, the header of `tests/test-money-gate.sh`, `docs/test-value-audit.md`) say the logic now lives in `hooks/money-gate.sh`. Dated records (CHANGELOG entries, proofs, retros) stay as written.

## Picture

```
 PreToolUse(Edit|Write|MultiEdit) --> hooks/anchor-root.sh --> hooks/money-gate.sh
                                                                  |
                           MONEY_GATE_REPOS set? --no--> exit 0   |
                                                                  v
                     jq: file_path, cwd, all strings under tool_input (recursive)
                                                                  |
                              repo in haystack? --no--> exit 0    |
                                                                  v
                  awk: boundary-aware term scan --> hits (lower, uniq, C sort)
                                                                  |
                                 no hits --> exit 0               |
                                                                  v
                     append log line; strict? print ask JSON; exit 0
```

## Design

Approaches considered:

| Approach | Why not |
|---|---|
| `grep -oiE` with `(^|[^A-Za-z0-9])` around the term | the consumed boundary character hides an adjacent match (`amount_balance` finds only `amount`); a second pass over the remainder gets that back but is fragile |
| perl for lookarounds | perl in a hook is the same dependency class PHILOSOPHY rules out for Python |
| awk, per-position walk | lowercase the text, then test every term at every position. 4 s on a 100 KB line under the stock macOS awk (validation round 1): past the timeout, the gate silently does not fire |
| awk, one `index()` loop per term (chosen) | for each term (each `[_-]?` variant expanded), find every occurrence with `index()` and keep those whose neighbours pass the boundary test; 0.16 s on 1 MB under the stock macOS awk |

Why a per-term search equals `finditer`: the boundaries are zero-width lookarounds, so no separator is ever consumed and `amount_balance` yields both terms. No term is a prefix of another, and a term's own separators (`private_key`, `api-key`, `net_worth`, `account_number`) never split off another term, so two matches never compete for the same text and alternation order cannot matter. The optional `s` is taken whenever it is followed by a boundary (`amounts` hits `amounts`, not `amount`). The parity corpus pins it. The diagram is in `## Picture` above.

## Failure modes

| Class | Mitigation |
|---|---|
| A boundary or ordering difference from Python | the parity corpus (34 cases, goldens from Python) fails |
| A non-ASCII character next to a term | the port reads bytes under `LC_ALL=C`, so any non-ASCII byte is a separator, as it is in Python for ordinary text (`dưbalance` hits `balance`). Deliberate divergence: under `re.IGNORECASE` Python also folds a few Unicode letters into ASCII terms (the Kelvin sign in `private_Key`, the long s in `tranſfer`, dotted `İBAN`); the port does not. No realistic payload carries them, so the corpus does not pin them |
| Raw invalid UTF-8 in the payload | out of parity: Claude Code sends valid JSON, and Python's handling depends on the locale |
| jq missing | the hook exits 0 and names the missing tool on stderr (fail open, as the Python shim did when python3 was missing, but visible) |
| A hook error | never block: every path exits 0 |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: port | `hooks/money-gate.sh`; delete `hooks/money-gate.py` | `bash tests/test-money-gate-parity.sh` passes every case and the latency check; `bash tests/test-money-gate.sh` green; no `python3` in `hooks/money-gate.sh` |
| T2: references | `lib/money-gate/README.md`, `lib/money-gate/SPEC.md`, `lib/config/module-registry.md`, `tests/test-money-gate.sh` header, `docs/test-value-audit.md` | no live doc names `money-gate.py` as current code; `lib/money-gate/SPEC.md`'s stale rows are fixed too (its Modes table says strict is the literal `1`, it calls the keywords `\b`-anchored, and its step 1 says "before python3 is spawned") |
| T3: records | `docs/CHANGELOG.md`, `docs/verification/money-gate-bash.md`, `docs/implementation-notes/money-gate-bash.md`, `docs/FEATURES.md` (regenerated) | CHANGELOG names the port |

## Test plan

| # | Check | Expect |
|---|---|---|
| P1 | `bash tests/test-money-gate-parity.sh` | every case passes, `0 failed`, and the 1 MB latency line passes |
| P2 | `bash tests/test-money-gate.sh` | exit 0 |
| P3 | `bash tests/test-kit-foldin-hooks.sh` | exit 0 |
| P4 | P1 under gawk and mawk (PATH shims); the stock macOS awk is P1 itself | every case passes |
| P6 | the 1 MB payload timed on an idle machine, stock macOS awk | under 500 ms, recorded in the verification doc |
| P5 | `grep -c python3 hooks/money-gate.sh` | 0 |

The harness (`tests/fixtures/money-gate-parity/run-case.sh`) gives each case its own HOME and an empty cwd, and records any file the hook leaves there other than the log it was told to write, so a port that writes a log Python never wrote fails.

Negative controls, through `lib/gate/negctl.sh` with P1 as the test command:

| Control | Mutation | Must go red |
|---|---|---|
| NC1 | drop the left-boundary test | `no-embedded-only`, `plural-and-embedded` |
| NC2 | treat only `1` as strict | `strict-true-upper`, `strict-yes`, `strict-on` |
| NC3 | scan only `new_string` | `old-string-delete`, `multiedit-array`, `numbers-and-bools` |
| NC4 | fall back to `~/.claude/logs/money-gate.log` when `MONEY_GATE_LOG` is set but empty | `log-set-empty` (stray file) |

## Verification

P1 to P5 hold and NC1 to NC3 report PASS. `bash tests/run-all.sh --changed` exits 0.

## After state

money-gate runs with no Python. Its behavior is byte-identical to the Python hook (as its shim surfaced it) on the parity corpus, and a 1 MB Write checks inside the latency budget. Four Python hooks remain (backlog-stage, context-hints, harvest, intake-sweep), plus citation-guard in SPEC-356.

## Decision Log

- Goldens come from the Python hook, generated by the orchestrator before the port, so the implementer cannot fit the test to the code.
- Parity includes quirks (a bare `/w/fin` path with an unrelated cwd does not match; an empty or relative `MONEY_GATE_LOG` writes no log). A behavior change would be a separate spec.
- Goldens run through the `ce08a00b` shim, not the bare `.py`, so a Python crash reads as the shim surfaced it: exit 0, nothing printed.
- Revision 2 (validation round 1): per-term `index()` search for latency; exact log-path, truthiness, and stdin rules; 20 new corpus cases; a per-case HOME and cwd with a stray-file check; the Unicode case-folding divergence recorded.
- The implementer is Devin (`devin -p`, headless, sandboxed) in this worktree; the orchestrator owns the spec, the goldens, verification, review, and ship.
