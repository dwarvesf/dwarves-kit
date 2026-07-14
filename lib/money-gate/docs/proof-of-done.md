# Proof of Done: money-gate

**Feature:** the module's first SPEC (`lib/money-gate/SPEC.md`) + its own acceptance record, replacing the joint proof it shared with `prose_rag`.
**Date:** 2026-07-15 · **Lane:** docs · **Host:** Hans-Air-M4 (macOS 26.5.2, Python 3.14.6) · **Kit:** v2.0.0

`money_gate` was the one kit module with no SPEC. It entered at kit-foldin (2026-07-11) as
a port of ops-toolkit's `cc-money-gate`, and its only acceptance record was
`docs/verification/money-gate-prose-rag-fold.md`, a proof shared with `prose_rag` that
recorded the *fold* (wiring, install, hook counts) rather than the gate's *behavior*.

This change is documentation plus test-hardening. **The hook's behavior is unchanged**: no
line of `money-gate.py`'s logic was touched. The only source edit is a docstring correction
(two statements the code on the same file contradicted). Everything else is the SPEC, this
proof, a README, and 5 new assertions that pin contract claims nothing was testing.

## Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| A1 | The module has a SPEC describing the code as it actually behaves | task; C3 |
| A2 | The module has its own `docs/proof-of-done.md`, not a joint one | task; C3 |
| A3 | The module has a README front door | C3 |
| A4 | Every behavioral claim the SPEC makes is backed by a test assertion | house rule: no untested SPEC claim |
| A5 | The gate really discriminates (fires on money-in-named-repo, silent otherwise) | NEGATIVE CONTROL |
| A6 | The gate always exits 0 (a broken gate cannot wedge an edit) | contract invariant |
| A7 | `bash tests/test-kit-contract.sh` stays green, and money_gate's known-gap IOU is closed | task; C3/C4 |
| A8 | Behavior unchanged (docs + tests only) | scope fence |

## Implementation

| Piece | What | Where |
|---|---|---|
| SPEC | Problem / Solution / Contract (decision sequence, env, degrade paths) / Non-goals / Verification, plus 3 recorded divergences | `lib/money-gate/SPEC.md` |
| Proof | this file | `lib/money-gate/docs/proof-of-done.md` |
| README | front door: ships inert, how to arm it, when it fires, known gaps | `lib/money-gate/README.md` |
| Test pins | `[8]` MultiEdit `edits[]` scanned, `[9]` `old_string` scanned, `[10]` strict needs literal `"1"`, `[11]` exit-0-while-asking, `[12]` characterization of the `\b` blind spot | `tests/test-money-gate.sh` (7 -> 12) |
| Docstring fix | "the new content" -> the whole payload (recursive); default log `cc-money-gate.log` -> `money-gate.log` | `hooks/money-gate.py` (comment only) |
| Gap closed | the `money_gate` IOU paragraph | `tests/kit-contract-known-gaps.txt` |

Where the code lives is worth stating, because it is why the contract never saw this
module: `money_gate` is **hook-only** (`hooks/money-gate.{sh,py}`). The contract's
`modules()` resolves a module to `lib/<name>/`, and `lib/money-gate/` did not exist, so
C3 and C4 skipped it entirely. Creating the doc dir is what puts the module *inside* the
lint's scope, which is why A7 is an acceptance criterion and not a formality.

## Confirmation run-table

| # | Check | Command | Expected | Result |
|---|---|---|---|---|
| 1 | Module suite, all 12 | `bash tests/test-money-gate.sh` | `all 12 passed`, exit 0 | PASS |
| 2 | Fires: ask on money edit in named repo (A5) | test `[1][2]` | valid `ask` JSON naming the terms | PASS |
| 3 | Log-only is the default (A5) | test `[3]` | logs, no stdout | PASS |
| 4 | Recursive scan: MultiEdit `edits[]` (A4) | test `[8]` | asks, names `payout` | PASS |
| 5 | Recursive scan: `old_string` (A4) | test `[9]` | asks, names `balance` | PASS |
| 6 | NEGATIVE CONTROL: 5 silent cases (A5) | tests `[4][5][6][7][10]` | no stdout, no log | PASS |
| 7 | Exit 0 even while asking (A6) | test `[11]` | rc 0 + ask JSON | PASS |
| 8 | Characterization: `\b` blind spot (A4) | test `[12]` | `payroll_total` does not fire | PASS |
| 9 | Kit contract green + gap closed (A7) | `bash tests/test-kit-contract.sh` | 22 passed, 0 failed; money_gate no longer a gap | PASS |
| 10 | NEGATIVE CONTROL: the lint really watches money-gate (A7) | yank `SPEC.md`, re-run the contract | C3 fails, naming `lib/money-gate/SPEC` | PASS |
| 11 | Behavior unchanged (A8) | `git diff --stat hooks/money-gate.py` | docstring lines only | PASS |

