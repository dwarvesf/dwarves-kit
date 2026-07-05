# SPEC-122: static per-turn floor reduction (measure-then-trim, cockpit-aware)

Status: draft
Owner: Han (ops-toolkit + dotfiles)
Related: `_meta/megagoals/token-optim-v2/` (SG-05 + SG-09 ablations), `research/2026-06-29-token-optim-v2-eval.md`, `research/2026-06-29-token-coherence-design.md`, dotfiles PR #163 (SG-07)

## Problem

Every turn re-reads a fixed static context (via cache_read) before any work happens. Two
independent token-optim-v2 ablations (SG-05 planner-split, SG-09 orchestrator) both found this
**fixed floor dominates**: splitting a mega-goal into fresh sessions LOSES on small/medium work
because each fresh session re-pays the floor. So the floor itself, not session topology, is the
real lever. Lowering it also lowers the /clear crossover, making session-splitting pay sooner.

Measured user-controllable floor (this session, ~3.7 B/tok):

| Component | bytes | ~tok | loads in the ops-toolkit cockpit? |
|---|---|---|---|
| Skill descriptions (all incl. plugins) | ~126 KB | ~34k | yes (global) |
| Global `~/.claude/CLAUDE.md` | 45 KB | ~12k | yes |
| ops-toolkit `CLAUDE.md` | 23 KB | ~6k | yes (cockpit) |
| Memory indices (global + repo) | 34 KB | ~9k | yes |
| MCP surface | small | small | yes (deferred) |

**Cockpit constraint (decisive):** Han starts sessions in ops-toolkit (his cockpit). A lever only
helps his primary floor if its content loads IN the cockpit. Moving skills/CLAUDE.md INTO
ops-toolkit gives zero cockpit saving (he is already there); the win is trimming what loads in the
cockpit (the two CLAUDE.md files + memory + global skills), not relocating things into it.

## Goal

Cut the cockpit-loading static floor by ~10-15k tokens through measured, selective trims that move
genuinely-rarely-consulted content to its existing skill/doc home, WITHOUT touching always-consulted
content (Tool selection, security, machine routing). Build a floor-meter first so every cut has a
true before/after. Land deferred-skill-descriptions (the ~30k prize) as a written feature-request,
since it needs harness support.

## Approaches considered

- **Deferred skill descriptions** (load names, fetch on demand, mirroring `ToolSearch`): the biggest
  lever (~30k) but needs Anthropic harness support. Captured as a feature-request (Tier C), not built.
- **Per-project skill scoping** (move domain skills to their repos): only ~4.4k movable, and for a
  cockpit-first user it mostly de-noises OTHER repos, not the cockpit. Limited; do only the clear
  single-repo skills (Tier B).
- **Selective trim of cockpit-loading content** (CLAUDE.md sections + memory): the levers that
  actually load in the cockpit. Chosen as the primary Tier-A work.

## Design

Floor-meter first, then the cuts, grouped by leverage-for-the-cockpit. Each cut moves content that
(a) already has a skill/doc that fires when needed, and (b) is not consulted on a typical turn.

Outcome after execution + Han's decisions is in the rightmost column; the floor turned out to be
mostly LEGITIMATE content, so most items shrank or were rejected on measurement (not a failure , the
honest result, and the floor-meter is what proved it).

| # | Item | Repo | Mechanism | Outcome |
|---|---|---|---|---|
| 1 | **floor-meter** (foundation) | ops-toolkit | tool/script sums the real per-turn floor (skills + CLAUDE.md×N + memory + MCP names); JSON + table; before/after | **DONE** (baseline 53,489 tok) |
| 2 | **ops-toolkit CLAUDE.md trim** | ops-toolkit | Out-of-scope essay (dated history -> `out-of-scope-history.md`, decision kept inline) + git-worktrees dup -> pointer; keep Privacy/Mode/Tool-selection/LaunchAgent | **DONE** (-1,203 tok; no behavioral rule moved) |
| 3 | **memory compaction** | ops-toolkit | `doc-compaction` on `.claude/memory/MEMORY.md` | **RECLASSIFIED** , the 63 entries are curated recall, not bloat; needs a judged pass + Han, not an autonomous trim |
| 4 | **global CLAUDE.md trim** | claude-context generator | above-marker sections that have a skill -> pointers | **REJECTED** , ~325 tok = 0.6% of floor; not worth trading inline HARD-guarantee for skill HEURISTIC auto-fire (reliability > 0.6%) |
| 5 | **skill domain-scoping** | dotfiles + domain repos | move CLEAR single-repo skills to their `.claude/skills/` | **DROPPED** (Han: keep all skills global; cockpit win ~1.9k not worth losing skills from the cockpit) |
| 6 | **MCP per-project scoping** | runtime | scope peekaboo/macos-use off global | **DROPPED** (Han: keep 3 global; deferred-tools makes MCP ~32 tok) |
| 7 | **deferred skill descriptions** (feature-request) | research/ doc | written request mirroring `ToolSearch` deferral; NOT built (needs Anthropic) | **DONE as request** , the real ~24.5k lever, ZERO reliability risk (harness still auto-fires; only descriptions defer) |

