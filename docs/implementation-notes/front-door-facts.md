# front-door-facts: implementation notes

Delta from the audit slice. Facts only; no restructure, no slimming.

## Decisions the audit did not settle

- Session module cell: fixed the cell (added `batch-debt-warn`, "8 hooks + 1 CLI") instead of dropping counts. `lib/config/modules.tsv` lists 9 hook entries for 8 distinct scripts (`harvest` wires twice).
- Requirements heading: added `### Requirements` before Option 1 and shortened the Option 3 sentence to point at it. The installer's error text already says "README: Requirements"; install.sh is not in this slice, so it is unchanged.
- Duplicate `## [1.6.0]` in `docs/CHANGELOG.md`: tag `v1.6.0` is dated 2026-05-22, so that heading keeps its name. The older 2026-05-20 block became `## [1.6.0-pre]`.
- v2 roadmap: kept the heading and the three items still unbuilt (prompt-type Stop hook, `/qa`, intra-spec parallel dispatch). Rewrote the harness line to "native loaders for the commands, agents, and skills on other harnesses", since Codex already gets the five hard controls.
- MANUAL stage index: `/kit:wrap` under Reflect (it owns the distill half), `/kit:battery` and `/kit:greenlight` under Check, `/kit:feature-map` under Shape, `/kit:gauntlet` under meta. README's table uses other labels (Verify, Ship, Land); the MANUAL index follows the five stages.
- `rules/` paragraph: `install.sh` step 6 copies into `.claude/rules/` of the cwd and skips existing files. A compat-only run exits before that step and the plugin path never copies. The paragraph says both.
- AGENTS.md keeps the bare file name `WORKFLOW.md` in the source-of-truth list (Pause if): it names a file, not a heading citation.
- Wave claim (MANUAL `/kit:dispatch` gotcha): qualified with the `/kit:mega` orchestrator's waves (`WAVE_CAP` default 2) rather than rewritten.
- AGENTS.md override line uses `~/.claude/dwarves-kit/bin/gate proof-ledger override`, per the coordinator, matching the guides.

## Pins and generated files touched

- `tests/test-meta-contract.sh` pinned "Enforcement is Claude-Code-only". The rewritten boundary is the truth, so the pin now checks the three tiers.
- `test-adopt` checks `lib/adopt/agents-known.sha256` against `git log -- AGENTS.md`. Regenerated with `lib/adopt/known-hashes.sh` in its own commit. Entries key on content hash, so the list stays valid after a squash. Drop that commit and regenerate if AGENTS.md changes again before landing.

## Skipped

- Audit rows 19 (three install paths) and 22 (spec and ADR IDs in README prose) are structural; left for the README rewrite.
- Rows 1, 5, 23 belong to other slices.
- `test-codex-hooks` fails on the base (hook content-hash pins for secrets-guard and ship-gate); no hook file is in this diff. Not fixed here.

## Open questions

- `commands/*.md` ship in the plugin; `docs/WORKFLOW.md` resolves against the kit root, like the other repo-relative paths in those files.