## Run detail

Module suite (verbatim, `Exit: 0`):

```
$ bash tests/test-money-gate.sh; echo "Exit: $?"
[1] strict + named repo + money content -> asks to confirm
  ok: ask emitted
[2] ask JSON is valid + names the matched terms
  ok: valid ask JSON with reason
[3] default (non-strict) mode logs but does not ask
  ok: logged, no block
[4] NC: named repo + non-money content -> silent
  ok: no fire on plain edit
[5] NC: money content OUTSIDE a named repo -> silent
  ok: no fire outside named repos
[6] NC: MONEY_GATE_REPOS unset -> inert even on money content (kit default)
  ok: inert without consumer config
[7] junk payload -> exit 0, silent
  ok: junk safe
[8] recursive scan reaches the MultiEdit edits[] array
  ok: MultiEdit edits[] scanned
[9] recursive scan reaches old_string (DELETING money content trips the gate)
  ok: old_string scanned
[10] NC: MONEY_GATE_STRICT must be the literal '1' -- 'true' logs but does NOT ask
  ok: non-'1' strict is log-only
[11] exit 0 ALWAYS, even when emitting an ask (decision travels in JSON, not rc)
  ok: asked and still exit 0
[12] CHARACTERIZATION (known gap): snake_case + plurals do NOT match -> no fire
  ok: gap confirmed: \b-anchored regex misses snake_case/plurals

test-money-gate: all 12 passed
Exit: 0
```

Live hook, strict mode, money edit in a named repo (the gate doing its job):

```
$ printf '%s' '{"tool_input":{"file_path":"/home/u/work/acme-books/tracking/transactions.csv",
    "new_string":"transfer 500 USD to wallet 0xabc"},"cwd":"/home/u/work/acme-books"}' \
  | MONEY_GATE_REPOS=acme-books MONEY_GATE_STRICT=1 MONEY_GATE_LOG=$T/g.log bash hooks/money-gate.sh
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "money-gate: edit in a financial repo touches transfer, usd, wallet: confirm before applying."}}
Exit: 0
```

Same edit, default (log-only) mode. No stdout, so nothing prompts; the record still lands:

```
$ ... | MONEY_GATE_REPOS=acme-books MONEY_GATE_LOG=$T/b.log bash hooks/money-gate.sh
Exit: 0
log: 1784050432	/home/u/work/acme-books/tracking/transactions.csv	transfer,usd,wallet
```

Kit contract, after adding `lib/money-gate/` (which is what pulls the module into C3/C4 scope):

```
$ bash tests/test-kit-contract.sh | tail -3

=== kit-contract: 22 passed, 0 failed ===
Exit: 0
```

The module is now genuinely inside the lint's scope, not merely adjacent to it. The
contract's own `modules()` resolver now returns it, and it carries no IOU:

```
$ # modules() as the contract computes it
  lib/board
  lib/money-gate      <- new; was absent, which is why C3/C4 never looked at it
  lib/plugin-check
  lib/prose-rag
  lib/queue
  lib/session
  lib/skill-curator
  lib/stats

$ grep -c '^lib/money-gate' tests/kit-contract-known-gaps.txt
0     # no known-gap entry: it passes C3/C4 outright, it is not exempted
```

