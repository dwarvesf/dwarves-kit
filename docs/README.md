# docs/, the kit's documentation

To use the kit, read the repo [`README.md`](../README.md) and [`QUICKSTART.md`](QUICKSTART.md) first. The rest of this folder is guides, reference and the record of how the kit was built through its own workflow. Specs, ADRs and retros are history for maintainers; nobody needs them to get started.

Two install-time facts. `lib/adopt.sh` (`/kit:adopt`) seeds `[gate] proof_of_done = true` and `lane_gates = true` into a fresh `.kit.toml`, so an adopted repo has both gates on; a raw `install.sh` leaves every gate off. `install.sh` and `lib/adopt.sh` also run the one migration of old kit logs into the durable ledger root (`lib/telemetry/kit-migrate.sh`).

## Entry docs

| Path | What it is |
|---|---|
| [`QUICKSTART.md`](QUICKSTART.md) | Install, adopt a repo, run your first `/kit:` cycle |
| [`MANUAL.md`](MANUAL.md) | The command reference: every command and agent, plus how to drive the kit by intent and recovery steps |
| [`WORKFLOW.md`](WORKFLOW.md) | The lifecycle contract: lanes, gates and loops (root `WORKFLOW.md` points here) |
| [`SYSTEM-DESIGN.md`](SYSTEM-DESIGN.md) | The system design model, rendered as the UML set in `design/` |

## Guides

| Path | What it is |
|---|---|
| [`guides/`](guides/README.md) | Task guides: adopt, the spine, debug, review, wrap, gates and proof, gauntlet, loops |
| [`guides/queue-run-runbook.md`](guides/queue-run-runbook.md) | Operator runbook: dispatch, monitor, review and close out an `#auto` row |

## Reference

| Path | What it is |
|---|---|
| [`reference/architecture.md`](reference/architecture.md) | Components, state model and the verification pipeline |
| [`reference/lifecycle.md`](reference/lifecycle.md) | The loop, the closed-loop idea, the command sequence and the five stages |
| [`reference/install.md`](reference/install.md) | Install layers, the module table, plugin, Codex and bash install |
| [`reference/skills.md`](reference/skills.md) | The skills roster |
| [`reference/project-structure.md`](reference/project-structure.md) | The directory layout of the kit repo |
| [`reference/operations.md`](reference/operations.md) | Testing, CI, the weekly scheduler, external tools and the codebase index |
| [`reference/roadmap.md`](reference/roadmap.md) | Work the kit defers on purpose |
| [`reference/credits.md`](reference/credits.md) | Where each pattern came from; `/kit:absorb` audits it |
| [`reference/data-flow.md`](reference/data-flow.md) | How data moves: signals, ledgers and the module map |
| [`reference/execution-planes.md`](reference/execution-planes.md) | The four engines that run agents and their trust models |
| [`reference/kit-contract.md`](reference/kit-contract.md) | The rules every module, tool and skill must satisfy |
| [`reference/consumer-contract.md`](reference/consumer-contract.md) | The stable surface a consumer repo may depend on |
| [`reference/hooks.md`](reference/hooks.md) | Which hook prints which message, its knobs and source |
| [`reference/glossary.md`](reference/glossary.md) | Plain-word definitions of the kit's terms |
| [`reference/tiers.md`](reference/tiers.md) | Feature inventory by distribution tier |
| [`reference/FEATURES.md`](reference/FEATURES.md) | Generated one-row-per-feature registry |
| [`reference/workflow-paths.md`](reference/workflow-paths.md) | Every entry point and where each path leads |
| [`reference/hard-rules.tsv`](reference/hard-rules.tsv) | The hard-rule registry and what enforces each rule |
| [`reference/hermes-layering.md`](reference/hermes-layering.md) | How the thin Hermes skills in `integrations/hermes/` sit on top of the kit |
| [`reference/wrap.md`](reference/wrap.md) | Which `wrap` verb to use in which situation |
| [`reference/PHILOSOPHY.md`](reference/PHILOSOPHY.md) | Design principles, target user, fit check, the rejection list |
| [`../lib/config/modules.tsv`](../lib/config/modules.tsv) | The module table `install.sh` and `lib/adopt.sh` both read |
| [`impl-playbook/`](impl-playbook/) | Per-language rules the review agents cite |
| [`patterns/`](patterns/) | Reusable loop and brief patterns |

## Design and figures

| Path | What it is |
|---|---|
| [`design/kit-uml.html`](design/kit-uml.html) | The UML drawing set rendered from `SYSTEM-DESIGN.md` |
| [`figures/`](figures/) | Guide figures, rendered from `figures/MODEL.md`; `v-model.svg` is the full V |

## Records

Dated records keep their paths and are never rewritten. A record that names an old path stays as it was.

| Path | What it is |
|---|---|
| [`specs/`](specs/) | One spec per feature; also the live spec store the hooks read |
| [`decisions/`](decisions/) | Architecture decision records, superseded in place |
| [`briefs/`](briefs/) | Pre-spec decision briefs and shared context |
| [`implementation-notes/`](implementation-notes/) | Per-spec delta logs written during a build |
| [`verification/`](verification/) | Proof-of-done records; `verification/README.md` is the marker the ship gate keys on, so never move it |
| [`retro/`](retro/) | Per-cycle retrospectives |
| [`research/`](research/) | Dated deep scans; `research/foundations/` holds the undated early notes |
| [`absorption/`](absorption/README.md) | The upstream absorption ritual and its dated reports |
| [`audits/`](audits/) | One-off audit reports and the skillspector baseline |
| [`releases/`](releases/) | Per-version release artifacts |

The release history is the root [`CHANGELOG.md`](../CHANGELOG.md). No counts live in this map on purpose; enumerate specs with `bash lib/spec/spec-index.sh`.
