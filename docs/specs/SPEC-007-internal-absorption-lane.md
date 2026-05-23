# Spec: Internal absorption lane (Han's own dev-workflow skills/hooks)

Generated: 2026-05-20
Status: PARKED (2026-05-20; revisit later, see Parked note)
Source: maintainer braindump 2026-05-20 (item e), split from SPEC-004 during its 2026-05-20 validation (SPEC-004 DEC-009). Backlog: ID-002.
Prior spec: docs/specs/SPEC-004-absorption-cadence.md
Depends on: SPEC-004 (the absorption ritual `docs/ABSORPTION.md`, the `docs/absorption/` proposal artifact, the `/user:absorb` command, and the inline adoption rubric, all of which this lane extends).
Validation: ran 2026-05-20 (4 reviewers); verdict NEEDS REVISION; resolution = PARKED (maintainer decision 2026-05-20: "skip for now, hold the problems and goals, revert soon"). NOT validated, NOT for execution until revisited.

## Parked: revisit later (the problems + goals are held here)

This spec is parked, not dissolved. The braindump's item e (absorbing Han's own dev-workflow skills/hooks) and its goals are kept here intact for a future revisit. The 4-reviewer validation surfaced blockers that make it not worth shipping as-is; record them so the revisit starts informed.

**Why parked (validation blockers, all verified against the filesystem 2026-05-20):**
1. **Redundant: both near-term survivors are already SPEC-006's.** `goal-craft` is SPEC-006's `/user:assign` activator; `session-closer-hook` is SPEC-006's deferred doc-update-clause-to-hook promotion. Net new yield from a standalone lane is ~0.
2. **Contradicts validated SPEC-006.** SPEC-006 makes `/user:assign` activator-agnostic and puts "reimplementing goal-crafting" out of scope (goal-craft is a *detected external activator*, not absorbed). SPEC-007's "fold goal-craft into a kit-owned `/user:assign`" reverses that. Keep SPEC-006's design; do NOT absorb goal-craft.
3. **The soak proxy is broken.** `~/.claude/skills/` is not a git repo, so `git log --reverse` yields no first-commit date for most candidates; and commit-age proves authorship, not battle-testing. A revisit must use a **usage signal** (e.g. the candidate being wired into a live `settings.json`), not commit-age.
4. **Mis-scoped ownership.** `content-spec`, `prompt-improver`, `knowledge-capture` are symlinks into the `dwarvesf/claude-skills` *team* repo, so they belong to the EXTERNAL lane (SPEC-004), not the internal one. A revisit needs an ownership check (resolve symlink -> check remote -> route to the correct lane) before scoring.
5. **`--internal` is speculative.** The internal pool is finite/near-static; a recurring command mode has no recurring consumer. A one-time inventory + the doctrine is the real deliverable.

**The one durable nugget to keep (the goal of any revisit):** the *in-house-lineage doctrine*: how an in-house invention earns kit entry (PHILOSOPHY §1 indirect-lineage carve-out + §5 soak measured by a **usage** signal). When revived, the cleanest home is likely a section in SPEC-004's `docs/ABSORPTION.md` rather than a standalone spec.

**The honest item-e conclusion (held for the revisit):** a careful gate absorbs almost nothing net-new. Review/testing are already covered by the kit's moat; goal-craft is already integrated by the spine; session-closer is the deferred hook. The *value of item e* is this audit + the doctrine, not a pile of absorptions. The scored inventory below is the audit record; treat its verdicts as provisional (description-level, not deep reads).

ID-002 stays `parked` in `_meta/BACKLOG.md` until this is revisited.

## Problem

Item e: Han develops skills and hooks while working across his personal repos (`ops-toolkit`, `~/.claude/skills/`, `dwarvesf/claude-skills`). Some encode generic Claude-Code / SDD-workflow discipline that could strengthen dwarves-kit. There is no defined lane to ask "should one of my own dev-workflow inventions become a kit component?" and no gate that answers it selectively.

This lane has a tension SPEC-004's external lane does not: a component Han wrote is **originated in-house**, so it appears to violate "Synthesize, don't originate," which demands an external proven source. SPEC-004 split this lane out (DEC-009) precisely so it could be **grounded in real, enumerated candidates** rather than shipped as abstract machinery, and so the lineage tension could be resolved concretely.

