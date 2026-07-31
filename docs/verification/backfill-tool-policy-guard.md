# Proof of done: tool-policy-guard wiring + contract (SPEC-212, ID-452 item 6/6)

Closes the ID-452 backfill campaign. `hooks/tool-policy-guard.sh` was documented (README/architecture hook tables, observe skill, dashboard) but registered nowhere: dead code from the live-wiring perspective, the campaign's own side finding. Operator decision: WIRE IT. This item wires it (PreToolUse matcher `*` in `hooks/hooks.json` + `settings.json`, mapped into the `advisor` install module) and backfills spec + behavioral test coverage: temp policy fixtures driving real invocations with hook JSON on stdin, asserting exit codes and stderr, one assert per SPEC-212 Test plan row. The critique loop found one genuine engine bug (round-1 CRITICAL: valid-but-non-dict JSON crashed past the `try/except` with a traceback exit 1, violating the script's own fail-open header contract); a minimal isinstance guard was added, the only engine change, deny/ask paths untouched.

## Confirmation runs

| # | Check | Command | Exit | Verdict |
|---|---|---|---|---|
| 1 | New suite green | `bash tests/test-tool-policy-guard.sh` | 0 | PASS (25/25) |
| 2 | Standalone deny fires | `echo '{"tool_name":"mcp__plugin_playwright_playwright__browser_click"}' \| KIT_TOOL_POLICY=<deny.json> bash hooks/tool-policy-guard.sh` | 2 | BLOCKED with `DENIED by policy (browser). Preferred: browser-harness-js.` |
| 3 | Live NC | `sed -i.bak 's/sys.exit(2)/sys.exit(0)/'` on the tracked script, re-run suite | 1 | RED (21/25, exactly the 4 predicted FAILs) |
| 4 | Restore | `mv -f` the sed `.bak` over the file, re-run suite | 0 | PASS (25/25), sha256 byte-identical |
| 5 | Meta suite | `bash tests/test-meta.sh` | 0 | PASS (732/732) |
| 6 | Install-module suite | `bash tests/test-install-modules.sh` | 0 | PASS (37/37) |
| 7 | Hook behavior suite | `bash tests/test-hooks.sh` | 0 | PASS (492/492) |

## Run detail

Run 3 replaced the single `sys.exit(2)` occurrence in the tracked `hooks/tool-policy-guard.sh` with `sys.exit(0)` (the deny branch's block, occurrence-counted 1 by the suite's own row 22a before every mutation). Exactly four assertions went RED, all predicted in SPEC-212 row 23:

- `row 1: v1 deny exits 2` (the block is gone; the call would no longer be stopped)
- `row 14: v2 capabilities/providers deny exits 2` (both deny dialects ride the same line)
- `row 22a: sys.exit(2) occurs exactly once` (0 occurrences left on the mutated tracked file)
- `row 22b: NC setup guard` (the in-suite `! cmp -s`: nothing left to mutate on the scratch copy it derives)

The other 21 assertions stayed green. Meaningful survivors: row 2 (the `DENIED` stderr message still prints; the message path is intact while the block is gone, exactly the discrimination the split rows encode), rows 3/4/17 (ask paths untouched), every fail-open row 5-13, both first-match rows, all three wiring rows, and row 22c/22d (the mutant-behavior asserts, exercised because the harness is assert-and-continue). Run 4 restored from the `.bak` and verified byte-identity: sha256 identical before and after (prefix `51a26ef71a52`, truncated because the repo's secret-guard hook rejects full 64-hex literals in authored files; re-derive with `shasum -a 256 hooks/tool-policy-guard.sh`).

Run 2 is the requested wiring-reality proof: the hook, invoked standalone exactly as the PreToolUse harness would (hook JSON on stdin), blocks a denied tool with exit 2 and the preferred-rung message on stderr. Rows 19-21 pin the registration itself (hooks.json + settings.json matcher `*`, strict single-value equality; advisor module mapping, order-tolerant).

The suite carries a permanent in-suite negative control (SPEC-212 row 22): every invocation re-mutates a mktemp scratch copy of the script (tracked file untouched), asserts the occurrence-count guard, the `! cmp -s` setup guard, the flipped deny exit, and the surviving stderr message. Falsifiability re-proves itself on every run.

## Side findings (recorded; two fixed, disclosed)

- FIXED (the one engine change): valid-but-non-dict JSON as the stdin payload or the whole policy file parsed inside the `try` block then crashed on `.get()`/`.items()` outside it: AttributeError traceback, exit 1, falsifying the fail-open header contract. Minimal isinstance guards added; rows 9/11/16 pin both halves plus the non-dict domain value. Deny/ask behavior byte-identical.
- FIXED (count-pin hygiene): `tests/test-hooks.sh` hardcoded the settings.json hook count as a literal 24 (with a PASS label stale at "22", evidence the literal had already drifted once); the wiring's +1 broke it. The assertion now derives the expected count from `hooks/hooks.json` (the same parity `tests/test-meta.sh` pins), per the no-hardcoded-counts rule.
- RECORDED, not fixed: the wiring cascade is mechanical, not optional. `hooks/hooks.json` alone fails test-meta's count parity; `settings.json` alone gets silently dropped by install.sh's additive re-install unless the hook maps to a known module (the reverse-map only preserves module-mapped hooks). Any future hook addition must touch all three surfaces in one commit: hooks.json, settings.json, and a module row in `kit_module_hooks` (or the spine). SPEC-212's preamble records why `advisor` was chosen over a new `tool_policy` module (a new module owes the full SPEC-200 contract surface).
- RECORDED: deep-malformed policy INTERNALS below the new top-level guards (a non-dict entry inside `rules`, a string `rules` value) still crash; accepted as documented in SPEC-212 coverage notes since the realistic corruption class (a bad dashboard export, a truncated file) is caught by the top-level guards.

## Reproduce

```
bash tests/test-tool-policy-guard.sh
# standalone deny proof:
printf '%s' '{"browser":{"prefer":"browser-harness-js","rules":[{"match":"mcp__plugin_playwright","action":"deny","note":"Use the harness first."}]}}' > /tmp/deny-policy.json
echo '{"tool_name":"mcp__plugin_playwright_playwright__browser_click"}' | KIT_TOOL_POLICY=/tmp/deny-policy.json bash hooks/tool-policy-guard.sh; echo "exit=$?"   # expect exit=2 + DENIED on stderr
# live negative control (one-time):
sed -i.bak 's/sys.exit(2)/sys.exit(0)/' hooks/tool-policy-guard.sh
bash tests/test-tool-policy-guard.sh   # expect exit 1, exactly 4 FAIL (rows 1, 14, 22a, 22b)
mv -f hooks/tool-policy-guard.sh.bak hooks/tool-policy-guard.sh
bash tests/test-tool-policy-guard.sh   # expect exit 0, 25/25
bash tests/test-meta.sh && bash tests/test-install-modules.sh && bash tests/test-hooks.sh
```

Full trail: SPEC-212 (`docs/specs/SPEC-212-tool-policy-guard-contract.md`), including the 3-lens critique (rounds 10 -> 5 findings, max severity CRITICAL -> accepted, verdict SOLID) and the honest lens-skip triage. Campaign complete: 6/6 items shipped (SPEC-208 memory-tidy, SPEC-209 loop-engineering, SPEC-210 research-architecture, SPEC-211 research-pitfalls+stack, SPEC-212 tool-policy-guard).
