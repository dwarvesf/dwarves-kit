# SPEC: money-gate

> Written 2026-07-15, after the fact. `money_gate` entered at kit-foldin (2026-07-11)
> as a port of ops-toolkit's `cc-money-gate` and was the one kit module that never got
> a SPEC: its only acceptance record was a proof-of-done shared with `prose_rag`
> (`docs/verification/money-gate-prose-rag-fold.md`). This SPEC is a description of the
> code as it stands, not a redesign. Where the code and its own docstring disagree, the
> code wins and the disagreement is called out.

## Problem

At the PreToolUse boundary every edit looks the same. The harness sees a tool name and a
payload; it does not know that `tracking/ledger/transactions.csv` moves real money and
`README.md` does not. The kit's spine hooks do not close this: `safety-gate` guards
destructive shell verbs, `secrets-guard` guards credential leaks, neither knows which
repos hold money.

So a wrong amount, a swapped wallet address, or a mangled payroll row lands **silently**,
and the first thing that notices is a human at reconciliation time, weeks later. The cost
of a careless money edit is asymmetric: a bad `README.md` edit is a `git checkout`, a bad
payroll edit is a wrong payment.

Origin: pixelmojo's "LLM semantic review on PreToolUse" idea, made deterministic (regex
over the payload) so it is fast enough to run on **every** edit and testable in-repo.

## Solution

A `PreToolUse(Edit|Write|MultiEdit)` hook that speaks only when **two** conditions hold at
once:

1. **Location**: the edit is inside a repo the consumer named in `MONEY_GATE_REPOS`.
2. **Content**: some string in the tool payload matches the money/auth keyword regex.

Either alone is silence. That conjunction is the whole design: content-only would fire on
every repo that says "amount", location-only would fire on every edit in a financial repo.

Default is **log-only** (safe to wire and forget). `MONEY_GATE_STRICT=1` upgrades it to a
PreToolUse `ask` decision, so Claude Code prompts before the edit lands.

The kit ships it **inert**. There are no default repo names (the adapter-default
invariant: the kit ships no tenant data), so an unset `MONEY_GATE_REPOS` means the hook
exits before it does anything at all.

## Contract

**Where the code lives.** `hooks/money-gate.sh` (the whole job: bash, jq, and POSIX
tools). `money_gate` is a **hook-only module**: this `lib/money-gate/` dir is its doc
home and carries no code.

**Wiring.** `install.sh --with money_gate` installs the one hook (`kit_module_hooks
money_gate` -> `money-gate.sh`) and records `modules.money_gate` in the consumer's
`kit.toml` (default `false`). Registered as PreToolUse matcher `Edit|Write|MultiEdit`,
timeout 5s, in `hooks/hooks.json` (plugin install) and `settings.json` (bash install).

**Exit code is always 0.** The decision travels in the JSON on stdout, never in the exit
code. This is load-bearing, not incidental: a gate that dies must not block an edit.

**Decision sequence** (first failing step exits 0, silent):

| # | Step | Rule |
|---|---|---|
| 1 | Short-circuit | `MONEY_GATE_REPOS` unset or empty -> `exit 0` before stdin is read |
| 2 | Parse | stdin must be exactly one JSON object; anything else returns 0 |
| 3 | Location | `haystack = f"{file_path}\n{cwd}"`; match if any non-empty `r` in `MONEY_GATE_REPOS.split(":")` satisfies `f"/{r}/" in haystack` **or** `haystack.endswith(f"/{r}")` |
| 4 | Content | `MONEY_RE` over `file_path` plus **every string in `tool_input`**, collected recursively (dict values, list items) |
| 5 | Decide | no keyword hits -> return 0; hits -> log, and in strict mode also emit the `ask` JSON |

`file_path` is read as `tool_input.file_path`, falling back to `tool_input.path`, else `""`.
`cwd` is read from the payload's top-level `cwd`, else `""`.

**The keyword set** (case-insensitive, boundary-aware):

