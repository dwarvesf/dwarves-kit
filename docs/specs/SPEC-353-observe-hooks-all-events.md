# Spec: session observe hooks counts every hook event, not just Stop

Generated: 2026-09-28
Status: DRAFT (branch `feat/observe-all-hook-events`)
Lane: normal
Type: spec-feature
File: `docs/specs/SPEC-353-observe-hooks-all-events.md`
References: `lib/session/observe/bin/session-observe` (`collect`, `hook_label`, `hook_rows`, the `hookInfos` block around line 364-372); `lib/session/observe/tests/smoke.sh`; `lib/session/observe/README.md`; `lib/session/observe/SPEC.md`.

## Problem

`session-observe hooks` reports per-hook p50/p95/max latency, but it only reads
durations from `entry["hookInfos"]`. In real transcripts that field rides only
on `system` entries with `"subtype": "stop_hook_summary"`, so the view covers
Stop hooks only. Every other hook event (SessionStart, PreToolUse,
PostToolUse, PostToolUseFailure, UserPromptSubmit) records its duration on a
separate `attachment` entry instead:

```json
{"type": "attachment", "attachment": {"type": "hook_success", "hookName": "SessionStart:startup", "hookEvent": "SessionStart", "command": "~/.claude/hooks/tool-first/tool-first.sh", "durationMs": 56, "exitCode": 0, "stdout": "...", "stderr": "", "toolUseID": "..."}}
```

Measured on one real ops-toolkit transcript (294 `hook_success` attachments,
22 `stop_hook_summary` system entries):

| Event | Source | Count |
|---|---|---|
| PreToolUse | attachment | 133 |
| PostToolUse | attachment | 120 |
| Stop | attachment (duplicate of hookInfos, see below) | 22 |
| SessionStart | attachment | 7 |
| PostToolUseFailure | attachment | 6 |
| UserPromptSubmit | attachment | 6 |
| Stop | hookInfos (`stop_hook_summary`) | 22 |

`hooks` today reads only the last row. A SessionStart hook that took 1.5s,
delaying every new session, never appears: its 7 firings sit in `attachment`
records the tool never opens.

The same real transcript also shows a Stop hook is recorded TWICE: once in
`hookInfos` (already counted) and again as an `attachment` with
`hookEvent: "Stop"` (would double-count if aggregated blindly). And some
commands (an install-time relay script observed in this transcript) fire
under five different events (`PreToolUse`, `PostToolUse`, `SessionStart`,
`Stop`, `PostToolUseFailure`) with the same script basename, so a single
`hook` label would otherwise merge unrelated event latencies into one row.

Some `attachment` records carry no `command` and no `durationMs` (for example
`hook_system_message`, `instructions`, `output_style`); those must be skipped,
not counted as a zero-duration hook.

## Solution

### Approaches considered

1. **Also aggregate `attachment` records of type `hook_success` for every
   event except Stop**, keyed by `(hook label, event)` instead of just label.
   Reuses the existing `hook_label()` normalizer and the existing
   `hook_durs`/`hook_sample` structures in `collect()`; only the key shape and
   one extra branch in the entry loop change.
2. **Read `hookEvent` off `hookInfos` too and always key by `(label, event)`,
   trusting `hookInfos` entries to self-report their event.** Rejected:
   `hookInfos` entries carry no `hookEvent` field in observed transcripts
   (only the parent `system` entry's `subtype: stop_hook_summary` says which
   event they are), so this would need a second field read for no gain; the
   parser already knows every `hookInfos` entry is Stop.
3. **Keep one row per hook label, sum every event's durations into it.**
   Rejected: it hides which event is slow (a SessionStart hook and a
   PreToolUse hook sharing a script name would blur together), and directly
   contradicts the acceptance criterion below (show the event per hook).

### Chosen approach + why

Approach 1, with the `(label, event)` keying from approach 2's motivation
folded in (test case 3 above proves it is needed, not speculative). The
change stays inside `collect()`'s single existing pass and `hook_rows()`; no
new pass over transcripts, no new module.

## Design

### The change

In `collect()`, at the existing `hookInfos` block (session-observe.py, around
line 364-372):

- `hook_durs` and `hook_sample` become keyed by a `(label, event)` tuple, not
  a bare label.
- Every `hookInfos[]` entry keys as `(hook_label(command), "Stop")` (the
  `stop_hook_summary` subtype is the only source of `hookInfos` in observed
  transcripts, so this is not a guess dressed as data; it is what the field
  means today).