Two failure modes bound this spec:
- **Too narrow**: the literal `ops-toolkit` repo yields only 2 generic candidates; reading item e that narrowly makes it nearly empty.
- **Too wide**: pulling in every generic skill Han has written turns the kit into a junk drawer (the "vendor-skill sprawl" the reject-list names first). The maintainer's directive (2026-05-20) is explicit: *plan carefully, absorb only what benefits the workflow, especially planning, review, and testing.*

So this spec is mostly a **gate + a scored inventory + a handful of survivors**, not a new engine.

## Decision: chosen version

**Extend SPEC-004's absorption mechanism with an internal lane: a `## The internal lane` section in `docs/ABSORPTION.md` (resolving the in-house lineage tension), a `--internal` mode on `/user:absorb` that scores Han's own dev-workflow skills/hooks against a relevance-filtered gate, and a one-time scored inventory (the centerpiece) whose ADOPT/ADAPT survivors become backlog items absorbed through the normal SDD WORKFLOW. The honest finding: of the whole pool, only `goal-craft` (ADAPT, planning) and `session-closer-hook` (ADAPT, gated on SPEC-006's promote signal) survive near-term; review and testing are already covered by the kit's moat, so nothing is absorbed there.**

### The internal-lineage resolution

PHILOSOPHY §1 carves out "components with indirect lineage (originated in-kit but grounded in existing patterns)" and §5 prescribes "test as a standalone experiment first; if it works in production for 3+ months, then propose merging with a source citation." Han's personal repos ARE that experiment ground. So the internal lane's lineage gate is:
- the candidate has lived in its source repo for the §5 bar (1 week minimum; 3 months for a net-new pattern), AND
- the soak duration is read from a **real date source**: the candidate's first git-commit date (`git log --reverse --format=%ad -- <path> | head -1`), NOT self-attested. (This fixes the "battle-tested since `<date>`" gap SPEC-004's validation flagged.)
- the citation becomes "battle-tested in `<source-repo>` since `<first-commit-date>`, distilled from `<pattern family>`."

### The relevance-filtered gate (the careful part)

A candidate passes ONLY if ALL hold:
1. **SDD-lifecycle relevance**: it strengthens a kit phase, prioritizing **planning (Think/Spec), review (Review), testing (Build/verify)** per the maintainer directive. Personal-domain skills (cashflow, tide, hermes, learning, trading, OCR, media) fail here on sight.
2. **The SPEC-004 adoption rubric** score >= 10 (Layer fit + Pain match + Adoption cost + Timing, 0-4 each).
3. **NO-list** (PHILOSOPHY §3) + **bash/md only** (no Python/Node in hooks).
4. **Not a duplicate** of an existing kit component (the gate criterion SPEC-004 DEC-010 added). This is the load-bearing filter here: the kit's review + testing are already strong, so most review/testing candidates are duplicates.
5. **Serves 2+ lifecycle phases** (applies to candidates; the lane mechanism itself is connective tissue per SPEC-004 DEC-008).
6. **The §5 soak** with the real date source above.

### The scored inventory (centerpiece)

Pool = Han's own generic dev-workflow skills/hooks across `ops-toolkit`, `~/.claude/skills/`, `dwarvesf/claude-skills`. Scored against the gate (rubric /16). Personal-domain skills excluded up front. Third-party skills (superpowers, ouroboros, frontend-design, Claude Code built-ins) are NOT Han's and are out of scope.

