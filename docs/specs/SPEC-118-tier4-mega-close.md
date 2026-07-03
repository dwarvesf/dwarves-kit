# SPEC-118: TIER-4 mega-close (verify the assembled wave, then hold the human gate)

Status: VALIDATED
Lane: full
Type: spec-feature

## Problem

`orchestrate.sh run <megadir>` drives a mega-goal as one fresh `claude -p` per sub-goal. When every
sub-goal box is checked, the loop does exactly one thing (orchestrate.sh:1153):

```bash
nx=$(_next "$roadmap")
[ -n "$nx" ] || { _say "[orchestrate] all sub-goals checked; done."; return 0; }
```

It prints "done" and returns. The mega-goal is never verified AS A WHOLE. The per-sub-goal V-model
already fired for each sub-goal in isolation, but nothing checks that the sub-goals WIRE TOGETHER,
that the assembled result meets the mega-goal OBJECTIVE, that no artifact was defined-but-never-
dispatched (the kit-hardening c6fbd99 class: three SG-04 agents existed + gated + rostered +
documented but no command dispatched them), or that the security surface of the combined change is
sound. All of that is silently pushed to the operator at the final human click.

ADR-0032 §5 names this as a gap the kit is obliged to close: "No mega-level TIER-4 close in
orchestrate.sh today (integration-verifier + review-team + advisor after all sub-goals) , currently
pushed to the operator. Make it a first-class close step (or a final sub-goal)."

## Solution

Replace the "done"-and-return with a real TIER-4 mega-close. After every sub-goal box is checked,
the close runs OVER THE ASSEMBLED WAVE (not re-running each sub-goal's per-task V-model):

1. **No-orphan sweep** (mechanical, in the bash driver) , every dispatchable artifact the wave
   added that is never dispatched is a BLOCKING finding. Fail-fast: a blocking orphan halts before
   an LLM session is spent.
2. **Verifier close session** (one dispatched `claude -p`, mockable via `CLAUDE_CMD`) , runs
   integration-verifier against the mega-goal OBJECTIVE + `/kit:review-team` (incl. the
   security-reviewer lens) + the advisor in BOTH modes (critique + over-suggest) over the assembled
   wave, and reports a verdict.
3. **Hold the human gate** , only after (1) and (2) pass, the close emits a `held` event + message
   and returns 0. It NEVER auto-merges past the gate (gated-final). The final click is the human's.

### Open-fork 1 resolution: STEP inside `cmd_run`, not a final auto sub-goal

The close is a **first-class STEP** that replaces the `_next`-empty terminal in `cmd_run`, not a
sub-goal the decompose appends. Rationale (see impl notes for the full argument):

- The goal's `Done =` says the close "replaces today's 'done'-and-return" , that IS the loop's
  `_next`-empty terminal (orchestrate.sh:1153). Only a STEP can replace the loop's own terminal; a
  sub-goal runs INSIDE the loop, it cannot BE its exit.
- The mega-level no-orphan sweep needs the driver's whole-wave view (the corpus root + the assembled
  artifacts), which a single sub-goal session does not naturally hold.
- The "prefer reuse , not a bespoke close engine" constraint is honored WITHOUT a sub-goal: the STEP
  reuses the existing `claude -p` dispatch seam (`CLAUDE_CMD` + prompt-via-tempfile-on-stdin, the
  same path `_run_one_session` uses) and the existing `_emit_event` event log. It builds NO parallel
  engine. "Reuse the lifecycle + gate ledger" means "don't hand-roll a second orchestrator," and the
  STEP doesn't.

## Design

### The close contract (what "runs over the assembled wave" means)

