---
title: Gauntlet surface map (input to SPEC-235 generalization)
status: research snapshot
---

# Every surface `/kit:gauntlet` touches

For SPEC-235 (ID-488): generalize onboarding-only gauntlet into a parameterized
probe-convergence engine (artifact-under-convergence + outcome contract; onboarding
becomes a preset).

| File | Role | Change for generalization | Why |
|---|---|---|---|
| `commands/gauntlet.md:1-193` | Engine: inputs table, bad-input table, loop, run-record contract, rules, lineage | yes | Loop mechanics (round/Tier1-Tier2/converge, `commands/gauntlet.md:78-112`), run-record shape (`:114-130`), rules 1-10 (`:138-163`) are already engine-generic. But vocabulary is onboarding-locked throughout: "contributor surface" (`:7-9`), "Surface globs" defaulting to CONTRIBUTING.md/onboarding docs (`:28`), "seed card" as task-card (`:31`), probe framed as "new contributor" (`:91-92`), rules 3-4 say "surface" not "artifact". Needs a param layer: `artifact globs` (was surface globs), `outcome contract` (was seed card + submission checker), `probe framing` (was "new contributor" instruction), with onboarding as a named preset |
| `docs/guides/gauntlet.md:1-92` | User how-to: checklist, invoking, reading verdict, worked example | yes | Entirely onboarding-framed: "let outside contributors in" (`:3`), checklist items are onboarding-specific (`:18-25`), worked example is the kit's own user/contributor personas (`:58-79`). Becomes preset-specific guide content once generalized; needs a generic top layer + onboarding as one worked example among others |
| `docs/patterns/gauntlet.md:1-190` | Kit-dev positioning: execute-pipeline mapping, V-model placement, mega-goal relation, floor-then-loop rule, 10 known limits | maybe | The mapping tables (`:54-59`, `:72-79`) and floor-then-loop rule (`:106-125`) are already engine-level generic reasoning, reusable as-is. Only surface-specific wording needs genericizing ("contributor surface" -> "artifact under convergence") sprinkled through limits 2, 3, 8 (`:136-165`) |
| `docs/specs/SPEC-226-gauntlet-telemetry-learning.md:1-57` | Pins telemetry/gate-ledger/observe-marker/debt-row contract | no | Contract is phase-name/marker-grammar based (`gauntlet` as a free-text phase, `:18`), not onboarding-coupled. Survives generalization unchanged; a preset still brackets/records under phase name `gauntlet` |
| `docs/specs/SPEC-227-gauntlet-scenario-pack.md:1-82` | Pins the J1-J11 onboarding journey scenario matrix + campaign shape | no (stays as onboarding-preset spec) | Entirely about the onboarding persona's journey (install/adopt/lane/debug/etc, `:12-13`). Becomes documentation for the onboarding PRESET specifically, not touched by the engine generalization itself |
| `docs/specs/SPEC-228-scenario-gen-wiring.md:1-56` | Pins scenario-generation method wired to gauntlet as one consumer | no | Generic scenario-generation pattern doc; gauntlet is just one of several altitudes it wires into. Unaffected |
| `docs/specs/SPEC-230-gauntlet-cloud-runner.md:1-20+` | SUPERSEDED/WILL-NOT-BUILD; pins runner_host stays local/ssh-alias | no | Dead spec, kept as design record. Decision (`runner_host` never "cloud") still holds after generalization; no touch |
| `kit.toml:166-168` | `[gauntlet]` config: `runner_host`, `probe_key_ref` | maybe | Section name/keys are already artifact-agnostic (runner + key ref, not onboarding-specific). May want a preset-scoping key later, but the two existing keys need no change |
| `lib/config/kit-config.sh:96-114` (test fixture) | Test asserts `kit_config_get_root gauntlet.runner_host` semantics | no | Tests root-only config-read behavior generically via the `gauntlet.*` namespace; unaffected by what gauntlet converges |
| `lib/config/module-registry.md:52` | One-line module registry row for gauntlet | maybe | Describes gauntlet as onboarding side-flow 11; wording needs updating once gauntlet is reframed as a general engine with a preset |
| `tests/gauntlet/cleanroom/run.sh:1-234` | Clean-room stager: builds the room, stages persona (`user`/`contributor`), row fixtures, probe prompt | yes | Deeply onboarding-hardcoded: `PERSONA` values are literally `user`/`contributor` (`:12,59,187`), the fixture is a hand-authored "shout" CLI with onboarding bugs baked in per row (`:60-171`), `row_checker()` switch hardcodes J1-J11 (`:50-56`), probe default prompt says "new contributor" (`:201`). This is the file that most needs a generic seam: artifact-fixture + outcome-contract should be injected, not hardcoded per persona |
| `tests/gauntlet/cleanroom/run-remote.sh:1-85` | Ships committed state to runner host, runs round remotely, pulls record | maybe | Runner/ssh/key-resolution logic (`:19-84`) is already artifact-agnostic; only the `<user\|contributor>` usage string and `PERSONA`/`ROW` positional args (`:13-14`) are onboarding-flavored naming, cosmetic |
| `tests/gauntlet/cleanroom/Dockerfile:1-24` | Clean-room image: node + claude CLI, no host state | maybe | Comment header says "kit's own runs" (`:1`) and `/work` contents are onboarding-specific (`kit.tar.gz`, `fixture-repo/`, `:11-16`); image itself (node+claude CLI) is reusable base, but the WORKDIR contract is onboarding-coupled |
| `tests/gauntlet/tier1.sh:1-59` | Tier 1 deterministic suite for the KIT's own onboarding docs | no (stays onboarding-preset-only) | Entirely about kit-specific doc existence + adopt-cycle checks (`:20-39`). This is itself an instance of a generic "Tier 1" contract the engine should accept as a pluggable command, not something to genericize in place |
| `tests/gauntlet/check-submission-user.sh:1-44`, `check-submission-user-J*.sh` (9 files), `check-submission-contributor.sh` | Deterministic submission checkers per persona/row | no (stay as onboarding-preset checkers) | These ARE the "outcome contract" instances for the onboarding preset; the engine generalization defines the pluggable slot they fill, doesn't rewrite them |
| `tests/gauntlet/check-lib.sh:1-38` | Shared `check`/`blocked_guard`/`gauntlet_verdict` helpers | maybe | Genuinely reusable helper shape (any outcome-contract script can source it); worth promoting to a documented "checker helper contract" so new presets reuse it instead of re-copying |
| `tests/gauntlet/README.md:1-88` | Instance doc: kit-self-gauntlet inputs tables, scenario pack, campaign shape, run-day checklist | no (becomes the onboarding preset's own README) | Fully persona/onboarding-specific; survives as documentation for the onboarding preset once the engine is generalized |
| `tests/gauntlet/journey.md`, `tests/gauntlet/scenarios.md`, `tests/gauntlet/make-card.sh` | Journey spec, reconciled J1-J11 matrix, per-row card materializer | no | All onboarding-journey content; part of the onboarding preset, not the engine |
| `tests/gauntlet/deploy/*` (`gauntlet-campaign`, `mini.gauntlet-campaign.plist`, `README.md`) | Unattended campaign runner deploy bundle | no | Deploy plumbing for running the onboarding campaign on a schedule; orthogonal to what artifact converges |
| `docs/FEATURES.md:27` | Generated feature-registry row for `/kit:gauntlet` | yes (regenerate) | `status: GENERATED projection` (`docs/FEATURES.md:3`); row text is pulled from `commands/gauntlet.md`'s frontmatter `description` (`commands/gauntlet.md:2`). Once that description is reworded to be engine-generic, regenerate via `bash lib/registry/feature-registry.sh generate` (`docs/FEATURES.md:9`) rather than hand-edit |
| `docs/workflow-map.md:270-271` | Hand-maintained ASCII rendering row for `/kit:gauntlet` | yes | "before outside-dev access... after contributor-surface edits" phrasing is onboarding-specific and hand-maintained (rendering of WORKFLOW.md per `docs/workflow-map.md:3-6`); needs a wording pass once the command is reframed, but WORKFLOW.md itself has no gauntlet section to sync against (see below) |
| `WORKFLOW.md` | No gauntlet section found (`grep -i gauntlet WORKFLOW.md` empty) | maybe | The canonical contract doc workflow-map.md claims to render has no gauntlet entry; either it's covered under a generic "side-flows" heading not grep-matched, or workflow-map.md's row is undocumented upstream. Worth a look during the spec pass, flagged as a gap, not confirmed drift |
| `README.md:90,314` | Two rows: Check(Govern) module list + full command table entry | yes | `:314` description is "Maintainer-only bounded-revise loop that converges the contributor surface..."; wording needs the same engine-generic pass as the command frontmatter |
| `skills/loop-engineering/SKILL.md:163` | Cites gauntlet rules 7-10 as a worked example of one engine's answers | no | Reference only, stays accurate regardless (rules 7-10 are engine-level, not onboarding-specific) |
| `_meta/BACKLOG.md:243` (ID-488) | The backlog row that IS this generalization task | n/a | Source of the task; names SPEC-235 as the not-yet-written spec this research feeds |
| foundation-workers SPEC-018, `test/onboarding/gauntlet/` | First worked instance (external repo), cited as lineage (`commands/gauntlet.md:192-193`, `docs/patterns/gauntlet.md:189-190`) | no (external repo, out of scope to edit) | Named as prior art only; not present in this worktree. Note for the spec: it is a SECOND onboarding-preset instance, evidence the "onboarding" framing is itself the thing to peel into a preset rather than the engine's identity |

## Summary

- Already generic: the loop mechanics (Tier1/Tier2, converge/halt, round cap), the
  run-record directory contract, rules 1-2 and 5-10, the telemetry/gate-ledger/observe
  wiring (SPEC-226), and `kit.toml [gauntlet]`'s runner/key config.
- Hardcoded to onboarding: the vocabulary layer in `commands/gauntlet.md` (surface,
  seed card, contributor), and severely in `tests/gauntlet/cleanroom/run.sh` (literal
  `user`/`contributor` personas, a hand-baked fixture CLI, a J1-J11 row switch).
- The onboarding instance (tests/gauntlet/*, SPEC-227/228, foundation-workers SPEC-018)
  should become the reference PRESET, not be rewritten; SPEC-235's job is extracting the
  parameter seam (artifact globs / outcome contract / probe framing) that lets a second
  preset exist beside it.
- Generated docs (`docs/FEATURES.md`) fix themselves on regenerate once the command
  frontmatter description changes; hand-maintained docs (`docs/workflow-map.md`,
  `README.md`) need a manual wording pass in the same PR.
- `docs/patterns/gauntlet.md`'s positioning (V-model, mega-goal, floor-then-loop) needs
  the least work: it already reasons at the engine altitude, only its surface-specific
  wording needs a genericizing pass.
