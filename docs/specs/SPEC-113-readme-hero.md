# SPEC-113: README hero + parity pin

Status: VALIDATED
Lane: normal
Type: spec-feature

## Problem

The README hero is a hand-drawn ASCII lifecycle, and its directory-layout counts are STALE:
`agents/ (11 files)` (live: 24), `hooks/ (14 scripts)` (live: 17). The 11-vs-live agents drift is
the exact class the mega-goal quality bar calls out ("died untested once; never again"). A new
external reader (OSS intent) meets a stale, hand-maintained hero. The mega-goal (roadmap:
ops-toolkit `_meta/megagoals/kit-face/`, assumptions 01) resolves this: a native-rendered mermaid
lifecycle + corrected, TEST-PINNED counts.

## Solution

1. **Mermaid hero** , replace the ASCII lifecycle block (README ~12-21) with a native ```mermaid
   flowchart: 6 phases (think -> spec -> execute -> review -> ship -> retro), a one-line role each,
   and the GATE CLASS at each boundary (two classes: **blocking** = the verification pipeline +
   ship-gate + push-to-main blocker; **advisory** = think/review). Reads in 10s on github.com; NOT
   the full V-model (that stays `docs/v-model.svg`, linked from WORKFLOW.md).
2. **Trust-story sentence** , one sentence folding in the kit-hardening upgrade (fresh-context
   re-audit + the advisor extra lens + deployable-done), NOT five feature bullets.
3. **Corrected + PINNED counts** , `agents/ (24 files)`, `hooks/ (17 scripts)` in the
   directory-layout; a NEW test-meta parity pin extracts the README layout counts and asserts them
   `== ls agents/*.md | wc -l` / `ls hooks/*.sh | wc -l` (SPEC-085 computed-pin shape), so the drift
   class dies like the hooks/commands pins did.
4. **WORKFLOW.md** keeps the ASCII canon (unchanged) and gains a `docs/v-model.svg` link (disposition
   of the orphaned asset).
5. Tighten prose only; Credits intact.

## Verification

```bash
cd dwarves-kit
# mermaid hero present, ASCII hero gone
grep -qF '```mermaid' README.md
! grep -qF 'goal --> think --> spec --> execute' README.md   # old ASCII hero removed
# 6 phases + two gate classes named
grep -qiE 'think.*spec.*execute.*review.*ship.*retro|retro' README.md
grep -qiE 'blocking' README.md && grep -qiE 'advisory' README.md
# counts corrected + PINNED (the parity pin computes, does not hardcode)
grep -qE 'agents/ *\(24 files\)' README.md
grep -qE 'hooks/ *\(17 ' README.md
# WORKFLOW links the svg (ASCII canon kept)
grep -qF 'v-model.svg' WORKFLOW.md
grep -q DEC README.md 2>/dev/null || true
bash tests/test-meta.sh   # green incl. the new README layout-count parity pin (agents + hooks)
```

## After state

- `README.md`: mermaid hero (6 phases, gate classes) replacing the ASCII lifecycle; trust-story
  sentence; `agents/ (24 files)` + `hooks/ (17 scripts)`; Credits intact.
- `WORKFLOW.md`: `docs/v-model.svg` link; ASCII canon unchanged.
- `tests/test-meta.sh`: a README-layout parity pin (agents + hooks counts computed from live files).
- `docs/verification/readme-hero.md`: the run-table + the GitHub-mermaid render check.

## Scope edges

**In:** README.md hero + counts, WORKFLOW.md svg link, the test-meta parity pin.
**Out:** docs index (02); MANUAL.md (already correct at 24 after 09).
**Not:** delegating README tables to MANUAL; a full-V-model diagram in the README; touching Credits.

## Open questions

The GitHub-render "capture" is verified by (a) valid ```mermaid fence syntax + (b) `gh api`
markdown-render returning 200 with the diagram, since a pixel screenshot is not capturable from the
loop; GitHub renders ```mermaid natively. The parity pin is the durable guarantee the counts never
re-drift (a screenshot rots; the pin does not).