```
cmd_run loop: _next empty (all boxes checked)
   |
   v
_tier4_close <dir> <roadmap>                         [TIER4_CLOSE=1 default; =0 restores done-and-return]
   |
   |-- 1. _no_orphan_check <corpus>   (mechanical, bash, deterministic)
   |        for each agents/<name>.md in the corpus:
   |          token = <name>; dispatched iff <name> appears AS A WHOLE WORD (grep -w, not a bare
   |          substring , else `advisor` false-matches `advisory`) in commands/ | lib/ | AGENTS.md |
   |          WORKFLOW.md (any file other than its own agents/<name>.md definition).
   |        zero dispatch refs  ->  BLOCKING orphan  ->  emit blocked event + finding + RETURN 1
   |        (HALT before the LLM session; the seeded-orphan NEGATIVE CONTROL lands here)
   |
   |-- 2. dispatch ONE `claude -p` close session          (via CLAUDE_CMD, mockable)
   |        prompt (built by _build_close_prompt): run integration-verifier against the mega-goal
   |        OBJECTIVE (the ROADMAP `**Destination:**` line if present, ELSE the `# Mega-goal:`
   |        title line , fixtures use the title, the real orchestrate-hardening ROADMAP has
   |        Destination) + /kit:review-team incl. the
   |        security-reviewer lens + the advisor in BOTH modes over the assembled wave; report a
   |        verdict. Plain `claude -p` (NEVER --stream to the conductor, ADR-0032 §1). Session
   |        nonzero -> emit blocked + RETURN 1.
   |
   |-- 3. HOLD the human gate
            emit `held` event + message; NEVER merge; RETURN 0 (clean held stop, verifiers ran).
