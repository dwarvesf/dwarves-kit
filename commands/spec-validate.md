---
description: "Adversarial review of a spec before implementation. 6 specialist lenses attack the spec from different angles (5 advisory, 1 blocking on the design record)."
---

You are running an adversarial spec review. Read the spec from `docs/specs/SPEC-NNN-<slug>.md` (the most recent non-shipped spec if several exist). If no spec exists, tell the user to run `/kit:spec` first.

## The 6 reviewers

Bracket both phases this lane owns for timing (SPEC-129), before running Reviewer 1:
`bash lib/gate/gate-ledger.sh outcome <rid> Validate start` and
`bash lib/gate/gate-ledger.sh outcome <rid> design-record start`.

Run each reviewer sequentially. For each one, present findings and ask the user if they want to address the issues before moving to the next reviewer. Reviewers 1-5 are advisory; Reviewer 6 (below) is the one exception that can block the `VALIDATED` flip.

### Reviewer 1: Security Auditor
Look for:
- Auth/authz gaps (who can access what? are there unprotected endpoints?)
- Input validation missing (SQL injection, XSS, path traversal)
- Secrets handling (hardcoded keys, unencrypted storage)
- Data exposure (PII in logs, verbose error messages)
- Dependency risks (known vulnerable packages)

### Reviewer 2: Failure Mode Analyst
Look for:
- What happens when external services are down?
- What happens with concurrent access / race conditions?
- What happens with malformed or unexpected input?
- What happens at 10x expected load?
- What's the recovery path for each failure?
- Are there any single points of failure?
- If the spec has a `## Failure modes` table, check each class is real and has both a detection signal and a mitigation; flag missing or hand-waved entries.

### Reviewer 3: Assumption Destroyer
Look for:
- Unstated assumptions about user behavior
- Assumptions about data quality or format
- Assumptions about infrastructure availability
- Assumptions about third-party API stability
- "Happy path only" designs with no error handling
- Implicit ordering dependencies between tasks

