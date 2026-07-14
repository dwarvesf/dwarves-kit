# money-gate

A `PreToolUse(Edit|Write|MultiEdit)` guard that asks for confirmation before a
money-touching edit lands in a repo you named financial. A careless edit to a cashflow
file, a payroll row, or a wallet address should never be silent.

Folded in from ops-toolkit's `cc-money-gate` at kit-foldin (2026-07-11), function-named on
entry (`MONEY_GATE_*`, the host-agent `CC_` prefix dropped).

**Hook-only module.** The code lives in `hooks/money-gate.sh` (shim) and
`hooks/money-gate.py` (logic, stdlib-only). This directory is the module's doc home:
`SPEC.md` is the contract, `docs/proof-of-done.md` is the acceptance record.

## Ships inert

The kit ships **no repo names** (the adapter-default invariant: no tenant data in the
kit). Until you set `MONEY_GATE_REPOS`, the hook exits 0 before it does anything.

```bash
bash install.sh --with money_gate          # wire the hook (records modules.money_gate)
export MONEY_GATE_REPOS=my-books:family-office   # colon-separated repo names
```

That alone gives you **log-only** mode: every money-touching edit in those repos is
appended to `~/.claude/logs/money-gate.log`, nothing is interrupted. Wire it, forget it,
read the log later.

```bash
export MONEY_GATE_STRICT=1                 # upgrade to ask-to-confirm
```

Now the same edit emits a PreToolUse `ask`, and Claude Code prompts you before it lands.
`MONEY_GATE_STRICT` must be the literal `1`; `true` is log-only.

## When it fires

Two conditions, both required:

| | Condition | Source |
|---|---|---|
| 1 | The edit is inside a repo named in `MONEY_GATE_REPOS` | the payload's `file_path` + `cwd` |
| 2 | Some string in the payload matches the money/auth keywords | `amount`, `balance`, `transfer`, `payout`, `payroll`, `invoice`, `wallet`, `ledger`, `cashflow`, `pnl`, `usd`, `vnd`, `api_key`, `token`, ... |

Either alone is silence. The content scan is recursive over the whole tool payload, so
`old_string` and the MultiEdit `edits[]` array count too: **deleting** a money line trips
the gate just as adding one does.

It never blocks. The strongest thing it can do is `ask`, and it always exits 0, so a
broken gate can never wedge an edit.

## Env

| Var | Default | Effect |
|---|---|---|
| `MONEY_GATE_REPOS` | unset | Colon-separated financial repo names. Unset = inert. |
| `MONEY_GATE_STRICT` | unset | Literal `1` = ask-to-confirm. Anything else = log-only. |
| `MONEY_GATE_LOG` | `~/.claude/logs/money-gate.log` | Log destination. |

## Test

```bash
bash tests/test-money-gate.sh   # -> test-money-gate: all 12 passed
```

## Known gaps

`SPEC.md` carries the full contract, the degrade paths, and three divergences worth
knowing before you trust this gate:

1. The log path bypasses the SPEC-097 durable-root resolver (`lib/telemetry/kit-log-dir.sh`).
2. The keyword list (`token`, `secret`, `password`) also fires on ordinary auth code.
3. **The regex is `\b`-anchored, so it misses snake_case identifiers and plurals.**
   `payroll_total = 5000` does **not** trip the gate; `payroll = 5000` does. This is the
   real hole, and identifier-shaped money code is exactly what an agent edits.
