# Spec: hooks/tool-policy-guard.sh contract + wiring (backfill)
Generated: 2026-07-31
Status: DRAFT (reverse-engineered, plus one NEW claim: the wiring)

Backfill item 6/6 of the ID-452 campaign, closing it. Unlike items 1-5 the target is EXECUTABLE bash, so the dialect shifts: temp policy-file fixtures drive real invocations with hook JSON on stdin, asserting exit codes and stderr; no prose pins. Operator decision recorded: the campaign found the hook documented (README/architecture hook tables) but registered nowhere, dead from the live-wiring perspective; the decision is WIRE IT, so AC-7 is a new claim, not reverse-engineered. The wiring cascaded beyond `hooks/hooks.json` by mechanical necessity, each step forced by an existing test: `tests/test-meta.sh` pins hook-count parity between `hooks/hooks.json` and `settings.json` (both files or neither), and `tests/test-install-modules.sh` proves an additive re-install never drops a wired hook, which only holds for hooks mapped to a known install module (install.sh reverse-maps existing wired hooks to modules; unmapped ones are silently dropped on re-install). Decision, logged: the hook joins the existing `advisor` module (advisory tier per `docs/architecture.md`, inert until config, same class as its sibling), NOT a new `tool_policy` module, because a new module owes the full SPEC-200 kit-contract surface, disproportionate for one fail-open hook. One engine change, disclosed: the round-1 CRITICAL found valid-but-non-dict JSON (a bare `[1,2,3]` payload or policy) crashing past the `try/except` with a traceback exit 1, violating the script's own fail-open header contract; a minimal isinstance guard was added (deny/ask paths untouched). Process deviation, stated honestly: the `/kit:test-plan` Step 0 research dispatch was skipped per the SPEC-208-211 precedent; the surface is one small script plus its registration files, read directly.

## Acceptance Criteria
- [ ] AC-1: deny: a policy rule whose `match` substring occurs in `tool_name` with `action: deny` exits 2, stderr naming the tool, `DENIED by policy (<domain>)`, `Preferred: <prefer>`, and the rule's note.
- [ ] AC-2: ask: `action: ask` exits 0 with a stderr warning naming the domain, `Preferred rung: <prefer>`, and `Proceed only if the lighter rung is genuinely exhausted.`
- [ ] AC-3: fail-open silence: explicit `allow`, no matching rule, missing policy file, malformed policy (syntactically invalid OR valid-but-non-dict JSON), malformed/empty/non-dict stdin payload, and missing `tool_name` all exit 0 with EMPTY stderr (a broken policy must never brick a tool call).
- [ ] AC-4: `KIT_TOOL_POLICY` overrides the default `~/.claude/dwarves-kit/tool-policy.json` path; the outcome tracks the named fixture.
- [ ] AC-5: schema normalization: v1 (domains at top level, `rules`) and v2 (domains under `capabilities`, `providers` with per-provider `action`) both enforce; `_`-prefixed and non-dict domain values are skipped.
- [ ] AC-6: first matching rule wins: an `ask` OR an `allow` listed before a `deny` with the identical match warns/passes, never blocks.
- [ ] AC-7 (NEW, the wiring): registered as PreToolUse matcher `*` in BOTH `hooks/hooks.json` (plugin path) and `settings.json` (bash path), exactly once each, and mapped into the `advisor` module in `install.sh` so the layered bash install can wire it and an additive re-install never drops it.

