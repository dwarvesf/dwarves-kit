---
title: Testing/QA + UI-design lane scan (az-skills, harness-experimental vs the kit's current lanes)
date: 2026-05-21
source: file-level scan of zvadaadam/az-skills (master, pushed 2026-05-18) + hoangnb24/harness-experimental (main) at current HEADs; builds on docs/research/2026-05-20-orchestration-deep-scan.md
feeds: SPEC-018 (test-plan evidence column), SPEC-019 (greenlight CI lane), SPEC-020 (UI-design loop)
benchmarked_against: commands/test-plan.md, commands/visual-team.md, commands/devs-team.md, agents/task-verifier.md, docs/PHILOSOPHY.md, SPEC-016, SPEC-018
status: active
---

# Testing/QA + UI-design lane scan

The prior deep-scan (2026-05-20) answered the orchestration question: is there a workflow spine worth absorbing? Answer: no, WORKFLOW.md is at parity. This scan asks a narrower question for the two lanes the maintainer is investing in next: **testing/QA and UI design. At the file level, what in `zvadaadam/az-skills` and `hoangnb24/harness-experimental` is genuinely unabsorbed, and which survive the PHILOSOPHY NO-list?**

The honest headline: the obvious wins from both repos were already pulled (visual-team and devs-team are the az-skills roundtables recast to house style; the risk-tier lanes are harness-experimental's). What remains is one large QA capability the kit lacks entirely (a CI/PR green loop), one cheap QA refinement (proof-by-evidence in the test plan), and an honest reframe of the UI lane (the kit should orchestrate a generator it already has, not build one).

---

## TL;DR

- **Already absorbed (do not re-litigate).** az-skills `design-roundtable` to `/user:visual-team`; az-skills `devs-roundtable` to `/user:devs-team`; harness-experimental tiny/normal/high-risk tiers to WORKFLOW.md; harness-experimental `decisions/` to the spec Decision Log. The deep-scan already concluded the workflow spine needs nothing.
- **ADAPT (1, the big one): a CI/PR green loop.** az-skills `greenlight-pr` triages CI failures (real vs flaky), triages bot review comments, fixes the real ones, retries flaky with a bounded budget, and iterates to green with honest terminal states. The kit ships nothing past the in-session worker to verifier to fix loop; its own GitHub Actions matrix has no driver. This is the single biggest new QA capability. ADAPT the pattern in bash + `gh` + jq; REJECT the Python `gl-snapshot.py`. **Feeds SPEC-019.**
- **ADAPT (2, the cheap one): proof-by-evidence in the test plan.** harness-experimental `TEST_MATRIX.md` ties every behavior to the evidence that proves it (8 columns, layered, status lifecycle). The kit's `## Test plan` matrix plans coverage categories but never names what proves each case. Add one `Proof` column. **Feeds SPEC-018 (amend the DRAFT).**
- **ADAPT (3, the honest one): a UI-design loop, not a generator.** The kit critiques visuals (`/user:visual-team`) but never produces them, by deliberate decision (SPEC-016 DEC-005: visual generation needs render machinery, violates bash/no-binaries). But the `frontend-design` skill is already installed and IS the generator. The kit's contribution is the loop: structured UI brief to `frontend-design` generation to `/user:visual-team` critique to revise. Downstream-facing, inherits the visual-team carve-out. **Feeds SPEC-020.**
- **REJECT (unchanged calculus).** Named-designer personas (Rams/Ive/Vignelli/Fukasawa/Jongerius in design-roundtable: persona theater, NO-list #3). An in-kit visual generator (`batch_design`/.pen: render machinery, bash/no-binaries). `code-simplifier`, `tour`, `repo-history-book` (out of the two lanes or overlapping existing hooks: vendor-skill sprawl). harness STATE-style validation engine (state-machine progression, trades readability for an engine).

---

## What is already absorbed

| Source artifact | Pattern | Kit landing | Recast |
|---|---|---|---|
| az-skills `design/design-roundtable` | parallel multi-lens visual critique | `/user:visual-team` (SPEC-016) | generic house lenses, critique-only, no generation |
| az-skills `engineering/devs-roundtable` | parallel multi-lens code/design critique | `/user:devs-team` (SPEC-016) | generic eng lenses on the solution |
| az-skills `engineering/code-review` | multi-perspective review | `/user:review-team` + `reviewer` | (pre-dates this scan) |
| harness-experimental FEATURE_INTAKE | tiny/normal/high-risk tiers | WORKFLOW.md risk lanes | cited source; deep-scan confirmed nobody does work-sizing better |
| harness-experimental `decisions/` | durable record the next agent inherits | spec Decision Log + GSD decision-gate idea | deep-scan ADOPT-1 |

The deep-scan (2026-05-20) is the authority on the workflow spine. This scan does not revisit it.

---

## Lane 1: Testing/QA

### Current kit surface

```
/user:test-plan   coverage matrix (happy/boundary/failure/security/regression) -> AC, flat
/user:execute     worker -> task-verifier -> fix-agent (max 2 retries), in-session
task-verifier     reads code, runs npm/go/pytest/cargo, checks AC/scope/extra/drift/quality
review-team       a test-coverage lens, post-code
tests/            test-hooks.sh (behavior), test-meta.sh (structural)
```

The gap: coverage is **planned** but proof is never **pinned**, and nothing exists past the local session. The kit verifies inside one run; it has no concept of driving its own CI to green.

### Findings

| Capability | Kit today | Source has | Gap | Verdict |
|---|---|---|---|---|
| Coverage design | flat 5-category matrix to AC | harness `TEST_MATRIX.md`: layered (unit/integration/e2e/platform) + **evidence column** + status lifecycle (planned/in_progress/implemented/changed/retired) | kit plans cases, never names what proves each | ADAPT (evidence column; layers deferred) |
| Proof discipline | verifier runs the suite | harness `validation.md`: proof strategy + **fixtures** (deterministic, repeatable) + acceptance-evidence | flaky risk unaddressed; no fixture naming | ADAPT (light: name fixtures in the plan) |
| CI / PR green loop | **none** | az-skills `greenlight-pr`: snapshot CI + comments, classify real vs flaky, fix real, retry flaky (3-budget per commit hash), poll re-review, iterate; terminal states `done` / `stop_pr_closed` / `stop_exhausted_retries` / `stop_waiting_review_pending` | kit ships nothing post-push; its CI matrix has no driver | **ADAPT** (pattern yes, Python no) |
| Test rigor by tier | tiers scale process weight | harness intake: tiers scale **validation rigor** (tiny=quick check, normal=update matrix, high-risk=full validation doc) | kit tiers do not couple to test depth | ADAPT (one line per lane) |

### Deep dive: greenlight-pr (the one large new capability)

`greenlight-pr` drives a PR to merge-ready by closing two loops the kit does not: CI-failure triage and bot-comment triage. Its shape (from `SKILL.md` + `references/{ci-classification,known-bots,triage-process}.md` + `scripts/gl-snapshot.py`):

1. **Snapshot.** `gl-snapshot.py` emits JSON of CI status + review comments + recommended actions; state persists for crash recovery.
2. **CI triage.** Each failing check is classified branch-specific (fixable code) vs flaky (environmental). Only branch failures get code changes; flaky failures retry with a 3-attempt budget per commit hash.
3. **Comment triage.** Inline bot comments evaluated via sub-agents to FIX / DISAGREE / DEFER, high-confidence fixes applied in one commit, each replied to.
4. **Iterate.** Push, wait for CI, poll for new reviews, re-snapshot, re-evaluate. Terminal states are honest stops, not a claim of done.

**Why it fits the kit (brutally honest version).** Unlike `/user:visual-team` (which the kit cannot dogfood, no UI), the kit *can* dogfood greenlight: it has a macOS + Ubuntu Actions matrix. PHILOSOPHY checks:

| Gate | Verdict |
|---|---|
| Bash over binaries / no Python in hooks | The carve-out is hooks; a command can shell out. But `gl-snapshot.py` is a Python script: REJECT it. `gh pr checks --json` + `gh pr view --json` + jq does the snapshot in bash. ADAPT the pattern, not the code. |
| Detect, don't dictate / no hard gates | greenlight is an opt-in lane the user pulls; terminal states are honest stops, not blocks. OK. |
| Bounded loop, not autonomous runtime | The in-session polling loop with a 3-attempt cap is the bounded in-session Stop-hook-shaped pattern the deep-scan ADAPT-2 confirmed is first-party-blessed (ralph-wiggum). Not an unbounded outer bash loop. OK. |
| Synthesize, don't originate | Clear source (az-skills greenlight-pr). OK. |
| Serves 2+ phases | Build + Review + Ship. OK. |
| No speculative features | Real consumer: the kit's own CI matrix. OK. |

**Honest tension to resolve in the spec:** position vs `/user:review` (pre-push critique) and `/user:ship` (opens the PR). greenlight is the **post-push** CI lane; it must not duplicate the pre-push review or the ship gate. SPEC-019 owns that boundary.

### Deep dive: behavior-to-proof (the cheap refinement)

harness `TEST_MATRIX.md` columns: Story, Contract, Unit, Integration, E2E, Platform, Status, Evidence. The load-bearing idea for the kit is **Evidence**: every row names the proof. The kit's `## Test plan` (SPEC-018, DRAFT) is `case -> category -> AC -> expected`. Adding `Proof` (the exact command or artifact that demonstrates the case) turns "we planned coverage" into "we named the evidence" at one-column cost. The test *layers* (unit/integration/e2e/platform) are deferred: most kit consumers are single-layer; add layers at the third real need (no premature abstraction).

---

## Lane 2: UI design

### Current kit surface

```
/user:design       conversational solution beat (1-question-at-a-time) -> DECISION-BRIEF ## Solution
/user:devs-team    5 eng-lens critique of the solution
/user:visual-team  5 visual-lens critique (DOWNSTREAM-only, critique-only, NO generation)
frontend-design    3rd-party skill (Anthropic), the actual UI generator (installed)
```

The gap: the kit critiques visuals but never produces them, and has no structured UI brief for either a generator or the critic to work against.

### Findings

| Capability | Kit today | Source has | Gap | Verdict |
|---|---|---|---|---|
| Structured UI brief | `/design` general + conversational | harness `design.md`: explicit UI/Platform Impact, states, data model, observability sections | nothing gives visual-team or a generator a concrete UI spec | ADAPT (a UI-track section) |
| Visual generation | out of scope by decision (SPEC-016 DEC-005) | az-skills `design-roundtable` generates via `batch_design`/.pen + screenshots | kit can critique a mockup, never make one | REJECT building; WIRE to `frontend-design` |
| design to make to critique loop | 2 of 3 stations exist, disconnected | (none does the full loop cleanly) | brief to generate to critique to revise is not first-class | ADAPT (orchestrate existing pieces) |
| Named-designer lenses | generic house lenses | design-roundtable: Rams/Ive/Vignelli/Fukasawa/Jongerius | n/a | REJECT (persona theater, NO-list #3) |

### Deep dive: a UI loop, not a generator

The temptation is to read "we want a UI-design skill" as "build a generator." That is a hard REJECT and already-decided: visual generation needs render/browser machinery and violates bash/no-binaries (SPEC-016 DEC-005, Out of Scope). But the picture changed in one way the kit can exploit: `frontend-design` (third-party, Anthropic) is already installed and is exactly that generator.

So the kit's contribution is **orchestration, not pixels**: a downstream-facing skill (or a thin `/user:design` UI track) that (1) produces a structured UI brief, (2) hands generation to `frontend-design`, (3) routes the output through `/user:visual-team`, (4) loops on revise. The kit already owns stations 1 (brief, via `/design`) and 3 (critique, via `visual-team`); the missing middle is owned by an external dependency, which is the kit's correct posture (external tools are dependencies, not features). Downstream-facing, so it inherits the visual-team PHILOSOPHY carve-out: it needs a named consumer outside the kit (UI-bearing downstream projects), which it has.

The structured UI brief borrows harness `design.md`'s UI/Platform Impact shape (layout, component states, responsive behavior, accessibility, design-system tokens), giving both the generator and the critic something concrete instead of prose.

---

## Absorb plan (prioritized)

| # | Recommendation | PHILOSOPHY satisfied | NO-list gate passed | Kit artifact | Feeds |
|---|---|---|---|---|---|
| 1 | **`/user:greenlight`** CI/PR green loop in bash + `gh` + jq; classify real vs flaky; fix real via fix-agent shape; bounded flaky retry; honest terminal states | Guardrails over guidance (a real loop, not prose); Verify before proceeding (extends verify to CI); Detect don't dictate (opt-in, terminal stops) | No Python (gh+jq); bounded in-session loop (not autonomous); one-sentence describable; source-cited; dogfoodable on the kit's own CI | New `commands/greenlight.md` (+ WORKFLOW.md slot after ship; reuse fix-agent) | **SPEC-019** |
| 2 | **Evidence column** in `## Test plan`: each case names the command/artifact that proves it | Verify before proceeding (proof, not just plan); Synthesize don't originate (harness TEST_MATRIX) | One column; no new component; bash meta-test pins it | Amend DRAFT `SPEC-018` matrix + `commands/test-plan.md` + a meta-test | **SPEC-018** (amend) |
| 3 | **UI-design loop** downstream skill: structured UI brief to `frontend-design` to `/user:visual-team` to revise | External tools are dependencies (uses frontend-design, does not rebuild it); Detect don't dictate; downstream carve-out | No renderer in the kit; orchestration only; named downstream consumer | New skill (or `/user:design` UI track) + harness design.md UI section shape | **SPEC-020** |

Recommendation 1 is the substantial build. 2 is a one-column amend. 3 is wiring + a brief shape, no renderer.

---

## What we should NOT absorb (and why)

| Tempting pattern | Where seen | Why rejected |
|---|---|---|
| Named-designer personas (Rams/Ive/Vignelli/Fukasawa/Jongerius) | az-skills design-roundtable | Persona theater (NO-list #3). visual-team's generic lenses already cover hierarchy/system/a11y/restraint/expressiveness. |
| In-kit visual generator (`batch_design`, `.pen`, screenshots) | az-skills design-roundtable | Render/browser machinery, violates bash/no-binaries. Already decided (SPEC-016 DEC-005). frontend-design owns generation. |
| Python `gl-snapshot.py` | az-skills greenlight-pr | `gh` + jq does the snapshot in bash; Python is a runtime dependency the kit refuses. Absorb the pattern, not the script. |
| `code-simplifier` skill | az-skills | Overlaps `slop-cleaner.sh` hook + review-team; not in either lane; vendor-skill sprawl (NO-list #1). |
| `tour`, `repo-history-book` skills | az-skills | Onboarding/history, out of the two lanes; vendor-skill sprawl. |
| Test layers (unit/integration/e2e/platform) in the matrix now | harness TEST_MATRIX | Most kit consumers are single-layer; add at the 3rd real need (no premature abstraction). Deferred, not rejected. |
| harness validation-doc engine / STATE progression | harness high-risk-story templates | State-machine progression; trades "readable in 30 seconds" for an engine. The kit detects and suggests; it does not own a progression controller. |

---

## Sources (fetched 2026-05-21)

- zvadaadam/az-skills (master): repo tree via `gh api`; `skills/engineering/greenlight-pr/SKILL.md` + `references/{ci-classification,known-bots,triage-process}.md` + `scripts/gl-snapshot.py`; `skills/design/design-roundtable/SKILL.md`; `skills/engineering/code-simplifier/SKILL.md`. Description: "A curated set of skills I use with my agents."
- hoangnb24/harness-experimental (main): `docs/TEST_MATRIX.md`; `docs/FEATURE_INTAKE.md`; `docs/templates/high-risk-story/{design,validation}.md`. (AGENTS.md + spine already covered by the 2026-05-20 deep-scan.)
- Kit baselines: `commands/{test-plan,visual-team,devs-team,design,execute}.md`; `agents/task-verifier.md`; `docs/PHILOSOPHY.md`; `docs/specs/SPEC-016`, `SPEC-018`; `WORKFLOW.md`.
- Builds on: `docs/research/2026-05-20-orchestration-deep-scan.md` (the workflow-spine authority).

### Not found / nothing relevant
- **A QA flow stronger than worker-to-verifier-to-fix:** none. The field converged on the kit's verify shape (deep-scan); greenlight extends it to CI altitude, it does not replace it.
- **A UI-design generator that fits bash/no-binaries:** none. Generation requires a renderer; the kit's correct move is to depend on `frontend-design`, not rebuild it.