| Candidate | Source | Phase | Rubric /16 | Verdict | Rationale |
|---|---|---|---|---|---|
| `goal-craft` | ~/.claude/skills | Planning (Think/Spec) | ~12 | **ADAPT** | SPEC-006's `/user:assign` already leans on "the goal-craft pattern"; absorbing a kit-owned version removes the dependency on a user-level skill and makes the spine self-contained. Adapt (fold the goal-crafting logic into `/user:assign`), do not ship the skill verbatim. |
| `session-closer-hook` | ops-toolkit | Review/Ship guardrail | ~14 | **ADAPT (gated)** | It is the hook embodiment of SPEC-006's doc-update completeness clause, which SPEC-006 (DEC-002) ships warn+log first and promotes to a hook only on a retro signal. So absorb it AS that promotion, when the signal fires, not before. bash+jq, fits the hook layer cleanly. |
| `doc-compaction` | ~/.claude/skills | Docs/Reflect | ~10 | **v2 candidate** | Real but no urgent pain; the kit's specs/docs grow but the doc-update clause + `/retro` cover most. Revisit if doc bloat shows up in a retro. |
| `incident-workflow` | ~/.claude/skills | Reflect (postmortem) | ~9 | **v2 candidate** | Forensic postmortems are out of the feature-lifecycle scope `/retro` covers; a kit incident mode is plausible later, no signal now. |
| `wrap-session` | ops-toolkit | Reflect/Ship | ~9 | **REJECT** | Duplicates the kit's `/retro` + `docs/handoff/` + the SPEC-006 doc-impact map. The LAB_LOG idea is already covered. |
| `plan-for-goal` | ~/.claude/skills | Planning | - | **REJECT** | Duplicate of `goal-craft` (folds into the `goal-craft` ADAPT, not separate). |
| `prompt-improver` | ~/.claude/skills | (cross-cutting) | ~7 | **REJECT** | General prompt-sharpening meta-skill, not SDD-lifecycle-specific; sprawl risk; does not serve 2+ kit phases in a kit-specific way. |
| `content-spec` | ~/.claude/skills | Spec (prose) | ~7 | **REJECT** | Doc/prose-writing spec discipline; the kit's `/spec` is for code/feature specs. Overlap + out-of-scope (content vs code). |
| `knowledge-capture` | dwarvesf/claude-skills | Reflect | ~6 | **REJECT** | Pushes learnings to an external knowledge repo; out of kit scope. `/retro` captures cycle learnings in-repo. |
| `extract-workflow` | ~/.claude/skills | (meta) | ~6 | **REJECT** | Meta-skill for turning repeated processes into skills; the kit's evolution is already governed by PHILOSOPHY §5 + the SPEC-004 absorption ritual. Sprawl risk. |
| (review skills) | various | Review | - | **NONE** | The kit's `/review` + `/review-team` + `reviewer` + `security-auditor` already absorb the strong external review patterns (superpowers/gstack/ToB). No Han-own review skill beats them. Honest gap: none to absorb. |
| (testing skills) | various | Build/verify | - | **NONE** | The kit's verification pipeline (`task-verifier` + `fix-agent`) + `test-meta`/`test-hooks` already cover testing. `superpowers:test-driven-development` is third-party, not Han's. No internal candidate adds value. |

**Net:** 2 near-term survivors (`goal-craft` ADAPT; `session-closer-hook` ADAPT-on-signal), 2 v2 candidates, the rest REJECT. The maintainer's emphasized areas split honestly: **planning** gains `goal-craft`; **review** and **testing** gain nothing because the kit is already strong there (stating that is the point of a careful gate, not a failure).

### Survivors flow through the normal WORKFLOW

Absorption proposes; it does not merge. Each ADOPT/ADAPT survivor becomes its own backlog item -> SPEC -> validate -> execute -> README citation -> §5 soak:
- `goal-craft` ADAPT -> a backlog item (its own spec) to fold goal-crafting into `/user:assign` (ties to SPEC-006).
- `session-closer-hook` ADAPT -> tied to SPEC-006's doc-update-clause promote-to-hook trigger; absorbed when that signal fires, not before.

### NO-list check
One-sentence description (gate 4): *"The internal absorption lane scores Han's own dev-workflow skills/hooks against a relevance-filtered gate and proposes the few that strengthen the kit's planning/review/testing without duplicating it."*

| Gate | Compliance |
|---|---|
| Bash over binaries | ✓ doc + a `--internal` mode on the existing command; survivors must be bash/md to pass the gate |
| Serves 2+ phases | n/a for the lane (connective tissue, SPEC-004 DEC-008); enforced on candidates |
| Detect, don't dictate | ✓ proposal-only; nothing auto-merged |
| Synthesize, don't originate | **✓-with-caveat.** The internal lane is the §1 indirect-lineage carve-out made explicit; the relevance-filter + first-commit-date soak are net-new but grounded. Labeled in Known limitations (mirrors SPEC-004 DEC-018). |
| One sentence describable | ✓ (above) |
| Source cited | ✓ PHILOSOPHY §1 carve-out + §5 soak; SPEC-004 mechanism; the ops-toolkit lifecycle |

## Solution

| Task | Files | Type | Depends on |
|---|---|---|---|
| TASK-1 | `docs/ABSORPTION.md` (new `## The internal lane` section: lineage resolution + relevance gate + first-commit soak) | Doc | SPEC-004 shipped |
| TASK-2 | `commands/absorb.md` (add `--internal` mode) | Command extension | SPEC-004 shipped, TASK-1 |
| TASK-3 | `docs/absorption/2026-05-20-internal.md` (the scored inventory above, as the first internal proposal) | Proposal artifact | TASK-1 |
| TASK-4 | `_meta/BACKLOG.md` (backlog entries for the ADOPT/ADAPT survivors) | Backlog | TASK-3 |
| TASK-5 | `tests/test-meta.sh` + `README`/`MANUAL`/`CHANGELOG` | Test + hygiene | TASK-1..4 |

