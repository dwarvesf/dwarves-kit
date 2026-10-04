# Spec: session observe hooks counts every hook event, not just Stop

Generated: 2026-09-28
Status: VALIDATED (round 3: 0 critical, 4 warnings, folded below). Prior rounds: round 1 (NEEDS REVISION, 2 critical, 6 warnings), round 2 (NEEDS REVISION, 1 critical, 6 warnings).
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

A broader scan across every project's transcripts (main files plus
`subagents/*.jsonl`) also finds `SubagentStart` (about 4.7k `attachment`
records) and `SubagentStop` (about 1.0k), both `attachment`-sourced with
`command` and `durationMs`, and both confined to `subagents/*.jsonl` files
where `hookInfos` never appears. They are ordinary non-Stop events for this
fix; see Design for why the Stop skip must not reach them.

The same broader scan finds `hook_cancelled` (a hook that hit its timeout,
`timedOut: true`, observed durations up to roughly 10s) and
`hook_non_blocking_error` (a hook that exited non-zero without blocking the
turn, 5 seen) attachments. Both carry `command` and `durationMs` and fall
under the same generic eligibility rule this spec uses; see Design for the
decision to count them.

The same real transcript shows a Stop hook recorded TWICE: once in
`hookInfos` (already counted) and again as an `attachment` with
`hookEvent: "Stop"` (would double-count if aggregated blindly). And some
commands (an install-time relay script observed in this transcript) fire
under five different events (`PreToolUse`, `PostToolUse`, `SessionStart`,
`Stop`, `PostToolUseFailure`) with the same script basename, so a single
`hook` label would otherwise merge unrelated event latencies into one row.

Some `attachment` records carry no `command` and no `durationMs` (for example
`hook_system_message`, `instructions`, `output_style`); those must be skipped,
not counted as a zero-duration hook.

**Headless gap: a plain `event == "Stop"` skip is wrong for some
transcripts.** `claude -p` runs (transcripts with `"entrypoint": "sdk-cli"`)
never write the `system` entry that carries `hookInfos`, so they have no
`stop_hook_summary` at all; their only record of a Stop hook is the
`attachment` copy. A scan of every local transcript file found 12 such
files (Stop attachments present, no `hookInfos` anywhere in the file) and 84
files carrying both sources, where every Stop attachment's command was
already a subset of that file's `hookInfos` commands (0 violations out of
84). A global `event == "Stop"` skip would silently zero out Stop-hook
latency for those 12 headless files: exactly the SessionStart-style blind
spot this item exists to close, just on a different event. The rule has to
be per file, not global; see Design.

A separate, smaller gap in the existing code: the current `hookInfos` branch
reads `h.get("durationMs") or 0`, so an entry with no `durationMs` counts as a
zero-ms sample instead of being skipped. Roughly 8 percent of `hookInfos`
entries in a broad transcript scan carry no `durationMs`; each one quietly
drags the Stop percentiles down today.

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
folded in. The real relay-script command in the Problem's evidence, observed
firing under five different events in one transcript, shows label-only
keying is not speculative caution: it would have merged that hook's Stop
share back into rows that `hookInfos` already counted. The Test plan below
adds a fixture line reproducing the same shape (one command under two
different events), so the split is exercised, not just argued for.

## Design

### Routing diagram

Per-file state (`stop_buffer = []`, `file_has_hookinfos = False`) resets at
the top of each `for path in iter_files(args):` iteration.

Stage 1, per entry inside one file:

```
                    entry in collect()'s single pass over one FILE
                                        |
                +-----------------------------------------------+
                |                                                |
       type == "system"                                type == "attachment"
   hookInfos: [{command, durationMs}]              attachment: {type, command,
                |                                    durationMs, hookEvent, ...}
                v                                                v
   file_has_hookinfos = True          attachment a dict, command a non-empty
                |                     string, durationMs a number, excluding
   for each h in hookInfos:           bool?  --no--> skip record
   durationMs a number,                                          |
   excluding bool? --no--> skip h                                yes
                |                                                 v
               yes                                  event = attachment["hookEvent"]
                v                                     (fallback "?" if not a
   key = (hook_label(command),                          non-empty string)
          "Stop")                                                |
                |                                    event == "Stop"?
                |                                yes /            \ no
                |                                   v               v
                |                    stop_buffer.append(    key = (hook_label
                |                     (key, durationMs,             (command), event)
                |                      sample))                       |
                |                    (held, not committed yet)        |
                v                                                     v
   hook_durs[key].append(durationMs)                hook_durs[key].append(durationMs)
   hook_sample[key] = command[:60]                   hook_sample[key] = command[:60]
```

