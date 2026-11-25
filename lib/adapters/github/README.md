# GitHub adapter

Two-way sync between the board and the Issues of a GitHub repo. It drives the `gh` CLI only: auth, remotes and retries stay `gh`'s problem, and no token passes through this process. The adapter name and the app name are both `github`. The contract it follows is `lib/adapters/README.md`.

## What it holds

GitHub has open and closed and nothing finer.

| Field | GitHub |
|---|---|
| title `ID-NNN · item` | frozen at create (`sync_fields` is false): a teammate retitling an issue must not echo back to the board; the row is the record |
| status | closed only: a shipped, done or resolved row closes its issue; a dropped or parked row closes it with a comment that says which; a closed issue reads back as shipped; a row moving back to an active state reopens its closed issue |
| notes | the issue body, frozen at create, plus a `bls: <ID>` marker line |
| #tags | in the body text |

The `bls: <ID>` marker in the body is the idempotency guard: GitHub has no idempotency key, so `read()` surfaces the marker and a re-run adopts the existing issue instead of creating a second one.

## Config

```toml
[sync]
apps        = "github"
github_repo = "owner/repo"      # optional: empty means whatever gh resolves from the origin remote of the board's repo
```

Flag: `--github-repo` (also `[sync] github_repo`). Filter keys: `github_only_tags`, `github_skip_tags`, `github_intake`. State: `<sync state dir>/<board-slug>/github.state.json`.

## Install notes

- `gh` on the PATH, signed in (`gh auth status`).
- With no `github_repo`, `gh` resolves the repo from the origin remote of the repo that owns the backlog (the engine passes it as the project root), never from the process cwd.

## One invocation

```bash
board sync --dry-run --apps github
```

## Tests

`lib/adapters/tests/test_github.py` runs against a fake `gh` runner; `test_conformance.py` checks the adapter against the contract. Neither reaches GitHub.
