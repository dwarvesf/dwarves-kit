# Sub-goal 02: Seed skills-map so JIT hints fire on my real intents

**Time budget:** ~1-2h (config)
**Depends on:** none (cc-context already merged, PR #274)
**Branch:** feat/cc-elev-r2-02-skillmap
**PR base:** main

## Outcome

`tools/cc-context/`'s JIT skill-activation hint only helps if `skills-map.json` maps my real trigger phrases to my skills. Populate it from my installed skills (`~/.claude/skills` + enabled plugin skills) with high-value keyword -> skill pairs drawn from how I actually phrase things, so a prompt like "have I written about X" surfaces the right skill hint.

## Quality bar

Real pairs, not a toy. Covers my most-used skills. No false-fire: an off-topic prompt yields no hint. Data only; cc-context's hook logic is untouched.

## How to close the loop

- Enumerate installed skills; write `skills-map.json` mapping concrete keyword sets to skill names for the top skills.
- cc-context, given 3-4 sample prompts that should match, emits the correct skill hint; given an off-topic prompt, emits nothing (negative control).
- Lane via lane-classify; extend `tools/cc-context/docs/proof-of-done.md` with the seed + a fire/no-fire run.

**Done =** `skills-map.json` holds real keyword->skill pairs for my top skills; cc-context emits the correct hint on matching sample prompts and stays silent off-topic; proof updated; on PR #NN.

## Scope edges

**In:** `tools/cc-context/skills-map.json` + proof update.
**Out:** changing cc-context's hook code/logic; authoring new skills.
**Not:** mapping all 87 skills exhaustively (cover the high-value set; note coverage in the proof).

## Where to look

`~/.claude/skills/*/SKILL.md` descriptions (trigger phrases), enabled plugins, the existing `skills-map.json` shape, cc-context's matching logic.

## PR body

Outcome: seed cc-context's skills-map.json with real keyword->skill pairs so JIT skill hints fire on my actual phrasings.
Verify: sample matching prompts emit the right hint; off-topic emits nothing.
Roadmap: `_meta/megagoals/cc-elevation-r2/ROADMAP.md` (sub-goal 02).

## Notes
