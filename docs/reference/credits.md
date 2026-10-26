# Credits

Every pattern in the kit traces to a proven source ("Synthesize, don't originate", see [`PHILOSOPHY.md`](PHILOSOPHY.md)). Each row below points at a real tool. `/kit:absorb` audits this list for drift, and `/kit:kit-health` counts its citations. Adding a source here is the maintainer's call.

Patterns extracted from:

- [GSD v1 / get-shit-done](https://github.com/gsd-build/get-shit-done) - spec generation, the original planning-dir convention (since unified onto docs/specs/), parallel researchers. Distinct from GSD v2 ([gsd-build/gsd-2](https://github.com/gsd-build/gsd-2), npm `gsd-pi`), a separate standalone agent on the Pi SDK referenced as an external execution runtime, not a pattern source
- [gstack](https://github.com/garrytan/gstack) - /office-hours, /review, /ship patterns; the /kit:ui-design loop shapes (brief schema, injection-wrap, accumulated-feedback)
- [frontend-design](https://github.com/anthropics/skills) - the external UI generator /kit:ui-design delegates to; its aesthetic-direction brief shape
- [ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) - /kit:ui-design brief sub-shapes (token ladder, states matrix, a11y bars, voice); generator + tooling rejected per bash-over-binaries
- [Trail of Bits](https://github.com/trailofbits/claude-code-config) - hook implementations, code quality rules, statusline pattern
- [ClaudeKit](https://github.com/mrgoonie/claudekit-skills) - validation gate, adversarial review, session-state pattern
- [Context Hub](https://github.com/andrewyng/context-hub) - API docs skill
- [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) - HUD/statusline, slop-cleaner pattern
- [Claude-Code-Game-Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) - /start router, path-scoped rules, Collaborative Design Protocol
- [Smart Ralph](https://github.com/smart-ralph) - fix-agent retry pattern (fail-fix-re-verify loop)
- [mattpocock/skills grill-with-docs](https://github.com/mattpocock/skills/blob/main/skills/engineering/grill-with-docs/SKILL.md) - /kit:grill mechanics: one-question-at-a-time with recommended answers, glossary/ADR write-as-you-go, the 3-criteria ADR bar, contradiction-first interviewing
- [repository-harness](https://github.com/hoangnb24/repository-harness) - the FEATURE_INTAKE flag-count lane-classification model (hard-gate + soft-count + auditable `explain`), the `@AGENTS.md` CLAUDE.md import shim, adopt `--dry-run`/`--refresh` modes, and the decision-capture-at-reflect flow (advisory). The enforcing dual of our enforcing/CC-only kit; absorbed 2026-06-10, see `history/2026-10-27:docs/absorption/2026-06-10-repository-harness.md`