Stage 2, once the file's entries are exhausted (still inside the same
`for path in iter_files(args):` iteration, before moving to the next file):

```
   if not file_has_hookinfos:                 # sdk-cli / headless file:
       for (key, dur, sample) in stop_buffer:  # its Stop attachments are
           hook_durs[key].append(dur)          # the only record of its
           hook_sample.setdefault(key, sample) # Stop hooks, so keep them
   else:
       discard stop_buffer                     # a file with hookInfos already
                                                 # counted every Stop hook there
```

Stage 3, after every file:

```
        hook_rows() unpacks (label, event) per key in hook_durs
                                          |
                        +------------------------------+
                        |                                |
                  hooks text table                  --json "hooks"
             hook/event/runs/p50ms/               [{"hook", "event",
             p95ms/maxms/sample                     "count", "p50_ms", ...}]
```

### The change

In `collect()`, at the existing `hookInfos` block (`lib/session/observe/bin/session-observe`,
around line 364-372):

- `hook_durs` and `hook_sample` become keyed by a `(label, event)` tuple, not
  a bare label.
- Every `hookInfos[]` entry keys as `(hook_label(command), "Stop")` (the
  `stop_hook_summary` subtype is the only source of `hookInfos` in observed
  transcripts, so this is not a guess dressed as data; it is what the field
  means today).
- The `hookInfos` branch now skips an entry whose `durationMs` is missing or
  not a number, instead of the current `h.get("durationMs") or 0`. "Number"
  means `isinstance(x, (int, float))` **excluding `bool`**: `True`/`False`
  are `int` subclasses in Python, so a naive `isinstance` check would accept
  a stray boolean as a duration. Counting a missing duration as zero silently
  drags the Stop percentiles down; skipping it matches "no duration recorded
  means not counted," the same rule the new attachment branch uses. This is
  a small independent fix riding along with the main one, on the same field,
  in the same block.
