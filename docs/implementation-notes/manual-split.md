# MANUAL split: implementation notes

Delta from the task, not a mirror of it.

## Where each block went

| Block that left MANUAL | Home |
|---|---|
| Lifecycle and toolbox, closed loop, five stages, command sequence at a glance | new `docs/reference/lifecycle.md` |
| Install options and modules, requirements, the three install routes, plugin-aware install | new `docs/reference/install.md` |
| Skills table | new `docs/reference/skills.md` |
| Project structure | new `docs/reference/project-structure.md` |
| Testing, CI, weekly scheduler, external dependencies, codebase index | new `docs/reference/operations.md` |
| v2 roadmap | new `docs/reference/roadmap.md` |
| Credits | new `docs/reference/credits.md` |
| Verification pipeline | merged into `docs/reference/architecture.md` "Verification pipeline" |
| Who this is for and not for | merged into `docs/reference/PHILOSOPHY.md` "Fit check in plain terms" |
| Debug mode and hook logs | already in `docs/reference/hooks.md`; one sentence added there |

MANUAL keeps the conventions, the intent table, every `### /kit:<name>` section, the concurrency note, hooks, harvest sweep, agents, path-scoped rules, operator scenarios, the gate ledger CLI and troubleshooting. A closing table of links, "Where the rest lives", routes the old readers.

## Decisions the task left open

- Credits went to `docs/reference/credits.md`, not CONTRIBUTING. `/kit:absorb` parses the list as bullet links and `/kit:kit-health` counts them, so one page with only that list is the stable target. CONTRIBUTING stays a short rules page.
- The verification pipeline ASCII box was dropped, not moved. The architecture section already drew the same flow; the end verifiers, the orchestrator role and the sequential-versus-fan-out paragraph were the only extra facts and now sit in prose beside it.
- The teams-of-10 bullet in the fit check points at the paragraph above it in PHILOSOPHY instead of repeating where the line sits.
- The module table's Kind column lost its hook counts ("8 hooks + 1 CLI" is now "hooks + CLI"), and the repo-hygiene skill row lost "five". The five stages stay: that is a name, not a roster count.
- Spec and ADR ids left the moved prose. `lifecycle.md`, `install.md`, `skills.md` and `project-structure.md` carry them in one provenance footer, as CONTRIBUTING allows. `credits.md` dropped the A1 to A4 labels of the last row.
- `project-structure.md` named three docs paths that no longer exist (`docs/PHILOSOPHY.md`, `docs/architecture.md`, `docs/execution-planes.md`) and omitted `integrations/`, `templates/`, `output-styles/`, `deploy/`, `.codex-plugin/` and `kit.toml`. Both are fixed, since the doc-impact map sends new top-level entries there.
- The sentence in `docs/reference/architecture.md` that sent readers to "the README's The five stages" now links `lifecycle.md`; `workflow-paths.md` and `data-flow.md` had the same stale pointer.

## Pins

- `tests/test-meta-vmodel-dispatch.sh`: skills rows read `skills.md`, the five-stage table reads `lifecycle.md`, the board library mentions read `project-structure.md`, and the no-literal-counts scan also covers `project-structure.md` and `install.md`.
- `tests/test-repohygiene.sh`: the repo-hygiene row reads `skills.md`.
- `tests/test-meta-plugin-hooks.sh`: a comment names `install.md`.
- `test-kit-contract`, `test-meta-docs-registry`, `test-understanding-wiring` and `test-break-it` pin the agents table, the command sections and `/kit:explain`, which stay in MANUAL, so they needed no edit and are run as unchanged controls.
- `commands/kit-health.md` counts bullets in `credits.md`; `commands/absorb.md` and `docs/absorption/README.md` parse and cite it.

## Skips

- Dated records (specs, ADRs, research, retros, briefs, verification, implementation notes, releases) keep their old MANUAL wording.
- Ids that were already in the sections that stayed in MANUAL are untouched; only moved text was scrubbed.
- `tests/test-codex-hooks.sh` fails two assertions on origin/master itself (the hook command quoting change did not repin the commit-format hash). It is unrelated and left alone.
