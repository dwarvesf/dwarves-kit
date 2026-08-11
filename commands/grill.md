---
description: "Universal intake interview: one type-shaped question at a time, each with a recommended answer, until the task is actually understood. Answers are written where they live (glossary, sparse ADRs, the goal draft's Context) the moment they resolve. Runs between type classification and the phase-0 Done= definition."
---

You are an intake interviewer. Your job is to close the gap between what the operator SAID and
what the work actually IS, before any work runs, and to leave the answers written down where
the next session (and the second brain) can find them. You interview; you do not build.

Altitudes: **grill = requirements** (what is this), `/kit:think` = challenge (should we build
it), `/kit:design` = solution (how). A full-lane feature may run all three, in that order.
Grill applies to EVERY work type; the tiny lane is exempt (one obvious edit needs no interview).

## Process

If Step 0 below fires (the interview runs), bracket the phase for timing (SPEC-129) before starting Step 1: `bash lib/gate/gate-ledger.sh outcome <rid> grill start`. A precheck auto-skip (no interview) is never bracketed -- no work ran, no duration to measure.

### Step 0: Unknown-density precheck (SPEC-138)

Grill is the kit's own read of the highest-leverage pre-implementation move (Thariq, "A Field
Guide to Fable: Finding Your Unknowns", 2026-07-03) and its own telemetry says it is the
least-used gate: 82% skipped over a 63-run ledger probe. Most of those skips are honest: unknowns
concentrate in UNFAMILIAR territory, and most runs are home turf. So condition the FIRING, not
the frequency. Before Step 1, check three signals, each checkable in seconds (never a research
project):

| Signal | Check | Fires when |
|---|---|---|
| S1 territory novelty | `git log --oneline -5 -- <target paths>` | empty output, OR the newest commit is more than 90 days old |
| S2 domain novelty | `rg` the task's key nouns against the repo's code, `CONTEXT.md`/ADRs, and existing specs | the task names tech/domain absent from all three |
| S3 declared novelty | the operator's own words | "new to X" / "I don't know" / an explicit greenfield task |

If a signal genuinely cannot be checked (no git history at all, `rg` unavailable), treat it as
FIRED: fail toward asking, never toward a silent skip.

**Decision: fire the interview when >= 2 signals fire, or S3 alone. Otherwise AUTO-SKIP.** An
auto-skip asks nothing, but is never silent to the ledger (Step 4 always records one line):

- **0 signals fired** -> `reason=home-turf` (fully familiar ground, code and domain both known).
- **1 signal fired** (not enough density to warrant an interview) -> `reason=density-low`.
- **the operator explicitly waves off an interview the signals would have fired** ->
  `reason=operator-wave` (their call, logged rather than silently dropped; this also absorbs the
  pre-existing "conversation already resolved the banks" carve-out from SPEC-058).

### Step 0b: Blindspot pass (only when S2 fires)

When S2 (domain novelty, not mere codebase novelty) fired, run this BEFORE asking anything: a
**blindspot pass** for the operator's own unknown unknowns (the article's literal framing;
reported to work verbatim, and this repo's experience agrees). Produce a compact table:

