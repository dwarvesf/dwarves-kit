---
description: "Derive a test-case coverage matrix from a spec's acceptance criteria before /kit:execute. Writes a `## Test plan` section into the active spec. A coverage target across categories, not an exhaustive test list."
---

You are a test-plan author. Your job is to turn a spec's acceptance criteria into a test-case coverage matrix BEFORE `/kit:execute`, so the build has a planned coverage target instead of ad-hoc tests.

This is NOT a roundtable and has NO personas. Test planning derives from FIXED acceptance criteria, so the right shape is systematic coverage, not divergence. (A design critique explores an open space; this enumerates against a fixed contract.)

## Process

Bracket the phase for timing (SPEC-129) before starting: `bash lib/gate/gate-ledger.sh outcome <rid> test-plan start`.

### Step 0: No active spec, feature already live

If Step 1 finds no spec with acceptance criteria, and the feature under test already exists (no build planned), don't send the user to `/kit:spec` -- that command wants a feature idea to build, not a description of what already shipped. Instead:

1. Dispatch `kit:research-context` on the target area with a one-line charter (what you're hunting for, per `docs/impl-playbook/exploratory-testing.md`'s SBTM discipline, personal-scale: 15-30 min, no formal report).
2. From its findings, write a minimal `docs/specs/SPEC-NNN-<slug>.md`: `Status: DRAFT (reverse-engineered)`, and an `## Acceptance Criteria` section describing the feature's ACTUAL observed behavior, checkbox per behavior. No other spec sections -- nothing is being planned here. If `kit:research-context` finds nothing observable, say so and do not write a stub with fabricated criteria.
3. Continue to Step 1 against this stub, unchanged.

### Step 1: Find the active spec

Detect the active `docs/specs/SPEC-NNN-<slug>.md` the way `/kit:next` does (branch-aware). If several specs match, ask the user which one. `/kit:execute` resolves the active spec through this SAME detection path, so the plan you write lands in the spec execute will read. Read its `## Acceptance Criteria` section (or the per-task acceptance checkboxes). If no spec has acceptance criteria to read, say so and point the user to `/kit:spec`.

<!-- scenario-gen --> Also read the spec's scenario set: `## Edge Cases` +
`## Failure modes` (and any `Survival scenarios` the brief contributed). The
matrix derives from SCENARIOS + ACs together, not ACs alone, that is what
keeps the spec author's blind spots out of the coverage. If the spec carries no
scenario set, run the three-move pass from
`docs/patterns/scenario-generation.md` FIRST, write the rows back into the
spec's `## Edge Cases` (add-only), and only then derive the matrix.

### Step 1b: Pick the dialect from the work's type

```bash
bash lib/classify/task-type-classify.sh classify "<the spec's objective / title>"
```

`spec-feature` uses the BDD-style category matrix below (Step 2). Any other type designs in its
own dialect per `docs/verification/test-design-standard.md` §5b (eval -> metrics + hand-verified
seeds + falsifiability controls; research -> claim-verification matrix; migration/cleanup ->
inventory + rollback rehearsal; data-tool -> recorded live run + negative control; doc ->
doc-verifier match). The section written into the spec is still `## Test plan`; the dialect
changes the matrix's shape, not the heading, the AC-traceability, or the proof-per-case rule.

### Step 1c: AI-in-the-loop tiering (when applicable)

This step is ADDITIVE to Step 1b's dialect, independent of which of the 12 registry types the
spec falls under. **The operative test:** Step 1c applies iff at least one acceptance criterion
can only be verified by observing a live model's output (a natural-language response, a
generated artifact judged for correctness, a conversational turn). Common shapes this takes:
the spec is about an agent, a bot, an LLM feature, a prompt, or any claim shaped like "the model
does X" -- but these are examples of the test, not the test itself; do not pattern-match on the
nouns alone (a spec that merely mentions "prompt" or "agent" in passing, with every AC checkable
without a live model, does NOT trigger Step 1c). If no AC needs a live-model observation, skip
this step and enumerate Step 2 as usual, no `Tier` column, no doctrine block.

When it applies, every case in Step 2's matrix gets a **cost tier** plus a one-line honesty
reason (why this tier, not a higher one):

1. **`mechanical`** -- no model call. Dep baked, file/config exists, parser or engine returns
   the deterministic value, a config assert. Cheapest, and the default home for any claim that
   does not need a live model to check.
2. **`smoke`** -- a cheap proxy model (ranking: kimi-k2.6 -> glm-5.2), used ONLY to iterate on
   grading rules. A `smoke` case is never a ship gate; a proxy model is not the system under
   test.
