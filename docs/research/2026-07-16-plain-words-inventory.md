# Plain-words inventory, kit-wide jargon scan (2026-07-16)

Goal (Han): after this, everything the kit produces uses the simplest words
possible, so onboarding a user requires zero new concepts. Precedent
calibrated against: edge→profile, surface/spoke/sources→app, hub→board
(rename + legacy alias, config keys + docs only). Scan by a read-only
subagent over README/AGENTS/WORKFLOW/MANUAL, commands + help text, kit.toml,
module-registry, and all recurring terms; persisted here by the lead.

## Top 10 renames worth doing (onboarding-pain × rename-cheapness)

| # | Rename | Why | Cost |
|---|---|---|---|
| 1 | spoke → **app** | finish today's rename; "spoke" survives in 17 files | config-alias sweep |
| 2 | grill → **interview** | slang; unguessable ("the one-question-at-a-time interview") | command + alias |
| 3 | leg → **stage** | coined word for what every PM calls a stage | docs + registry + ADR-0034 amendment |
| 4 | spine → **core** | "core" is the everyday word for the always-on base | docs |
| 5 | cockpit → **dashboard** | aviation metaphor; mostly absorbed into sync already | docs + verb |
| 6 | brownfield → **existing codebase** | industry jargon, reference tables only | docs |
| 7 | SDD → **spec-driven** (spelled out) | bare acronym on the onboarding path | docs |
| 8 | wave → **batch** | "a batch of sub-goals run at once" | config-key + alias (`wave_cap`) |
| 9 | tier → **level** | plain rung/step word | config-key + alias (`tier4_close`) |
| 10 | RID → **run id**; posture → **mode** | unexpanded acronym; dressed-up "mode" | docs / config-alias |

**High-pain but semantic-everywhere (stage as their own projects, NOT doc
sweeps):** mega/mega-goal → roadmap (532/336 files), lane → risk level (647),
gate → check (1016), ledger → log/history (780), harness → kit (319).

## The five legs (Specify / Execute / Observe / Govern / Learn)

Key finding: ADR-0034 decision 3 made legs **metadata, never module renames**, the names live only in the module-registry leg column + 3 docs + the
`bin/config list` renderer + one lint. Blast radius = docs + one table + one
lint + a mandatory ADR-0034 amendment. NOT semantic-everywhere.

| Current | Proposed | Verdict |
|---|---|---|
| Specify | **Shape** | rename ("Plan" collides with the planning loop-type + writing-plans skill; "shape" already used in-repo) |
| Execute | **Build** | rename, clear win, the PM word |
| Observe | **Watch** | rename, mild win |
| Govern | **Check** | rename, clear win ("Govern" is the most corporate of the five); "Guard" if Check reads too close to verify |
| Learn | **Learn** | KEEP, already plain, and more accurate than "Improve" (the leg distills, it does not itself improve the product) |

Recommended plain set: **Shape / Build / Watch / Check / Learn**, container
word **leg → stage**. Recipe: amend ADR-0034 → registry leg column (old names
as parenthetical aliases one release) → README/WORKFLOW/data-flow prose + two
mermaid diagrams → `bin/config list` strings + registry-lint assertions.

## Full inventory

Cost legend: docs = docs-only · cfg = config-key + alias · sem =
semantic-everywhere (40+ files). Counts = files containing the term.

| term | count · main homes | plain meaning | candidate | cost | call |
|---|---|---|---|---|---|
| spoke | 17 · README, registry | an app you sync the board to | app | cfg | rename |
| grill | 136 · commands, AGENTS | the task-intake interview | interview | cmd+docs | rename |
| leg | 74 · README, registry, ADR-0034 | one of the 5 stages | stage | docs+ADR | rename |
| spine | 71 · AGENTS, install | the always-on base hooks | core | docs | rename |
| cockpit | 74 · README, registry | the Hermes dashboard view | dashboard | docs | rename |
| brownfield | 21 · README, WORKFLOW | an existing codebase | existing codebase | docs | rename |
| SDD | 89 · AGENTS, PHILOSOPHY | spec-driven development | spell out | docs | rename |
| wave | 266 · mega, `wave_cap` | a batch of sub-goals run at once | batch | cfg | rename |
| tier | 137 · `tier4_close` | a level of the close sequence | level | cfg | rename |
| RID | many · AGENTS, ledger | run id from the branch slug | run id | docs | rename |
| posture | few · `mega_merge_posture` | merge mode | mode | cfg | rename |
| over-suggest | 52 · advisor | advisor's extra-ideas mode | extra suggestions | docs | rename/glossary |
| tombstone | 12 · lib docs | removed-item marker | removed-marker | docs | rename |
| mega/mega-goal | 532/336 | multi-objective program | roadmap | sem | own project |
| lane | 647 · classify, ship-gate | task risk-size setting ceremony | risk level | sem | glossary; own project |
| gate | 1016 · everywhere | a checkpoint at a boundary | check | sem | glossary ("quality gate" is quasi-standard) |
| ledger | 780 · gate/telemetry | append-only run record | log/history | sem | glossary; long-term log |
| harness | 319 · README, PHILOSOPHY | the whole kit machinery | kit | sem | standardize on "kit" |
| proof-of-done | 323 | re-runnable evidence of done | proof | sem | keep (self-explaining) |
| dispatch | 384 · queue | hand work to a worker | send/hand off | sem | glossary |
| lens | 345 · review-team | a review angle | angle | sem | glossary |
| orchestrate | 247 · queue | run sub-goals coordinated | coordinate | sem | glossary |
| verifier | 240 · agents | read-only checker agent | checker | sem | glossary |
| worktree | 237 | git worktree |, | sem | keep (git-standard) |
| mirror | 150 · sync | copy the board out | copy/sync | sem | glossary |
| retro | 148 | retrospective |, | sem | keep (agile-standard) |
| adopt | 131 | inject the kit contract | set up | sem | keep |
| promote | 123 · board | approve staged item onto the board | approve | sem | glossary |
| snapshot | 110 | point-in-time capture |, | sem | keep |
| scaffold | 100 | generate starting structure | skeleton | sem | glossary |
| intake | 90 | where new work enters | inbox | sem | keep |
| triage | 75 | sort incoming items | sort | sem | keep (standard) |
| registry | 176 | lookup table/manifest |, | sem | glossary |
| advisor | 229 | suggest-only review agent |, | sem | keep |
| spec-drift | 41 | code diverging from spec | spec mismatch | cfg+docs | glossary |
| quiz-gate | 57 | understanding-check nudge | understanding check | cmd+docs | glossary |
| writeback | 38 · legacy bridge | sync back to the source | sync back | cfg | rename during ID-290 port |
| surface | 431 · pervasive | operator-facing entry point | context-dependent | sem | glossary (sync-target sense already → app) |

Minor/glossary-only: spanner, wavefront, fan-out, V-model, descent, DEBT
(keep, standard), contract (keep), manifest (keep), staging (plain enough).

Keep-because-standard: worktree, retro, triage, snapshot, debt, kanban,
backlog, cron, PR/branch/commit.
