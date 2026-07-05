---
title: Understanding is the new bottleneck , adopting the understanding-gate into the SDLC
date: 2026-07-03
purpose: >
  Captures the analysis of Geoffrey Litt's "Understanding is the New Bottleneck" (2026-07-02)
  and how it applies to Han's dwarves-kit SDLC + ops-toolkit learning skills. Two moves: a
  design-record BEFORE implementation (human gates direction via a diagram, not code), and an
  explainer+quiz AFTER (human gates understanding, staying a creative participant for the next
  loop). Both add a missing UNDERSTANDING axis orthogonal to the kit's existing VERIFICATION
  gates. Feeds ADR-0031 (dwarves-kit) + the understanding-gate mega-goal.
source_repos: [dwarves-kit, ops-toolkit]
refresh_cadence: as-needed
next_review: null
status: active
---

# Understanding is the new bottleneck

Source article: Geoffrey Litt, "Understanding is the New Bottleneck" (geoffreylitt.com, 2026-07-02).
Read in full 2026-07-03; extract + application below.

## The article's thesis (Litt's framing)

As agents get better at **verifying their own work**, if the human's only job were verification
the human becomes redundant. Litt reframes: we **understand to PARTICIPATE**, not to verify. A
project is "many, many loops with the agent"; to shape each next loop you need "a rich set of
concepts in your mind to think creatively and fluently." Lose that and you accrue **cognitive
debt** (Margaret Storey's term) , "the humans involved may have simply lost the plot." It feels
cheap short-term; it bites later like tech debt.

His fix borrows from pedagogy (three techniques):
1. **Explainers, not raw diffs.** A raw diff is "a pile of files edited in alphabetical order with
   no explanation." Reading is hard work and "it's too easy to fool yourself into thinking you did
   the reading when you really didn't retain." His `/explain-diff` skill emits: background ->
   goal+intuition (concepts before code) -> a **literate diff** (prose-ordered snippets, not
   alphabetical) -> interactive figures -> a **5-question quiz**. Rule: "I won't send code to
   others until I can pass the quiz, and I do the same when reviewing others' code."
2. **Quiz as a speed regulator.** "A quiz is a speed regulator ... so that I can remain a full
   creative participant." AI loops run faster than comprehension; the quiz is a mechanical brake.
3. **Micro-worlds** (Papert's "Mathland"). Agents write debuggers/simulations/command-centers the
   human INHABITS rather than reads (a Prolog step-debugger; a website-migration command-center
   with side-by-side old/new). Understanding through doing, with agent-laid scaffolding.

Plus **shared collaborative spaces** (plans live on commentable Notion pages -> shared mental
models -> creative team conversations), and the closing frame: **"the point was always to augment,
not just automate"** (Alan Kay).

Caveat Litt flags AND we extend: agent-generated explainers can be **plausibly wrong**. Proportionality
of micro-worlds is unsolved (not every diff earns a debugger). Notion recommendation is a disclosed
conflict (he works there).

## The unifying frame: Understanding is a THIRD axis

The kit's V-model has a left arm (shape) and a right arm (check). Every gate it ships is a
VERIFICATION gate (proof-of-done, review-team, ship-gate) , they answer "is it correct?". None
answer "does the human understand it enough to drive loop N+1?". Litt's argument is that after
autonomous agents, THAT is the binding constraint. So the adoption adds an understanding axis at
two points:

```
        LEFT (shape)                          RIGHT (check)
  think design spec validate            execute verify review ship
            |                                          |
   DESIGN RECORD (before)                   EXPLAINER + QUIZ (after)
   diagram / ADR / C4-lite                  literate diff + 5 Qs
   human gates DIRECTION                    human gates UNDERSTANDING
   "participate forward"                    "participate into loop N+1"
```

## The blunt application to Han

Han's stated MO , "hands-off on reading code, anal about feature/test coverage" , is EXACTLY the
cognitive-debt profile the article warns about: high verification, low understanding. Live evidence
from the 2026-07-02/03 sessions: after ~8h away Han had to ask "recall where we are", "how many
sub-goals", "check the kit-hardening" , he had fallen out of the loop because the fast autonomous
runs carried proof forward but never understanding. Coverage kept the work SAFE; it did not keep
Han FLUENT. Every fast mega-goal run compounds this debt. The two gates below are the interest
payment.

## Part 1 , Design record (the BEFORE gate; Han's explicit ask)

For any spec above tiny that is "design-bearing", record the design BEFORE implementation so the
human gates DIRECTION off a diagram, not a diff.

**Format , a `## Design` block in the spec, scaled, mermaid-first, C4-LITE:**

| Element | Content | When |
|---|---|---|
| Approaches + chosen | 2-3, one-line tradeoff each, what the rejected traded away | always (design-bearing) |
| Diagram (prefer Mermaid , GitHub-renders, diffable) | by fit: sequence (control-flow/protocol) / state (lifecycle) / ER (schema) / flowchart (algorithm) / C4 container-or-component (new component's place) | always (design-bearing) |
| ADR link(s) | one `docs/decisions/NNNN` per lasting/irreversible decision | per load-bearing choice |
| Boundaries + failure modes | what changes when the load-bearing dimension grows; what breaks | if it touches data/external/migration |

**"Design-bearing" trigger:** above tiny AND any of , new component/module, non-obvious control
flow, schema change, external integration, irreversible choice, 2+ viable approaches. Else the
section collapses to `obvious: <why>` and skips the diagram. **Proportionality is the whole game:**
do NOT cargo-cult four C4 levels; use the one level that clarifies, only for genuinely new-component
work.

**Where to modify (5 points):** `commands/spec.md` Step 3 (promote the soft `### Architecture
(diagram if it helps)` into the conditional-required `## Design` block + trigger); `commands/
spec-validate.md` (a design-bearing spec cannot reach VALIDATED without the Design section);
`commands/design.md` (emit diagram + ADR-links, not just approaches/chosen); `WORKFLOW.md` (Design
row expected, not just opt-in for design-bearing normal/full); `plan-for-mega-goal/subgoal-template.md`
(a `Design:` field sibling to `Done-mode:`). Lands as a kit DEC/ADR (ADR-0031); amends SPEC-008/011.

## Part 2 , Explainer + quiz (the AFTER gate) , mapped to skills Han ALREADY owns

The realization: Han already owns every primitive the article recommends. The gap is WIRING them
into the SDLC. Ranked by leverage:

| Adopt | Litt technique | Existing Han skill (raw material) | Integration |
|---|---|---|---|
| 1. Explainer + quiz per gated PR (headline) | /explain-diff literate diff + 5 Qs; "won't ship till I pass the quiz" | `narrate-log` (session->prose) + `svg-knowledge-diagram` + `deep-understand` (already runs AskUserQuestion quizzes with a MASTERY GATE) | new `/kit:explain` composes them; the quiz IS deep-understand's engine pointed at the diff |
| 2. Quiz as speed-regulator on `gate` PRs | "a quiz is a speed regulator" | `deep-understand` mastery gate | before merging a gated-final PR, pass 5 Qs from the diff , cheap (one AskUserQuestion), fixes the AFK-lost-plot pattern |
| 3. Design record (Part 1) | understand-to-participate, before | `svg-knowledge-diagram`, `/kit:design` | above |
| 4. Micro-worlds (defer, selective) | inhabit not read | `interactive-concept-board` (builds exactly these) | agent invokes only for a genuinely complex subsystem; proportionality unsolved , not per-diff |
| 5. Shared space (defer, team-scale) | commentable Notion plans | `knowledge-capture` (Notion push) | a dfoundation-team move, not solo-kit |
| , Durable capture | (implicit) | `learning-ledger` -> `til` | the explainer's evergreen bits flush to til; understanding compounds instead of evaporating |

**Integration insight:** Han's LEARNING kit and SDD kit have been two separate worlds , one teaches
concepts, one ships code. Litt's argument is that after autonomous agents they must MERGE: the SDLC
must EMIT understanding artifacts, routed through the learning skills. `/kit:explain` is the bridge;
the quiz-as-merge-gate makes shipping and understanding one act.

**Hard design constraint (from Litt's caveat):** the quiz must be generated from the ACTUAL diff +
test results, NOT the agent's own narrative of them , or it teaches the agent's misconceptions.

## Two firing modes (Han 2026-07-03)

- **Inline / default:** the understanding-gate fires when something SIGNIFICANT is implemented (a
  significance classifier, sibling to lane-classify) , explainer+quiz at the gate, in-flow.
- **Weekend batch (option):** defer understanding to a weekend batch-learning session that collects
  the week's significant changes and routes them through the ops-toolkit learning kit
  (`learning-day-process` / `learning-ledger` / `deep-understand`), an improvement to the current
  learning skills. Matches Han's existing weekend-learning cadence.

## Refinement (2026-07-03, operator): conscious-debt budget + impl-notes as the feed

Han's operating model, self-described: default hands-off-on-code + coverage-focused, with SELECTIVE
deep engagement on "some cases". This is not the flaw the article warns about , it is a valid
strategy IF the debt is tracked. The reframe: the goal is not ZERO cognitive debt (impossible +
wasteful when shipping fast), it is CONSCIOUS, TRACKED, selectively-paid debt , managed like money
(you don't clear every balance the day it posts). The only real failure is UNTRACKED debt.

So the gate does NOT quiz every significant change (fatigue; fights the deliberate default). It is a
triage + a ledger:

- **Two signals:** significance (did a lot change) AND understanding-worthiness (will not-understanding
  cost a later loop? , new primitive future work builds on / irreversible / first-of-kind / high blast
  radius / must-explain-defend-decide). Tap ONLY high×high; wave+log the rest. The machine does the
  noticing so Han doesn't carry that load.
- **Three responses to a ★ tap:** engage now (explainer+quiz) / defer (weekend) / wave (accept
  knowingly). All logged to a debt ledger. A nudge, never must-pass-to-merge.
- **impl-notes are the agent-side FEED.** `docs/implementation-notes/<slug>.md` = the spec->reality
  delta (decisions the spec didn't pin down). Each entry is a high-worthiness candidate. This gives
  impl-notes a consumer, REVERSING the 2026-07-02 audit's write-only-drop finding (ID-234): keep +
  wire them. Pipeline: `impl-note -> worthiness-flag -> ledger (engage/defer/wave) -> paid down`.
- **The two flows are one system:** inline ★-tap for high-urgency understanding; the weekend batch is
  the debt PAYDOWN reading the deferred+waved ledger. Debt with a statement date.

Folded into ADR-0031 (Refinement) + the understanding-gate mega-goal (SG-02 two signals, SG-04 nudge,
SG-05 paydown). Resolves 2 of 3 open forks.

## Addendum (2026-07-03): context hygiene under /goal + the agent-driven ledger observatory

Two operator refinements from a session that hit 873k/87% context on a mega-goal run.

**Finding: the `claude -p` context-hygiene was bypassed by how we launch.** `orchestrate.sh run` is a
pure-bash driver that spawns a fresh `claude -p` per sub-goal (SPEC-087/ADR-0027) , the driver holds
zero LLM context. But EVERY mega-goal POINTER_PROMPT instructs `/goal` + paste, and `/goal` is an
IN-SESSION loop that accumulates all sub-goals in one context. The hygienic path exists but operators
are told to use the accumulating one. (Secondary trap: running `orchestrate.sh`/`claude -p` INSIDE a
claude Bash call pipes the child's stdout , the full stream-json transcript under `--stream` , back
into the parent context.)

**Fix (operator's steer , keep /goal, inject hygiene underneath):** `/goal` is the official,
Anthropic-maintained loop and stays the OUTER conductor; do NOT switch to `orchestrate.sh` as primary.
Instead change what the /goal loop DOES per turn: from "execute the sub-goal inline" to "DELEGATE the
sub-goal to a fresh headless `claude -p` (plain `-p`, NEVER `--stream`/`--verbose`) that runs the full
/spec->/execute->PR lifecycle in ITS OWN context and prints back ONLY a terse result (box flipped, PR
#N, proof path)." The /goal session absorbs one line per sub-goal, does the auto-bottom-up merge (it
sees all boxes), delegates TIER-4 the same way, and stays a thin conductor holding roadmap + terse
results (~tens of k, not 873k). The operator still interacts with /goal and course-corrects. Caveat:
bash-driven orchestrate.sh ENFORCES delegation; /goal-driven delegation relies on the model obeying a
forceful "delegate, don't inline" pointer clause. Implementation = a `plan-for-mega-goal` pointer-
template rewrite + the four existing pointers; zero code. orchestrate.sh gaps to note: no mega-level
TIER-4 close (operator/delegate runs it), and serial-path (WAVE_CAP=1) doesn't auto-merge (wave path
WAVE_CAP>=2, post-wavefront, does via mega-merge.sh).

**The ledger observatory is NOT a TUI (operator reframe).** The operator never opens an app , everything
goes through the Claude Code agent (or a web Artifact to share/review), and the CTA is new backlog rows
(a feedback loop). So the custom Go/bubbletea TUI is DELETED. The design collapses to an agent-callable
capability, the same shape as icy-ops/asus-mesh/growatt-pull (read-only CLI the agent drives + a skill):

```
ledgers -> DuckDB ETL -> `ledger` CLI (agent calls on demand) -> render:
                                                                  - terminal (bot-reply-formatting)
                                                                  - web Artifact (share/review)
                                                                -> FEEDBACK: anomalies -> work-intake -> board rows
```

Ledger inventory (2026-07-03): the KIT side is already schema-uniform , ~10 stores + the 2 planned
(debt, token) share one `ISO8601 | VERB | k=v` append-only marker under `~/.local/state/dwarves-kit/
logs/`, so one pipe-log reader drains the whole kit corpus. 3 bespoke outliers need small adapters:
`learned-ledger.md` (markdown), tide `state.sqlite` (DuckDB reads sqlite natively), tg-cleanup `*.json`
(DuckDB reads json natively). So ETL = a handful of DuckDB views + a refresh, NOT a custom engine.
Reuse `lane-telemetry` for the kit-side read; do not rebuild it. Feedback loop wires to `work-intake` +
the cockpit boards , the ledgers stop being write-only and start generating improvement backlog. Scope
= a tool + a skill (Phase 1 over existing ledgers; debt/token conform on arrival), NOT a 6-sub-goal
mega-goal. Sequence after the debt+token ledgers exist; build the tool in a FRESH session (this one hit
the very context ceiling the finding is about).

## Packaging

Design-record (Part 1) is small + explicitly asked , standalone kit change. The explainer+quiz
understanding-gate (Part 2) is a mega-goal (`understanding-gate`), run AFTER kit-face ships (dogfood
a production kit; don't stack ahead of need). Overlaps kit-face on mermaid (01) + viz (micro-worlds
~ lane dashboard); note, don't merge , different concern (production-front vs human<>agent
understanding).
