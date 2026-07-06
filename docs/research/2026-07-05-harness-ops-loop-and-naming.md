---
title: "Harness ops: the five-leg feedback loop, the done-condition ladder, and the script naming convention"
date: 2026-07-05
purpose: >
  Canonical snapshot of the harness-ops concepts Han and Claude converged on
  2026-07-05: (1) the Specify -> Execute -> Observe -> Govern -> Learn loop
  mapped onto the existing stack with a maturity audit; (2) the done-condition
  strength ladder (shipped to the goal-authoring skills, dotfiles #203-#206);
  (3) the naming convention + census + rename plan for the small-script sprawl.
status: reference
---

# Harness ops: loop, ladder, naming

Three concepts, one session (2026-07-05). Each section states the concept, where it
is enforced (the canonical home), and what is still open.

## 1. The five-leg harness feedback loop

```
Specify ──► Execute ──► Observe ──► Govern ──► Learn ──┐
   ▲                                                    │
   └────────────── feedback closes the loop ────────────┘
```

| Leg | Ours today | Maturity |
|---|---|---|
| Specify | SDD kit (spec -> validate), goal-craft, plan-for-goal, done-ladder | strong |
| Execute | `/goal` loops, mega conductor, overnight queue (mega-runner #705, being superseded by kit `orchestrate.sh queue` per the 2026-07-05 re-plan) | strong |
| Observe | gate-ledger, ledger-observatory (mega-durations, review-yield, `redteam` rows), queue journal | built, young |
| Govern | ship-gate/proof-gate, merge policy auto/gate, launch guards, secret-guard, allow-lists, `--max-cost-usd`, ladder rung selection | strongest |
| Learn | learning-ledger, cc-harvest -> `backlog-staging.md` -> `add-backlog` (human gate), absorb-ideas skill, advisor P6 -> NOTES | weakest: event-driven, fires only when Han pushes |

**Learn-leg closure (decided):** a recurring `kit-retro` goal in the overnight queue
(weekly or per-3-megas): read observatory + gate-ledger + closed megas' `NOTES ##
Proposed additions`, distill via the **absorb-ideas skill** (NOT `/kit:absorb`, which is
kit-internals-scoped per dotfiles #199), stage candidates to `backlog-staging.md`.
The retro never edits the kit/skills/CLAUDE.md directly; `add-backlog` stays the human
gate. Pre-staged sub-goal: `_meta/megagoals/kit-wiring/goals/kit-retro.md` (#706);
its first live run doubles as the rung-4 cost checkpoint reading.

## 2. The done-condition strength ladder (pointer)

Canonical home: the byte-identical `<!-- BEGIN done-ladder -->` block in
`goal-craft/SKILL.md`, `plan-for-goal/SKILL.md`, and
`plan-for-mega-goal/references/subgoal-template.md` (dotfiles #203, metering #204,
property/fuzz + lens matrix #205). Summary only (the block is the source of truth):
four rungs (assertion -> named negative controls -> independent re-execution ->
adversarial verdict), rung picked by RISK/blast radius, never size; rung 4 =
in-harness skeptic on the frozen diff vs the PR base, verbatim `VERDICT: SECURE`,
fail-closed, cap 3 rounds, every round a `redteam` gate-ledger row. Cost measured
2026-07-05: ~88k tokens/round, ~25-30% of an average sub-goal, expected on 1-2
sub-goals per mega (net +3-10%/mega, partly offset by rung-keyed ceremony cuts).
Origin: generalizes the dotfiles `secret-guard-printer-context` goal (auditor rounds
until VERDICT SECURE). Over-test is rung 2, still the mandatory floor for
significant changes; it stopped being the ceiling.

Mega tiers were also named in the same pass (dotfiles #206), uniform `TIER N (name)`:
0 operate root, 1 framing, 2 decompose, 3 build-to-proof, 4 convergence gate.

## 3. Script naming: census, convention, rename plan

2026-07-05 inventory (Explore agent, full table in the session transcript; counts
approximate): ~24 `cc-*` PATH commands (dominant harness prefix), 29 dwarves-kit
`lib/*.sh` uniformly `<subject>-<role>.sh`, hooks mostly `<subject>-<role>.sh`,
tools clusters `*-deploy` (~14) and `*-ops` (4). The sprawl is real but concentrated
at the edges: two unprefixed cc-elevation tools (`meta-agent`, `prose-rag`), one
alias sprawl (`md-preview`/`mdp`/`markdown-preview`/`md-open`, the last a STALE
symlink into a dead worktree), lone abbreviations (`mdp`, `dgst`, `verif-counts.sh`),
one snake_case executable (`validate_topology.py`), and the backlog cluster (below).

### The convention (4 rules)

1. **Namespace by surface.** Harness PATH commands = `cc-<name>`. Repo lib (invoked
   by path) = `<subject>-<role>.sh`, no prefix. Hooks = `<subject>-<role>.sh`.
   Tool dirs = `<object>-<role>`.
2. **Role suffixes are a closed vocabulary; the suffix states the behavior class:**
   `-gate` (can block you) · `-guard` (blocking hook) · `-ledger` (append-only
   record) · `-classify` (routing decision) · `-observe`/`-report` (read-only) ·
   `-sync` (two-place reconciliation) · `-runner` (drains a queue) · `-bridge`
   (connects two systems) · `-deploy` (deploy bundle).
3. **Verb-first only for human-typed action commands** (`add-backlog`,
   `verify-claim`); everything else noun-first.
4. **One canonical name, at most one alias, no new abbreviations, no snake_case
   executables.**

Enforcement home: ops-toolkit `CLAUDE.md` "Adding a new tool" + the `ops-tool-shape`
skill (new names conform at scaffold time; old names die by the plan below).

### Rename plan, by blast radius

| Class | Renames | When |
|---|---|---|
| Safe now | `meta-agent` -> `cc-meta-agent`, `prose-rag` -> `cc-prose-rag` (old-name symlinks kept a while); fix the stale `md-open` symlink; drop the `markdown-preview` alias (keep `md-preview` + `mdp`); `validate_topology.py` -> `validate-topology.py` | pending Han's nod on the map |
| After the live mega closes | dwarves-kit `verif-counts.sh` -> `verify-counts.sh` + kit docs sweep | own kit PR |
| Document, never rename | the backlog cluster (glossary below); skill names (auto-fire triggers); `cc-observe`'s 4-surface reuse (intentional) | glossary here |

### Backlog-cluster glossary (document instead of rename)

| Name | Role in the pipeline |
|---|---|
| `cc-harvest` / `cc-backlog` | session harvest -> auto-STAGE candidates into `_meta/backlog-staging.md` (gitignored) |
| `add-backlog` | the human gate: review staged candidates, PROMOTE onto the board |
| `_meta/BACKLOG.md` + `backlog.sh` (kit lib) | the board itself + its engine (states, render) |
| `board` / `board-all` (ops-toolkit `_meta/`) | per-repo / cross-repo render wrappers |
| `assign` (kit) | board row -> runnable goal draft |
| board `queue` / `mirror` / `writeback` | the 2026-07-05 re-plan consolidates these as kit `board` subcommands (runner-fastpath 04/07/08) |

Pipeline read: **harvest -> stage -> promote (`add-backlog`) -> board -> assign ->
queue -> run**. The names span two families (`cc-*` intake vs `board`/`backlog`
operate) because they sit on two surfaces (personal session tooling vs the generic
kit board). OPEN QUESTION, deliberately deferred: once the re-planned kit `board`
tool (queue/mirror/writeback subcommands) ships, decide whether the intake pair
folds in as `board stage`/`board promote` (one readable family, but drags personal
harvest machinery toward the generic kit) or keeps the `cc-` prefix with this
glossary as the map. Decide at the post-mega retro, not mid-flight; the consumer-
config seam (no personal data in the kit) is the constraint either way.

## Pointers

- Runner-fastpath re-plan (queue moves into the kit, mega-runner retired, board
  tooling consolidated): the mega's ROADMAP + goals `03K-kit-queue.md` /
  `03R-retire-runner.md` (Han's 2026-07-05 planning session).
- Done-ladder blocks: the three skills named above (dotfiles #203-#206).
- Learn leg: `_meta/megagoals/kit-wiring/goals/kit-retro.md` (#706).
- Naming survey raw table: session transcript 2026-07-05 (Explore agent output).
