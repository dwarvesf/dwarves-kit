# SPEC-116: model-routing enforcement (the `Model:` field reaches `--model`)

Status: VALIDATED
Lane: full
Type: spec-feature

## Spec validation (5-lens adversarial pass, self-run headless per AGENTS.md zone 2)

- **Security:** no auth/secret/injection surface (shell dispatch of an internal `--model` flag,
  no user-facing input). Pass, no findings.
- **Failure modes:** an invalid `Model:` value (e.g. a typo'd tier) is passed verbatim to
  `claude -p --model <value>` unchanged from today's behavior , `claude`'s own CLI validates the
  tier name, `_route()` does not duplicate that validation (SPEC-087's design, unchanged here).
  Noted, not a defect this spec introduces. No other failure-mode gaps found.
- **Assumptions:** confirmed no competing model-selection mechanism exists (`grep -n
  'CLAUDE_MODEL\|ANTHROPIC_MODEL' lib/*.sh` , zero hits) that could race or override `--model` at
  dispatch. The MOCK-`CLAUDE_CMD` test pattern assumes the shim faithfully stands in for the real
  `claude` binary's argv handling, the same assumption `tests/test-orchestrate.sh` already relies
  on (established precedent, not new risk).
- **Scope:** atomic , one spec doc + one new test file (+ fixtures), zero `lib/` edits. Verification
  commands are concrete and runnable. Test coverage is scoped to what the Done criteria requires:
  per-tier default-applied proof via the existing serial-path mock harness (extending
  `tests/test-orchestrate.sh`'s TEST 8 pattern to opus/haiku, not just sonnet) plus ONE wave-path
  case (opus) reusing `tests/test-orchestrate-wavefront.sh`'s throwaway-git-init mock pattern, not a
  full tier x path matrix , that would exceed what "prove the wiring is real" requires. No
  loop-reachable scope/architecture decision is made autonomously; the two decisions this spec
  makes (enforcement site, fallback tier) are both read directly off already-Accepted precedent
  (ADR-0032, SPEC-107), not invented.
- **Solution design:** simplest possible design , reuse the two existing mock-`CLAUDE_CMD` test
  patterns already in the repo rather than building a new harness; zero new abstractions; zero
  `lib/` changes since the mechanism already exists. The alternative (adding a `route-suggest.sh`
  call inside `orchestrate.sh` to "double-check" the tier at dispatch) was considered and rejected:
  it would add a runtime dependency + failure mode for zero benefit, since the two surfaces already
  cannot conflict by construction (disjoint phases).

**Verdict: APPROVED**, no critical issues, no warnings requiring a fix before implementation.

## Problem

ADR-0032 section 2 (ACCEPTED) decides the routing RULE, planning-dominant sub-goals -> `opus`,
execution-dominant -> `sonnet`, trivial -> `haiku`, and says the mechanism is "`Model:` field ->
orchestrate `--model`". `orchestrate-hardening` open-fork 3 asks WHERE that enforcement lives
(`lib/queue/orchestrate.sh` vs `lib/classify/route-suggest.sh`) and whether `route-suggest.sh`'s "Opus-spend"
suggester could silently disagree with an explicit `Model:` field. Neither question has a written
answer, and no test proves the DEFAULT-applied case (a goal file that carries `Model: opus` and
reaches a real `claude -p --model opus` dispatch) across all three tiers , `tests/test-orchestrate.sh`
TEST 8 (:187-225) proves only the `sonnet` tier + the inherit negative control, not `opus`/`haiku`,
and not the wave (concurrent) delegate path.

## Research (what already exists , this spec ENFORCES/PROVES, does not build)

- `lib/queue/orchestrate.sh:_route()` (SPEC-087, :392-403) already reads a goal file's bare `Model:` /
  `Effort:` lines and is already threaded into `--model`/`--effort` at BOTH delegate dispatch sites:
  the serial path (`cmd_run`, :1159-1162) and the concurrent wave path (`_wave_run`, :786-788). Both
  feed `route_flags` into the single shared `_run_one_session()` (:601-631), whose three mutually
  exclusive run-paths (watchdog / stream-json / plain) each pass `$route_flags` straight into the real
  `"$CLAUDE_CMD" -p $route_flags ...` invocation. An absent `Model:` line yields an empty `route_flags`
  , the session inherits the parent tier (documented at :394 and reaffirmed by SPEC-107's "one stance":
  `_route()`'s absent-field->inherit fallback is UNCHANGED by SPEC-107, only the write-time default on
  the authoring surfaces changed).
- `lib/classify/route-suggest.sh` (token-optim-v3 SG-06) is a standalone CLI invoked by a human/`agents/meta-agent.md`
  Mode B at DECOMPOSE time, when DRAFTING a goal file's `Model:` line from measured SG-09 ablation data.
  `grep -rn route-suggest.sh lib/ | grep -v route-suggest.sh` (i.e. every caller except the file itself)
  returns zero hits inside `lib/queue/orchestrate.sh` , the dispatch path never invokes it. It cannot silently
  override an explicit `Model:` field because it has no dispatch-time call site at all.

## Solution (pins open-fork 3; proves the existing wiring; adds the dedicated test)

1. **Enforcement site (open-fork 3): `lib/queue/orchestrate.sh`.** `_route()` + the two `route_flags`
   dispatch sites are the enforcement mechanism; `route-suggest.sh` stays a decompose-time SUGGESTER
   only (per its own header comment: "a SUGGESTER, never an auto-router"). This is not a new decision,
   it is what the code already does; this spec is the first place it is written down and load-bearing.
2. **Route-suggest alignment (structural, not runtime):** because `route-suggest.sh` has no call site
   in `lib/queue/orchestrate.sh`, an explicit `Model:` field can never be contradicted at dispatch time , the
   two surfaces operate in disjoint phases (decompose-time suggestion vs dispatch-time enforcement).
   `tests/test-model-routing.sh` pins this with a grep negative control (no `route-suggest` call site
   in the dispatch functions) instead of a runtime mock, since there is no runtime interaction to mock.
3. **Fallback tier (the no-`Model:`-field default): inherit the parent session's tier.** This is the
   EXISTING, already-documented default (`_route()` :394, SPEC-107 "Open questions"): a goal file with
   no `Model:` line makes `route_flags` empty, so `_run_one_session()` passes no `--model` flag and the
   `claude -p` child inherits whatever tier launched the conductor. SPEC-107 changed the WRITE-time
   default on authoring surfaces (write `Model: sonnet` instead of omitting) but explicitly left this
   READ-time fallback unchanged. This spec's negative control proves the fallback is real (no crash, no
   silently-wrong tier) rather than re-asserting the write-time policy.
4. **`tests/test-model-routing.sh`** (new, dedicated file , distinct from `tests/test-routing.sh`, which
   covers `route-suggest.sh`'s suggestion logic, not dispatch enforcement): a MOCK `CLAUDE_CMD` shim
   (same pattern as `tests/test-orchestrate.sh`) records its invocation args; drives BOTH delegate paths
   (serial `run` and the wave path via `WAVE_CAP>=2`) with fixture goal files carrying `Model: opus`,
   `Model: sonnet`, `Model: haiku`, and no `Model:` line; asserts the recorded args contain the matching
   `--model <tier>` (or none, for the no-field case); asserts the route-suggest non-contradiction grep.

No `lib/` code changes are required , the enforcement already exists and is already wired into both
delegate paths under SPEC-087/SPEC-106. This spec's diff is `docs/specs/`, `docs/decisions/` cross-reference,
and `tests/test-model-routing.sh` + its fixtures.

## Verification

```bash
cd dwarves-kit
bash tests/test-model-routing.sh   # new: per-tier default-applied (opus/sonnet/haiku), serial + wave,
                                    # route-suggest alignment grep, no-field fallback negative control
bash tests/test-orchestrate.sh     # unchanged, still green (TEST 8 sonnet+inherit case)
bash tests/test-meta.sh            # structural integrity unaffected

# tests/test-routing.sh (route-suggest.sh's own suggestion-logic suite) is UNTOUCHED by this diff
# and out of scope, but on this host fails under the stock /bin/bash 3.2 (no mapfile/assoc-arrays):
# pre-existing, unrelated to model-routing enforcement. Confirm with homebrew bash:
/opt/homebrew/bin/bash tests/test-routing.sh   # green with bash 4+
```

## After state

- `docs/specs/SPEC-116-model-routing-enforce.md` (this file) pins open-fork 3: enforcement site =
  `lib/queue/orchestrate.sh`, fallback tier = inherit.
- `tests/test-model-routing.sh` + `tests/fixtures/model-routing/` prove the default-applied positive
  case for opus/sonnet/haiku on both delegate paths, the route-suggest non-contradiction, and the
  no-`Model:`-field negative control.
- No behavior change to `lib/queue/orchestrate.sh` or `lib/classify/route-suggest.sh` , this is a proof + pin, not a
  new feature.

## Scope edges

**In:** the enforcement-site decision (open-fork 3), the route-suggest alignment confirmation, the
`tests/test-model-routing.sh` proof (serial + wave, all three tiers, negative control).
**Out:** token capture (orchestrate-hardening sub-goal 02), the TIER-4 mega-close (03), multiplexer
panes (04), docs-wiring (05). `ROADMAP.md` lives in the `ops-toolkit` repo and is not touched here.
**Not:** re-deciding ADR-0032's routing RULE; changing `route-suggest.sh`'s heuristic; changing
`_route()`'s absent-field fallback (inherit stays inherit, per SPEC-107).

## Open questions

None , both open questions this spec was scoped to resolve (enforcement site, fallback tier) are
answered above from the code and SPEC-107's already-accepted precedent, not newly invented here.