## Acceptance criteria

1. floor-meter exists, runs, emits a per-component table + total; a baseline + post-trim reading
   are both captured (the proof).
2. Items 2-3 land in ops-toolkit; item 4 below-marker + 5 + 6 land in dotfiles (item 4 above-marker
   is proposed, not bulldozed, per the claude-context ownership); item 7 is a research/ doc.
3. Every trim KEEPS the always-consulted content (Tool selection, security/Privacy, machine routing,
   the adherence canary) , verified by grep post-render.
4. Each moved block points to its skill/doc home; nothing is deleted outright that lacks a home.
5. Measured before/after recorded for the cockpit floor; PR(s) opened. ops-toolkit ship-gate proof.

## Test

```
bash tools/floor-meter/floor-meter            # baseline, then re-run post-trim for the delta
# always-consulted survive:
grep -q 'Tool selection' ~/.claude/CLAUDE.md && grep -q 'Privacy rules' ops-toolkit/CLAUDE.md
tail -1 ~/.claude/CLAUDE.md | grep -q 'Neko-san' || echo "canary at top-section, not file-end (expected)"
```

## Notes

- Honest economics: Tier A (items 1-4) ~10k cockpit cut today; Tier B (5-6) helps non-cockpit
  sessions + cleanliness; Tier C (7) is the real ~30k prize but gated on Anthropic.
- Sensitivity: the global CLAUDE.md above-marker + the skill moves change Han's daily surface;
  measure + show the diff, do not bulldoze (the SG-07 lesson, memory `feedback_keep_critical_claude_md_inline`).

## Review

Date: 2026-06-29 · Files reviewed: 12 (one code file: `tools/floor-meter/bin/floor-meter`; rest
docs) · Reviewers: security, architecture, test-coverage. All findings MEDIUM/LOW (no CRITICAL/HIGH,
so no validator pass needed). Every actionable finding was FIXED in this PR; the verdict moved from
FIX-THEN-SHIP to SHIP-ready.

| Finding | Lens(es) | Sev | Conf | Route | Status |
|---|---|---|---|---|---|
| Dedup gap: global CLAUDE.md double-counts for `--root` inside `~/.claude/` (g not added to `seen`) | test-coverage | MEDIUM | 75 | gated_auto | **FIXED** (`seen.add(g)`; `--self-check` guards it) |
| Auto-memory path-slug is a reverse-engineered seam; silent 0 on format drift | architecture + test (corroborated) | MEDIUM | 75 | gated_auto | **FIXED** (seam comment + warn-on-miss to stderr) |
| MCP `* 40` anonymous magic number | architecture | LOW | 75 | gated_auto | **FIXED** (`MCP_BYTES_PER_NAME`) |
| `~/.claude.json` full dict bound to `d` (holds token values); only keys used | security (informational) | INFO | 100 | advisory | **FIXED** (inline key extraction, no bind) |

### Security
**SECURE.** No critical/high/medium. Confirmed read-only, no writes/network/exec, leaks nothing:
the three secret-adjacent files (`~/.claude.json`, SKILL.md, MEMORY.md) yield only key names / byte
sizes / single description lines, never credential values. `baseline.json` is clean.

### Architecture
**8/10.** floor-meter is a DEEP module for its size (2-flag interface hiding 4 distinct CC-layout
knowledge claims; deletion test passes, no shared state). Two findings (both fixed). CLAUDE.md trim
judged correct (essay -> pointer, history preserved in `out-of-scope-history.md`).

### Test coverage
**6/10 -> improved.** Primary claim (cockpit-awareness) was well-verified by the negative control's
exact arithmetic. Caught the one structural bug (dedup) + edge gaps; all now covered by `--self-check`
+ the added Reproduce edge cases (`--root ~/.claude`, `--root ~`).

### Scores
Security ~9 · Architecture 8 · Test-coverage 6 (pre-fix) · Combined ~7.7 → **SHIP** after fixes.

### Verdict: SHIP (held open for Han's end-of-wave review, gate-stacked)
