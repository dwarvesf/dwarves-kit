# Implementation notes: dead parts, wired or removed

Delta from the slice brief. Each decision below was verified against the code first.

## Skipped (the brief's claim was false)

- **redteam-gate.sh stays.** The brief says it has no caller. The dotfiles skills `goal-craft`, `plan-for-goal` and `plan-for-mega-goal` call `bin/gate redteam start|round` at each round boundary, so it has a live caller outside this repo. The stale "not yet wired anywhere" header was corrected. `lib/gate/README.md` has no redteam text, so there was nothing to drop there.
- **lib/money-gate/ stays.** The brief says it holds only `SPEC.md`. It holds `README.md`, `SPEC.md` and `docs/proof-of-done.md`. `tests/test-kit-contract.sh` requires every declared module (`money_gate` is in `KIT_KNOWN_MODULES`) to have a `lib/<name>/` home, and its header records the money-gate-had-no-SPEC incident as the reason. Moving the SPEC would break contract checks C3 and C4. Drift #17 is a wording problem, not a layout problem: the dir is the docs home of a hook-only module.
- **bin/learn stays.** `VERSION` is 2.3.0, below the 2.4.0 removal point. `lib/learn/` does not exist.

## Done

- **session-state-save removed.** Nothing reads `last-state.md` (checked `hooks/`, `lib/`, `commands/`, `skills/`, `agents/`). The hook, its `Stop` and `SubagentStop` entries (the `SubagentStop` key held only this hook, so the key went too), and its token in install.sh's `session` hook list are gone. Its `test-hooks.sh` sections and anchor cases 1 to 3 went with it. Case 4 (pre-compact-backup) stays. `lib/adopt.sh` carries a second copy of the module hook list; it is outside this slice and listed under "Needs from others".
- **intake-sweep wired through `backlog-stage.sh --surface`, not by calling `intake-sweep.sh` directly.** `backlog-stage.sh` already runs the sweep on `--surface`, and it holds the `BACKLOG_STAGE_AUTO` opt-in. That opt-in was set on purpose: unattended staging filled a file nobody drained and fed a board that grew 13 to 25 rows a day. Calling `intake-sweep.sh` directly would bypass it for every consumer that has an `_meta/intake-sources.json`. Wiring the `--surface` pass gives the sweep its trigger and keeps the opt-in. Without `BACKLOG_STAGE_AUTO` the entry exits 0 at once. The `board` module's hook list already names `backlog-stage.sh`, so a consumer without the board module never gets the entry.
- **Feature registry reads hook commands that carry arguments.** `hook_events()` in `lib/registry/feature-registry.sh` matched `endswith(hooks/<name>)`, so any wired command with an argument (`backlog-stage.sh --surface`, `harvest.sh --lab-log`) lost its event. It now strips the `anchor-root.sh` wrapper and also matches `<name> `. `harvest.sh` now shows `PreCompact+SessionEnd`, which its own description already claimed.
- **`/kit:spec` flips a board row to `validated`.** The spec template gains an optional `Board: <ID>` header. On an APPROVED validate round, `commands/spec.md` runs `backlog.sh set <ID> validated` when that header exists. A spec without it makes no board call, so a spec never creates or touches a row on its own.
- **plugin-check:** no doc in the repo calls it a gate, so no edit.
- **prose-rag leftovers:** `lib/prose-rag/bin/` (the retired Rust binary) and `lib/prose-rag/rust/` (cargo output) were untracked and ignored. Both were moved to the Trash from the shared checkout only.