- A new branch, alongside the `hookInfos` branch, handles
  `entry.get("type") == "attachment"`:
  - Skip unless `attachment` is a dict, `attachment["command"]` is a
    non-empty string, and `attachment["durationMs"]` is a number per the same
    int-or-float-excluding-bool check above. This is the general rule the
    item asks for ("any other attachment type that carries `durationMs` and
    `command`"): it does not special-case `hook_success` by name, so a
    future attachment type with the same two fields is picked up
    automatically, and one missing either field (no `command`, no
    `durationMs`) is skipped rather than counted as zero.
  - **Decision: this generic rule also counts `hook_cancelled` and
    `hook_non_blocking_error` attachments**, both of which carry `command`
    and `durationMs` in observed transcripts. This is deliberate, not an
    accepted side effect: a cancelled (timed-out) or non-blocking-failed
    hook still occupied turn time, and excluding it would hide exactly the
    worst-case hooks this view exists to surface. The existing `hookErrors`
    counter is **not** a safety net against double-counting here: in
    observed transcripts every non-empty `hookErrors` list sits on a
    `stop_hook_summary` system entry (Stop only), and most `hook_cancelled`
    / `hook_non_blocking_error` attachments fire under non-Stop events (a
    broad scan found 57 of 64 non-Stop). Those never reach `hookErrors` at
    all, so the `hooks` view is the only place their cost shows up; it is
    not a duplicate of an existing error signal. The small Stop-event share
    of these attachments is excluded by the `event == "Stop"` skip below,
    same as any other Stop attachment.
  - Read `event = attachment.get("hookEvent")` (fall back to `"?"` if not a
    non-empty string).
  - **`event == "Stop"` is buffered per file, not skipped outright.** A
    global skip is wrong for a headless (`entrypoint: sdk-cli`) transcript,
    which never writes a `hookInfos`-carrying `system` entry at all (see
    Problem, "Headless gap"). Instead: hold the `(key, durationMs, sample)`
    tuple in a per-file `stop_buffer` list. Once the file's entries are
    exhausted, commit the whole buffer into `hook_durs`/`hook_sample` only
    if that file had **no** `hookInfos` entries anywhere in it
    (`file_has_hookinfos` stays `False`); otherwise discard the buffer,
    because that file's `hookInfos` already counts every Stop hook in it
    (the item's "double-counting rule," now scoped per file instead of
    globally, since the 84-file scan found the two sources agree file by
    file, not just in aggregate).
  - A non-Stop `event` keys directly as `(hook_label(attachment["command"]),
    event)` and appends `durationMs` immediately, same as the `hookInfos`
    branch; no buffering needed, since there is no cross-source duplicate to
    reconcile outside Stop.
  - **`SubagentStart` and `SubagentStop` are ordinary non-Stop events under
    this rule.** The skip is a literal `event == "Stop"` string check;
    `"SubagentStop" != "Stop"`, so a subagent-lifecycle hook is counted like
    any other non-Stop event and is never skipped. Stated explicitly because
    the two strings look related: the fix does not special-case subagent
    events, and must not start special-casing them later without new
    evidence.
- `hook_rows()` unpacks the tuple key and returns `[label, event, count, p50,
  p95, max, sample]` (event inserted after label, before the count column,
  so the existing count/p50/p95/max/sample columns keep their relative
  order).
- The `hooks` text table gains an `event` column:
  `["hook", "event", "runs", "p50ms", "p95ms", "maxms", "sample"]`.
- The `--json` `hooks` array gains an `"event"` key per row (same tuple
  unpack, at the JSON emission site that currently iterates
  `data["hook_durs"].items()`). **This changes the array's cardinality**:
  today one entry per hook label; after this change, one entry per
  `(label, event)` pair. A hook firing under N distinct events now
  contributes N array entries instead of one. No consumer inside this repo
  reads `--json hooks` today (vps-mon ingest reads `report`'s other
  sections), but the shape change is real and belongs in the module's own
  `SPEC.md`, not only in this cross-cutting spec (see Task breakdown, T2).
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
- No change to `hook_errors` counting beyond what is already unchanged above
  (untouched; `hookErrors` is a separate field from `hookInfos`/`attachment`
  and this item does not touch it).
- No de-duplication heuristic beyond the per-file Stop reconciliation and the
  missing-duration skip. If a future transcript shape duplicates a
  non-Stop event the same way, that is a separate, evidence-driven change.

## Task breakdown

| Task | Files | Depends on |
|---|---|---|
| T1: attachment aggregation, `(label, event)` keying, per-file Stop buffering, skip-missing on both branches, `hook_cancelled`/`hook_non_blocking_error` coverage, fixtures + smoke tests | `lib/session/observe/bin/session-observe`, `lib/session/observe/tests/fixtures/hook-events-sample.jsonl`, `lib/session/observe/tests/fixtures/hook-events-sdkcli-sample.jsonl`, `lib/session/observe/tests/smoke.sh` | none |
| T2: docs | `lib/session/observe/README.md` ("What it reads" hooks bullet + the sample `# hooks` output table + the "Limits" line at `README.md:81`), `lib/session/observe/SPEC.md` (hooks purpose bullet, the "Source" paragraph, the `collect` behaviour `hookInfos[]` bullet, the stale "Hook labels" known-limitation line, and the `## Verification (acceptance criteria)` smoke-case list at `SPEC.md:74-80`, extended to describe the new fixtures and cases), `bin/session-observe` module docstring | T1 |

T1 carries 10 acceptance criteria (AC1-AC10, see Acceptance criteria) as one
task; it stays one task. It is not split into T1a/T1b unless the diff grows
past what one task can hold; if that happens, the `hookInfos` skip-missing
fix (AC1, AC6, AC9) is the natural first slice (independently valuable, low
risk), with attachment aggregation and per-file Stop buffering following.

T2 also corrects the same stale "fragment by first word" line in TWO places,
not one: `SPEC.md`'s "Hook labels" paragraph and the near-identical line in
`README.md`'s "Limits" section (`README.md:81`). Both say long-text inline
hooks fragment by first word, and both are already wrong:
`hook_label()`'s `len(c) > 120` check routes any long command (not just ones
starting with `echo`) to the stable `inline-echo:<hash>` branch before the
first-word fallback runs, and `tests/fixtures/goal-hook-sample.jsonl` already
proves distinct long-text hooks (alpha/beta/gamma) land in separate rows, not
one merged-by-first-word row (see
`lib/session/observe/docs/implementation-notes/02-goal-hook-collapse.md`).
Unrelated to this spec's fix, but T2 already opens both files, so both stale
lines are corrected in the same edit pass.

