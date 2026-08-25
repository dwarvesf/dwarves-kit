# Craft private stream integration for synced skills

Core-tier skills live as plain files in a repo and sync from a local
`SKILL.md` (see [SYNC.md](SYNC.md) and [SCHEMA.md §3.5](SCHEMA.md)). Craft-tier
skills are different: their single source lives on the **private update
stream** — the same perpetual-update channel that delivers other Craft features
(ladders, persona packs, the private update channel per
`docs/tiers.md`). A Craft skill's maintained updates propagate to every
harness in one pull.

This doc covers how a Craft skill references the stream, what sync does with it,
and how to operate it.

## Why Craft rides the stream

The Craft tier's value is *maintained, kept-current* skills. If a Craft skill's
source were a hand-cloned repo file, it would drift from upstream the moment
the maintainer shipped a fix. Riding the private stream means a single
`fleet sync` (or the stream's own pull) brings every harness up to the
maintained version at once — the literal "fleet skills ride the stream" line in
`docs/tiers.md`.

> Honesty boundary (from the design brief): the sync engine generates loaders
> **everywhere**; enforcement of anything beyond generation stays where the
> harness supports it. A Craft skill synced from the stream is still a generated
> loader on each harness — the stream only changes *where the source comes
> from*.

## Declaring a Craft skill on the stream

A Craft skill differs from a core skill in two `fleet.toml` fields:

- `tier = "craft"` (omits the core plain-file constraints V10/V11).
- `source` uses the `private://` or `url:` scheme instead of a relative repo
  path.

```toml
[[skills]]
id = "internal-deploy-runbook"
source = "private://skills/deploy/SKILL.md"   # resolves via the private stream
version = "0.9.0"
tier = "craft"
harnesses = ["cc", "codex", "opencode"]
metadata = { category = "devops", stream = "skills" }
```

| Source form | Meaning | When to use |
|---|---|---|
| `private://<stream>/<path>` | Resolve `<path>` from the private update stream named `<stream>`. | The canonical Craft form; the source is maintained upstream and pulled, not cloned. |
| `url:<https-url>` | Fetch the `SKILL.md` from a `https` URL at sync time. | A hosted source you control; less preferred than `private://` because it has no stream identity or version provenance. |

`core` skills **may not** use either scheme — that is a V10 validation error
(see [SYNC.md Troubleshooting](SYNC.md)).

## What sync does with a stream source

For a Craft skill, `fleet sync`:

1. Authenticates to the private stream using the operator's Craft entitlement
   (the same credential the update channel uses).
2. Resolves `source` to a concrete `SKILL.md` revision on the stream.
3. Validates that `SKILL.md` (V7) and the cross-file contract (V8/V9) against
   `fleet.toml`, exactly as for a core skill.
4. Generates each harness loader from the resolved source.
5. Records the resolved stream revision in the checksum so a later upstream
   change shows as `update` (not `drift`) — sync knows the source moved, so it
   regenerates rather than flagging a conflict.

The loaders written to `cc`/`codex`/`opencode` are byte-identical in shape to
core loaders; only the *origin* of the bytes differs.

## Pulling updates

When the upstream maintainer ships a new version of a stream-hosted skill:

1. Refresh the stream (the same step that updates ladders/packs):
   ```bash
   fleet stream pull          # or the update-channel's own pull command
   ```
2. Re-run sync. Craft skills whose stream revision changed show as `update`;
   `fleet sync` regenerates their loaders.
3. Run `fleet sync --check` in CI to confirm every Craft skill still resolves
   and validates against the refreshed stream.

Because the source is upstream-owned, **never** edit a stream-hosted `SKILL.md`
locally and expect it to survive — a stream pull will replace it. Local
corrections go back to the maintainer (open a change against the stream source),
not into a local copy.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `skill X: core source must be a plain path (V10)` | A `core` skill used `private://`/`url:`. | Set `tier = "craft"`, or move the content into the repo as a relative path. |
| `skill X: stream auth failed` | No Craft entitlement / stale stream token. | Re-authenticate the update channel; confirm the Craft license is active. |
| `skill X: source 'private://...' not found on stream` | Wrong stream name or path, or the skill isn't published to that stream. | Check `metadata.stream` and the path; confirm the skill is published upstream. |
| `skill X: stream revision unresolved` | The stream returned no revision for the pinned `version`. | Bump `version` to a published one, or pin `version` to match the stream's current tag. |
| `skill X: url: fetch failed` | The `https` source is unreachable or returns non-200. | Verify the URL and network access; prefer `private://` for maintained sources. |
| Loaders never update after a stream pull | Sync ran before the pull, or with a stale cache. | Pull the stream, then re-run `fleet sync`; check the recorded revision moved. |

## Relationship to other tiers

- **Core** (`docs/tiers.md`): free forever, plain files, N4 adoption driver.
  Synced from a local `SKILL.md`. No stream dependency.
- **Craft** (this doc): perpetual license + update stream. Synced skills ride
  the private stream.
- **Crew** (`docs/tiers.md`): org-shared packs + the fleet dashboard panel; the
  org's routing map becomes policy-as-code the gateway checks. The dashboard
  render of a Craft skill labels it as stream-backed.