### Reviewer 4: Scope Critic
Look for:
- **Aggressive atomicity check (critical)**: Each task must fit in ~50% of a fresh context window (~100k tokens). Heuristic: if a task touches more than 5 files, or its description needs more than 3 sentences, or its acceptance criteria has more than 5 bullet points, it's too large. Flag it and suggest splitting. Source: GSD's "each plan is maximum 3 tasks, each fits in 50% context" principle.
- Tasks that bundle unrelated changes (e.g., "set up auth AND create user dashboard" is two tasks)
- Features disguised as requirements (nice-to-have dressed up as must-have)
- Gold-plating (things that sound important but aren't needed for v1)
- Missing tasks (gaps between spec and acceptance criteria: does completing all tasks actually satisfy the global acceptance criteria?)
- Unclear acceptance criteria (not testable: "should be fast" is not testable, "response under 200ms at p95" is)
- Missing dependency declarations (Task B clearly depends on Task A's output but doesn't say so)
- **Autonomy gate (ID-036 / SPEC-084)**: if the spec's behavior runs inside an autonomous loop (`/kit:execute` pipeline, `/goal`), check it does not let the loop make a scope / architecture / risk decision without a human gate; flag any loop-reachable decision point with no stop.
- **Picture presence (mechanical, ID-454)**: on a `full`-lane spec, `## Picture` must be present and non-empty: an ASCII/box-drawing diagram, or, for a UI-shaped spec, a pointer to a `/kit:prototype` run (`prototype/<name>` + the variant to look at). A missing or empty `## Picture` on a full-lane spec is a finding. Below full lane, presence is encouraged only; do not flag its absence.
- **Picture agrees with the task list (lens question, ID-454)**: read the picture (or the prototype it points at) against `## Task Breakdown`. Every piece the picture draws should get touched by some task, and every task that adds a new piece should show up in the picture. Flag drift either direction.

### Reviewer 5: Solution-Design & Extensibility Critic
Look for:
- Is the chosen approach the simplest design that satisfies the requirements, or is it over- or under-engineered for what the problem needs?
- Are the 2-3 alternatives real and distinct, or strawmen? Are the tradeoffs honest?
- Coupling & boundaries: does each unit have one clear purpose and a defined interface? Can internals change without breaking consumers? A unit that can't be described without reading its internals has a boundary problem.
- Extensibility: does the design state what changes when the load-bearing dimension grows, and is that claim grounded or hand-waved? Flag "it scales" with no mechanism.
- Is there a materially lower-coupling or more extensible design the spec didn't consider?
- If the spec has an `### Interfaces (I/O contract)`, check inputs/outputs/invariants are concrete (named shapes, not "data in / data out").

**Calibration (critical):** only flag issues that would produce a flawed implementation or a design that cannot evolve. Do NOT flag stylistic preferences, "this section could be longer", or theoretical extensibility nobody asked for (YAGNI). Approve unless there is a real design weakness. If a spec predates this template (no `Approaches considered` section), raise the absent structure as ONE advisory recommendation, not a per-point critical flag; do not storm legacy or downstream specs.

Source: forked from superpowers:brainstorming ("design for isolation and clarity") + its spec-document-reviewer calibration. See docs/specs/SPEC-008.

### Reviewer 6: Design Record Auditor (ADR-0031 §1, BLOCKING)
Unlike Reviewers 1-5 above (all advisory), this check can REFUSE the `VALIDATED` flip.

1. **Decide design-bearing.** Is the spec above the tiny lane AND does it do any of: introduce
   a new component/module, non-obvious control flow, a schema/data-model change, an external
   integration, an irreversible choice, or offer 2+ viable approaches?
2. **If design-bearing:** the spec's `## Design` section must be non-empty and contain a
   diagram (mermaid preferred) picked by fit (sequence / state / ER / flowchart / C4-lite) plus
   a chosen approach. A missing `## Design` section, an empty one, or a bare `obvious: <why>`
   collapse on a spec that genuinely IS design-bearing is a **CRITICAL, BLOCKING** finding: do
   NOT flip Status to `VALIDATED`. List it under Critical Issues and stop; the author fills the
   block and re-runs this reviewer.
3. **If NOT design-bearing** (an obvious/tiny-shaped change): the `## Design` section
   correctly collapsing to `obvious: <why>` is a PASS , do not require a diagram. If the spec
   still carries a heavy Design block for genuinely obvious work, flag it as a PROPORTIONALITY
   warning (compliance theater), non-blocking.
4. **Legacy grace.** A spec written before this template existed (no `## Design` heading at
   all) and judged NOT design-bearing is not penalized for the section's absence, mirroring
   Reviewer 5's legacy-grace clause.

**Calibration (critical):** this is the ONE reviewer whose finding can withhold `VALIDATED`.
Keep the design-bearing test honest in both directions , neither rubber-stamping a real
architecture change as `obvious`, nor demanding a diagram for a one-line config tweak.

## Output format

After all 6 reviewers complete, produce a summary:

```markdown
# Spec Validation Report
Date: [date]
Spec: [spec name]

## Critical Issues (must fix before implementation)
1. [issue] — [which reviewer found it] — [suggested fix]

## Warnings (address before shipping)
1. [issue] — [which reviewer] — [suggested fix]

## Passed
- [things that look solid]

## Verdict: APPROVED / NEEDS REVISION
```

If NEEDS REVISION, update `docs/specs/SPEC-NNN-<slug>.md` with the fixes and mark the Decision Log with entries for each change made.

If APPROVED, update the Status line in SPEC.md to `VALIDATED`. **Exception (ADR-0031 §1):** if Reviewer 6 raised a CRITICAL, BLOCKING finding (a design-bearing spec with an empty/missing `## Design` block), the Verdict is NEEDS REVISION regardless of Reviewers 1-5's outcome, and Status does NOT flip to `VALIDATED` until the Design block is filled and this reviewer re-runs clean.

After the verdict, record it for lane telemetry (SPEC-139), one line:
`bash lib/gate/gate-ledger.sh record <rid> Validate ran "<APPROVED|NEEDS REVISION> critical=<N> warnings=<K>"`.
Close its timing bracket (SPEC-129): `bash lib/gate/gate-ledger.sh outcome <rid> Validate end caught=<true if the verdict is NEEDS REVISION, else false>`.

Reviewer 6 is also the `design-record` matrix row's phase owner (it is the one enforcement point
for that row, per WORKFLOW.md "## The understanding axis"), so record it by its own name too:
`bash lib/gate/gate-ledger.sh record <rid> design-record ran "design-bearing=<yes|no> <pass|critical>"`.
This closes the "no command records design-record ran" gap WORKFLOW.md's "## Command emit
coverage" section used to flag as a known pre-existing gap. Close its timing bracket (SPEC-129):
`bash lib/gate/gate-ledger.sh outcome <rid> design-record end caught=<true if the row is critical, else false>`.
