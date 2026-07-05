---
title: Absorbing "A Field Guide to Fable, Finding Your Unknowns" into the kit
date: 2026-07-04
purpose: >
  Design note for absorbing Thariq's (Claude Code team, Anthropic) Fable field guide
  into dwarves-kit + the mega-goal machinery. Diffs each of his techniques against what
  already exists, then designs the four absorptions worth building: grill
  unknown-density conditioning + blindspot pass, a deviation-rate lens for
  ledger-observatory, a batch of one-line template/contract absorptions, and the
  /kit:pitch buy-in assembler. Use it as the design source for backlog rows
  ID-247/248/249/250.
source_repos: [ops-toolkit, dwarves-kit, dotfiles]
refresh_cadence: none
next_review: null
status: active
---

# Absorbing "Finding Your Unknowns" (Thariq, 2026-07-03)

**Source:** https://x.com/trq212/status/2073100352921215386 (X Article: "A Field Guide
to Fable: Finding Your Unknowns"; fetched via the fxtwitter API 2026-07-04). Author is
on the Claude Code team at Anthropic; published the day Fable 5 launched.

**Core thesis:** the map (prompts/skills/context) is not the territory (codebase, real
constraints); the gap is *unknowns*. Fable is the first model where output quality is
bottlenecked by the operator's ability to clarify unknowns, not by model capability.
Techniques are organized by phase (pre / during / post implementation) over the
Rumsfeld 2x2 (known-known, known-unknown, unknown-known, unknown-unknown).

## Verdict table

| His technique | Phase | We have | Verdict |
|---|---|---|---|
| Blind spot pass (find MY unknown-unknowns) | pre | research agents map the codebase for Claude, not for the operator | ABSORB (Design 1, step 0) |
| Brainstorm + throwaway HTML prototypes | pre | brainstorming skill, think phase, Efferd default | have; absorb the "N wildly different directions to react to" move for taste work |
| Interview, one question at a time, architecture-changing first | pre | `/kit:grill` IS this (contradiction-first) but 82% skipped over 63 runs | ABSORB the conditioning, not more frequency (Design 1) |
| References over description (point at source code, cross-language ok) | pre | ad-hoc habit | ABSORB, spec template field (Design 3) |
| Plan ordered by likelihood-to-change | pre | specs are section-ordered | ABSORB, template ordering rule (Design 3) |
| implementation-notes.md with Deviations | during | have STRONGER (delta-from-spec, hook-enforced, per-spec file) | absorb only the worker default: conservative + log + keep going (Design 3) |
| Pitches / explainers for buy-in | post | proof-of-done + PR bodies, partial | ABSORB (Design 4, `/kit:pitch` assembler) |
| Quiz before merge, merge-blocking | post | understanding-gate shipped 2026-07-04: /kit:explain, quiz-gate star-tap, debt ledger, weekend paydown | have, deliberately weaker (nudge+debt over block, for time-to-done); keep |

We are ahead of the article during/post. The absorbable value is pre-implementation,
exactly where the gate ledger says the kit is thinnest in practice.

## Design 1: grill unknown-density conditioning + blindspot pass (ID-247, dwarves-kit)

**Problem.** `/kit:grill` is the article's highest-leverage technique and our
least-used gate (82% skip over the 63-run ledger probe). The skips are mostly honest:
unknowns concentrate in UNFAMILIAR territory and most runs are home turf. So the fix
is the trigger, not the frequency: fire grill when unknown-density is high, skip
silently (with an auditable reason) when it is not.

**Mechanic: a 3-signal precheck** in `commands/grill.md`'s preamble (instructions, not
code; the signals are things the agent can check in seconds):

| Signal | Check | Fires when |
|---|---|---|
| S1 territory novelty | `git log --oneline -5 -- <target paths>` | empty, or newest commit > 90d old |
| S2 domain novelty | task nouns absent from the repo (rg) and from existing specs/ADRs | the task names tech/domain the repo has never seen |
| S3 declared novelty | operator says "new to X" / "I don't know" / greenfield task | explicit |

Fire the interview when >= 2 signals fire, or S3 alone. Otherwise auto-skip and emit
the reason.

**Emit change (small, kit-side):** the gate-ledger skip line gains a
`reason=<home-turf|density-low|operator-wave>` token. This is what makes the skip
auditable: ledger-observatory can then separate honest skips from ceremony instead of
reading a bare 82% skip-rate. The reader for this token rides ID-245's `kit_gates`
per-gate table (same parse that picks up `caught=`).

**Interview reshape (ordering by blast radius):**

