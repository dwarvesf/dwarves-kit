# Sub-goal 04: surface-consolidation

**Merge policy:** auto
**Time budget:** 1 day of loop work (plus a small dotfiles-repo companion PR)
**Proof:** run-table (SPEC-194): (a) `bin/learn debt list|collect|mark-paid` green on the SPEC-126 fixture; (b) `bin/session observe|intel|recall|report|semantic` each green on its tool's existing smoke test; (c) `bin/board promote` green on the add-backlog fixture; (d) a BEFORE/AFTER bin/ census table (11 mixed-grammar entries -> the ADR's target list, complete: spec/goal/stats/mega/queue entries exist); (e) cross-repo grep-audit: ZERO references to `lib/queue/weekend-batch.sh`, `bin/session-*`, or bare `add-backlog` in dwarves-kit, dotfiles, AND ops-toolkit shims. NCs: every retired path/entry provably dead (invoking each fails, captured), proving no silent alias survived. Ladder rung 2.
**Design:** obvious (the design is ADR-0034 §1/§7/§8; this executes it)
**Depends on:** 01
Model: sonnet
**Branch:** `feat/loop-04-surface-consol` (+ dotfiles branch `fix/kit-bin-repoint`)
**PR base:** master

## Touches

bin/ (regroup: new `learn`, new `session` dispatcher, five `session-*` retire, `add-backlog` folds into board, missing subsystem entries created), lib/learn/ (new), lib/queue/weekend-batch.sh (moves out), skills/ (stats-skill relocation per ADR §8), install.sh (CLI-shim wiring for renamed entries), tests/, docs/consumer-contract.md; CROSS-REPO: dotfiles source for weekend-debt-paydown + learning-router + session-observe skills (repoint only); ops-toolkit `_meta/board`/`board-all` UNTOUCHED (already on `bin/board`)

## Outcome

The ADR-0034 target surface EXISTS, in one PR wave: (1) `lib/learn/` holds the relocated weekend-batch; `bin/learn` is the stable entry (`learn debt <list|collect|mark-paid>` today; `propose`/`drain` stubs REFUSE with a "ships in SPEC-195/196" message, never silently no-op). (2) `bin/` speaks ONE grammar: the five `session-*` CLIs collapse into `bin/session <verb>`; `add-backlog` folds as `board promote` (plus whatever single human-typed alias the ADR kept); `spec`/`goal`/`stats`/`mega`/`queue` get their missing entries; module CLIs keep module names per the two-class rule. (3) The stats skill lands where ADR §8 put it. Every consumer repoints (dotfiles skills, vps-mon heartbeat caller, install.sh shim list); no alias shims anywhere (kit-modularity precedent).

## Quality bar

A regroup, not a rewrite: every tool's behavior, flags, and outputs are byte-level unchanged; only paths and entry grammar move. The before/after census table + grep-audit are the artifacts a reviewer trusts. After this PR, `ls bin/` READS like a kit.

## How to close the loop

1. `git mv lib/queue/weekend-batch.sh lib/learn/` (history preserved); build `bin/learn` + `bin/session` dispatchers per the bin/board shape; create missing subsystem entries; fold add-backlog per ADR.
2. Repoint every call-site: `rg -n 'queue/weekend-batch|bin/session-|session-observe|session-intel|session-recall|session-report|session-semantic|add-backlog' --hidden` in dwarves-kit, dotfiles (chezmoi source, apply + stage + commit in ONE shell call per the S-64 watcher rule), and ops-toolkit; record the before/after table. install.sh CLI-shim list updated in the same commit.
3. Run each surface's existing tests through the NEW entries; capture the run-tables.
4. NCs: each retired path (`lib/queue/weekend-batch.sh`, each `bin/session-*`, bare `add-backlog` if retired) exits non-zero, captured.
5. Full suite green, both repos.

**Done =** the ADR target census is REALITY (before/after table matches), all run-tables green through the new entries, three-repo grep-audit clean, every retired path provably dead, suites green.

Kit-adopted repo: record gates via `bash lib/gate/gate-ledger.sh` per lane plan before the PR push. The dotfiles companion PR links this one.

## Handoff on completion

1. Flip ROADMAP box + PR #s (kit + dotfiles). 2. HANDOFF.md: 06 unblocks now (needs 01+04); 05 needs 01+02+04, so it unblocks only once 02 is also merged; 05 first action = read ADR-0034 §2 + the kit-retro contract. 3. DECISIONS.md: the final verb table for bin/learn. 4. EXIT.

## Scope edges

**In:** the weekend-batch move, the full bin/ regroup (collapse, fold, complete), skills relocation, call-site repoints (three repos checked, two edited), install.sh shim wiring, consumer-contract.md update.
**Out:** propose/drain implementations (05/06), any tool behavior change, module renames, the scheduler (10).
**Not:** folding harvest/backlog-stage hooks into lib/learn (they stay capture-side per ADR-0034), a `kit` uber-dispatcher (rejected in kit-modularity SG-03; the ADR does not reopen it), "improving" any tool while moving it.

## Where to look

ADR-0034 §1 (approved text wins over this file on any conflict); `lib/queue/weekend-batch.sh`; `bin/board` (the entry shape to copy); SPEC-184; the two dotfiles skills' SKILL.md.

## PR body

Surface consolidation per ADR-0034: bin/ regrouped to one `<subsystem> <verb>` grammar (session-* 5->1, add-backlog -> board promote, missing entries created), lib/learn subsystem with weekend-batch relocated, stats skill relocated, all call-sites repointed (companion dotfiles PR #<n>), zero aliases. Verify: before/after census table + grep-audit + per-surface run-tables in the proof-of-done. Roadmap: `_meta/megagoals/harness-loop/ROADMAP.md` SG-04.

## Notes

- 2026-07-12 (from SG-01 advisor P5 #6): the Outcome's parenthetical "plus whatever single human-typed alias the ADR kept" resolved to NO alias; ADR-0034 decision 7 rejects keeping one. The approved ADR text wins over this file on any conflict (this file already says so).
