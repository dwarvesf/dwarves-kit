# SPEC-355: money-gate runs as bash plus jq

**Status:** DRAFT
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
| Malformed or empty stdin | exit 0, no output, no log |
| Location match | `haystack = file_path + "\n" + cwd`, where `file_path` is `tool_input.file_path`, else `tool_input.path`, else `""` (null counts as empty). A repo name `r` (a non-empty `:`-separated entry of `MONEY_GATE_REPOS`) matches when `haystack` contains `/r/` or ends with `/r`. Literal substring match, no regex |
| Scanned text | `file_path`, then every string value anywhere under `tool_input` (recursive over objects and arrays, in document order), joined by newlines. Keys, numbers, booleans, and null are never scanned |
| Money terms | Python's `MONEY_RE`, case-insensitive: a term from the list, optional trailing `s`, where the character before is not `[A-Za-z0-9]` (or is the start) and the character after is not `[A-Za-z0-9]` (or is the end). `_`, `-`, blanks, and punctuation count as separators. The term list and the `[_-]?` variants are exactly those in `money-gate.py` |
| Hits | every match, lowercased, deduplicated, sorted by byte order (`LC_ALL=C`) |
| Log | on any hit: append `<epoch>\t<file_path>\t<hits joined by ",">` to `$MONEY_GATE_LOG` (default `~/.claude/logs/money-gate.log`), creating its directory; a write failure is ignored |
| Strict | `MONEY_GATE_STRICT`, trimmed and lowercased, in `1 true yes on`: print one JSON object `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":<reason>}}` |
| Reason | `money-gate: edit in a financial repo touches <first 6 hits joined by ", ">: confirm before applying.` |

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
| awk scan (chosen) | lowercase the text, then walk it position by position, testing the term list and both boundaries by hand; no dependency beyond POSIX awk |

The implementation note: Python's boundaries are zero-width lookarounds, so a separator is never consumed and `amount_balance` yields both terms. `finditer` scans left to right, takes the first alternative in list order that matches at a position, consumes only the term (plus its optional `s`), and resumes right after it. The port does the same. The parity corpus pins it.

## Failure modes

| Class | Mitigation |
|---|---|
| A boundary or ordering difference from Python | the parity corpus (34 cases, goldens from Python) fails |
| A non-ASCII character next to a term | Python's `[A-Za-z0-9]` is ASCII-only, so a Vietnamese letter counts as a separator; the port uses the same byte classes under `LC_ALL=C` |
| jq missing | the hook exits 0 (fail open, as the Python shim did when python3 was missing) |
| A hook error | never block: every path exits 0 |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: port | `hooks/money-gate.sh`; delete `hooks/money-gate.py` | `bash tests/test-money-gate-parity.sh` 34/34; `bash tests/test-money-gate.sh` green; no `python3` in `hooks/money-gate.sh` |
| T2: references | `lib/money-gate/README.md`, `lib/money-gate/SPEC.md`, `lib/config/module-registry.md`, `tests/test-money-gate.sh` header, `docs/test-value-audit.md` | no live doc names `money-gate.py` as current code |
| T3: records | `docs/CHANGELOG.md`, `docs/verification/money-gate-bash.md`, `docs/implementation-notes/money-gate-bash.md`, `docs/FEATURES.md` (regenerated) | CHANGELOG names the port |

## Test plan

| # | Check | Expect |
|---|---|---|
| P1 | `bash tests/test-money-gate-parity.sh` | `34 passed, 0 failed` |
| P2 | `bash tests/test-money-gate.sh` | exit 0 |
| P3 | `bash tests/test-kit-foldin-hooks.sh` | exit 0 |
| P4 | P1 under gawk and mawk (PATH shims) | 34/34 |
| P5 | `grep -c python3 hooks/money-gate.sh` | 0 |

Negative controls, through `lib/gate/negctl.sh` with P1 as the test command:

| Control | Mutation | Must go red |
|---|---|---|
| NC1 | drop the left-boundary test | `no-embedded-only`, `plural-and-embedded` |
| NC2 | treat only `1` as strict | `strict-true-upper`, `strict-yes`, `strict-on` |
| NC3 | scan only `new_string` | `old-string-delete`, `multiedit-array`, `numbers-and-bools` |

## Verification

P1 to P5 hold and NC1 to NC3 report PASS. `bash tests/run-all.sh --changed` exits 0.

## After state

money-gate runs with no Python. Its behavior is byte-identical to the Python hook on the parity corpus. Four Python hooks remain (backlog-stage, context-hints, harvest, intake-sweep), plus citation-guard in SPEC-356.

## Decision Log

- Goldens come from the Python hook, generated by the orchestrator before the port, so the implementer cannot fit the test to the code.
- Parity includes quirks (a bare `/w/fin` path with an unrelated cwd does not match). A behavior change would be a separate spec.
- The implementer is Devin (`devin -p`, headless, sandboxed) in this worktree; the orchestrator owns the spec, the goldens, verification, review, and ship.