T2 also extends `SPEC.md`'s `## Verification (acceptance criteria)` numbered
list (currently ending at item 22, plus a "Plus, against `sample.jsonl`'s
three appended usage entries" block) with a new block in the same style:
"Plus, against `hook-events-sample.jsonl`" (the AC1-AC9 cases) and "Plus,
against `hook-events-sdkcli-sample.jsonl`" (the AC10 headless case), so the
module's own spec stays the single source for what `smoke.sh` actually
checks.

## Test plan

New fixture `lib/session/observe/tests/fixtures/hook-events-sample.jsonl`
(a transcript that HAS `hookInfos`, i.e. not headless):

| Line | Shape | Purpose |
|---|---|---|
| 1 | `system` entry, `subtype: stop_hook_summary`, `hookInfos: [{"command": "bash /x/stop-hook.sh", "durationMs": 30}]` | existing Stop path, unchanged |
| 2 | `system` entry, `subtype: stop_hook_summary`, `hookInfos: [{"command": "bash /x/nodur-hook.sh"}]` (no `durationMs`) | `hookInfos`-branch skip-missing: must produce no row, not a zero-ms row |
| 3 | `attachment`, `type: hook_success`, `hookEvent: SessionStart`, `command: ~/.claude/hooks/tool-first/tool-first.sh`, `durationMs: 1500` | the missed case: a slow SessionStart hook must now surface |
| 4 | `attachment`, `type: hook_success`, `hookEvent: PreToolUse`, `command: bash /x/pre-hook.sh`, `durationMs: 40` | a non-Stop event, first sample |
| 5 | `attachment`, `type: hook_success`, `hookEvent: Stop`, `command: bash /x/stop-hook.sh`, `durationMs: 9999` | the duplicate-Stop shape; this file has `hookInfos`, so the buffered copy is discarded (double-counting rule) |
| 6 | `attachment`, `type: output_style`, no `command`, no `durationMs` | a record with neither field; must be skipped without error |
| 7 | `attachment`, `type: hook_success`, `hookEvent: PreToolUse`, `command: bash /x/pre-hook.sh`, `durationMs: 44` | second firing of line 4's hook, for a real p50/max over 2 samples |
| 8 | `attachment`, `type: hook_success`, `hookEvent: PostToolUse`, `command: bash /x/pre-hook.sh`, `durationMs: 70` | same command as lines 4/7 under a different event: proves the `(label, event)` split, not label-only aggregation |
| 9 | `attachment`, `type: hook_cancelled`, `hookEvent: SessionStart`, `command: ~/.claude/hooks/repo-memory/repo-memory.sh`, `durationMs: 3500`, `timedOut: true` | a timed-out hook is still counted (Design decision) |

New fixture `lib/session/observe/tests/fixtures/hook-events-sdkcli-sample.jsonl`
(a headless transcript, `"entrypoint": "sdk-cli"`, with NO `system`/`hookInfos`
entry anywhere, matching the 12 real files found in the headless-gap scan):

| Line | Shape | Purpose |
|---|---|---|
| 1 | `attachment`, `type: hook_success`, `hookEvent: Stop`, `command: bash /x/headless-stop-hook.sh`, `durationMs: 25` | the only record of a Stop hook in a headless transcript; must be counted, not skipped, because the file has no `hookInfos` |

## Acceptance criteria

- AC1: `stop-hook.sh` / `Stop` row shows `runs=1`, sourced only from
  `hookInfos` line 1; the attachment Stop duplicate (line 5) and the
  no-duration `hookInfos` entry (line 2, a different command) do not add to
  it or produce a row of their own.
- AC2: `tool-first.sh` / `SessionStart` row shows `runs=1`, `maxms>=1500`
  (the previously-invisible slow SessionStart hook now surfaces).
- AC3: `pre-hook.sh` / `PreToolUse` row shows `runs=2`, `p50ms` and `maxms`
  computed over `[40, 44]`.
- AC4: `pre-hook.sh` / `PostToolUse` row shows `runs=1`, `maxms=70`, and is a
  separate row from the `PreToolUse` row for the same command: proves the
  `(label, event)` split, not label-only aggregation.
- AC5: `repo-memory.sh` / `SessionStart` row (from the `hook_cancelled`
  attachment, line 9) shows `runs=1`, `maxms>=3500`: a cancelled/timed-out
  hook is counted, per the Design decision.
- AC6: line 2 (`hookInfos` entry with no `durationMs`) and line 6
  (attachment with no `command`, no `durationMs`) each produce no row and no
  crash. The fixture's total row count is exactly 5: `stop-hook.sh`/`Stop`,
  `tool-first.sh`/`SessionStart`, `pre-hook.sh`/`PreToolUse`,
  `pre-hook.sh`/`PostToolUse`, `repo-memory.sh`/`SessionStart`.
- AC7: the `hooks` text table header is
  `hook  event  runs  p50ms  p95ms  maxms  sample` (`event` between `hook`
  and `runs`). `--json`'s `hooks` array carries an `"event"` key per row and
  has one entry per `(hook, event)` pair, not one per hook label: a
  documented cardinality change (see Design), not an oversight. `--top N`
  now caps the number of `(hook, event)` rows returned, not the number of
  distinct hook labels: a hook firing under 3 events can occupy up to 3 of
  those N slots, where before this change it occupied at most 1.
- AC8: `smoke.sh` cases `[4]` and `[5]` (slow-hook flagged, fast inline-echo
  hook stays small) are updated to read column `$6` for `maxms`, not `$5`.
  The new `event` column shifts `maxms` from column 5 to column 6; with the
  old `$5` both cases would coincidentally still pass against
  `sample.jsonl`, because every hook there has exactly one duration sample
  so `p95` equals `max`, which is a coincidental pass, not a real one. Case
  `[6]` (hook-error count) is unaffected, it greps a fixed string, not a
  column. `sample.jsonl` carries no `attachment` records, so its `hooks`
  output keeps the same rows and duration values as before, with `event`
  added as `Stop` on every existing row and the new header column; it is
  **not** byte-identical to the pre-change output.
- AC9: the negative control reverts `session-observe` to its whole pre-fix
  version (the file as it stands before this spec's implementation lands,
  for example `git show <base-ref>:lib/session/observe/bin/session-observe`
  applied over the fixture run), not just one branch. That means no
  attachment aggregation, no `(label, event)` keying, no `event` column, and
  the old `h.get("durationMs") or 0` behaviour. On `hook-events-sample.jsonl`
  it produces exactly 2 rows total, both keyed by label only: `stop-hook.sh`
  (from `hookInfos` line 1, `runs=1`, `maxms=30`) and `nodur-hook.sh` (from
  `hookInfos` line 2, wrongly shown with `runs=1`, `maxms=0`, because the old
  code counts a missing duration as zero). No SessionStart, PreToolUse,
  PostToolUse, or cancelled-hook rows appear at all. This demonstrates the
  fixture actually exercises every part of the fix and is not trivially
  green either way.
- AC10: on `hook-events-sdkcli-sample.jsonl` (no `system`/`hookInfos` entry
  anywhere), `headless-stop-hook.sh` / `Stop` row shows `runs=1`,
  `maxms=25`, sourced entirely from the `attachment` (line 1), because
  `file_has_hookinfos` stays `False` for this file and the buffered Stop
  duration is committed instead of discarded. Run alongside
  `hook-events-sample.jsonl` in the same `smoke.sh` invocation (two separate
  `--file` calls) to prove the per-file reconciliation is scoped correctly:
  the sdk-cli file's Stop row appears while the other file's duplicate Stop
  attachment (its own AC1) still does not.
- AC11 (docs): `README.md`'s "What it reads" hooks bullet, its sample
  `# hooks` output table, and its "Limits" line at `README.md:81`;
  `SPEC.md`'s hooks purpose bullet, its "Source" paragraph, its `collect`
  behaviour `hookInfos[]` bullet, its "Hook labels" known-limitation line,
  and its `## Verification (acceptance criteria)` smoke-case list at
  `SPEC.md:74-80` (extended with the new fixtures, per Task breakdown); and
  the `bin/session-observe` module docstring: all updated to say hook
  durations come from `hookInfos` (Stop only, via `stop_hook_summary`, and
  only when the file carries no other Stop source) plus `attachment`
  records (`hook_success`, `hook_cancelled`, `hook_non_blocking_error`, or
  any future type carrying `command` and `durationMs`) for every other
  event, plus Stop on a headless file; the sample table shows the `event`
  column.

## Verification

```
bash lib/session/observe/tests/smoke.sh
```

(new cases for AC1-AC10 land in `smoke.sh` against the two new fixtures in
the same change that implements this spec.)

## Out of scope

- Widening `hook_errors` counting to `attachment` records beyond what is
  already unchanged (this item is about durations, not error counts;
  `hookErrors` already covers errors on the `system` entry).
- A `--project`/`--days` interaction change; the fix is inside the existing
  single-pass `collect()`, so filtering is unaffected.
- Deduplicating a hypothetical future duplicate on a non-Stop event; only
  the observed Stop duplication is handled (see Design "Not building").
- Resolving duplicate hook-attachment records across resumed or forked
  copies of the same transcript (observed: roughly 172 of about 65k hook
  attachment keys appear in more than one transcript file in a broad
  multi-repo scan). This predates this spec: `collect()` already processes
  each file returned by `iter_files(args)` independently with no cross-file
  dedup, for every counter it tracks, not only hooks.

## Decision log

- `(label, event)` keying chosen over label-only after finding a real
  command that fires under 5 different events in one transcript; label-only
  would have silently mixed a hook's Stop share back into its other-event
  rows.
- The attachment-eligibility check is generic (`command` + `durationMs`
  present), not hardcoded to `attachment.type == "hook_success"`, per the
  item's own phrasing ("hook_success, and any other attachment type that
  carries durationMs and command").
- `hook_cancelled` and `hook_non_blocking_error` are counted, not filtered
  out: a cancelled or failed hook still cost turn time, and excluding it
  would hide the worst-case hooks this view exists to surface.
- The Stop skip is a literal string match against `"Stop"` only.
  `SubagentStart`/`SubagentStop` are left untouched on purpose; the fix does
  not audit or special-case them.
- The Stop-attachment skip is per file, not global: buffer, then commit only
  if the file has no `hookInfos`. Chosen after finding 12 real headless
  (`entrypoint: sdk-cli`) transcripts with Stop attachments and no
  `hookInfos` at all, and 84 files with both sources where the two always
  agreed (0 violations); a global skip would have zeroed Stop-hook latency
  for every headless transcript, reintroducing the same blind spot this
  item exists to close.
- Both branches (`hookInfos` and `attachment`) now skip an entry with no
  usable `durationMs` instead of counting it as zero: consistent behavior,
  matching real data where roughly 8 percent of `hookInfos` entries carry no
  `durationMs`.
- The `--json` `hooks` array's cardinality change (one row per hook to one
  row per `(hook, event)`) is called out explicitly here and lands in this
  module's own `SPEC.md` in the same change (T2), per validation feedback.
- The numeric check on both branches excludes `bool` explicitly
  (`isinstance(True, int)` is true in Python), so a stray boolean value
  never counts as a duration.
- `hookErrors` is not treated as already covering `hook_cancelled` /
  `hook_non_blocking_error`: it only appears on `stop_hook_summary` (Stop)
  entries in observed transcripts, and most of those two attachment types
  fire under non-Stop events, so counting their durations in `hooks` is not
  a duplicate signal.
