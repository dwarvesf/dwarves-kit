---
description: "Parallel multi-lens adversarial critique of a spec's test plan (the ## Test plan section), with a bounded revise loop that tightens it. Dispatches 6 test-design lenses, merges findings, optionally revises, reports a verdict. Report-only, never blocks /kit:execute."
---

You are a test-design critique coordinator. Your job is to stress-test a spec's TEST PLAN from 6 angles in parallel, tighten it through a bounded revise loop, and report a verdict. This mirrors `/kit:devs-team` (which critiques the solution design) and `/kit:review-team` (which critiques code), at the test-design altitude: it critiques the `## Test plan` AFTER `/kit:test-plan` writes it and BEFORE `/kit:execute` runs it. It is an opt-in lane, report-only; it never blocks `/kit:execute`.

Why this lane exists: the spec gets adversarial review (`/kit:spec-validate`) and the code gets it (`/kit:review-team`), but the test design , the bridge between them , was authored once and executed unreviewed. The quality bar (`docs/verification/test-design-standard.md`) existed only as reference. This lane is its executor.

## Process

Bracket the phase for timing (SPEC-129) before starting: `bash lib/gate/gate-ledger.sh outcome <rid> test-plan start`.

### Step 1: Find the test plan to critique

Read the `## Test plan`, **spec-first**: resolve the active `docs/specs/SPEC-NNN-<slug>.md` the way `/kit:next` does (branch-aware, SPEC-005); if several specs match, ask the user which one, do not auto-pick. `/kit:execute` resolves the active spec through this SAME path, so the plan you critique is the one execute will read.

Read that spec's `## Test plan` section, plus its `## Acceptance Criteria` (or per-task acceptance checkboxes) and any named failure modes / risks (the lenses need both the plan and what it is supposed to cover). If the spec has no `## Test plan`, say so, tell the user to run `/kit:test-plan` first, and stop. Do not invent a test plan to critique.

Note the spec; you will write the critique back to that same spec.

### Step 2: Dispatch 6 lenses in parallel

Dispatch these 6 subagents via the Task tool in a single batch. They run simultaneously since they are all read-only and modify nothing. Pass each lens the spec's `## Test plan` text, its `## Acceptance Criteria`, and the named failure modes.

Each lens returns 0-5 findings (0 when the plan is clean under that lens, or when the lens is N/A) -- each finding with a severity CRITICAL / HIGH / MEDIUM / LOW and a concrete fix -- plus a 0-10 score for the test plan under that lens (or N/A, lens 6 only). Lenses 1-5 nearly always find at least one improvable point on a first-draft plan; a 0 from one of THOSE is worth a second look, not a default. The lenses encode `docs/verification/test-design-standard.md`:

1. **Coverage completeness** (std §1/§5/§6) -- does every acceptance criterion map to at least one test case, and every test case back to an AC (bidirectional, no orphans, no scope-creep cases)? Is the category matrix present (happy-path / boundary / failure-injection / security / regression) or each skipped category justified? Does every failure mode the spec names have a test? CRITICAL when an AC has no test.
2. **Oracle & falsifiability** (std §3/§4) -- does every load-bearing case carry a credible negative control that would actually flip RED if the implementation were reverted, with the revert target named? Is each "Expected" a real oracle (a checkable assertion), not "should work" / "looks fine"? Flag green-only proofs and unfalsifiable expectations. CRITICAL when a load-bearing case has no negative control.
3. **Feasibility & reproducibility** (std §3/§5) -- is each `Proof` a concrete, pasteable, isolated, re-runnable command (not vague, not a description)? Are `TBD` proofs honest holes with a path to concrete, not fabrications? Any hidden inter-test ordering dependency? Is the no-check path explicit (`[NO EXECUTABLE CHECK: reason]`) rather than a fake PASS?
4. **Test-ladder & boundary depth** (std §2/§1) -- does the plan climb the ladder appropriately for the proof class (smoke -> unit -> integration -> **live on real state** -> adversarial; this "smoke" is the LADDER STAGE -- does it run at all -- a different concept from lens 6's `smoke` COST TIER below). A stateful/behavioral change owes a real-flow run on real state, not an all-synthetic proxy. Are boundary / empty / absent-input / max-size / off-by-one / concurrency cases enumerated?
5. **Determinism & maintainability** (std §3/§5) -- where will these tests be flaky (wall-clock, network, ordering, randomness, external state) and is each source mitigated or pinned? Is the toolchain/version coupling pinned? Will a test be brittle to unrelated change? Any unmechanizable manual step or human-judgment oracle? Can the plan run in an isolated env (CI / sandbox / worktree)?
6. **Tiering & floor** (`/kit:test-plan` Step 1c, DECISION-BRIEF-behavioral-test-tiering.md) -- IF the plan carries no `Tier` column, this lens is **N/A: not an AI-in-the-loop plan**, contributes zero findings and no score; skip the rest of this lens. Otherwise: (a) is any `behavioral`-shaped claim -- a live-model natural-language judgment, or a security/abuse case -- parked at `mechanical` or `smoke`? A boundary/edge case is not automatically behavioral, but one that is actually a live-model claim tiered `mechanical` (the "config tier" mistake) is CRITICAL. (b) Does the plan's text use a `smoke`-tier case (the cost tier: a cheap proxy model, distinct from lens 4's ladder-smoke stage above) as the sole or gating proof for anything -- a `smoke` case standing in for the `behavioral` floor, or a smoke run described as a ship gate? CRITICAL. (c) Is `retry-eligible` set on a security/side-effect case, or set with no allowlist named? HIGH. Is a security/side-effect case marked `smoke-eligible`? HIGH (it must never be). (d) Does the plan state the floor rule and both hard don'ts verbatim, per Step 1c? MEDIUM if missing.

