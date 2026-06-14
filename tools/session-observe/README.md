# cc-observe

See my own Claude Code usage as data: which Skills and tools I actually use (with error rates), and which hooks are slow. Pure read-only parsing of the session transcripts under `~/.claude/projects/`, no instrumentation, no daemon.

Part of the `cc-elevation` self-observability axis. Full design: `SPEC.md`. Why no hook wrapper: `docs/implementation-notes/01-observability.md`.

## Install

```bash
ln -s "$(pwd)/tools/cc-observe/bin/cc-observe" ~/.local/bin/cc-observe   # ~/.local/bin is on PATH
```

Needs only `python3` (stdlib).

## Use

```bash
cc-observe report                 # all three views, all projects, all time
cc-observe report --days 7        # the weekly digest (recommended cadence)
cc-observe skills --days 30       # which skills fired in the last 30 days
cc-observe tools  --days 7        # tool usage + error rates
cc-observe hooks  --days 7        # per-hook p50/p95/max latency + hook errors
cc-observe report --days 7 --json # machine-readable, for vps-mon ingest
```

Scope to one project (note the **equals form**, slugs start with `-`):

```bash
cc-observe hooks --project=-Users-tieubao-workspace-tieubao-ops-toolkit --days 7
```

## What it reads

Each transcript entry already carries `hookInfos: [{command, durationMs}]`, `hookErrors`, and the `tool_use` / `tool_result` blocks. cc-observe tallies them:

- **skills / tools**: count `tool_use` by name (Skill by `input.skill`); attribute `is_error` results back via `tool_use_id`.
- **hooks**: group `hookInfos[].durationMs` by a normalized hook label; count `hookErrors`.

## Output (real run, abbreviated)

```
# tools  (225 transcripts)
  tool   count  errors  rate
  Bash    3697     219    6%
  Edit    1517     113    7%
  Read    1457     124    9%

# hooks
  hook              runs  p50ms  p95ms  maxms
  slop-cleaner.sh   1072   2967   6211  10303
```

## Limits

- Script hooks (`*.sh`/`*.py`) label cleanly by basename. Long-text inline/condition hooks (e.g. the `/goal` Stop-hook) fragment by first word. The actionable latency is in the script hooks.
- `--days` is a coarse file-mtime window.
- Read-only by contract: cc-observe never writes anything.

## Next (not in this tool yet)

Schedule `cc-observe report --days 7 --json` on a cadence and feed it to vps-mon. That deploy step is deferred; the tool stands alone today.
