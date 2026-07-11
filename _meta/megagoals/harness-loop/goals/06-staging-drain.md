# Sub-goal 06: staging-drain

**Merge policy:** auto
**Time budget:** 2-4 hours of loop work
**Proof:** (SPEC-196) run-table: `learn drain` rendered against a COPY of the real 69-candidate staging file (grouped, age-sorted, evidence-first) captured as a freeze-PNG + the raw text; expiry NC (fixture row aged 31d moves to `[expired]`, byte-diff shows nothing deleted); promote-unchanged NC (add-backlog fixture test green, untouched). Rung 2.
**Design:** obvious (render + a dated move within one file; ADR-0034 names the verb)
**Depends on:** 01, 04
Model: sonnet
**Branch:** `feat/loop-06-staging-drain`
**PR base:** master

## Touches

lib/learn/drain* (never propose*), lib/learn/staging-format* (IF first to merge, per the shared-fixture rule), lib/board/bin/add-backlog (only if the expiry index-skip needs it), tests/test-learn-drain*, docs/specs/SPEC-196*. Deliberately file-disjoint from SG-05 so the SPEC-106 wave can run both concurrently; the ONE overlap candidate (staging-format) is resolved by the first-to-merge rule, the second rebases.

## Outcome

Draining staged candidates becomes a 5-minute glanceable ritual: `learn drain` renders `_meta/backlog-staging.md` grouped by `Home:`, age-sorted oldest-first, one line per candidate (title · age · tags · evidence pointer), with the numbered index add-backlog expects, phone-legible (the stats terminal-formatter discipline). Rows staged >30 days move to a `## [expired]` section on each drain run, never deleted, count reported; add-backlog's promote/reject numbering skips expired rows.

## Quality bar

The render answers "what do I promote?" in one screen. A candidate's age and evidence are visible without opening the file; nothing is ever silently lost (expiry is a move + a count, byte-auditable).

## How to close the loop

1. Build `learn drain` (pure read + render; the ONLY write is the expiry move, flock-guarded like harvest post-#226).
2. Run against a copied real staging file; capture text + freeze-PNG.
3. Expiry NC: fixture with a 31d row + a 5d row; diff proves move-not-delete; re-run is idempotent.
4. add-backlog fixture: promote + reject still green; expired rows unselectable.

**Done =** drain render captured on real-shaped data + expiry NC diff + add-backlog tests green, in the committed proof-of-done.

Kit-adopted repo: record gates via `bash lib/gate/gate-ledger.sh` per lane plan before the PR push.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HANDOFF.md next = 09 (if 08 merged) else 10 prereqs. 3. DECISIONS.md: note the expiry constant landed in lib/learn/ per the pinned decision below. 4. EXIT.

## Scope edges

**In:** drain render, 30d expiry move (the window is a `lib/learn/` constant with a `--days` override, PINNED: never a kit.toml key, so this stays file-disjoint from SG-05's kit.toml edit and the parallel dispatch holds), add-backlog index-skip if needed, tests. Whichever of SG-05/SG-06 merges FIRST also lands the shared staging-block format fixture (one committed fixture + a small parse helper in lib/learn/); the second consumes it, so the `## [staged]`/`## [expired]` block edges have ONE definition.
**Out:** promotion logic changes, staging WRITE paths (backlog-stage.py, stats --propose), notification/nudge hooks.
**Not:** a TUI, an HTML drain surface (terminal is the ritual), auto-promote-anything.

## Where to look

`hooks/backlog-stage.py` (block format), `lib/board/bin/add-backlog` (index + promote mechanics), the real `ops-toolkit/_meta/backlog-staging.md` for shape (COPY it; never mutate the live file from tests), stats terminal formatter for the phone-legible discipline.

## PR body

`learn drain`: grouped, age-sorted, evidence-first staging render + 30d expiry-to-section (never delete); add-backlog flow unchanged. Verify: render PNG + expiry NC diff in the proof-of-done. Roadmap: `_meta/megagoals/harness-loop/ROADMAP.md` SG-06.

## Notes