**These runs were made in a clean tree** (`git archive HEAD` + only this change's files).
The live working copy currently carries a second, unrelated in-flight change from a
concurrent session (a C10 contract rule, `lib/cosmetic/`, `lib/telemetry/tests/`), which
inflates the contract to 24 checks. 22 is this branch's true number; verifying against the
contaminated tree would have recorded a count this branch cannot reproduce.

## NEGATIVE CONTROL

The gate exists is a weak claim; the gate *discriminates* is the claim worth proving. An
`ask` that fires unconditionally would pass test `[1]` and be worthless. Five controls
force silence, each removing exactly one of the two conditions the SPEC says must both
hold:

| Control | What is removed | Test | Result |
|---|---|---|---|
| Non-money edit in a named repo (`README.md`, prose) | the **content** condition | `[4]` | silent |
| Money content outside a named repo | the **location** condition | `[5]` | silent |
| `MONEY_GATE_REPOS` unset (the shipped kit default) | the module's arming | `[6]` | inert |
| Junk payload (`{}`) | parseable input | `[7]` | silent, exit 0 |
| `MONEY_GATE_STRICT=true` (not literal `1`) | the strict upgrade | `[10]` | logs, does **not** ask |

Live, the two that matter most (verbatim):

```
--- NEGATIVE CONTROL: money content OUTSIDE a named repo ---
$ printf '%s' '{"tool_input":{"file_path":"/home/u/work/other-repo/foo.py",
    "new_string":"transfer balance payout amount"},"cwd":"/home/u/work/other-repo"}' \
  | MONEY_GATE_REPOS=acme-books MONEY_GATE_STRICT=1 MONEY_GATE_LOG=$T/c.log bash hooks/money-gate.sh
Exit: 0 (stdout empty above = no ask)
log written: no

--- NEGATIVE CONTROL: MONEY_GATE_REPOS unset (kit default) ---
$ printf '%s' '{"tool_input":{"file_path":"/home/u/work/acme-books/tracking/transactions.csv",
    "new_string":"transfer 500 USD to wallet 0xabc"},"cwd":"/home/u/work/acme-books"}' \
  | env -u MONEY_GATE_REPOS MONEY_GATE_STRICT=1 MONEY_GATE_LOG=$T/d.log bash hooks/money-gate.sh
Exit: 0 (inert)
log written: no
```

The third control is `[10]`, and it is the uncomfortable one: the *same* payload that asks
in `[1]` goes quiet the moment `MONEY_GATE_STRICT` is spelled `true` instead of `1`. It
still logs, so the gate is not broken, but an operator who armed the gate with `true` would
believe they are being prompted and never be. That is now contract (SPEC "Modes"), pinned
by a test, rather than a surprise waiting in the source.

`[12]` is a characterization control, not a pass: it proves the `\b`-anchored regex is blind
to `payroll_total` / `invoice_id` / `amounts`. It is recorded as SPEC divergence 3 and left
unfixed on purpose, because widening the match set is a behavior change and this change is
docs-only (A8). The test makes the hole loud instead of invisible.

### The lint itself gets a negative control

Adding three files and watching a suite stay green proves nothing: a lint that skips the
module would also stay green. So the claim under test is "C3 now *watches* money-gate",
and the way to prove it is to break it on purpose. Yank the SPEC and the contract must go
red, naming the exact missing artifact:

```
$ mv lib/money-gate/SPEC.md lib/money-gate/SPEC.md.hidden
$ bash tests/test-kit-contract.sh
== C3 docs: README + SPEC + proof-of-done per module ==
  FAIL every module has README + a spec + docs/proof-of-done.md (no NEW gaps) (offenders: lib/money-gate/SPEC )
=== kit-contract: 21 passed, 1 failed ===
Exit: 1

$ mv lib/money-gate/SPEC.md.hidden lib/money-gate/SPEC.md   # restore
$ bash tests/test-kit-contract.sh | tail -1
=== kit-contract: 22 passed, 0 failed ===
Exit: 0
```

Before this change that same deletion would have been a no-op: `lib/money-gate/` did not
exist, so `modules()` never yielded it and C3 had nothing to miss. The module was not
passing the contract, it was **invisible to it**. That is the actual gap this change closes,
and the red run above is the evidence.

## Reproduce

```bash
bash tests/test-money-gate.sh    # -> test-money-gate: all 12 passed
bash tests/test-kit-contract.sh  # -> kit-contract: 22 passed, 0 failed
git diff --stat hooks/money-gate.py   # docstring lines only: behavior unchanged
```
