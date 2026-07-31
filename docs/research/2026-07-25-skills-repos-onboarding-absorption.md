---
title: Absorption analysis, mattpocock/skills (delta) + zvadaadam/az-skills (full) + dev-tool onboarding patterns
date: 2026-07-25
purpose: >
  Three-part absorption record: (1) delta-read of mattpocock/skills since the
  2026-07-08 baseline, (2) first full deep-read of zvadaadam/az-skills,
  (3) onboarding-pattern survey of famous dev tools applied to the kit's
  "too many features, where do I start" problem. Verdict tables, smallest
  absorption designs, the continuous-tracking watch protocol, and the proposed
  first-30-minutes golden path. Checked against PHILOSOPHY §6 N1-N7.
source_repos: [dwarves-kit, ops-toolkit, dfoundation]
refresh_cadence: as-needed
next_review: 2026-10-01
status: active
---

# Skills repos + onboarding absorption (2026-07-25)

Prior touches (dedup gate): mattpocock/skills fully mined 2026-07-08
(ops-toolkit `research/2026-07-08-mattpocock-skills-design-patterns.md`, ID-119 shipped;
grill-with-docs -> /kit:grill, productivity/handoff -> handoff skill).
az-skills partially known: plan-for-mega-goal -> /kit:mega (kit ID-037),
noah-zender-it queued separately (ID-134, untouched here).

## Watch markers (continuous tracking, see §5)

| Repo | Signal to watch | Last seen (2026-07-25) | Cadence |
|---|---|---|---|
| mattpocock/skills | CHANGELOG.md version; re-read on MINOR bump or `Add/graduate/promote/rename .* skill` commit | v1.1.0 released; plugin/Codex/prototype/wayfinder changes are 9 unreleased changesets, next release = 1.2.0 (corrected 2026-07-31, see 2026-07-31-mattpocock-trio-adoption.md) | monthly |
| zvadaadam/az-skills | closed-PR titles (`Add * skill`) or PRs touching `scripts/install.sh`/`.githooks/` | PR #21 (Remove ai-journal) | quarterly |

# 1. mattpocock/skills delta since 2026-07-08

NOT a quiet window: ~44 commits, v1.1.0 + v1.2 (native CC plugin). New:
setup-ts-deep-modules (dependency-cruiser enforcement), to-questionnaire,
batch-grill-me; code-review promoted, wayfinder graduated. Mechanism edits:
wayfinder reframed onto native issue trackers (typed tickets
research/prototype/grilling/task, "fog of war", frontier queries
tracker-native); grilling gained a confirmation gate + facts-vs-decisions
split; prototype became a durable primary-source artifact; tdd went
reference-only; to-prd renamed to-spec, to-issues+to-plan merged.

New authoring patterns beyond the 07-08 baseline:

1. **Dual distribution**: editable-copy installer (`npx skills add`) AND native
   CC plugin (repo is its own single-plugin marketplace via
   `.claude-plugin/plugin.json` + `marketplace.json`), ADR 0002; Codex plugin
   deliberately deferred (manifest limitation).
2. **Dual-harness metadata**: every SKILL.md ships a sibling
   `agents/openai.yaml` so one body serves CC + Codex without duplication.
3. **Graduation includes storage migration**: wayfinder's in-progress->shipped
   move ALSO moved its state store (local md -> host issue tracker).

## Verdicts (per mechanism)

| Mechanism | Verdict | Where it lands |
|---|---|---|
| Dual distribution + dual-harness metadata | ABSORB (design input) | ID-396 packaging ADR prior art: exactly the "one core + generated per-host adapter" doctrine, live in the wild |
| Grilling confirmation gate + facts-vs-decisions split | ABSORB (tiny) | kit ID-404: /kit:grill separates facts (explore the codebase) from decisions (ask the human); won't proceed past shared understanding without confirm |
| Wayfinder typed tickets (research/prototype/grilling/task) | ABSORB (one line) | DF-151 card template gains an optional `type` field; typed cards route review depth |
| Wayfinder tracker-native storage / fog-of-war | PARK | tripwire: the Multica pilot outgrows flat cards and needs dependency/frontier queries |
| batch-grill "don't block the round" | SKIP | work-intake batch discipline already covers it |
| Graduation-with-storage-migration | SKIP (note) | matches the experiments->tools gradient; nothing to build |

# 2. zvadaadam/az-skills full read