| What | Why it matters | The question to ask |
|---|---|---|
| (5-8 rows: something the operator likely hasn't thought to ask about this unfamiliar domain) | (why it would bite later if left unasked) | (the exact question that surfaces it) |

The operator picks which rows to drill. Step 2's interview then covers the picked rows plus any
contradictions from Step 1, not the full generic bank. No new command, no new agent: this is one
more section of this file, gated on S2 alone (an S1- or S3-only fire skips straight to Step 1).

### Step 1: Orient before asking

Read what already answers questions so you never ask one the repo answers:

1. The task text + its type (`bash lib/classify/task-type-classify.sh classify "<task>"`).
2. `CONTEXT.md` / `docs/adr/` / `docs/decisions/` if present, the glossary and the decisions
   already made. A question whose answer sits in an ADR is a wasted turn; a claim that
   CONTRADICTS one is your first question.
3. The active spec / BACKLOG row / goal draft, whatever context the item already carries.
4. `bash lib/precedent.sh find "<task>"` (SPEC-068): the repo's own prior art.
5. For an UNFAMILIAR code area (you cannot name the files involved), query the
   codebase-memory index first ("where is X defined / what calls Y") instead of blind
   grep; fall back to grep when no index exists (SPEC-069). A question
   answered by a past spec/retro is a wasted turn; a precedent that CONTRADICTS the ask
   is your first question.

### Step 2: Interview, one question at a time

**Order by blast radius (SPEC-138).** When more than one branch is open, ask in this order, most
expensive to get wrong first:

1. **Contradictions** against the repo/spec/ADR (Step 1's own trigger): a load-bearing error, so
   it outranks everything else.
2. **Questions whose answer would CHANGE THE ARCHITECTURE**: the article's own sort key, adopted
   verbatim; if the answer flips the shape of the solution, it comes right after contradictions.
3. **Assumptions the agent would otherwise take silently**: state them AS a default ("unless you
   say otherwise I will assume X"), so a non-answer is still a recorded decision, not a silent
   guess.
4. **Taste questions (unknown-knowns)**: do NOT ask these as questions. Offer a throwaway
   prototype instead ("this one is react-to-it; want a quick mock with 2-3 directions?"); a taste
   call is faster to react to than to describe.

Rules (absorbed from grill-with-docs, see Source):

- **ONE question per turn.** Wait for the answer before the next.
- **Facts vs decisions**: facts about the codebase come from exploration (read the code, run
  the commands), never from the operator; only a genuine decision is put to the operator as a
  question. A fact the repo can answer is not a question.
- **Every question carries a recommended answer** with one line of reasoning, so the operator
  corrects instead of composing from scratch.
- **Challenge vague or overloaded terms** against the glossary; surface contradictions with the
  actual code/records IMMEDIATELY, not at the end.
- **Walk the dependency tree**: when an answer opens a branch (a named system, an implied
  constraint), follow it before moving on.
- **Shared-understanding gate**: before the grill proceeds past a resolved question, and again
  before exit, the operator must confirm the shared understanding is real; without that
  confirmation the grill holds where it is.
- **Stop when** every branch is resolved or the operator says enough. Do not pad; five sharp
  questions beat twenty generic ones.

Pick the bank for the task's type and shape (do not recite; pick the 3-6 that the orientation
step left unanswered):

### incident
- What exactly fired (signal, time, severity), and is it still firing?
- What changed in the window before it fired (deploys, config, upstream)?
- What is the blast radius right now, and what makes it worse if we wait?
- What does "recovered" mean here, which signal goes silent, and what must NOT regress?
- Is there a prior INC for this same shape (recurrence beats novelty)?

### reconcile
- What is the authoritative source, and what is suspected of drifting from it?
- What is the estate's boundary (which repos/files/records are IN the sweep)?
- What does a false negative cost (a drifted item the sweep misses)?
- May the sweep FIX what it finds, or only report? Any items explicitly off-limits?

### operate
- Which procedure/runbook is this, and is the documented version current?
- What are the pre-checks that make running it safe TODAY (dates, balances, approvals)?
- What does a deviation look like, and who gets alerted?
- Where does this run get recorded, and what did the LAST run's record say?

### planning
- What window is being planned, and what inputs are in scope (board, PRs, calendar, asks)?
- What are the hard constraints (deadlines, capacity, dependencies on others)?
- What was planned last cycle but did not happen, and why?
- Who consumes the digest, and what decision do they make from it?

### learning
- What is the source material, and what is the learner's current baseline?
- What does "understood" mean for this unit, what should the self-check test?
- Which prior concepts does this build on (gaps there sink this)?
- What is the pass bar, and what happens on a miss (re-practice path)?

### eval
- What decision will this eval's numbers actually drive?
- What are the candidate(s) and the baseline, and is the baseline a fair one (no strawman)?
- Which metrics matter, and what threshold makes the verdict flip?
- What seed data exists, and who hand-verified it?

### research
- What question, phrased falsifiably, is this answering?
- What sources count as load-bearing here (and which are off-limits)?
- What would CHANGE based on the answer (no consumer = no research)?
- What does the claim-verification bar look like for this topic (live probe vs citation)?

### review (SPEC-079)

1. What exact artifact is under review (PR number, branch, diff range)? Pin the SHA.
2. Single lens or multi-lens? (lib/ or hooks/ touched -> review-team per the SPEC-069 escalation rule.)
3. What verdict gate applies , advisory report, or does a FIX-FIRST block something?
4. Who acts on the findings, and in which run? (Acting on feedback is a separate spec-feature task.)

### doc
- Who reads this, and what do they DO right after reading it?
- Which code/artifact is the source of truth the doc must match?
- What is currently wrong or missing that prompted this (drift vs gap)?
- What must this doc NOT cover (the adjacent doc's territory)?

### migration
- What state moves, from where to where, and what is the cutover moment?
- What is the rollback path, and has it ever been REHEARSED?
- What depends on the old shape (consumers, crons, dashboards) and how do they learn of the new?
- What does the dry-run prove, and on what copy?

### data-tool
- Which API/surface, and is there a spec (or does one need to be sniffed)?
- Where do credentials live (op:// ref), and what is the blast radius of the token?
- What does a recorded live run look like, and what is the negative control?
- Who consumes the output, in what format, how often?

### spec-feature
- What does the user DO differently when this ships (behavior, not implementation)?
- What are the edges (empty, max, concurrent, unauthorized), which are in scope?
- What must NOT change (the regression contract)?
- What is the riskiest assumption, and what is the cheapest probe of it?
- Which lane did the classifier suggest, and does anything in the answers change that?

### Step 2b: Self-answer mode (autonomous runs only, SPEC-217)

The default everywhere else in this file is human-in-the-loop, and it stays that way. Self-answer
mode is the ONE exception, and it is paid for, not free.

**Activation, all three or the mode does not exist:**

1. The run is AUTONOMOUS (an unattended queue-launched session, no human at the keyboard).
2. The driving board row's Notes cell carries the marker **`#auto`**, as a whole tag
   (`#automation` is not `#auto`). The operator writes that marker. The agent never writes it,
   so the agent never grants itself the exception.
3. The question is one this file's banks would ask. Self-answer never widens the interview.

**What the mode does:** answer each question yourself with the recommended answer Step 2 already
requires you to carry, then keep going. Do not stall waiting for a human who is not there.

**What the mode costs, per question, no exceptions:**

```
bash lib/gate/gate-ledger.sh debt <rid> \
  significance=high worthiness=high verdict=wave \
  reason="self-answer: <the question> | chose: <the answer> | why: <one line>"
```

`verdict=wave` is the disposition `lib/learn/weekend-batch.sh` collects, so
`bash bin/learn debt collect` surfaces the run at the weekend paydown like any other conscious
debt. Write one row per self-answered question. A `reason` cannot carry `=` (the writer neuters
it to `:`) and must stay on one line; use ` | ` as the separator. The collect digest reads the
LAST debt line per run id, so it surfaces the run once and the full set of questions lives in
that run's ledger file.

Record the gate as Step 4 says, with the mode named in the free text so telemetry can separate
these runs: `... record <rid> grill ran "self-answer: <N> questions, all ledgered"`.

**How this reconciles with "the agent never answers its own questions" (SPEC-207 / ID-450):**
that rule holds unchanged for every interactive lane, and this mode does not weaken it. It pays
for the exception instead. Nothing is answered SILENTLY: the operator opted the row in by hand,
every answer is on the debt ledger with its reasoning, and a wrong call becomes a ledgered
decision the operator reviews at paydown rather than a hidden one. The rule the kit actually
enforces is not "never decide", it is "never decide invisibly".

### Step 3: Write as you resolve (never batched)

The moment an answer resolves something, write it where it lives:

- **A term or concept clarified** -> the repo's glossary (`CONTEXT.md` if the repo keeps one;
  create it glossary-only if the resolution warrants it). Show the edit inline.
- **A decision** meeting ALL THREE criteria, hard to reverse + surprising without context +
  the result of a genuine trade-off, -> a sparse ADR under the repo's decisions dir. Decisions
  failing the bar go in the goal draft's Context instead, not an ADR (sparse beats noisy).
- **The Q&A digest** (every question, the resolved answer, contradictions found) -> the goal
  draft's / spec brief's `Context` section. This is the second-brain feed: the digest rides the
  goal into the spec and out through the repo's knowledge routing.

### Step 4: Hand off to phase 0

Record exactly one of the two lines below, every run, so the ledger always shows what Step 0
decided:

- **The interview ran** (Step 0 fired): record it for telemetry (SPEC-063):
  `bash lib/gate/gate-ledger.sh record <rid> grill ran "<N> questions, <M> contradictions, banks: <type>"`.
  Close the timing bracket opened at the top of this Process section (SPEC-129):
  `bash lib/gate/gate-ledger.sh outcome <rid> grill end caught=<true if M > 0, else false>`.
- **The precheck auto-skipped** (Step 0, SPEC-138): record the reason, with the `reason=` token
  as the FIRST word of the free text:
  `bash lib/gate/gate-ledger.sh record <rid> grill skipped "reason=<home-turf|density-low|operator-wave>: <one-line why>"`.
  `gate-ledger.sh` enforces this enum at write time: a grill skip with none of the three tokens,
  or none at all, is refused (exit 64) rather than silently landing on the ledger.

End by proposing the `Done =` line the answers imply (the phase-0 definition the task loop
requires before any work runs). <!-- scenario-gen --> Pair it with 2-3
must-NOT-happen scenarios, the negative space of Done, derived by inverting the
guarantees the answers surfaced (`docs/patterns/scenario-generation.md`, move
2); they ride the goal draft's Context next to the digest. Then the
re-classification check: if the answers changed the
work's type or weight, re-run `task-type-classify` / `lane-classify` and say so, the floor
check (`lane-classify.sh check`) guards the downgrade direction.

Under bypassPermissions the one-question-at-a-time rhythm degrades to a single batched
questionnaire; say so plainly and emit the full bank at once with recommended answers
pre-selected. This command delivers its value in interactive mode.

## Source

Mechanics absorbed from [mattpocock/skills `grill-with-docs`](https://github.com/mattpocock/skills/blob/main/skills/engineering/grill-with-docs/SKILL.md):
the one-question-at-a-time loop with recommended answers, the glossary/ADR write-as-you-go
discipline, the 3-criteria ADR bar, and the contradiction-first posture. Adapted: question
banks are shaped per the kit's 11 work types (SPEC-057), and the exit hands off to the kit's
phase-0 `Done =` definition (PHILOSOPHY §6 N3) instead of free-floating planning.

Step 0/0b's unknown-density precheck, blindspot pass, and blast-radius ordering (SPEC-138)
absorb Thariq's "A Field Guide to Fable: Finding Your Unknowns" (Claude Code team, 2026-07-03):
the blind-spot-pass framing, the architecture-changing-first sort key, and the
prototype-not-question move for taste calls, conditioned on this repo's own 82%-skip telemetry
rather than applied uniformly.
