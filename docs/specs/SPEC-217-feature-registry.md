# Spec: generated feature registry with freshness pin
Generated: 2026-07-31
Status: APPROVED (operator pre-approved design; adversarial validate overridden in the gate ledger)
Lane: full

Phase A of the feature-registry program (operator-approved design, dispatch prompt verbatim; Phase B is the feature-map audit-loop skill, its own spec). The kit exposes four feature kinds (commands, agents, skills, hooks) but has no single machine-derived inventory of them: `docs/workflow-paths.md` section 5 was hand-derived and will drift the moment the next feature lands, and the ID-452 campaign had to hand-enumerate coverage gaps. This spec adds a deterministic generator, `lib/registry/feature-registry.sh`, that scans the live tree and emits `docs/FEATURES.md` as a GENERATED projection, plus a `tests/test-meta.sh` freshness pin that fails on drift, the same class as the existing README/architecture derived-count pins. Bash + standard tools only (`grep`/`sed`/`awk`/`jq`, all already required by tests). No timestamps in the generated output: the pin diffs a fresh regeneration against the committed file, so any nondeterministic byte would be a permanent RED.

Trigger-class derivation (deterministic rules, no judgment):
- command with `disable-model-invocation: true` -> `[H]`; any other command -> `[H/I]`
- skill with `disable-model-invocation: true` -> `[H]`; any other skill -> `[I]`
- hook -> `[E]`, event(s) read from `hooks/hooks.json` (matched on `/hooks/<file>`); `statusline.sh` rides the `statusLine` key in `settings.json`, reported as `StatusLine`; a hook wired nowhere reports `-`
- agent -> `[D]`, dispatched-by derived by token-grepping `commands/*.md` for the agent name

## Acceptance Criteria
- [ ] AC-1: `bash lib/registry/feature-registry.sh generate [outfile]` writes the registry (default `docs/FEATURES.md`) and is deterministic: two consecutive runs produce byte-identical output.
- [ ] AC-2: the output is marked GENERATED with a no-hand-edit warning and the regenerate command, and carries one table per kind (Commands, Agents, Skills, Hooks); every live `commands/*.md`, `agents/*.md`, `skills/*/SKILL.md`, `hooks/*.sh` file appears exactly once.
- [ ] AC-3: each row carries kind, name, trigger class per the derivation rules above, a one-line description (frontmatter `description:` for commands/agents/skills, the header comment for hooks; truncated, pipes escaped), spec refs (SPEC-NNN files in `docs/specs/` mentioning the feature name as a token), and test refs (files in `tests/` mentioning it).
- [ ] AC-4: agents additionally carry dispatched-by (the `commands/*.md` files naming them); hooks additionally carry their event from `hooks/hooks.json`.
- [ ] AC-5: `tests/test-meta.sh` gains a freshness pin: regenerate to a temp file, diff against the committed `docs/FEATURES.md`, FAIL on any drift; the pin passes on the committed tree.
- [ ] AC-6: negative control: adding a dummy feature file makes the pin go RED; removing it restores GREEN.

## Test plan
Date: 2026-07-31. Dialect: executable-generator behavior, exercised through the freshness pin plus direct invocations.

| # | Case | Covers | Expected |
|---|---|---|---|
| 1 | generate twice, cmp | AC-1 | byte-identical |
| 2 | committed FEATURES.md vs fresh regeneration | AC-5 | diff clean, pin PASS |
| 3 | row count per kind vs `ls` count | AC-2 | equal, derived not hardcoded |
| 4 | dummy `commands/zz-dummy-feature.md` present, regenerate + diff | AC-6 | pin RED |
| 5 | dummy removed, regenerate + diff | AC-6 | pin GREEN again |
| 6 | wayfind row | AC-3 | trigger `[H]` (disable-model-invocation true) |
| 7 | safety-gate row | AC-4 | event `PreToolUse` |

## Verification
```
bash tests/test-meta.sh
```
Green, including the new `docs/FEATURES.md is fresh` pin. Negative control per AC-6 recorded in `docs/verification/feature-registry.md`.

## After state
`lib/registry/feature-registry.sh` exists; `docs/FEATURES.md` is committed and pinned fresh by `tests/test-meta.sh`; any future feature added without regenerating the registry fails the meta suite. Phase B (`skills/feature-map/`) consumes the generator as its Tier 1 mechanical check.
