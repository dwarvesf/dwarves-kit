# SPEC: cc-observe

**Status**: ready (implementation passes all smoke criteria + a real-data run)
**Audience**: implementer + future me
**Last updated**: 2026-06-14

## Purpose

Make my own Claude Code usage observable, the way I instrument any system I run. Answer three questions from the session transcripts, with no instrumentation:

- **skills**: which Skills actually fire, how often, with what error rate (which of my ~90 skills earn their keep vs rot).
- **tools**: which tools (Bash/Edit/Read/Agent/...) fire, with error rates.
- **hooks**: per-hook execution latency (count, p50, p95, max) and hook-error counts (which hooks are slow and eating turn time).

Source: the JSONL transcripts under `~/.claude/projects/`. Each entry already carries `hookInfos: [{command, durationMs}]` + `hookErrors`, and every `tool_use` / `tool_result` block. So the tool is a read-only parser, no wrapper, no daemon, no dotfiles change (see `docs/implementation-notes/01-observability.md` for why the originally-specced timing wrapper was dropped).

This is sub-goal 01 of the `cc-elevation` mega-goal (self-observability axis). Source analysis: `research/2026-06-14-claude-code-events-tools-elevation.md` Axis 2.

## CLI contract

```
cc-observe <skills|tools|hooks|report> [--file F | --project=SLUG] [--root DIR] [--days N] [--top N] [--json]
```

| Arg | Default | Meaning |
|---|---|---|
| `<cmd>` | required | `skills`, `tools`, `hooks`, or `report` (all three) |
| `--file F` | none | parse a single transcript (used by tests) |
| `--project=SLUG` | none | one project dir under the root. Slugs start with `-` (cwd-derived), so the **equals form is required**. |
| `--root DIR` | `~/.claude/projects` | transcripts root (all projects) |
| `--days N` | 0 (all) | only files modified within N days (coarse mtime window) |
| `--top N` | 0 (all) | limit to top N rows |
| `--json` | false | machine-readable output (for vps-mon ingest) |

**Exit codes**: 0 success; 1 `--file` not found; 2 usage error (argparse).

The intended recurring use is `cc-observe report --days 7 --json` (the weekly digest); the per-view commands are for ad-hoc inspection.

## Behaviour

1. Resolve the file set: `--file`, else `--project=` dir, else walk `--root`. `--days` skips files whose mtime predates the window.
2. Single pass over every JSONL line (unparseable lines skipped):
   - `tool_use` blocks -> count by tool name; `Skill` also counts `input.skill`. Remember `id -> name`.
   - `tool_result` blocks with `is_error` -> attribute the error to the tool/skill via `tool_use_id`.
   - `hookInfos[]` -> collect `durationMs` per normalized hook label; `hookErrors` -> counted.
3. Emit the requested view(s) as aligned tables, or one JSON object with `--json`.

**Hook labels**: script hooks collapse to their basename (`slop-cleaner.sh`); inline `echo` guard hooks key on a short command hash (`inline-echo:ab12cd34`); other commands use their first token. Known limitation: long-text inline/condition hooks (e.g. the `/goal` Stop-hook, whose command is the goal text) fragment by first word. Script hooks, the ones with actionable latency, label cleanly.

## Non-goals

- No instrumentation / wrapper / daemon. Read-only over existing transcripts.
- No cost/$ accounting (Max plan; usage + latency are the signal here). Token cost is a later, separate concern.
- No live dashboard. `--json` feeds vps-mon; rendering lives there.
- No writes anywhere. This tool only reads.

## Verification (acceptance criteria)

Exercised by `tests/smoke.sh` against `tests/fixtures/sample.jsonl` (Skill, two Bash one errored, a Read, a system entry with a 500ms slow hook + a 12ms fast hook + one hook error):

1. `skills` counts the Skill once.
2. `tools` counts Bash twice with one error; Read once with zero.
3. `hooks` flags the slow hook with max >= 500ms.
4. `hooks` keeps the fast hook < 100ms (negative control: latency discriminates).
5. `hooks` surfaces the hook-error count.
6. `--json` emits valid JSON.
7. missing `--file` exits 1.
8. `report` prints all three sections.

Plus a real-data run (`report --days 2`, 225 transcripts, 0.47s) in `docs/proof-of-done.md`.

## Dependencies

- **python3** (stdlib only: argparse, json, collections, re, hashlib). No external packages, no `uv`.

## Install

```bash
ln -s "$(pwd)/tools/cc-observe/bin/cc-observe" ~/.local/bin/cc-observe
cc-observe report --days 7
```

## Provenance

Born 2026-06-14 as sub-goal 01 of the `cc-elevation` mega-goal. The originally-specced hook-timing wrapper was dropped once the transcript was found to already record `hookInfos[].durationMs`; the tool became a pure parser.