## Test plan
Date: 2026-07-31 (revised once after the round-1 critique)
Source: this spec's ## Acceptance Criteria. Dialect: executable-hook behavior (fixtures + real invocations), plus 3 wiring reads. All fixtures live in a mktemp dir with EXIT-trap cleanup; every invocation sets `KIT_TOOL_POLICY` explicitly AND runs with `HOME` pointed at an empty mktemp home, so neither the machine's real default-path policy nor an implementation that silently ignores the env var can confound a result (round-1 HIGH). The harness is assert-and-continue (never short-circuits on a failed assert), so the live NC's survivor claims are exercised, not skipped. `G=hooks/tool-policy-guard.sh`. Deny rows split exit-code and stderr-message assertions on purpose: the live NC mutates only the block, so the message assertions are its named survivors. Silent rows assert stderr EMPTINESS (`! test -s`), never absence-of-prefix, so a traceback can not pass green. Proof cells escape literal pipes as `\|`; the materialized script uses bare `|`.

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|-------------|----------|-------|
| 1 | v1 deny: exit code | security/safety | AC-1, AC-4 | exit 2 (blocked); fixture at a non-default path + empty `HOME` proves the override in the same breath | `echo '{"tool_name":"mcp__plugin_playwright_playwright__browser_click"}' \| HOME=$F/home KIT_TOOL_POLICY=$F/deny.json bash $G; test $? -eq 2` |
| 2 | v1 deny: stderr message | happy-path | AC-1 | stderr carries the tool name, `DENIED by policy (browser)`, `Preferred: browser-harness-js`, the note (NC survivor: printed before the exit) | same invocation, stderr captured; `grep -F` each fragment |
| 3 | v1 ask: exit code | happy-path | AC-2 | exit 0 (warn, never block) | ask fixture; `test $? -eq 0` |
| 4 | v1 ask: stderr warning | happy-path | AC-2 | stderr carries `policy-controlled (<domain>)`, `Preferred rung:`, the full proceed-only sentence | same invocation, stderr captured; `grep -F` each fragment |
| 5 | explicit allow: silent pass | boundary | AC-3 | exit 0, stderr EMPTY | allow fixture; `test $? -eq 0 && ! test -s err` |
| 6 | no matching rule: silent pass | boundary | AC-3 | exit 0, stderr EMPTY (an unlisted tool is never policy business) | deny fixture, unmatched tool_name |
| 7 | missing policy file: silent pass | failure-injection | AC-3, AC-4 | exit 0, stderr EMPTY (`KIT_TOOL_POLICY` at a nonexistent path; row 1's negative twin) | `KIT_TOOL_POLICY=$F/nonexistent.json` |
| 8 | syntactically malformed policy | failure-injection | AC-3 | exit 0, stderr EMPTY, even for a tool the deny fixture would block | `not json` policy, playwright tool_name |
| 9 | valid-but-non-dict policy | failure-injection | AC-3 | exit 0, stderr EMPTY: `[1,2,3]` as the whole policy file (round-1 CRITICAL: crashed exit 1 pre-guard) | `[1,2,3]` policy fixture |
| 10 | malformed stdin payload | failure-injection | AC-3 | exit 0, stderr EMPTY | `printf 'not json' \| ...` against the deny fixture |
| 11 | valid-but-non-dict stdin payload | failure-injection | AC-3 | exit 0, stderr EMPTY: `[1,2,3]` as the payload (round-1 CRITICAL, other half) | `printf '[1,2,3]' \| ...` against the deny fixture |
| 12 | empty stdin: fail open | failure-injection | AC-3 | exit 0, stderr EMPTY (payload defaults to `{}`) | `printf '' \| ...` against the deny fixture |
| 13 | missing tool_name: silent pass | boundary | AC-3 | exit 0, stderr EMPTY | `echo '{}' \| ...` against the deny fixture |
| 14 | v2 capabilities/providers deny | security/safety | AC-5, AC-1 | exit 2, stderr `DENIED by policy (computer_use)` (providers normalized into rules; `_doc` string key skipped en route) | v2 fixture: `_doc` + `capabilities.computer_use.providers` deny |
| 15 | `_`-prefixed domain skipped | boundary | AC-5 | exit 0, stderr EMPTY: a deny rule under `_disabled` never fires | `_disabled` fixture, matching tool_name |
| 16 | non-dict domain value skipped | boundary | AC-5 | exit 0, stderr EMPTY: a non-underscore domain whose value is a bare string is skipped, not crashed on (round-1 HIGH: the isinstance half of the skip guard was untested) | `{"computer_use":"disabled"}` fixture, matching tool_name |
| 17 | first match wins: ask shadows deny | regression | AC-6 | exit 0, stderr has `policy-controlled` and NOT `DENIED` (identical match, ask listed first) | ask-then-deny fixture; `grep -qF` + `! grep -qF` |
| 18 | first match wins: allow shadows deny | regression | AC-6 | exit 0, stderr EMPTY (a permissive rule silently shadowing a later deny is the scarier regression; round-1 MEDIUM) | allow-then-deny fixture |
| 19 | wiring: hooks.json | happy-path | AC-7 | the jq extraction yields the SINGLE value `*` (strict whole-output equality, not a grep: two entries or a second matcher can not pass; round-1 MEDIUM) | `[ "$(jq -r '.hooks.PreToolUse[] \| select(.hooks[].command \| contains("tool-policy-guard")) \| .matcher' hooks/hooks.json)" = "*" ]` |
| 20 | wiring: settings.json | happy-path | AC-7 | same strict single-value equality on the bash-install side (count parity itself stays test-meta's) | same jq form over `settings.json` |
| 21 | wiring: advisor module mapping | regression | AC-7 | install.sh's advisor case-arm names `tool-policy-guard.sh`, asserted order-tolerantly (a reorder or a third advisor hook is legitimate; round-1 MEDIUM); spine-only ABSENCE is test-install-modules' UNWANTED list, not here | `grep -E '^\s*advisor\)' install.sh \| grep -qF 'tool-policy-guard.sh'` |
| 22 | in-suite negative control (permanent, scratch copy) | falsifiability | AC-1 | first assert `grep -c 'sys.exit(2)' $G` is exactly 1 (a future second deny exit would silently narrow the control; round-1 LOW), then on a mktemp COPY with `sys.exit(2)` -> `sys.exit(0)`: the `! cmp -s` setup guard proves the mutation took, the deny fixture returns exit 0 on the mutant, and its stderr STILL prints `DENIED` (message path intact, block gone: the discrimination rows 1 vs 2 encode); EXIT-trap cleanup | inside the test script: count guard + mktemp copy + sed + `! cmp -s` + exit/stderr asserts |
| 23 | live negative control (one-time, recorded) | falsifiability | AC-1, AC-5 | mutate the TRACKED `$G` the same way via `sed -i.bak`; expect EXACTLY this 4-assert flip set: row 1 RED, row 14 RED (both deny exits ride the same line), row 22's count guard RED (0 occurrences left) and row 22's `! cmp -s` guard RED (nothing left to mutate); meaningful survivors: rows 2/4/17 (stderr paths), every fail-open row, every wiring row, row 22's mutant-behavior asserts; restore from the `.bak`, prove byte-identity via truncated sha256 + re-derive command, re-run green; emergency recovery `mv -f $G.bak $G` (or `git checkout -- $G`) | recorded with both transcripts in `docs/verification/backfill-tool-policy-guard.md` |

### Coverage notes
- Every AC maps to at least one row and every row to an AC; no orphans. Failure-injection is genuinely deep here (rows 7-13), the first campaign target whose fail-open branch is executable rather than prose.
- Only rows 2/4 pin message fragments, and those ARE the operator-facing contract (what Claude reads when blocked/warned); a message reword breaks the row and prompts a re-verify, same stance as the prose specs.
- Deliberately unpinned, accepted: the default-path branch with `KIT_TOOL_POLICY` unset (testing it reads real `$HOME` state; the HOME-isolation discipline covers the confound instead); the v2 `prefer` vs legacy `preferred` alias and the per-provider default `action: allow`; deep-malformed policy INTERNALS (a non-dict entry inside `rules`, a string `rules` value) below the new top-level guards; cross-domain match precedence and the rules-before-providers concatenation order (dict-order iteration, low discriminating power; round-1 MEDIUM accepted); stdout silence; the dashboard-side export that produces the policy file (`lib/bench/dashboard.py`, out of scope).
- Wiring counts (hooks tables, script inventory) stay owned by `tests/test-meta.sh`; rows 19-21 pin only the NEW registration facts test-meta checks generically, not by name. The live-NC-on-a-tracked-file shape (no trap; `.bak` + documented emergency recovery, one-time, operator-run) was challenged by the determinism lens and is ACCEPTED per the SPEC-208-211 campaign precedent: the permanent in-suite row 22 is the load-bearing control.

## Test plan critique
Date: 2026-07-31 (revised once after the round-1 critique)
Spec: SPEC-212
Lenses run: Coverage completeness, Oracle & falsifiability, Determinism & maintainability (3 of the standard 6, dispatched as parallel read-only subagents; the oracle lens re-ran the fixtures live and hand-simulated both NCs against the real script). Skipped, honestly: Feasibility (every proof was pasted-and-run live during authoring), Test-ladder depth (single small script, the ladder is flat), Tiering & floor (no model call in scope). Same ID-452 calibrated-cost triage as SPEC-208-211.

Rounds:
- [[QL-VERDICT round=1 clean=false findings=10]]
- [[QL-VERDICT round=2 clean=false findings=5]]

Round 1 (full 3-lens dispatch) returned 10 deduplicated findings: 1 CRITICAL, 3 HIGH, 5 MEDIUM, 1 LOW. One revision was applied (the matrix above, plus the minimal engine guard). Round 2 was a narrow mechanical re-check by the coordinator, each new/changed proof run live. K fell 10 to 5, max severity CRITICAL to accepted; the loop stops.

### Critical findings
1. Valid-but-non-dict JSON (a bare list/string/number as the stdin payload or the whole policy file) parsed successfully inside the `try` block then crashed on `.get()`/`.items()` OUTSIDE it: AttributeError traceback, exit 1, non-empty stderr, falsifying the script's own fail-open header contract; the lens proved it live (coverage lens) -- fix: minimal isinstance guards added to the script (the one engine change of this backfill, deny/ask paths untouched) + rows 9/11 pin both halves -- resolved in round 1.

### High findings
1. The non-dict half of the domain-skip guard (`or not isinstance(spec, dict)`) was never exercised: the only skip fixture (`_doc`) is underscore-prefixed, so deleting the isinstance clause would pass every drafted row (coverage lens) -- fix: row 16 -- resolved in round 1.
2. AC-4's override proof was confounded by ambient machine state: an implementation ignoring `KIT_TOOL_POLICY` would pass row 1 only because this machine happens to lack a default-path policy (oracle lens) -- fix: every invocation now runs with `HOME` at an empty mktemp home -- resolved in round 1.
3. The live NC mutates the tracked script with no trap-guaranteed restore; an interrupt strands the repo with deny neutered (determinism lens) -- ACCEPTED per campaign precedent: one-time, operator-run, recorded, `.bak` + emergency recovery documented; row 22 is the load-bearing permanent control -- OPEN as accepted.

### Medium findings
1. Cross-domain precedence and rules-before-providers concatenation order untested (coverage lens) -- accepted, documented in coverage notes -- OPEN as accepted.
2. Allow-before-deny shadowing (the scarier first-match regression) had no row (coverage lens) -- fix: row 18 -- resolved in round 1.
3. Row 22's mutant-behavior asserts could not be called live-NC "survivors" if the harness short-circuits on the failed setup guard (oracle lens) -- fix: the harness is declared and built assert-and-continue -- resolved in round 1.
4. Row 21's proof pinned install.sh's case-arm verbatim (a third literal copy), breaking on a legitimate reorder (determinism lens) -- fix: order-tolerant two-step grep -- resolved in round 1.
5. Rows 19/20 specified the jq extraction but not the assertion strictness, leaving a duplicate-registration false-pass open to a loose materialization (determinism lens) -- fix: strict whole-output equality pinned in the proof cells -- resolved in round 1.

### Low findings
1. No assertion pinned the `sys.exit(2)` occurrence count, so a future second deny exit would silently narrow both NCs (oracle lens) -- fix: row 22's count guard -- resolved in round 1.

### Scores (round 1, pre-revision)
- Coverage completeness: 6/10
- Oracle & falsifiability: 6/10
- Determinism & maintainability: 6/10

### Verdict: SOLID (after the round-1 revision resolved the CRITICAL, two of three HIGHs, and three of five MEDIUMs; the remainder are accepted with rationale recorded above)
