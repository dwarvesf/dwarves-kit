# codex

Keeps the Codex hook manifest trustworthy. Each command in `hooks/codex-hooks.json` pins the sha256 of the hook file it runs. Editing a hook makes its pin stale, and this module rewrites the pins.

**Entry points**
- `lib/codex/repin.sh [kit-root]`: recompute every pin and rewrite `hooks/codex-hooks.json` in place. It writes nothing when all pins are fresh.
- `lib/codex/repin.sh check [kit-root]`: verify only. Exit 0 when fresh, exit 1 naming each stale file.

The pinned file list is read from the manifest, so a new hook needs no change here. `kit-root` defaults to the repo that holds the script.

**Tests**: `bash tests/test-codex-hooks.sh` (its "Codex trust repin" block drives `repin.sh`). It turns red when a pin is stale.

**Spec and docs**: `docs/specs/SPEC-288-codex-hook-parity.md`.
