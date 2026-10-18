# One engine per job: implementation notes

Four jobs each had two or three implementations. This change keeps one per job.

## 1. Transcript parsing

`lib/session/parse_transcript.py` is the only transcript parser. It gained two CLI modes, and two callers moved onto them.

| Caller | Mode | Replaces |
|---|---|---|
| `lib/skill-curator/lib/transcript.sh` | `--tail-text K` | a two-pass jq filter |
| `hooks/harvest.sh` `transcript_text` | `--harvest-text MAX` | a 30-line jq reducer |

- Output is byte-identical: `cmp` on the skill-curator fixture (K=1, 2, 40) and on a 130 KB real transcript.
- `tests/test-harvest-parity.sh` stays at 171 of 171, crash shapes included.
- `--harvest-text` is strict (a non-object line, a bad message, or a non-string text block prints nothing, exit 1) because the parity fixtures pin the original crash behavior. `--tail-text` is tolerant. `parse_lines(strict=True)` is the one switch.
- Behavior change in `--tail-text`: a malformed line no longer ends the parse. The old `jq -c` aborted at the first bad line and dropped everything after it.
- Not touched: the third jq copy named in the risk list (the audit agent). It is an agent prompt, not code.

## 2. Sync engine (drift 33)

Decision: remove the `board mirror --engine sync` path and the extract/plan half of `lib/sync/cockpit.py`. Keep the file, trimmed.

- `--engine sync` was dry-run only and refused a real run. No config, script, or job passes it.
- `cockpit.py` itself is NOT removable. Live code imports three helpers from it: `sources/hermes.py` (untrusted markers, `redact_secrets`), `sources/notion_taskboard_pull.py` (`redact_secrets`), `lib/mega/runs-dashboard.py` (`repo_root_of`). The file now holds only those.
- The file name is now a misnomer. Renaming needs edits in `notion_taskboard_pull.py` and `runs-dashboard.py`, outside this slice. Left for the lead.
- The live engine for `mirror`, `status`, and `writeback` stays `board-mirror.sh` and `board-writeback.sh`. Not rewritten.
- The `board.sh` note now says what is true: one bridge engine, with `board sync` as a separate job.

## 3. Hermes bridges: inventory, no change

STOP CONDITION met: both bridges are in live use. Nothing about them changed.

| Bridge | Key | Evidence it is live |
|---|---|---|
| Cockpit mirror (`board-mirror.sh`) | `bridge=on` in a consumer's `boards.txt` | One operator registry has 15 of 18 rows `on`. Its mirror snapshot holds cards from 12 repos, and the scheduled sweep passes the mirror flags every tick. |
| Per-repo spoke (`sources/hermes.py`) | `hermes` in `[sync] apps`, or `--apps hermes` | No committed `.kit.toml` lists `hermes` (the one repo that had it turned it off on purpose). A scheduled intake job runs `board sync --apps hermes` every 15 minutes, passing it per invocation, and its `hermes.state.json` was written minutes before this scan. |

The spoke looks unused in every config file, so a grep of `.kit.toml` alone would have retired a live relay. The operator picks which bridge to retire, if either.

## 4. Hook log root (drift 12)

Hook logs now live in `<ledger root>/hooks/`, resolved by one helper, `lib/telemetry/hook-log-dir.sh`.

- Precedence is `kit_resolve_log_dir`'s: `KIT_LEDGER_DIR`, then `DWARVES_KIT_LOG_DIR`, then `[ledger].location`, then the XDG default. `DWARVES_KIT_LOG_DIR` still works and now also moves the hook logs.
- Cost: resolving the root reads the kit config (about 30 ms). `safety-gate.sh` and `secrets-guard.sh` run on every tool call, so they resolve only inside the function that writes a log line. The hooks source the helper with no forks.
- Migration: on first use, `cp -n` copies the nine known hook logs from the ledger root and from `~/.claude/dwarves-kit/logs`. The old dir is never deleted or overwritten, a symlinked source is refused, and a pinned root never ingests the machine's old dir (a test's temp dir stays clean). The `.migrated` sentinel lands only when every copy succeeded.
- A hook with no `lib/` beside it falls back to an inline function: env knobs, then the XDG default. It still logs under `<root>/hooks`.
- Inherited trust: `[ledger].location` comes from the project `.kit.toml`, as it already does for every ledger writer. A hostile repo can choose where hook logs land.
- `hooks/codex-hooks.json` pins were recomputed with `lib/codex/repin.sh`, because six hook files changed.
- Tests that read `$DWARVES_KIT_LOG_DIR/<hook>.log` now read `<root>/hooks/<hook>.log`. Where a test sets `KIT_LEDGER_DIR` too, that variable wins, so the test reads it.

## Out of fence, for the lead

- `README.md`, `docs/MANUAL.md`, `docs/architecture.md`, `lib/gate/README.md`, `lib/cosmetic/README.md`, and `lib/config/module-registry.md` still name `~/.claude/dwarves-kit/logs` for hook logs, or `--engine sync`.
- `docs/SYSTEM-DESIGN.md` rows 12 and 33 and the "Four transcript parsers" risk.
- `docs/decisions/0035-durable-ledger-root.md` says hook logs deliberately stay on the legacy default. This change reverses that.
