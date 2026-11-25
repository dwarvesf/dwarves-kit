# Multica adapter

Two-way sync between the board and one project of a self-hosted Multica board (the team pilot, see ops-toolkit `tools/multica-deploy/`), over its REST API. The adapter name and the app name are both `multica`. The contract it follows is `lib/adapters/README.md`.

## What it holds

| Field | Multica |
|---|---|
| title `ID-NNN · item` | two-way |
| status | full two-way through a fixed-enum map plus a `<!-- board:kw -->` marker at the end of the description |
| notes | the description (the board wins, lazy), with the marker appended |
| #tags | in the body text |

Multica's status enum is one notch coarser than the board's state machine (`speccing` and `claimed` both land on `todo`), so each issue carries its exact board state in a trailing `<!-- board:kw -->` description marker. The marker is trusted while the Multica status still equals its forward image; the reverse map speaks the moment someone moves the issue on the Multica board. Sync rewrites the marker on every status or body write.

Issues are always created unassigned and in `backlog` or `todo` family states only: assigning an agent is what dispatches execution in Multica, and that stays a human act on the Multica UI. A new card needs a named verification line in its body (`Verify: <command>`), mirroring the kit's own `Done =` contract; a row without one is refused at creation.

## Config

```toml
[sync]
apps              = "multica"
multica_url       = "https://multica.example"   # root-only: set it in the operator kit.toml, a project .kit.toml value is ignored
multica_workspace = "<workspace_uuid>"
multica_project   = "<project_uuid>"
multica_token_ref = "op://<vault>/<item>/credential"   # root-only
```

Flags: `--multica-url`, `--multica-workspace`, `--multica-project` (also the `[sync]` keys above). Filter keys: `multica_only_tags`, `multica_skip_tags`, `multica_intake`. State: `<sync state dir>/<board-slug>/multica.state.json`.

`multica_url` and `multica_token_ref` pick the host and the secret that host receives, so `board sync` reads them from the operator and kit-root files only and names a project value it ignores. The token reaches the engine through the `MULTICA_TOKEN` environment variable and never through argv.

## Install notes

- No auto-bootstrap: point `multica_workspace` and `multica_project` at an existing project (the pilot's sync-bot account, workspace and project ids live in `op://Toolkit/multica-sync-bot`).
- The token resolves from `multica_token_ref` at invocation (Keychain-cached `secret-cache-read` first, the 1Password CLI as the fallback). A `MULTICA_TOKEN` that is already set is used as it is.
- A missing url, workspace, project or token ends the run with a message that names the missing key.

## One invocation

```bash
board sync --dry-run --apps multica
```

## Tests

`lib/adapters/tests/test_multica.py` runs against a fake HTTP runner; `test_conformance.py` checks the adapter against the contract. Neither reaches a Multica server.
