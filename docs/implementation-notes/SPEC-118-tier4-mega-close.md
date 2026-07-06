# Implementation notes: SPEC-118 TIER-4 mega-close

The DELTA from the spec. Decisions the spec did not pin, deviations, tradeoffs, constraints found.

## 2026-07-03 12:15 Open-fork 1 resolved: STEP, not final auto sub-goal

Context: ROADMAP open-fork 1 (step inside `orchestrate.sh run` vs a final auto sub-goal the
decompose appends). Goal file: scaffold either way behind the SAME close contract; if final-auto-
sub-goal, REUSE the existing lifecycle + gate ledger, not a bespoke close engine.

Decision: **first-class STEP inside `cmd_run`**, replacing the `_next`-empty "done"-and-return
(orchestrate.sh:1153).

Why: the goal's `Done =` says the close "replaces today's 'done'-and-return" , that IS the
`_next`-empty terminal, which only a STEP can replace (a sub-goal cannot replace the loop's own
terminal). The mega-level no-orphan sweep needs the driver's whole-wave view (the megagoal dir +
repo), which a single sub-goal session does not naturally have. The "prefer reuse" constraint is
honored WITHOUT making it a sub-goal: the STEP reuses the existing `claude -p` dispatch seam
(`CLAUDE_CMD` + prompt-via-tempfile-on-stdin, same as `_run_one_session`) and the existing
`gate-ledger.sh` + `_emit_event` , it builds NO bespoke close engine. "Reuse the lifecycle + gate
ledger" ≠ "must be a sub-goal"; it means "don't hand-roll a parallel engine," and the STEP doesn't.

Impact: the close is the loop's terminal behaviour, always-on when all boxes are checked. Verified
safe: every existing `cmd_run` fixture stops at a `gate` sub-goal BEFORE the all-checked terminal,
so no existing test reaches the close (checked test-orchestrate.sh + test-orchestrate-wavefront.sh).

## 2026-07-03 12:15 Split: mechanical no-orphan in bash, judgment verifiers in a claude session

Context: the close "runs" four things (a) integration-verifier (b) review-team (c) advisor (d)
no-orphan. (a)-(c) are Claude-Code subagents; the driver is non-LLM bash.

Decision: (a)-(c) run inside ONE dispatched `claude -p` CLOSE session (mockable via `CLAUDE_CMD`),
whose prompt instructs it to run integration-verifier against the mega-goal OBJECTIVE + review-team
(security lens) + advisor (both modes) over the assembled wave and report a verdict. (d) the
no-orphan sweep is a MECHANICAL bash function in the driver.

Why: the mechanical sweep is deterministic, so it is unit-testable with a seeded orphan and no LLM
mock; keeping it in bash is what makes the seeded-orphan NEGATIVE CONTROL a real, cheap test. The
judgment verifiers cannot be faithfully faked in bash, so they ride the same delegate `claude -p`
seam the rest of the orchestrator already uses (no new machinery). This mirrors the kit's own split:
deterministic checks in the driver, judgement in the LLM session.

Order: run the cheap deterministic no-orphan sweep FIRST (fail-fast: a blocking orphan halts before
an LLM session is spent), THEN dispatch the verifier session, THEN HOLD the gate. The contract's
a-d list is WHAT the close runs, not a strict temporal order; "only after those pass does it hold"
is preserved (the gate holds only after BOTH the sweep and the session pass).

## 2026-07-03 12:15 No-orphan sweep scope (ponytail boundary)

The mechanical sweep targets the c6fbd99 orphan class concretely: a DISPATCHABLE **agent**
(`agents/<name>.md`, AGENTS ONLY , the exact c6fbd99 AC6 class) that has NO dispatch reference
anywhere else in the tree (defined + gated + rostered + documented but never DISPATCHED). It is NOT a
general dead-code detector for arbitrary bash symbols or CLI flags (over-built + unreliable); the
softer flag/step/path wiring is the close SESSION's integration-verifier's job (its judgment lens,
exactly as in c6fbd99). The seeded-orphan NC uses an added agent file no command references.

## 2026-07-03 12:25 spec-validate findings resolved

Adversarial spec-validate (5 lenses) returned REVISE with 2 BLOCKING + 3 SHOULD-FIX. All resolved in
the spec before code:
- BLOCKING objective source: `**Destination:**` exists only in the real mega ROADMAP, not in test
  fixtures (which use `# Mega-goal:`). Fix: extract Destination if present, ELSE the title line.
- BLOCKING regression: `test-model-routing.sh` SECTION 2 runs a single all-auto sub-goal to the
  `_next`-empty terminal (verified: `- [ ] SG-01 only auto , auto`, zero gates) , it DOES reach the
  close. Fix: `TIER4_CLOSE` default 1 with an opt-out; SECTION 2's `run_serial_case` sets
  `TIER4_CLOSE=0`; test-model-routing.sh + test-token-capture.sh added to the regression run.
- SHOULD-FIX corpus fallback: unresolvable git-root (mktemp megadir) -> skip the sweep with a WARN,
  never a false halt.
- SHOULD-FIX substring match: `advisor` false-matches `advisory` -> use whole-word `grep -w`.
- SHOULD-FIX agents-vs-commands scope drift: reconciled to AGENTS ONLY (above).
- NITs (held event vocab, "before gate" wording): folded into the spec Design.

## 2026-07-03 12:45 review-team findings (security + architecture): both SHIP

- SHOULD-FIX (arch) dry-run parity: `--dry-run` said nothing about the close firing at the terminal.
  FIXED , the dry-run plan now prints a one-line preview when `TIER4_CLOSE=1`.
- NIT (arch) rc=2 dead + mis-report: `_tier4_close` pre-guarded the corpus, so `_no_orphan_check`'s
  rc=2 ("no corpus") was unreachable via that path AND a would-be rc=2 would have fallen through to
  the "clean" message. FIXED , removed the duplicate outer guard; a `case` on rc 0/1/2 now lets the
  callee's return code drive the arm, so the contract is code-enforced.
- SHOULD-FIX (security) gated-final is driver-enforced but session-side prompt-only: the close
  dispatches its verifier session with the same full `CLAUDE_FLAGS` (`--dangerously-skip-permissions`)
  every delegate session uses, so the dispatched LLM *could* `git push`/`gh pr merge` itself despite
  the "Do NOT merge" instruction. HONEST DISCLOSURE, not silently fixed: (a) the DRIVER-level
  gated-final holds and is tested , `_tier4_close` and `cmd_run` call no merge/push on any path, the
  merge-recorder stays empty; (b) this is a pre-existing whole-file trust model (every `claude -p`
  dispatch already inherits full flags by design), not new to this diff; (c) both reviewers said SHIP
  and file it as a fast-follow. Deferred rather than jammed in as a fragile word-split `--disallowedTools`
  flag (the space-bearing tool patterns do not survive the file's word-split flag convention) or a
  default-inert config knob (ponytail: no knob that changes nothing). Fast-follow: a dedicated
  read-mostly permission posture for the close session (the verifier agents are all read-only).
