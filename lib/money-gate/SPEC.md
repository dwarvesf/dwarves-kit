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

**Where the code lives.** `hooks/money-gate.sh` (a bash shim) and `hooks/money-gate.py`
(the logic, stdlib-only). `money_gate` is a **hook-only module**: this `lib/money-gate/`
dir is its doc home and carries no code.

**Wiring.** `install.sh --with money_gate` installs the one hook (`kit_module_hooks
money_gate` -> `money-gate.sh`) and records `modules.money_gate` in the consumer's
`kit.toml` (default `false`). Registered as PreToolUse matcher `Edit|Write|MultiEdit`,
timeout 5s, in `hooks/hooks.json` (plugin install) and `settings.json` (bash install).

**Exit code is always 0.** The decision travels in the JSON on stdout, never in the exit
code. This is load-bearing, not incidental: a gate that dies must not block an edit.

**Decision sequence** (first failing step exits 0, silent):

| # | Step | Rule |
|---|---|---|
| 1 | Shim short-circuit | `MONEY_GATE_REPOS` unset or empty -> `exit 0` before `python3` is spawned |
| 2 | Parse | stdin must be JSON; a `JSONDecodeError`/`ValueError` returns 0 |
| 3 | Location | `haystack = f"{file_path}\n{cwd}"`; match if any non-empty `r` in `MONEY_GATE_REPOS.split(":")` satisfies `f"/{r}/" in haystack` **or** `haystack.endswith(f"/{r}")` |
| 4 | Content | `MONEY_RE` over `file_path` plus **every string in `tool_input`**, collected recursively (dict values, list items) |
| 5 | Decide | no keyword hits -> return 0; hits -> log, and in strict mode also emit the `ask` JSON |

`file_path` is read as `tool_input.file_path`, falling back to `tool_input.path`, else `""`.
`cwd` is read from the payload's top-level `cwd`, else `""`.

**The keyword set** (word-boundary, case-insensitive):

```
amount | balance | transfer | payout | payment | payroll | invoice | wallet |
private[_-]?key | secret | password | api[_-]?key | token | iban |
account[_-]?number | routing | ledger | cashflow | pnl | net[_-]?worth |
deposit | withdraw | usd | vnd
```

Each keyword is `\b`-anchored, which is narrower than it looks: see divergence 3 below.

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
| log-only (default) | `MONEY_GATE_STRICT` != `1` | append one line to the log, print nothing |
| strict | `MONEY_GATE_STRICT` == `1` | the same log line, **plus** an `ask` JSON on stdout |

`MONEY_GATE_STRICT` is compared to the **literal string `"1"`**. Any other truthy-looking
value (`true`, `yes`, `on`) is log-only. Verified; this is a footgun and is recorded as
contract, not as a bug to be fixed silently.

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
| `MONEY_GATE_STRICT` | unset | `1` (literal) upgrades log-only to an `ask` decision. |
| `MONEY_GATE_LOG` | `~/.claude/logs/money-gate.log` | Log destination. |

**Degrade paths**, every one of them `exit 0` and silent:

- `MONEY_GATE_REPOS` unset -> shim exits before spawning Python.
- stdin is not JSON (`{}`, empty, garbage) -> `return 0`.
- `python3` missing or the script raises -> the shim's `|| true` and trailing `exit 0`
  swallow it. (Stderr noise from the failed exec is not suppressed; the exit code is
  still 0, so the edit is never blocked.)
- The log is unwritable -> `OSError` swallowed, the `ask` still emits.

### Known divergences (recorded, not fixed here)

Two things the code does that no design record ever justified. Both are described because
this SPEC documents reality; neither is changed by it.

1. **The log does not resolve through `lib/telemetry/kit-log-dir.sh`.** SPEC-097 and
   contract rule C6 make that the durable-root resolver for every module that persists
   state. `money-gate.py` builds `~/.claude/logs/money-gate.log` directly. C6's sweep
   greps `lib` only, so a hook-only module is outside its scope and the divergence is
   invisible to the lint. Whether an append-only audit trail is "state" in C6's sense
   (as opposed to run telemetry) was never decided in writing.
2. **`secret|password|api[_-]?key|token` makes the gate fire on ordinary auth code**
   inside a named repo. Verified: `const token = getAccessToken()` in a named repo asks.
   Whether that breadth is the point (auth edits in a money repo *are* worth a prompt) or
   an accepted false-positive tax was never stated. It overlaps the `secrets-guard` spine
   hook, which owns credential-leak detection proper.
3. **The `\b` anchors make the gate blind to snake_case identifiers and plurals.** `_` is
   a word character, so `\bpayroll\b` does not match `payroll_total`, and `\bamount\b`
   does not match `amounts`. Verified against the live regex:

   | Input | Hits |
   |---|---|
   | `payroll_total`, `invoice_id`, `total_payroll`, `amounts` | *(none)* |
   | `payroll`, `amount`, `payroll-total` (hyphen is not a word char) | matched |

   So a Python file whose only money signal is `payroll_total = 5000` **does not trip the
   gate**, while the same line written `payroll = 5000` does. This is the gate's largest
   real hole: identifier-shaped money code is exactly what an agent edits. It is pinned by
   test `[12]` as a characterization test, so widening the regex will fail that test
   loudly rather than drift silently. Not fixed here: this SPEC records the code, and
   changing the match set is a behavior change that deserves its own diff.

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

- **Fires** `[1][2][3][8][9][11]`: the `ask` emits on a money edit in a named repo, its
  JSON is valid and names the matched terms; log-only mode logs without asking; the
  recursive scan reaches the MultiEdit `edits[]` array and `old_string`; the process exits
  0 even while asking.
- **Stays silent** (negative controls) `[4][5][6][7][10]`: a non-money edit in a named
  repo; a money edit outside a named repo; `MONEY_GATE_REPOS` unset (the kit default); a
  junk payload; `MONEY_GATE_STRICT` set to a non-`1` truthy string. These are what prove
  the gate discriminates rather than firing on everything.
- **Characterization** `[12]`: pins divergence 3 (snake_case and plurals do not match), so
  the blind spot fails loudly if the regex is ever widened.

Acceptance record: `lib/money-gate/docs/proof-of-done.md`.