```
amount | balance | transfer | payout | payment | payroll | invoice | wallet |
private[_-]?key | secret | password | api[_-]?key | token | iban |
account[_-]?number | routing | ledger | cashflow | pnl | net[_-]?worth |
deposit | withdraw | usd | vnd
```

A keyword matches when the byte before it is not `[A-Za-z0-9]` (or is the start) and the
byte after is not `[A-Za-z0-9]` (or is the end), with an optional trailing `s`: `_`,
`-`, blanks, and punctuation all count as separators. See divergence 3 below.

**The recursive scan is broader than the docstring claims.** The module docstring said the
gate looks at "the path or the new content". It does not: `collect_strings()` walks the
whole `tool_input`, so `old_string` and the MultiEdit `edits[]` array are scanned too.
Consequence, verified: **deleting** a money line trips the gate exactly as readily as
adding one. That is defensible for a money guard (removing a ledger row is as dangerous as
writing one), but it was never written down. (The docstring was corrected in the same
change that added this SPEC; the code was not touched.)

**Modes.**

| Mode | Condition | Behavior |
|---|---|---|
| log-only (default) | `MONEY_GATE_STRICT` not truthy | append one line to the log, print nothing |
| strict | `MONEY_GATE_STRICT` truthy | the same log line, **plus** an `ask` JSON on stdout |

`MONEY_GATE_STRICT` is trimmed (`str.strip()` semantics) and lowercased; `1`, `true`,
`yes`, `on` arm strict. Any other value is log-only. (Was: the literal `"1"` only, a
silent footgun fixed 2026-07-15; see divergence 4.)

The strict-mode payload:

```json
{"hookSpecificOutput": {
  "hookEventName": "PreToolUse",
  "permissionDecision": "ask",
  "permissionDecisionReason": "money-gate: edit in a financial repo touches <terms>: confirm before applying."
}}
```

`<terms>` is the matched keywords, lowercased, deduped, sorted, **capped at the first 6**.

**The log** is written in *both* modes (the log is the record; strict only adds the
prompt). Path: `MONEY_GATE_LOG`, default `~/.claude/logs/money-gate.log`. Format, one line
per fire:

```
<epoch>\t<file_path>\t<comma-joined hits>
```

The parent dir is created on demand and `OSError` is swallowed: an unwritable log never
blocks an edit.

**Env.**

| Var | Default | Effect |
|---|---|---|
| `MONEY_GATE_REPOS` | unset | Colon-separated repo names treated as financial. **Unset = the gate is inert.** No kit default exists. |
| `MONEY_GATE_STRICT` | unset | A truthy spelling (`1`/`true`/`yes`/`on`) upgrades log-only to an `ask` decision. |
| `MONEY_GATE_LOG` | `~/.claude/logs/money-gate.log` | Log destination. |

**Degrade paths**, every one of them `exit 0`:

- `MONEY_GATE_REPOS` unset -> exits before reading stdin.
- stdin is not exactly one JSON object (empty, garbage, an array, two values) -> silent.
- `jq` missing -> `exit 0` with one stderr line naming the missing tool (fail open,
  but visible).
- The log is unwritable, or `MONEY_GATE_LOG` is set but empty or slashless -> nothing
  is written anywhere; the `ask` still emits.

### Known divergences (recorded, not fixed here)

Things the code does that no design record ever justified. They are described because
this SPEC documents reality; items 3 and 4 are fixes, the rest stand.

1. **The log does not resolve through `lib/telemetry/kit-log-dir.sh`.** The ledger-durability
   spec (`docs/specs/SPEC-097-ledger-durability.md`) and contract rule C6 make that the
   durable-root resolver for every module that persists
   state. `money-gate.sh` builds `~/.claude/logs/money-gate.log` directly. C6's sweep
   greps `lib` only, so a hook-only module is outside its scope and the divergence is
   invisible to the lint. Whether an append-only audit trail is "state" in C6's sense
   (as opposed to run telemetry) was never decided in writing.