- A new branch, alongside the `hookInfos` branch, handles
  `entry.get("type") == "attachment"`:
  - Skip unless `attachment` is a dict, `attachment["command"]` is a
    non-empty string, and `attachment["durationMs"]` is an int or float.
    This is the general rule the item asks for ("any other attachment type
    that carries `durationMs` and `command`"): it does not special-case
    `hook_success` by name, so a future attachment type with the same two
    fields is picked up automatically, and one missing either field (no
    `command`, no `durationMs`) is skipped rather than counted as zero.
  - Read `event = attachment.get("hookEvent")` (fall back to `"?"` if not a
    non-empty string).
  - **Skip when `event == "Stop"`.** `hookInfos` already counts every Stop
    hook; counting the `attachment` copy too would double it (the item's
    "double-counting rule").
  - Otherwise key as `(hook_label(attachment["command"]), event)` and append
    `durationMs`, same as the `hookInfos` branch.
- `hook_rows()` unpacks the tuple key and returns `[label, event, count, p50,
  p95, max, sample]` (event inserted after label, before the count column,
  so the existing count/p50/p95/max/sample columns keep their relative
  order).
- The `hooks` text table gains an `event` column:
  `["hook", "event", "runs", "p50ms", "p95ms", "maxms", "sample"]`.
- The `--json` `hooks` array gains an `"event"` key per row (same tuple
  unpack, at the JSON emission site that currently iterates
  `data["hook_durs"].items()`).
- Ranking (`hook_rows` sorts by `max(durations)` descending) is unchanged;
  it now ranks `(label, event)` rows instead of `label` rows.

### Why `(label, event)` and not label-only

A hook script observed firing under `PreToolUse`, `PostToolUse`,
`SessionStart`, `Stop`, and `PostToolUseFailure` in the same transcript is
the concrete case: label-only aggregation would merge five different event
latencies (and, worse, its `Stop` share into the same row that already got
`Stop` counted via `hookInfos`, silently multiplying that hook's slice of
the total). Splitting by event keeps each row honest and makes "which event
is this hook slow under" answerable directly, which is what the item's
"consider showing the event per hook" question was asking.

### Not building

- No change to `hook_label()` itself. It already normalizes script vs.
  inline commands; the fix is what feeds it and how results are keyed, not
  the normalizer.
- No change to `hook_errors` counting (untouched; `hookErrors` is a separate
  field from `hookInfos`/`attachment` and this item does not touch it).
- No de-duplication heuristic beyond the `event == "Stop"` skip. If a future
  transcript shape duplicates a non-Stop event the same way, that is a
  separate, evidence-driven change, not something to guess at now.

## Test plan

New fixture `lib/session/observe/tests/fixtures/hook-events-sample.jsonl`:

| Line | Shape | Purpose |
|---|---|---|
| 1 | `system` entry, `subtype: stop_hook_summary`, `hookInfos: [{"command": "bash /x/stop-hook.sh", "durationMs": 30}]` | existing Stop path, unchanged |
| 2 | `attachment`, `type: hook_success`, `hookEvent: SessionStart`, `command: ~/.claude/hooks/tool-first/tool-first.sh`, `durationMs: 1500` | the missed case: a slow SessionStart hook must now surface |
| 3 | `attachment`, `type: hook_success`, `hookEvent: PreToolUse`, `command: bash /x/pre-hook.sh`, `durationMs: 40` | a second, distinct non-Stop event counts on its own row |
| 4 | `attachment`, `type: hook_success`, `hookEvent: Stop`, `command: bash /x/stop-hook.sh`, `durationMs: 9999` | the duplicate-Stop shape; must be skipped (double-counting rule) |
| 5 | `attachment`, `type: output_style`, no `command`, no `durationMs` | a record with no duration/command; must be skipped without error |
| 6 | `attachment`, `type: hook_success`, `hookEvent: PreToolUse`, `command: bash /x/pre-hook.sh`, `durationMs: 44` | second firing of line 3's hook, for a real p50/max over 2 samples |

## Acceptance criteria

- AC1: `session-observe hooks --file hook-events-sample.jsonl` shows a
  `stop-hook.sh` / `Stop` row with `runs=1`, sourced from `hookInfos`
  (line 1), never `2` (line 4 must not add to it).
- AC2: the same output shows a `tool-first.sh` / `SessionStart` row with
  `runs=1` and `maxms>=1500` (the previously-invisible slow SessionStart
  hook now surfaces).
- AC3: the same output shows a `pre-hook.sh` / `PreToolUse` row with
  `runs=2`, `p50ms` and `maxms` computed over `[40, 44]`.
- AC4: line 5 (no `command`, no `durationMs`) produces no row and no crash;
  total row count is exactly 3 (Stop, SessionStart, PreToolUse), not 4.
- AC5: the `hooks` text table header includes an `event` column between
  `hook` and `runs`; `--json`'s `hooks` array carries `"event"` per row.
- AC6: negative control - reverting the `collect()` attachment branch (the
  old code, `hookInfos`-only) on this same fixture produces only the
  `stop-hook.sh` / `Stop` row; the SessionStart and PreToolUse rows are
  absent, demonstrating the fixture actually exercises the fix and is not
  trivially green.
- AC7: existing `smoke.sh` cases `[4]`, `[5]`, `[6]` (slow-hook flagged,
  fast inline-echo hook stays small, hook-error count) still pass unchanged
  against `tests/fixtures/sample.jsonl` (that fixture carries no
  `attachment` records, so its `hooks` output is byte-identical to before).

## Verification

```
bash lib/session/observe/tests/smoke.sh
```

(new cases for AC1-AC6 land in `smoke.sh` against the new fixture in the same
change that implements this spec; this spec adds no code, so the command
above is run once the implementation phase lands it.)

## Out of scope

- Widening `hook_errors` counting to `attachment` records (this item is
  about durations, not error counts; `hookErrors` already covers errors on
  the `system` entry).
- A `--project`/`--days` interaction change; the fix is inside the existing
  single-pass `collect()`, so filtering is unaffected.
- Deduplicating a hypothetical future duplicate on a non-Stop event; only
  the observed Stop duplication is handled (see Design "Not building").

## Decision log

- `(label, event)` keying chosen over label-only after finding a real
  command that fires under 5 different events in one transcript; label-only
  would have silently mixed a hook's Stop share back into its other-event
  rows.
- The attachment-eligibility check is generic (`command` + `durationMs`
  present), not hardcoded to `attachment.type == "hook_success"`, per the
  item's own phrasing ("hook_success, and any other attachment type that
  carries durationMs and command").