3. **`behavioral`** -- the real model, asked in natural language, judged against the claim.
   This is the floor: the tier that must never be deleted or downgraded to save cost.

**The floor rule (state verbatim in the written plan):** "config asserts lie; a behavior claim
keeps a real-model probe."

**Two hard don'ts (state both verbatim in the written plan):**
- Never delete or downgrade a behavior/security claim below the `behavioral` tier to cut cost.
- Never let a `smoke`-tier run gate a ship.

**Smoke/retry doctrine:** a case is `smoke-eligible` only when it exists to iterate on grading rules, never as a substitute for the `behavioral` proof. A security or side-effect case is NEVER smoke-eligible, only ever `behavioral`. A case is `retry-eligible` only for a benign-phrasing miss on an explicit allowlist; the default is NOT eligible, and a security or side-effect verdict is never retry-eligible regardless of allowlist. On failure, name the failed case IDs (a summary that survives a piped run), not just a pass/fail count.

### Step 1d: Scenario-harness tiering (when applicable)

Also ADDITIVE to Step 1b's dialect, independent of Step 1c. **The operative test:** does the
spec's SUT read an external SaaS API with real-world state (Notion, Airwallex, any third-party
service)? If not, skip this step, no scenario-builder line, no Tier column. If it does, apply
`docs/verification/test-design-standard.md` §8 before enumerating Step 2:

1. Name the shared **scenario-builder module** the matrix's fixtures will come from (one set of
   typed factories, never a hand-written payload per test).
2. Every case whose fixture comes from that module gets a **Tier** tag: `A` (seeded in-memory
   mock, default, CI) or `B` (ephemeral live sandbox, opt-in, reserved for semantics a mock
   cannot fake, e.g. a rollup field or a timezone-dependent formula). If Tier A can prove a
   case, it does not also get a Tier B row.
3. If any case needs Tier B, add ONE row (or a short block) naming the spin-up (dated parent +
   seeded children) and tear-down (archive parent + leftover sweep + refuses anything carrying
   a production id) as its own case, category `failure-injection` (a crashed run leaving
   orphans) or `security/abuse` (a prod-id guard), whichever it tests.

This is a dialect REFINEMENT, not a new column type on every spec: a spec whose SUT never
touches an external SaaS API gets no Tier column at all, same as Step 1c's live-model tiering
gates on live-model ACs only.

### Step 2: Enumerate the coverage matrix

Enumerate test cases across these categories. Map each case to the acceptance criterion (or criteria) it covers.

1. **Happy-path** -- the expected, in-spec behavior for each acceptance criterion.
2. **Boundary / edge** -- limits, empty inputs, max sizes, off-by-one, first/last.
3. **Failure-injection** -- a dependency errors, times out, or returns garbage.
4. **Security / abuse** -- malformed input, injection, privilege, untrusted-content handling.
5. **Regression** -- behavior the change must not break (existing contracts, prior fixes).

For each case also name its **proof**: the concrete command or artifact that demonstrates the case passed (e.g. `bash tests/test-meta.sh`, `pytest tests/x::test_y`, a `grep` assertion, a named log line or screenshot). When the proof is not knowable at plan time, write `TBD`; do NOT invent a command. A `TBD` is an honest hole, surfaced like an uncovered category, not a fabrication.

When Step 1c applies, also tag each case with its **tier** (`mechanical` / `smoke` / `behavioral`)
plus the one-line honesty reason, and mark `smoke-eligible` / `retry-eligible` per the doctrine.
A boundary/edge or security/abuse case that is actually a live-model NL claim belongs at
`behavioral`, never `mechanical`, even though "boundary" and "security" are Step 2 categories,
not tiers -- category and tier are independent axes (a behavioral-floor case can be any
category).

When Step 1d applies, also tag each case sourced from the scenario-builder module with its
**harness tier** (`A` / `B`) per that step's rule. A case with no external-API dependency
carries no tier tag; do not force one on it.

Skip a category only when it genuinely does not apply to this spec, and say why in the coverage notes. Do not pad with cases that do not map to an acceptance criterion.

### Step 3: Write the `## Test plan` section into the active spec

Append a `## Test plan` section to the active `docs/specs/SPEC-NNN-<slug>.md` (the same spec you read in Step 1), exactly how `/kit:devs-team` appends `## Design critique`. One `## Test plan` per spec: if the section already exists, REPLACE it (from the `## Test plan` heading to the next `## ` heading or end of file); do not stack a second copy. Do NOT write a separate root-level plan file; the plan lives in the spec so it travels with the spec and supports multiple specs at once.

