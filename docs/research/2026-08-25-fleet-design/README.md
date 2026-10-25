# Skill Fleet

One skill body, every harness. The skill fleet keeps a single canonical
`SKILL.md` per skill and generates each runtime's loader from it, so you edit
one file instead of maintaining a hand-copied duplicate in Claude Code, Codex,
and opencode/pi.

The fleet has three moving parts:

1. **Registry** — `fleet.toml` declares which skills go to which harnesses, at
   what version, from what single source. It is declarative; it never stores the
   generated loaders.
2. **Sync/adapt engine** — `fleet sync` generates each harness's loader format
   from the one body and detects drift (a generated copy that diverged from
   source) without silently overwriting it.
3. **Render** — `fleet render` prints a runtime-by-purpose grid (skills live
   where, versions, drift flags). See the design brief
   `../briefs/DECISION-BRIEF-skill-fleet.md` for the visual.

This directory holds the operator and contributor docs:

| Doc | Audience | What it covers |
|---|---|---|
| [SCHEMA.md](SCHEMA.md) | contributor / author | `fleet.toml` and `SKILL.md` format rules, valid + invalid examples, versioning, the V1–V13 validation ruleset. |
| [SYNC.md](SYNC.md) | user / operator | `fleet sync` usage, the `--check` flag, drift detection behavior, and troubleshooting. |
| [PRIVATE-STREAM.md](PRIVATE-STREAM.md) | user (Craft tier) | How Craft-tier synced skills ride the private update stream. |
| [CONTRIBUTING.md](CONTRIBUTING.md) | contributor | How to add a new skill to the registry, the core-tier constraints, and the path from schema change to shipped loaders. |

## Why this exists

Without a fleet, an agent estate fragments: skills installed in Claude Code, a
different set under Codex, another under pi — drifting versions, duplicated
bodies, no view of what lives where. The ecosystem's answer today is
superpowers-style per-harness reinstall: hand-maintained duplicates. That is a
recorded AVOID in this kit (the packaging doctrine, ID-396). The fleet makes the
antidote a product feature: one source, generated adapters. That generalizes
[mattpocock's dual-harness pattern](../briefs/DECISION-BRIEF-skill-fleet.md)
to three harnesses.

Two hard properties the design protects:

- **Core tier is plain files only (N4).** A `tier = "core"` skill's `source`
  must be a relative repo path — no `url:`, no `private://`, no runtime fetch.
  Its dependencies must be local CLIs already on a standard dev machine. No
  network dependency at consume time.
- **Craft skills ride the private stream.** Craft-tier skills may reference the
  private update channel; maintained skill updates propagate to every harness
  in one pull. See [PRIVATE-STREAM.md](PRIVATE-STREAM.md).

## Supported harnesses

| `harness` id | Full name | Generated loader |
|---|---|---|
| `cc` | Claude Code / CC dir | `<out>/<category>/<id>/SKILL.md` (directory skill) |
| `codex` | OpenAI Codex | `<out>/<id>.openai.yaml` + sibling `<id>.md` |
| `opencode` | pi / opencode | `<out>/<category>/<id>/SKILL.md` |

## Status

The fleet is a **designed, queued** subsystem (board IDs ID-431 and ID-432).
The schema in this directory is the canonical contract (registry schema version
`1.0.0`). The `fleet sync`, `fleet render`, and private-stream integration are
documented here as the behavior they will implement; the docs track the schema
as the source of truth and will be reconciled against the implementation when
the engine lands.
