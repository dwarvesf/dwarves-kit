> Renamed 2026-07-11 (kit naming invariant, function-named callables): the CLI
> names below read `cc-*` historically; the shipped callables are now
> `session-intel` / `session-observe` / `session-semantic` / `session-report` /
> `session-recall`, env knobs `SESSION_INTEL_*` / `SESSION_SEMANTIC_*` / `SESSION_REPORT_*`.

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
cc-observe <skills|tools|hooks|subagents|friction|sessions|cost|report> [--file F | --project=SLUG] [--root DIR] [--days N] [--top N] [--json]
```

| Arg | Default | Meaning |
|---|---|---|
| `<cmd>` | required | `skills`, `tools`, `hooks`, `subagents`, `friction`, `sessions`, `cost`, or `report` (all of them) |
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
   - `tool_use` named `Agent`/`Task` in a non-sidechain entry -> count a subagent spawn by `timestamp` day and by `input.subagent_type`. A real user-message turn (text content, non-sidechain) -> count a prompt for that day (the `per100` denominator). Sidechain entries are the subagents' own runs, excluded from both.
   - friction: `Edit`/`Write`/`MultiEdit` -> per-session edit count by `file_path`, folded into `thrash` at end of each transcript (`>= THRASH_MIN`); `tool_result` content matching a `PERM_MARKERS` string -> a permission-friction event attributed to the tool via `tool_use_id` (Bash labeled by command); `isCompactSummary` entry -> a compaction for that day; a Skill's errored `tool_result` -> a skill mis-fire (skill-precision).
   - sessions: per transcript, track first/last `timestamp` (wall-clock), tool-use count, prompt-turn count -> `classify_session` buckets it (quick/standard/deep/marathon/automation, thresholds in `ARCH`); sidechain transcripts are skipped (not Han's sessions). Prompt-turns + tool-uses are bucketed by UTC hour (`circadian`). A prompt turn whose text holds `INTERRUPT_MARK` is an interruption.
   - cost: `message.usage` (input/output/cache-read/cache-create) summed per `message.model`; `model_cost` applies the dated `PRICING` table by family substring (unknown family -> tokens counted, `$` shown as `?`). Cache-hit = cache-read / (read + create). cost-per-merged-PR is out of scope (see Non-goals).
3. Emit the requested view(s) as aligned tables, or one JSON object with `--json`.

**Hook labels**: script hooks collapse to their basename (`slop-cleaner.sh`); inline `echo` guard hooks key on a short command hash (`inline-echo:ab12cd34`); other commands use their first token. Known limitation: long-text inline/condition hooks (e.g. the `/goal` Stop-hook, whose command is the goal text) fragment by first word. Script hooks, the ones with actionable latency, label cleanly.

## Non-goals

- No instrumentation / wrapper / daemon. Read-only over existing transcripts.
- The `cost` view's `$` is an **attribution estimate** from a static dated `PRICING` table, NOT a bill (Max plan is flat-rate). No live pricing fetch.
- **No cost-per-merged-PR.** It was in SG-03's outcome but has no clean data path: transcripts span all repos while merges are per-repo, and ops-toolkit squash-merges (so `git log --merges` finds ~0). Deferred to NOTES proposed-additions; needs PR data (gh), not transcript data.
- No live dashboard. `--json` feeds vps-mon; rendering lives there.
- No writes anywhere. This tool only reads.

## Verification (acceptance criteria)

Exercised by `tests/smoke.sh` against `tests/fixtures/sample.jsonl` (Skill, three Bash two errored incl. a denied deploy, a Read, a system entry with a 500ms slow hook + a 12ms fast hook + one hook error, a text prompt turn, two main-session Agent spawns + one sidechain spawn, a thrice-edited file + a once-edited file, a permission-denied Bash, an errored Skill, a compaction entry):

1. `skills` counts the Skill once.
2. `tools` counts Bash 3x with two errors; Read once with zero.
3. `hooks` flags the slow hook with max >= 500ms.
4. `hooks` keeps the fast hook < 100ms (negative control: latency discriminates).
5. `hooks` surfaces the hook-error count.
6. `--json` emits valid JSON.
7. missing `--file` exits 1.
8. `report` prints all sections (skills, tools, hooks, subagents, friction, sessions, cost).
9. `subagents` counts 2 spawns on the day, 1 prompt, per100=200.0.
10. `subagents` excludes the sidechain spawn (negative control: total 2 not 3, Explore 1 not 2).
11. `friction` thrash: the thrice-edited file shows sessions 1 / max-edits 3; the once-edited file is NOT flagged (negative control).
12. `friction` permission: the denied Bash is attributed (`Bash:deploy` 1).
13. `friction` context-pressure: 1 compaction on the day.
14. `friction` skill-precision: the errored skill shows 100% inert; a clean skill is NOT in the precision table (negative control).

Plus, against `tests/fixtures/session-sample.jsonl` (a clean 10.5-min, 2-turn session, one turn interrupted, no sidechain):

15. `sessions` archetype: the session classifies as `standard` (1, 100%).
16. `sessions` interruption: 1 interrupt of 2 turns (negative control: the clean turn is not counted).
17. `sessions` circadian: hour 08 shows 2 turns / 2 tools.
18. `sessions` archetype on the sidechain-tainted main fixture: NO session is classified (negative control: subagent transcripts excluded).

Plus, against `sample.jsonl`'s three appended usage entries (opus 1M/1M/900k-rd/100k-wr, haiku 1M-in, fable 1M-in):

19. `cost` by-model: the opus row prices to `$93.22`.
20. `cost`: haiku 1M input prices to `$0.80`.
21. `cost` negative control: fable (unknown family) counts tokens but shows `?`, not a `$`.
22. `cost` cache-hit: 90% (900k read / 100k create) in the header.

Plus real-data runs (`friction --days 7`, `sessions --days 7`, `cost --days 7`) in `docs/proof-of-done.md`.

## Dependencies

- **python3** (stdlib only: argparse, json, collections, re, hashlib). No external packages, no `uv`.

## Install

```bash
ln -s "$(pwd)/tools/cc-observe/bin/cc-observe" ~/.local/bin/cc-observe
cc-observe report --days 7
```

## Provenance

Born 2026-06-14 as sub-goal 01 of the `cc-elevation` mega-goal. The originally-specced hook-timing wrapper was dropped once the transcript was found to already record `hookInfos[].durationMs`; the tool became a pure parser.