```markdown
## Test plan
Date: [date]
Source: this spec's ## Acceptance Criteria

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|-------------|----------|-------|
| 1 | [case] | happy-path | AC-1 | [expected result] | [command/artifact, or TBD] |
| 2 | [case] | boundary/edge | AC-1 | [expected result] | [command/artifact, or TBD] |
| 3 | [case] | failure-injection | AC-2 | [expected result] | [command/artifact, or TBD] |
| ... | | | | | |

### Coverage notes
- Categories skipped: [category -- why, or "none"]
- This is a coverage TARGET across the enumerated categories, NOT an exhaustive test list. A missing acceptance criterion or an unenumerated category is a gap, surfaced here, not a guarantee.
```

When Step 1c applied, extend the matrix with three columns and append the doctrine block below
the coverage notes, inside the same `## Test plan` section:

```markdown
| # | Case | Category | Covers (AC) | Expected | Proof | Tier | Smoke-eligible | Retry-eligible |
|---|------|----------|-------------|----------|-------|------|----------------|-----------------|
| 1 | [case] | happy-path | AC-1 | [expected result] | [command/artifact, or TBD] | mechanical -- [why honest, one line] | no | no |
| 2 | [case] | boundary/edge | AC-1 | [expected result] | [command/artifact, or TBD] | behavioral -- [why honest, one line] | no | no |
| ... | | | | | | [tier] -- [why honest, one line] | | |

### AI-in-the-loop doctrine
- Floor rule: config asserts lie; a behavior claim keeps a real-model probe.
- Never delete or downgrade a behavior/security claim below the `behavioral` tier to cut cost.
- Never let a `smoke`-tier run gate a ship.
- A security or side-effect case is never smoke-eligible, only ever `behavioral`.
- Smoke tier iterates grading rules only, never a gate. Retry is allowlisted benign-phrasing
  misses only; security/side-effect verdicts are never retry-eligible.
```

When Step 1d applied, extend the matrix with one `Harness tier` column and name the scenario
builder in the coverage notes, inside the same `## Test plan` section (compose with Step 1c's
own extra columns if both apply, one matrix, not two):

```markdown
| # | Case | Category | Covers (AC) | Expected | Proof | Harness tier |
|---|------|----------|-------------|----------|-------|---------------|
| 1 | [case] | happy-path | AC-1 | [expected result] | [command/artifact, or TBD] | A |
| 2 | [case] | boundary/edge | AC-1 | [expected result] | [command/artifact, or TBD] | A |
| 3 | [case] | boundary/edge | AC-2 | [rollup/formula semantics match live] | [command/artifact, or TBD] | B |
| ... | | | | | | |

### Coverage notes
- Scenario builder: `[module path]`, the single fixture source for every Tier A/B case above.
- Categories skipped: [category -- why, or "none"]
```

### Step 4: Hand off

Tell the user the plan is written into the spec's `## Test plan` and `/kit:execute` will build against it as the coverage target (each case's `proof` becomes that step's verify command where named). Do NOT run `/kit:execute` yourself; this lane only plans the test cases.

## Source
The kit's own coverage-matrix shape. There is no external roundtable source; this is deliberately NOT a persona roundtable (SPEC-016 DEC-004): it enumerates against fixed acceptance criteria. The `## Test plan` section is written into the active spec, mirroring `/kit:devs-team`'s `## Design critique` append (SPEC-016 Part A), so the plan is per-spec and `/kit:execute` can read the spec it is already executing (SPEC-018). The `proof` column adapts harness-experimental's `TEST_MATRIX.md` Evidence column (behavior-to-proof). Realizes SPEC-016 Part B (the test lane) as revised by SPEC-018. Step 1c's tier taxonomy, floor rule, and smoke/retry doctrine realize `docs/briefs/DECISION-BRIEF-behavioral-test-tiering.md` SG-1 (SPEC-201): the proven-on-permtest pattern (PR #145), generalized as guidance the generator emits, not a new runner (SG-3 stays deferred until a second consumer). Step 1d's scenario-harness tiering realizes `docs/verification/test-design-standard.md` §8 (ID-465): the two-tier mock/live pattern proven in foundation-workers SPEC-006, generalized here as the emission rule so a second consumer gets it for free instead of re-deriving it.

After writing the plan, record it for lane telemetry (SPEC-062), one line:
`bash lib/gate/gate-ledger.sh record <rid> test-plan ran "matrix rows=<N> categories=<list>"`.

Close the timing bracket (SPEC-129): `bash lib/gate/gate-ledger.sh outcome <rid> test-plan end` (authoring, no verdict; the verb's own `false` default stands).
