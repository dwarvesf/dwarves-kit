# Context for implementation (SPEC-235, gauntlet generalization)

## Stack
Bash + markdown command prompts. Commands live in `commands/*.md` (frontmatter `description:` + prompt body). Test runner: `bash tests/test-meta.sh`. Feature registry: `bash lib/registry/feature-registry.sh generate` regenerates `docs/FEATURES.md` from command frontmatter (freshness-gated by test-meta).

## Conventions
- Command files are the product; prose IS the code. STE-lite register, no em dashes.
- Generated projections (`docs/FEATURES.md`) are never hand-edited; hand-maintained renderings (`docs/workflow-map.md`, `README.md` command table, `docs/workflow-paths.md`) get a wording pass in the same PR.
- Gate ledger brackets phases; ship-gate reads recorded gates before push.

## Key files
- `commands/gauntlet.md` - the engine + (today) the onboarding hardcoding. Primary rewrite target.
- `docs/patterns/gauntlet.md` - kit-dev positioning, 10 known limits. Genericize wording; restate limits 4/8 per artifact kind.
- `docs/guides/gauntlet.md` - operator how-to. Generic top layer + onboarding worked example.
- `tests/gauntlet/**` - the kit's own onboarding INSTANCE (cleanroom stager, Tier-1 suite, checkers, J1-J11 scenario pack, campaign deploy). DO NOT rewrite; it becomes the reference preset's implementation.
- `kit.toml [gauntlet]` + `lib/config/kit-config.sh:96-114` + `lib/config/module-registry.md:52` - config keys `gauntlet.runner_host` / `gauntlet.probe_key_ref` are root-only-readable; key shape must not change.
- `docs/specs/SPEC-226-gauntlet-telemetry-learning.md` - telemetry contract; phase name literal `gauntlet`, marker `[[QL-VERDICT ...]]` grammar preset-invariant.
- Full surface map: `docs/research/2026-08-31-gauntlet-surface-map.md`; landmines: `docs/research/2026-08-31-gauntlet-pitfalls.md`.

## External dependencies
None. The change is prompt + doc files plus one registry regeneration. Live consumer to compat-check (not edit): `tests/gauntlet/deploy/mini.gauntlet-campaign.plist` invokes the onboarding campaign runner with today's input names.