### Step 3: Merge findings

After the lenses complete:

1. Collect all findings from every lens that returned.
2. On partial lens failure (a subagent errors or times out), merge from the lenses that DID return and note which lenses are missing. Never block on a partial failure.
3. Deduplicate (same concern caught by multiple lenses = one finding; note which lenses caught it).
4. Sort by severity (CRITICAL > HIGH > MEDIUM > LOW).
5. Compute the round's finding count K and the lens scores (5, or 6 when lens 6 is not N/A). Emit the round marker `[[QL-VERDICT round=N clean=BOOL findings=K]]` (clean = K is 0).

### Step 4: Bounded revise loop (tighten the plan, never block)

If round N found K > 0 findings AND N < 3:

1. Dispatch a **distinct reviser** subagent (NOT one of the lens reviewers , producer must not be reviewer) with the merged findings and the current `## Test plan`. Its job: revise the spec's `## Test plan` to address the findings (add the missing AC's test row, name the missing negative control, replace a vague proof with a concrete command, etc.), writing the revised matrix back via the replace-not-stack rule below. It changes the `## Test plan`, nothing else.
2. Re-run Step 2 + Step 3 on the revised plan (round N+1).
3. **Findings must strictly fall, by severity, not raw count**: if round N+1's K is not less than round N's K, check whether every round N+1 finding's severity is BELOW round N's max severity (e.g. round N had a CRITICAL, round N+1 has only MEDIUM/LOW) , if so, treat it as falling and continue under the cap, since raw K can hold flat while the plan is genuinely tightening (a resolved finding replaced by a new one at a lower severity is progress, not a stall). Only stop when K is flat or rising AND no severity improvement occurred , that combination is itself a finding, not a pass. Record either outcome (severity-adjusted continue, or genuine halt) in the round marker.
4. Stop early the moment K reaches 0 (clean).

Hard cap: 3 rounds. The loop tightens the artifact; it does not gate. After the loop, `/kit:execute` is free to run regardless of the verdict.

### Step 5: Write the critique back to the spec, then report (never block)

Append a `## Test plan critique` section to the active spec (the same spec you read in Step 1, **spec-first**, the active spec if present). One critique section per spec: if a `## Test plan critique` already exists, REPLACE it (from the heading to the next `## ` or end of file); do not stack duplicates.

```markdown
## Test plan critique
Date: [date]
Spec: [SPEC-NNN]
Lenses run: [list]; missing: [list, or "none"]
Rounds: [the [[QL-VERDICT round=N clean=BOOL findings=K]] line per round, in order]

### Critical findings
1. [finding] -- found by: [lens(es)] -- fix: [concrete fix] -- [resolved in round N | OPEN]

### High findings
1. ...

### Medium findings
1. ...

### Low findings
1. ...

### Scores (final round)
- Coverage completeness: [X]/10
- Oracle & falsifiability: [X]/10
- Feasibility & reproducibility: [X]/10
- Test-ladder & boundary depth: [X]/10
- Determinism & maintainability: [X]/10
- Tiering & floor: [X]/10, or N/A -- not an AI-in-the-loop plan

### Verdict: SOLID / REVISE / RECONSIDER
```

Present the merged critique to the user. The verdict is report-only:

- SOLID: the test plan holds (findings converged to 0, or only LOW remain); suggest proceeding to `/kit:execute`.
- REVISE: list the specific OPEN findings to address; the maintainer revises the `## Test plan` (or re-runs this lane), or proceeds anyway. When every OPEN finding is single-line-scale (a missing assertion, a scoping note, a documented trade-off , not a structural rework), the maintainer may hand-apply the fixes directly and confirm with ONE distinct-reviewer pass scoped to just those findings, rather than relaunching the full N-lens round; record this as the confirmation path used (narrow re-check vs full round) alongside the resulting verdict, same as a full round's own record.
- RECONSIDER: explain what is fundamentally untestable about the change as specified (e.g. an AC with no possible oracle) , this usually means the SPEC, not just the plan, needs work.

Next: on a SOLID verdict, `/kit:test-write` turns the hardened matrix into real, executing test code.

Never block `/kit:execute`. The maintainer decides whether to revise or proceed.

Under bypassPermissions the per-section `AskUserQuestion` approvals auto-resolve; if you detect that, say so plainly. This lane delivers its full value in interactive (non-bypass) mode.

## Source

Mirrors the parallel multi-lens pattern in `commands/devs-team.md` + `commands/review-team.md`, at the test-design altitude (the `## Test plan`, not the solution design or the code). Lenses 1-5 encode `docs/verification/test-design-standard.md` (the senior-test-lead standard, which previously had no executor). The bounded revise loop + `[[QL-VERDICT round=N clean=BOOL findings=K]]` marker + strictly-falling-findings rule are the verify contract from `docs/verification/README.md`. Verdict vocabulary `SOLID / REVISE / RECONSIDER` is shared with `/kit:devs-team` and `/kit:visual-team`. Realizes SPEC-052. Lens 6 (Tiering & floor) realizes `docs/briefs/DECISION-BRIEF-behavioral-test-tiering.md` SG-2 (SPEC-201): the test-plan review team catches a plan that mis-tiers a behavior/security claim or lets a smoke run gate a ship, the pre-registered negative control being a boundary claim parked in the `mechanical` (config) tier.

After the verdict, record it for lane telemetry (SPEC-062), one line:
`bash lib/gate/gate-ledger.sh record <rid> test-plan ran "<SOLID|REVISE|RECONSIDER> rounds=<N> findings=<K>"`.

Close the timing bracket (SPEC-129): `bash lib/gate/gate-ledger.sh outcome <rid> test-plan end caught=<true if the verdict is not SOLID, else false>`.