```

- **Split rationale.** (1) is mechanical + deterministic, so it is unit-testable with a seeded
  orphan and NO llm mock , that is what makes the negative control a real, cheap test. (2) is
  judgment (integration wiring, security, advisor ideas) that cannot be faithfully faked in bash, so
  it rides the same delegate `claude -p` seam the rest of the orchestrator uses. Mirror of the kit's
  own split: deterministic checks in the driver, judgement in the LLM session. In c6fbd99 the
  integration-verifier is exactly what flagged the orphan agents by judgment; the mechanical sweep
  here is the deterministic backstop for the specific agent-dispatch class.
- **Order.** No-orphan sweep FIRST (fail-fast; a blocking orphan should not cost an LLM session),
  then the verifier session, then the hold. The contract's a-d is WHAT the close runs, not a strict
  temporal order; "only after those pass does it hold the gate" is preserved (the gate holds only
  after BOTH the sweep and the session pass).
- **Never auto-merges.** The close is verify-then-HOLD. It calls no merge hook. The per-sub-goal
  auto-bottom-up merge (mega-merge) is a separate concern that already ran per sub-goal; the close is
  the final whole-wave gate the human clicks through.
- **Corpus.** `_no_orphan_check` sweeps `${TIER4_CORPUS:-<the megadir's git repo root>}`. For the
  kit's own dogfood run the work repo is the kit repo. Tests pass `TIER4_CORPUS` explicitly. If
  `TIER4_CORPUS` is unset AND the megadir git-root cannot be resolved (e.g. a `mktemp` megadir not
  in a repo), the no-orphan sweep is SKIPPED with an advisory WARN (non-halting) , there is no
  corpus to sweep, so it must not manufacture a false halt; the verifier session + hold still run.
- **Objective.** integration-verifier is pointed at the mega-goal OBJECTIVE , the ROADMAP
  `**Destination:**` line if present, else the `# Mega-goal:` title line , injected into the prompt.
- **`held` is a log-only marker.** It is a new `_emit_event` status string (the existing vocab is
  flip/executing/shipped/blocked/stalled/merged/handoff); `_emit_event` takes free-form status, so
  no crash. The board renders `shipped` at close time (boxes are checked), so `held` surfaces only in
  the event log, which is its intent (an audit marker, not a board state).
- **Opt-out `TIER4_CLOSE`.** Default `1` (on , replaces the done-and-return). `TIER4_CLOSE=0`
  restores the bare done-and-return, mirroring the WATCHDOG / CAPTURE_TOKENS / DETERMINISTIC_HANDOFF
  env-gate pattern (orchestrate.sh:56,69,100). Unrelated suites that run an all-auto fixture to the
  terminal (`test-model-routing.sh` SECTION 2's `run_serial_case`) set `TIER4_CLOSE=0` so the close
  is exercised ONLY by its own dedicated test, not as a side effect elsewhere.

### No-orphan sweep scope (ponytail boundary)

The MECHANICAL sweep targets the c6fbd99 orphan class concretely and reliably: a dispatchable
**agent** (`agents/<name>.md`) with no dispatch reference. It is NOT a general dead-code detector for
arbitrary bash symbols or CLI flags (unreliable, over-built). The softer flag/step/path wiring is
covered by the close SESSION's integration-verifier (its judgment lens, exactly as in c6fbd99). This
split keeps the deterministic test honest and the coverage complete.

## Test plan

`tests/test-tier4-close.sh`, all via the `CLAUDE_CMD` mock seam (no live LLM), each row a coverage
cell:

| Category | Case | Asserts |
|---|---|---|
| verifiers-before-gate | clean all-checked run reaches the close | the close DISPATCHES the verifier session (mock sentinel written) AND emits `held` , i.e. a verifier ran and the gate is held, NOT the bare done-and-return (the "session ran before the gate" property reduces to "session dispatched AND held emitted", the only runtime-observable form) |
| no-orphan unit | `_no_orphan_check` on a clean corpus | returns 0, no orphan printed |
| seeded-orphan NC | `_no_orphan_check` on a corpus with an added agent no command dispatches | returns nonzero, names the orphan agent (BLOCKING) |
| seeded-orphan NC (e2e) | full close run over a corpus carrying a seeded orphan | close HALTS nonzero, orphan named, verifier session NOT reached, gate NOT held |
| gate-held | clean close run | a `held`/"NOT auto-merged" message; NO merge hook invoked; exit 0 |
| replaces done-and-return | clean close run | the bare "all sub-goals checked; done." return is GONE (the close ran instead) |
| opt-out | `TIER4_CLOSE=0` clean all-checked run | restores the done-and-return; no close session dispatched (backward-compat escape hatch) |

COVERAGE-DELTA row is recorded in the proof-of-done: covered = {verifiers-run-before-gate,
no-orphan unit + seeded-orphan NC (unit + e2e), gate-held, replaces-done-and-return, opt-out};
uncovered = {a LIVE integration-verifier/review-team/advisor verdict (the session content is the
LLM's job, mocked here , the driver only proves it is DISPATCHED before the gate); the softer
flag/step no-orphan lens (delegated to the close session's integration-verifier by design)}.

## Verification

```bash
bash tests/test-tier4-close.sh      # the new coverage: verifiers-before-gate + seeded-orphan NC + gate-held
bash tests/test-orchestrate.sh      # regression: serial delegate path unchanged (fixtures stop at gates)
bash tests/test-orchestrate-wavefront.sh   # regression: wave path + the blocked/halt negatives unchanged
bash tests/test-model-routing.sh    # regression: SECTION 2 reaches the terminal -> must set TIER4_CLOSE=0
bash tests/test-token-capture.sh    # regression: serial delegate capture path unchanged
bash tests/test-meta.sh             # structural integrity (agent roster, dispatch invariants)
```

Pass = `test-tier4-close.sh` all green AND every regression suite above still green.

## After state

- `orchestrate.sh` has `_tier4_close` + `_no_orphan_check` + `_build_close_prompt`; `cmd_run`'s
  `_next`-empty branch calls the close (default on; `TIER4_CLOSE=0` restores the old return).
- The close runs the no-orphan sweep + a verifier `claude -p` session over the assembled wave, then
  HOLDS the human gate. It never auto-merges.
- `tests/test-tier4-close.sh` pins verifiers-run-before-gate, the seeded-orphan NC, and gate-held.
- The header docstring documents the close step + `TIER4_CLOSE` / `TIER4_CORPUS`.

## Scope edges

**In:** the `_tier4_close` STEP (replacing the done-and-return), `_no_orphan_check` (mechanical agent
sweep), `_build_close_prompt`, the verifier-session dispatch, the hold-the-gate behavior, the tests +
coverage-delta, header docs.

**Out:** the model routing (SG-01, shipped); the token capture (SG-02, shipped); the panes (SG-04);
the docs wiring (SG-05). A LIVE integration-verifier/review-team/advisor verdict (mocked here). The
per-sub-goal merge (mega-merge, already runs).

**Not:** re-running each sub-goal's per-task V-model (the close verifies the WHOLE); auto-merging
past the human gate (gated-final , HOLD it); a bespoke close engine when the existing `claude -p`
dispatch + event log are reused (open-fork 1 prefers reuse); a general dead-code detector (the
mechanical sweep is the agent-dispatch class only; softer wiring is the close session's job).

## Open questions

None blocking. The corpus default (`TIER4_CORPUS`) is the megadir's git repo root; the kit's own
dogfood run sets it to the work repo. Documented in the header.
