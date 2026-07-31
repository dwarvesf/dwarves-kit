# Proof of done: audit-scanner-agent (SPEC-220)

## Acceptance criteria

| AC | Claim | Status |
|---|---|---|
| AC-1 | agents/audit-scanner.md with read-only tools roster (no bare Bash / Write / Edit) | MET (run 1) |
| AC-2 | body carries dispatch contract + output shape + audit-loop grammar rules | MET (run 1, AC3 block) |
| AC-3 | doc-drift step 4 + feature-map step 4 dispatch kit:audit-scanner preferred, general-purpose fallback | MET (run 1, AC2 block) |
| AC-4 | audit-loop pattern line, FEATURES.md regenerated, workflow-paths index + topology, README count/row, MANUAL row, architecture.md row | MET (run 2) |
| AC-5 | contract test with in-suite NC (write-capable fixture trips, clean fixture passes) | MET (run 1) |
| AC-6 | live NC: mutated roster copy goes RED, tracked file stays green | MET (run 3) |

## Confirmation runs

| # | Check | Command | Result |
|---|---|---|---|
| 1 | contract test, green run | `bash tests/test-audit-scanner-contract.sh` | 15/15 PASS, exit 0 |
| 2 | registration + freshness pins | `bash tests/test-meta.sh` | 741/741 PASS (FEATURES.md freshness, README 27-agent counts + row, MANUAL row, architecture inventory 61 rows / 27-agent headline) |
| 3 | live negative control | `sed` a `- Write` entry into a COPY of the agent file, `AUDIT_SCANNER_AGENT_FILE=<copy> bash tests/test-audit-scanner-contract.sh` | 14/15, roster check FAIL `(write tool)`, exit 1; `git status` shows the tracked file untouched |

## Run detail

Run 1 is the green run: the roster audit (no bare Bash, no Write/Edit/NotebookEdit, Read+Grep+Glob present, every `Bash(...)` verb from the read-only allowlist), the both-sides dispatch wiring (both skills name `kit:audit-scanner` + the general-purpose fallback; the agent names both instances), and the audit-grammar pins (verdict grammar, no-evidence-downgrades-to-UNSURE, UNTESTABLE-never-REMOVE, never-fixes) all pass, plus the in-suite NC pair proving the roster check discriminates (write-capable fixture FAILS, clean fixture PASSES).

Run 2 exercises the registration machinery end to end: the FEATURES.md freshness pin picks the new agent up only after regeneration (the Tests column required a SECOND regeneration after the contract test file landed, since test refs derive from `tests/`); README layout + header counts, the MANUAL.md reverse cross-ref, and the architecture.md inventory row-count pin each forced their registration edit.

Run 3 is the injected-defect control on the real artifact (beyond the in-suite fixture): one added `- Write` line in a temp COPY of the shipped agent file flips exactly the roster assertion RED via the test's `AUDIT_SCANNER_AGENT_FILE` seam; the tracked file was never modified.

## Reproduce

```
bash tests/test-audit-scanner-contract.sh
bash tests/test-meta.sh
D=$(mktemp -d); sed 's/^  - Glob$/  - Glob\n  - Write/' agents/audit-scanner.md > "$D/m.md"
AUDIT_SCANNER_AGENT_FILE="$D/m.md" bash tests/test-audit-scanner-contract.sh   # expect exit 1
```