2. **`secret|password|api[_-]?key|token` makes the gate fire on ordinary auth code**
   inside a named repo. Verified: `const token = getAccessToken()` in a named repo asks.
   Whether that breadth is the point (auth edits in a money repo *are* worth a prompt) or
   an accepted false-positive tax was never stated. It overlaps the `secrets-guard` spine
   hook, which owns credential-leak detection proper.
3. **FIXED 2026-07-15: the `\b` anchors made the gate blind to snake_case and plurals.**
   `_` is a word character, so `\bpayroll\b` did not match `payroll_total`, and `\bamount\b`
   did not match `amounts`. A Python file whose only money signal was `payroll_total = 5000`
   **did not trip the gate**, while the same line written `payroll = 5000` did. That was the
   gate's largest real hole: identifier-shaped money code is exactly what an agent edits.

   The boundaries are now underscore-aware lookarounds (`(?<![A-Za-z0-9])` / `s?(?![A-Za-z0-9])`),
   so `_` reads as a separator and the bare plural is caught:

   | Input | Fires? |
   |---|---|
   | `payroll_total`, `total_payroll`, `invoice_id`, `_balance_`, `amounts` | yes (was: no) |
   | `payroll`, `amount`, `payroll-total` | yes (unchanged) |
   | `mypayroll`, `payrolling`, `tokenizer`, `balanced` | no (an alphanumeric neighbour still blocks the match) |

   Test `[12]` was a characterization test pinning the hole; it is now the assertion proving
   it shut, with `[12c]` as the negative control against over-matching.

4. **FIXED 2026-07-15: `MONEY_GATE_STRICT` compared against the literal `"1"`.** An operator
   who armed the gate with `MONEY_GATE_STRICT=true` silently got log-only mode while believing
   they were being prompted. A safety knob that silently does nothing is worse than no knob.
   Any truthy spelling (`1`/`true`/`yes`/`on`, case-insensitive) now arms it; `0`/`false`/`no`/
   `off`/empty stay log-only (test `[10]`, negative control `[10b]`).

## Non-goals

- **Blocking.** The strongest decision is `ask`; the gate never returns `deny`, and it
  cannot block via the exit code (always 0). A human confirms, or nothing happens.
- **Semantic review.** The match is a regex over the payload, deliberately: an LLM call on
  every Edit is too slow for a PreToolUse hook and cannot be tested in-repo. False
  positives are the accepted price of determinism.
- **Reading the file on disk.** Only the tool payload is inspected. An edit whose money
  context lives entirely in the surrounding, unmodified lines is invisible to the gate.
- **Resolving repo roots.** `MONEY_GATE_REPOS` entries are matched as path substrings, not
  against git. Any directory that shares the name matches.
- **Shipping tenant defaults.** No repo names, no vendor keywords. Unset means inert.
- **Being the secrets gate.** The keyword list overlaps, but `secrets-guard` owns that job.

## Verification

```bash
bash tests/test-money-gate.sh   # -> test-money-gate: all 12 passed
```

12 assertions: 6 positive, 5 negative controls, 1 characterization test.

- **Fires** `[1][2][3][8][9][10][11][12b]`: the `ask` emits on a money edit in a named
  repo, its JSON is valid and names the matched terms; log-only mode logs without asking;
  the recursive scan reaches the MultiEdit `edits[]` array and `old_string`; truthy
  `MONEY_GATE_STRICT` spellings arm it; the process exits 0 even while asking.
- **Stays silent** (negative controls) `[4][5][6][7][10b][12c]`: a non-money edit in a
  named repo; a money edit outside a named repo; `MONEY_GATE_REPOS` unset (the kit
  default); a junk payload; falsy `MONEY_GATE_STRICT` spellings; terms embedded in a
  longer word. These are what prove the gate discriminates rather than firing on
  everything.
- **Assertion** `[12]`: proves divergence 3 shut (snake_case and plurals DO match), so
  the fix fails loudly if the boundary logic is ever narrowed back.

Acceptance record: `lib/money-gate/docs/proof-of-done.md`.