46 stars, ~3.5 months old, bus factor 1 (agent-identity co-authors are the
maintainer's own runs), bursty cadence, 0 open issues, 21 merged PRs.
**License: NONE** , all-rights-reserved by default: mechanisms may be learned
and re-implemented; files must never be copied.

Catalog: 20 skills across engineering (call-advisor/call-worker, code-review,
code-simplifier, complexity-check, deslop, devs-roundtable, greenlight-pr,
pre-factor, repo-history-book, tour), design (design-roundtable,
brand-name-explore), marketing (ai-answer-audit, geo-optimize), productivity
(interview-me, plan-for-goal, plan-for-mega-goal, noah-zender-it,
skill-feedback). Onboarding machinery: NONE (flat category README; the one
nicety is install.sh's categorized summary print). Admitted failure modes:
plan-for-mega-goal's ghstack-missing 34-minute zero-PR run; greenlight-pr
designs two of four terminal states for degenerate cases.

## Verdicts (OVERLAP rows skipped: code-review, code-simplifier, interview-me, plan-for-goal, plan-for-mega-goal)

| Mechanism | Verdict | Why / where |
|---|---|---|
| **greenlight-pr**: autonomous PR-to-merge (CI-fix + bot-comment triage FIX/DISAGREE/DEFER + JSON snapshot state machine + 4 named terminal states + per-SHA retry budget) | **ABSORB (strong)** | kit ID-401. Serves N5 (hands-off middle) exactly where /kit:ship stops today (ship opens the PR; nothing drives an open PR through CI failures + review comments to merge-ready). The named-terminal-states + snapshot-per-tick shape also feeds ID-394's failure-semantics gap |
| **deslop**: dedicated AI-slop strip pass (redundant comments, over-defensive handling, unnecessary casts), surgical, behavior-preserving | ABSORB | kit ID-402: a deslop lens on the review/simplify surface. Serves the slop-gate strategy (DF-45 ph.3); complements delivery-ratio (which detects, doesn't fix) |
| Budget-capped resumable external-model calls (cost telemetry + session resume as contract) | ABSORB (design input) | note on kit ID-390 (multi-vendor dispatch, executing): the adapter's follow-up gains `total_cost_usd` emit + session-resume contract |
| repo-history-book: hierarchical commit->day->phase summarization + fact/interpretation ledger | PARK | tripwire: next narrate-log/narrate-experiment run where interpretation disputes arise; then absorb the fact/interp ledger only |
| Persona-divergence roundtables (N practitioners GENERATE N artifacts, converge; consensus=confidence, divergence=human decision) | PARK | different mechanism than lens critique (kit:devs-team critiques ONE design). Tripwire: a taste-critical design call where lens-critique consensus arrives comfortably fast (the repo's own tell that the answer is wrong) |
| complexity-check (4 lenses, 3-7 finding cap, "one-paragraph-defense" stop rule) | PARK | Ponytail + delivery-ratio cover the instinct. Tripwire: review telemetry (ID-392) shows complexity escaping the gates |
| ai-answer-audit + geo-optimize (AI-answer evidence audit -> citation strategy) | PARK | genuinely NEW domain. Tripwire: visibility-comms starts active GEO/AI-visibility work |
| tour (self-contained HTML architecture tours, explorer/synthesizer/critic) | SKIP | codebase-memory + zoom-out + /kit:explain cover the need; the HTML artifact is a nicety |
| skill-feedback (PostHog telemetry auto-wired into settings.json at install) | SKIP (anti-pattern for us) | silent settings.json mutation at install violates our consent-explicit stance; cc-observe stays local-only. Recorded as a caution for ID-396's install doctrine: an installer must never silently wire telemetry |
| brand-name-explore | SKIP | naming is website-brand skill territory; revisit only inside that skill's own iteration |

# 3. Onboarding patterns -> the kit

Full survey in the dispatched report (pattern taxonomy: scaffold-once wizard,
a-la-carte add-one-thing, convention golden path, tiered docs, doctor
diagnostic, ambient self-trigger, guided-tour-with-handoff, disabled-by-default
registry; exemplars shadcn/Astro/Rails/Laravel-Bootcamp/Stripe/Tailwind/
rustup/brew-doctor/flutter-doctor/git-status/Nx/oh-my-zsh/CC-marketplace/
superpowers/spec-kit). Key finding: **the kit already has the two hardest
mechanisms right** (/kit:start IS a doctor; /kit:onboard IS a
state-not-owning tour). The gap is framing + doc shape.

## Pickups (clustered into two kit rows)

**ID-400 (doc pass, one PR):**
1. README leads with ONE command path, not the module list: "`bash install.sh
   && /kit:onboard`. Everything else is discoverable later."
2. Kill the tutorial framing: "There is no tutorial to finish. Run /kit:start
   at the top of every session; it is always your onboarding."
3. `docs/QUICKSTART.md` (~10 lines): clone -> install -> onboard -> start ->
   first tiny-lane change -> ship. AGENTS.md stays the reference.
4. The add-one-module-later verb documented per module (shadcn-add shape:
   edit `.kit.toml`, `/kit:adopt --refresh`), so module #13 never needs
   re-onboarding.
5. Honest-disclosure convention generalized (the /kit:onboard plugin-gaps
   four-bullet treatment, applied wherever behavior differs by install mode).

**ID-405 (ambient self-suggest, small code):**
6. Modules suggest themselves from context (superpowers pattern, bounded):
   e.g. repeated errors suggest /kit:debug the way /kit:start already suggests
   from git state. Makes "12 modules" stop feeling like 12 decisions.

## The first-30-minutes golden path (goes into QUICKSTART)

```
0. git clone <kit>
1. bash install.sh          # no flags -> baseline spine, zero decisions
2. /kit:onboard             # once; Enter-Enter-Enter sane defaults; adopts THIS repo
3. /kit:start               # every session; doctor: state + ONE next action
4. pick a real small task   # ship something real, not a toy (Laravel Bootcamp lesson)
5. /kit:spec (tiny lane) -> 6. /kit:execute -> 7. /kit:review -> /kit:ship
8. back to /kit:start       # the diagnostic IS the onboarding, forever
```

AVOID (all confirmed against §1/§6): central init wizard owning module state;
a completable "tutorial mode"; leading with the full catalog; golden-path docs
with no live diagnostic behind them; adoption "levels" (phase gates in
costume).

## 3b. The zero-think onboarding design (Han's ask 2026-07-25: "they don't have to think")

Three moments, each with exactly ONE thing to do; education is embedded in the
doing, never a separate phase. Teammates never see the bash installer, the
module list, or a decision.

```
MOMENT 0 - RECEIVE        Han sends ONE message (the DF-152 2-pager ends with it):
                          "/plugin marketplace add dwarvesf/dwarves-kit
                           /plugin install kit
                           then open your repo and type /kit:onboard"
                          No clone, no installer, no choices.

MOMENT 1 - INSTALL        The plugin path (already shipped: .claude-plugin/
  (0 decisions)           plugin.json + marketplace.json v2.0.0). Managed
                          bundle, auto-current. The bash installer is demoted
                          to the maintainer/power path in all docs.

MOMENT 2 - ONBOARD        /kit:onboard in their repo: Enter-Enter-Enter
  (the education)         defaults, previews every write, adopts the repo
                          (4 PORTABLE files, needs ID-406), honest plugin-gap
                          disclosure, five-sentence tour. The tour IS the
                          lesson; nothing to read first.

MOMENT 3 - WORK           /kit:start at the top of every session: state + ONE
  (forever-onboarding)    next action. The doctor educates by always naming
                          the next step. First real task: tiny lane -> ship.
                          Onboarding never "completes"; it is the diagnostic.
```

Blocking gaps, in build order: **ID-406** (portable adopt: today's rendered
files carry /Users/tieubao/... paths, breaking Moment 2 on any other machine)
-> **ID-400** (docs say exactly this story, plugin-first) -> **DF-152** (the
Moment-0 message artifact). ID-405 (ambient self-suggest) deepens Moment 3
later. The install defect Han remembered as "symlinks" is actually
render-time path expansion in lib/adopt.sh (verified: no symlinks in adopted
repos; 2 absolute-path hits in ops-toolkit CLAUDE.md).

# 4. North-star alignment (§6 check)

ID-400/405 serve N7 (pickup cost, the 2/5 team dimension); ID-401 serves N5;
ID-402 serves N7's review economics; ID-403 (watch protocol) + ID-404 serve
N6; the dual-distribution prior art serves N4. No criterion conflicts found.
The skill-feedback SKIP is a §6-driven rejection (silent install-time
settings.json mutation breaks propose-never-dispose).

# 5. Continuous tracking (the "take care of slight improvements" ask)

No new daemon (minimum infra). The watch rides existing machinery:

1. Both repos registered as **/kit:absorb seed sources** (kit ID-403) with the
   watch signals + last-seen markers from the table at the top of this file.
2. /kit:absorb's seed-rescan (maintainer-run, existing) checks the two URLs:
   `raw.githubusercontent.com/mattpocock/skills/main/CHANGELOG.md` (MINOR bump
   = re-read entry) and
   `api.github.com/repos/zvadaadam/az-skills/issues?state=closed` (new
   `Add * skill` PR = read that skill).
3. Update the markers table here after each check, so the next check is a
   diff, not a re-read.