### Task Breakdown

**Phase 1: The lane**
- [ ] **TASK-1: `## The internal lane` in `docs/ABSORPTION.md`.** Document: the in-house lineage resolution (§1 carve-out + §5 soak, date source = first git-commit), the relevance-filtered gate (the six criteria above, prioritizing planning/review/testing), and that personal-domain skills fail on sight. Reuse SPEC-004's rubric + proposal artifact; do not duplicate them.
  - Acceptance: section exists with the lineage resolution + the six gate criteria + the first-commit-date soak source; states the planning/review/testing priority and the personal-domain exclusion; references (not duplicates) SPEC-004's rubric + `docs/absorption/`.

**Phase 2: The command mode**
- [ ] **TASK-2: `/user:absorb --internal`.** Add a mode that resolves Han's own dev-workflow skill/hook sources, reads each candidate's first-commit date for the soak check, scores against the relevance gate, and writes a dated internal proposal under `docs/absorption/`. Same proposal-only + `git status` self-check as the external mode. Maintainer-only.
  - Acceptance: `--internal` documented; reads first-commit date for soak; applies the relevance gate; writes a dated proposal; proposal-only self-check; degrades gracefully if a source path is absent.

**Phase 3: The grounding (centerpiece)**
- [ ] **TASK-3: Write the first internal proposal `docs/absorption/2026-05-20-internal.md`.** Land the scored inventory above as a real dated proposal: the table + the honest "review/testing already covered" finding + the survivor handoffs. This is the deliverable that makes the lane grounded, not abstract.
  - Acceptance: the scored inventory is captured as a dated proposal with verdicts + rationale; the "no review/testing candidates" finding stated explicitly; survivors named with their handoff.

