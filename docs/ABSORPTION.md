# ABSORPTION.md: the recurring upstream-absorption ritual

> Maintainer-facing. The repeatable procedure for keeping dwarves-kit synthesized from the best upstream patterns without drifting. Operationalizes PHILOSOPHY section 5 (Evolution strategy) into a ritual with a cadence, a gate, and a proposal artifact. Spec: SPEC-004. The internal ops-toolkit lane is SPEC-007 (parked).

## The external lane

Two scan lanes, run by `/user:absorb`, both feeding one dated proposal under `docs/absorption/`:

- **Lane A, drift re-audit.** Re-check the README Credits source repos against what the kit has absorbed: have they shipped new patterns, deprecated old ones, or moved HEAD since the last run? Generalizes SPEC-002's one-shot audit.
- **Lane B, seed-rescan.** Re-scan a pinned seed set (see `## Seed list`) for new/changed patterns in the kit's interest areas, generalizing SPEC-014's one-shot wide survey into a recurring scan. v1 is a re-scan of known repos, NOT open web-search discovery of brand-new sources (the kit has no discovery primitive; deferred until a real "we keep missing new repos" signal).

**The human merge gate (the load-bearing rule).** Discovery, scoring, and drafting are automatic. **Adopting** any source or pattern, and **adding** a newly-noted source to README Credits, are maintainer-approved and flow through the standard SDD WORKFLOW. The ritual proposes; the maintainer decides; nothing is absorbed automatically. This is "synthesize, don't originate" (PHILOSOPHY section 1): the kit only ships patterns a human vouched for, with a citation.

## Interest areas

Lane B scans for patterns in the kit's interest areas, weighted by absorb yield:
- **Workflow / orchestration**, the kit's core; high absorb yield.
- **Agents**, subagent design, roundtable/critique patterns, the AGENTS.md operating layer (SPEC-016, ADR-0013); high yield.
- **QA / testing**, coverage matrices, test-plan lanes, verification (SPEC-016, SPEC-018). Mixed: pattern-level yield is real, but tooling that needs a binary/runtime (Playwright) routes to "recommend external" (PHILOSOPHY section 3), not absorb.
- **UI / design**, design-roundtable / visual patterns (SPEC-016). Low absorb yield: most needs visual binaries -> "recommend external"; scanned but not deeply.

A candidate that needs a binary, paid dep, or new runtime scores low on the rubric's adoption-cost factor and surfaces as **recommend external**, never silently absorbed.

## Seed list

Lane B's scan targets, defined to avoid a two-source-of-truth: the **live README Credits parse** UNION a **pinned list of only the non-Credits extras** below. Credits stays the single source for credited repos; this list holds only the extras. Grown AND shrunk only by maintainer edit (the human gate).

Pinned non-Credits extras (from the SPEC-014 survey set, repos not in README Credits; the maintainer pins/corrects exact owner/repo URLs as part of the gate):
- `obra/superpowers` , skills framework (brainstorming, writing-plans, TDD, debugging)
- SuperClaude , command/persona framework
- BMAD , agent/method framework
- agent-os , agent operating-system patterns
- claude-flow , multi-agent orchestration
- ouroboros , self-referential loop / evolution
- `doraemonkeys/claude-code-debug-mode` , tagged-log debug patterns

**Since-last-run baseline.** Lane B detects "changed" per repo by comparing its current HEAD SHA (`gh api repos/{owner}/{repo}/commits/HEAD --jq .sha`) to the SHA recorded in the most recent prior proposal's footer; the first run flags every repo as new and records the baseline. WebFetch has no diff capability, so the SHA ledger is the baseline.

**Ranking + cap.** Rank candidates by rubric total, tie-break by interest-area weight (agents/workflow > QA/UI). Surface the top <=15 prominently; every gate-passer (>=10 + all gates) still appears, capped-out ones go to the proposal's overflow appendix. The cap orders display, it never decides what passes, so a real ADOPT can never be silently dropped.

When the pinned list outgrows readability here, promote it to a structured `docs/absorption/SOURCES.md` (no command-logic change). When open web-search discovery earns its keep (a real missed-source signal), add it as a third lane behind the same merge gate.

## The adoption rubric

Formalizes PHILOSOPHY section 5's four factors into a scored gate. (`/eval-tool` is NOT a kit command; the rubric lives here as text.)

| Factor | Score 0-4 (0 = no, 4 = strong) |
|---|---|
| **Layer fit** | does it fit a kit layer (hook / command / agent / doc) cleanly? |
| **Pain match** | does it solve a real pain the kit has today? |
| **Adoption cost** | inverse cost: 4 = trivial bash/doc, 0 = new runtime/dependency/binary |
| **Timing** | battle-tested upstream now (3+ months), not bleeding-edge? |

Total out of 16. **ADOPT requires >= 10** AND passing every other gate below.

## The gate

A candidate is ADOPT only if ALL hold:
1. Rubric total **>= 10**.
2. Passes the **NO-list** (PHILOSOPHY section 3): no compiled binary, no paid dep, no LLM-in-hook, readable in 30s.
3. Passes the **reject-list** (PHILOSOPHY "What we explicitly reject").
4. **Serves 2+ of the lifecycle phases** (this gate applies to the absorbed *candidate*, a feature; `/user:absorb` itself is connective tissue, exempt, like `/kit-health`).
5. **Does not duplicate** an existing kit component OR a recommended external tool.

Fail any -> ADAPT (reimplement in kit idiom) or REJECT (with the reason, often "recommend external").

## Cadence

**Maintainer-triggered, target monthly, no enforcement.** Nothing forces a run (a scheduler/loop is autonomous-runtime territory, rejected). The dated proposals under `docs/absorption/` are the **last-run ledger**: each run stamps its date, so staleness is visible on the next run. A nudge hook is deferred until a missed-cadence signal appears.

## The proposal artifact

`/user:absorb` writes a dated proposal under `docs/absorption/` (template: `docs/absorption/TEMPLATE.md`). It is **proposal-only**: the command edits no kit component and ends with a `git status` self-check asserting changes appear only under `docs/absorption/`. A no-drift run still writes a dated "no candidates" proposal, so the directory doubles as run history. Same-month re-runs append a numeric suffix; never overwrite (the point-in-time audit is the value).

## Handoff into WORKFLOW

An ADOPT/ADAPT the maintainer approves becomes a `_meta/BACKLOG.md` item, then a SPEC, then flows the full SDD WORKFLOW (spec -> validate -> execute -> review -> ship), gets a README Credits citation, and starts a PHILOSOPHY section 5 soak. A component that fails its soak after absorption routes to section 5's deprecation path; the originating proposal is annotated with the outcome (closing the audit loop).
