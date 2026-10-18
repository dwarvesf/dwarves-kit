# Implementation notes: adopt gates on, migration at install

Decisions the slice brief left open. No spec; the brief and `docs/SYSTEM-DESIGN.md` risk rows are the contract.

## Adopt seeds the two gates on

- Only a FRESH `.kit.toml` is seeded. An existing file is never edited, so "only add missing keys" is read as "never flip or add a key in a file the repo owns". Reason: the seeded comment tells an operator to delete a key to follow the operator setting again. Appending a missing key on `--refresh` would silently override that choice and turn gates on for repos adopted earlier. The behavior change is for new adopts, as the CHANGELOG says.
- The seed for `proof_of_done` and `lane_gates` is `true` unless the operator overlay names the key. Reading the kit root is skipped for these two because the kit root keeps them `false` for a raw install. An operator who wrote `proof_of_done = false` keeps that in the seed.
- `kit.toml` is untouched: a raw install still blocks nothing.

## Migration at install

- One entry point, `lib/telemetry/kit-migrate.sh` (`kit_migrate`), holds both copies: the run corpus (`cp -Rn`) and the hook logs (`cp -n`). `install.sh` calls it before the plugin-compat branch so both modes migrate. `lib/adopt.sh` calls it on a real run, not on `--check` or `--dry-run`.
- `kit_migrate_log_dir` keeps its name. Six corpus libs outside this slice call it at load (`gate-ledger.sh`, `proof-ledger.sh`, `proof-table-gen.sh`, `precedent.sh`, `weekend-batch.sh`, `lane-classify.sh`), and `ship-gate.sh` reaches several of them. It is now a shim that only calls `kit_note_unmigrated`. This removes the copy from every hook path without editing files another slice may own.
- Follow-up sweep: the eight load-time `kit_migrate_log_dir || true` calls in the corpus libs were removed once they did nothing but print the note. `ledger_root` and `kit_hook_log_dir` still print it; the shim stays for outside callers.
- `kit_note_unmigrated [root]` prints one stderr line, once per process, when the legacy dir is a real dir and the shared root lacks `.migrated` or `hooks/.migrated`. It stays silent for a pinned root, an isolated root, and after the migration. `kit_hook_log_dir` passes its root in, so the hook hot path does not resolve twice.
- Behavior drop: `[ledger].location = "isolated"` used to ingest the machine corpus into `./.kit/logs` on first use. Install-time migration skips an isolated root (the hook-log path already refused it). A per-project root should not hold the machine-wide corpus.
- A fixture `$CLAUDE_DIR` (not `$HOME/.claude`) skips the migration, since the legacy dir is derived from `$HOME`. This keeps fixture installs in tests from copying a real machine corpus.
- A plugin-only machine that never runs `install.sh` or `/kit:adopt` is not migrated. The note names the command to run. That is the cost of "never at runtime".