**Phase 4: Survivors -> backlog**
- [ ] **TASK-4: Backlog entries for survivors.** Add `_meta/BACKLOG.md` entries: `goal-craft` ADAPT (fold into `/user:assign`, ties to SPEC-006) and `session-closer-hook` ADAPT (tied to SPEC-006's doc-update promote-to-hook trigger). Mark `doc-compaction` + `incident-workflow` as v2 candidates.
  - Acceptance: survivors are backlog items with target specs noted; v2 candidates listed; no survivor is merged by this spec (proposal-only).

**Phase 5: Verify + hygiene**
- [ ] **TASK-5: Tests + cross-refs.** `tests/test-meta.sh`: assert `docs/ABSORPTION.md` has the `## The internal lane` section; `docs/absorption/2026-05-20-internal.md` exists. README/MANUAL note the `--internal` mode. CHANGELOG entry.
  - Acceptance: `bash tests/test-meta.sh` passes (delta documented); `bash tests/test-hooks.sh` 42/42; `--internal` in the MANUAL; CHANGELOG entry.

## Acceptance Criteria (global)
- [ ] `docs/ABSORPTION.md` has an internal-lane section with the lineage resolution + relevance gate + first-commit-date soak
- [ ] `/user:absorb --internal` scores Han's own dev-workflow candidates against the gate, proposal-only
- [ ] The scored inventory lands as a dated proposal; the "review/testing already covered, nothing to absorb" finding is stated, not hidden
- [ ] Only gate-passing survivors (`goal-craft`, `session-closer-hook`) become backlog items; the rest are REJECT/v2 with rationale
- [ ] No survivor is merged by this spec (each runs the full WORKFLOW later)
- [ ] `bash tests/test-hooks.sh` 42/42; `bash tests/test-meta.sh` passes (delta documented)
- [ ] No new dependency, env var, settings.json field; no new command (extends `/user:absorb`)
- [ ] CHANGELOG entry

## Known limitations
1. **The relevance-filter + first-commit-date soak are net-new (originated-in-kit), grounded in PHILOSOPHY §1/§5 but not themselves §5-soaked.** Labeled, not hidden (mirrors SPEC-004 DEC-018).
2. **The scored inventory is a point-in-time judgment from skill descriptions, not a deep read of each candidate.** Final ADOPT requires reading the candidate + confirming the §5 soak at execute time; the inventory is a proposal, not a merge.
3. **The "review/testing already covered" finding could change** if the kit's review/verify weakens or a genuinely novel Han-own review/test skill appears; the lane re-scores on the next `--internal` run.
4. **Candidate ownership ("Han's own") is asserted from usage, not a license audit.** A candidate that turns out to be third-party-derived must cite that lineage (external lane), not claim in-house origin.

## Edge Cases
1. **A candidate is younger than the §5 bar** (first-commit date too recent). Gate fails it with "needs more soak until `<date>`"; it stays a candidate, not an ADOPT.
2. **A candidate duplicates an existing kit component** (most review/testing ones). The no-duplicate gate criterion REJECTs it; the proposal names the duplication.
3. **A candidate is personal-domain dressed as dev-workflow.** The SDD-relevance filter rejects it on sight (criterion 1).
4. **A survivor's absorption later fails its §5 soak.** Routes to PHILOSOPHY §5's deprecation path (inherited from SPEC-004 DEC-017).
5. **`--internal` run with a source path absent** (e.g. `dwarvesf/claude-skills` not cloned locally). Reports the source as unavailable and scores what it can, like the external lane's per-source continue-on-failure.

## Out of Scope
- Merging any survivor (each runs its own SPEC -> validate -> execute later; `goal-craft` ties to SPEC-006, `session-closer-hook` to SPEC-006's promote trigger).
- Re-deriving SPEC-004's rubric / proposal artifact (reused, not duplicated).
- Personal-domain skills (cashflow, tide, hermes, learning, trading, OCR, media, etc.).
- Third-party skills (superpowers, ouroboros, frontend-design, Claude Code built-ins), those are the external lane, not internal.
- A scheduler / autonomous loop.

## Decision Log
- **DEC-001**: The internal lane is grounded by a real scored inventory, not abstract machinery (the reason SPEC-004 split it here).
- **DEC-002**: The in-house lineage tension is resolved via the §1 indirect-lineage carve-out + the §5 soak with a real date source (first git-commit), not self-attestation.
- **DEC-003**: The gate is relevance-filtered to the SDD lifecycle, prioritizing planning/review/testing per the maintainer directive, with the no-duplicate criterion as the load-bearing wall against absorbing what the kit already does well.
- **DEC-004**: Only `goal-craft` (ADAPT) and `session-closer-hook` (ADAPT-on-signal) survive near-term; review + testing yield NONE because the kit is already strong there. Stating the empty result is the careful-absorption the directive asked for.
- **DEC-005**: `session-closer-hook` is absorbed AS the promotion of SPEC-006's doc-update clause to a hook, when SPEC-006's retro signal fires, not pre-emptively. Keeps the two specs consistent.
- **DEC-006**: `goal-craft` is ADAPTed into `/user:assign` (kit-owned goal-crafting), removing the spine's dependency on a user-level skill (ties to SPEC-006).
- **DEC-007**: Survivors flow through the full WORKFLOW; this spec proposes, it does not merge.

## Source citations
- In-house lineage carve-out + soak: `docs/PHILOSOPHY.md` §1 (indirect lineage) + §5 (experiment-first, 1-week/3-month bar).
- The absorption mechanism this extends: `docs/specs/SPEC-004-absorption-cadence.md` (ritual, rubric, `docs/absorption/`, `/user:absorb`, no-duplicate gate DEC-010, failed-soak deprecation DEC-017).
- The candidate inventory: 2026-05-20 ops-toolkit + `~/.claude/skills` sweep (ops-toolkit yields `wrap-session` + `session-closer-hook`; the broader dev-workflow pool lives in `~/.claude/skills` + `dwarvesf/claude-skills`).
- `session-closer-hook` <-> SPEC-006 doc-update clause: `docs/specs/SPEC-006-orchestration-spine.md` DEC-002 (warn+log, promote-to-hook on signal).
- `goal-craft` <-> the spine: `docs/specs/SPEC-006-orchestration-spine.md` (`/user:assign` goal-crafting).
- ops-toolkit lifecycle (experiment -> harden -> distill): `~/workspace/tieubao/ops-toolkit/CLAUDE.md`.

## Validation
To be filled by `/user:spec-validate`. Expected challenges: (a) is the scored inventory's REJECT reasoning sound, or does it under-value a candidate (esp. the "review/testing already covered" claim); (b) is `--internal` justified or should the one-time inventory suffice without a recurring command mode; (c) is the first-commit-date a sufficient soak proxy; (d) does ADAPTing `goal-craft` into `/user:assign` belong here or in SPEC-006.
