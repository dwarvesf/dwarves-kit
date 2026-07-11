#!/usr/bin/env python3
"""money-gate: PreToolUse(Edit/Write) gate for money-touching edits
(kit-foldin port of ops-toolkit cc-money-gate, function-named).

When an edit lands in a repo you named financial (MONEY_GATE_REPOS) and the path or
the new content touches money/auth (amounts, balances, transfers, wallets, keys,
payroll, ...), this asks for confirmation before the edit lands. The point: a
careless edit to cashflow / PnL / a wallet address should never be silent.

pixelmojo's "LLM semantic review on PreToolUse" idea, but deterministic (regex on
path + content) so it is fast enough to run on every edit and testable in-repo.

Default is log-only (safe to wire). MONEY_GATE_STRICT=1 emits a PreToolUse `ask`
decision so Claude Code prompts for confirmation.

Env:
  MONEY_GATE_REPOS=a:b      sensitive repo names. CONSUMER CONFIG, no default: unset
                          means the gate is inert (adapter-default invariant; the
                          kit ships no tenant repo names)
  MONEY_GATE_STRICT=1       ask-to-confirm instead of log-only
  MONEY_GATE_LOG=FILE       log destination (default ~/.claude/logs/cc-money-gate.log)
Stdlib only. Exit 0 always (decision is carried in the JSON, not the exit code).
"""
import json
import os
import re
import sys
import time

DEFAULT_LOG = os.path.expanduser("~/.claude/logs/money-gate.log")
MONEY_RE = re.compile(
    r"\b(amount|balance|transfer|payout|payment|payroll|invoice|wallet|private[_-]?key|"
    r"secret|password|api[_-]?key|token|iban|account[_-]?number|routing|"
    r"ledger|cashflow|pnl|net[_-]?worth|deposit|withdraw|usd|vnd)\b",
    re.IGNORECASE,
)


def collect_strings(obj, out):
    if isinstance(obj, str):
        out.append(obj)
    elif isinstance(obj, dict):
        for v in obj.values():
            collect_strings(v, out)
    elif isinstance(obj, list):
        for v in obj:
            collect_strings(v, out)


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0
    tool_input = payload.get("tool_input") or {}
    file_path = tool_input.get("file_path") or tool_input.get("path") or ""
    cwd = payload.get("cwd") or ""

    repos = (os.environ.get("MONEY_GATE_REPOS") or "").split(":")
    haystack_loc = f"{file_path}\n{cwd}"
    in_sensitive = any(f"/{r}/" in haystack_loc or haystack_loc.endswith(f"/{r}") for r in repos if r)
    if not in_sensitive:
        return 0

    parts = [file_path]
    collect_strings(tool_input, parts)
    blob = "\n".join(parts)
    hits = sorted({m.group(0).lower() for m in MONEY_RE.finditer(blob)})
    if not hits:
        return 0

    reason = f"money-gate: edit in a financial repo touches {', '.join(hits[:6])}: confirm before applying."
    # log (default + strict)
    try:
        os.makedirs(os.path.dirname(os.environ.get("MONEY_GATE_LOG", DEFAULT_LOG)), exist_ok=True)
        with open(os.environ.get("MONEY_GATE_LOG", DEFAULT_LOG), "a", encoding="utf-8") as fh:
            fh.write(f"{int(time.time())}\t{file_path}\t{','.join(hits)}\n")
    except OSError:
        pass

    if os.environ.get("MONEY_GATE_STRICT") == "1":
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": reason,
        }}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