1. Contradictions first (already the grill contract).
2. Questions whose answer would CHANGE THE ARCHITECTURE (the article's line, adopted
   verbatim as the sort key).
3. Assumptions the agent will otherwise take silently, stated as defaults ("unless you
   say otherwise I will assume X"), so a non-answer is still a decision.
4. Taste questions (unknown-knowns) are NOT asked as questions: offer a throwaway
   prototype instead ("this one is react-to-it; want a mock with 3 directions?").

**Blindspot pass = step 0, conditional on S2.** When DOMAIN novelty fired (not mere
codebase novelty), run a blindspot pass BEFORE asking anything: a compact table of 5-8
unknown-unknowns, each row = what / why it matters / the question the operator should
be asking. Operator picks rows to drill; the interview then covers picked rows +
contradictions only. Use the literal words "blindspot pass" and "unknown unknowns"
(the article reports the literal framing works; matches our experience). No new
command, no new agent: one section in grill.md.

**Ceremony-detector tie-in:** ID-245's ceremony anomaly conditions on `caught` and
fix-correlation; with `reason=` it gains its first legitimate-skip whitelist. A gate
skipped with `reason=density-low` on runs that later show zero fix() correlation is a
CORRECT skip, evidence the conditioning works; density-low skips FOLLOWED by fixes in
grill-shaped areas (interfaces, data models) are the signal to loosen the threshold.

## Design 2: deviation-rate lens (ID-248, ledger-observatory; extends ID-245)

**Thesis bridge.** The article's frame: defects ORIGINATE as unclarified unknowns
upstream. Our benchmark work measures defects CAUGHT downstream (gate-yield,
defect-correlation). The bridge metric already exists on disk and nobody reads it:
hook-enforced `docs/implementation-notes/<slug>.md` files log every mid-run deviation.

```
unknowns upstream          mid-flight              downstream
(grill/spec quality) ---> deviations logged --->  gate catches / fix() escapes
     Design 1              THIS LENS                ID-245 (shipped scope)
```

**Adapter `impl_notes`** (new, same read-only delete-and-rematerialize contract):
glob the configured repo roots for `**/docs/implementation-notes/*.md`, parse per
file:

| column | type | source |
|---|---|---|
| repo | VARCHAR | root the file was found under |
| slug | VARCHAR | filename stem (spec-slug by the hook contract) |
| n_deviations | INTEGER | count of `## YYYY-MM-DD HH:MM` entry headers |
| zero_marker | BOOLEAN | the "No deviations; matches <spec> verbatim" line present |
| first_ts / last_ts | VARCHAR | min/max entry timestamps |

Single-sourced in `schemas.py` like the existing three tables (`column_names()` /
`ddl()` / `assert_parity`).

**Query `deviation-rate`** (CLI command, `--json|--table`): per slug, `n_deviations`
JOINed against `git_fixes` (the git-log adapter ID-245 change 3 already introduces;
this is why 248 sequences AFTER 245's adapter) on same-files-later-window. Three
classifications:

| class | rule | reading |
|---|---|---|
| UNDER-SPECCED | n_deviations >= 3 | spec phase too thin; grill should have fired (feeds Design 1 threshold) |
| CLEAN | 0 deviations, no later fixes | map matched territory |
| SUSPECT | zero_marker set AND later fix() commits on the same files | notes dishonest, or unknowns escaped past the notes |

**Anomaly `unknown-density`** (extends `anomalies.py DEFAULTS`, propose-not-autofile
as shipped): rolling median n_deviations over the window above threshold proposes
"condition grill ON for this repo/domain" via the cc-backlog staging buffer.

**Negative control (load-bearing, mirrors the ceremony NC):** a zero-marker file with
NO later fixes must NOT be flagged SUSPECT. Honest zero-deviation runs are the
success case; flagging them teaches people to stop writing the marker.

**Sequencing:** lands as change #5 in
`tools/ledger-observatory/docs/benchmark-followup.md`, same PR family as ID-245
(needs `git_fixes`; `impl_notes` itself is independent and can land first).

## Design 3: one-line absorptions batch (ID-249, cross-repo)

| # | Change | Where | Line |
|---|---|---|---|
| 1 | `References:` optional spec field | dwarves-kit spec template (+ spec-validate treats as optional, NO gate) | pointer to code/doc that implements the wanted semantics + one line on what to imitate; source code beats description, cross-language ok |
| 2 | Change-risk plan ordering | same template, Design/Plan section instruction | order by likelihood-you'll-tweak: data models, public interfaces, UX flows first; mechanical refactors last |
| 3 | Worker unknowns policy | `_meta/megagoals/OPERATE.md`, one bullet under Worker checkpoint discipline (+ the portable skill copy when ID-246 lands) | mid-run unknown not covered by the sub-goal: pick the conservative option, log it under Deviations in the implementation-notes file, keep going; never stall the wave |

All three are template/contract edits with no code and no gate changes; ship first
(zero dependencies).

## Design 4: `/kit:pitch` buy-in assembler (ID-250, dwarves-kit)

**Problem.** Thariq's post-implementation move: package the prototype + spec +
implementation notes into ONE doc for buy-in, because approvals accelerate when (a)
reviewers who start with your original unknowns get them pre-answered, and (b) experts
see you accounted for the failure points THEY would have anticipated. We ship the raw
ingredients on every gated run (spec Problem/Solution, proof-of-done run-table,
implementation-notes Deviations, grill Q&A once ID-247 lands) but nobody assembles
them for a third-party audience. PR bodies are written for the merger; a Dwarves
teammate, a client, or an approver needs a different ordering.

**Design stance: an ASSEMBLER, not a writer.** The pitch generates nothing new; it
re-audiences artifacts the run already produced. `/kit:explain` (shipped in
understanding-gate) is the INWARD lens (operator understanding, quiz at the end);
`/kit:pitch` is the OUTWARD lens (third-party buy-in, ask at the end). Same diff, two
audiences, so a thin separate command (`commands/pitch.md`), no new lib.

**Doc shape (outcome-first, per the article's "lead with the demo"):**

| # | Section | Assembled from |
|---|---|---|
| 1 | Outcome | what shipped, one paragraph; demo/screenshot/prototype link if one exists |
| 2 | Unknowns we accounted for | grill answers (ID-247 record), impl-notes Deviations + how each was resolved, the proof's negative controls (= the failure points an expert would probe) |
| 3 | Evidence | proof-of-done confirmation run-table verbatim + PR links |
| 4 | Cost / not-done | deliberate exclusions, known ceilings (from spec Out-of-scope + ponytail markers) |
| 5 | The ask | what approval/decision is requested |

Section 2 is the load-bearing one and is EXACTLY the three data sources Designs 1-3
formalize; missing sources degrade gracefully ("no grill record for this run").

**Trigger: on-demand + a conditioned ship-time offer.** A pitch on every ship would be
ceremony (the exact thing the benchmark work kills). Two entry points:

1. `/kit:pitch <rid|spec-slug>` any time (primary; also works for teammates via the
   portable kit).
2. One advisory line in `/kit:ship` Step 8, AFTER the SPEC-136 `significance-classify
   record` + `quiz-gate tap` calls: if the just-recorded verdict has
   `significance=high` AND the repo is team-shared (dfoundation, client repos; never
   solo ops-toolkit runs), print "significant outward change: `/kit:pitch <rid>`
   assembles the buy-in doc". Advisory, exit-0, never blocks, mirrors the tap
   anti-fatigue posture.

**Output + boundaries:** markdown to stdout + `--out <file>` (paste into Discord/PR/
client email by hand). NEVER auto-posts anywhere (no chat/ticket writes unbidden); an
HTML surface can come later via the Artifact tool if a client-facing case demands it.

**Sequencing constraint (live, 2026-07-04):** dwarves-kit `feat/ug-record-at-ship`
(SPEC-136, in flight in a concurrent session) is editing ship.md Step 8 right now,
wiring the `record` verb this design's ship-time offer READS. ID-250 lands strictly
AFTER SPEC-136 merges: same seam, and the significance verdict it conditions on does
not exist on a live path until then.

## Deliberately not adopted

- **Merge-blocking quiz.** Understanding-gate chose nudge + debt ledger + weekend
  paydown over a hard block, a time-to-done tradeoff made deliberately this week.
  Revisit only if quiz-gate telemetry shows waves clustering on high-risk diffs.
- **HTML-artifact-everything.** The Artifact tool + render surfaces already cover the
  visualization leg.

## Rollout order

1. **ID-249** one-liners (no deps, minutes).
2. **ID-245 + ID-248** as one PR family (kit_gates -> gate-yield -> git_fixes ->
   defect-correlation -> impl_notes -> deviation-rate -> anomalies).
3. **ID-247** grill conditioning (kit-side, independent; its observability lands with
   the 245/248 readers).
4. **ID-250** pitch assembler (kit-side; strictly after SPEC-136
   `feat/ug-record-at-ship` merges, it reads that verdict and shares the ship.md
   Step 8 seam).
