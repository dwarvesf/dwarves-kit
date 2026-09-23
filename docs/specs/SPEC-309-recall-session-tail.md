# Spec: session recall --tail shows what one session is doing now

Generated: 2026-09-23
Status: DRAFT (branch `feat/recall-session-tail`)
Lane: full
Type: spec-feature
File: `docs/specs/SPEC-309-recall-session-tail.md`
References: `lib/session/recall/session_recall.py` (`resolve_files`, `resolve_project_dirs`, `opening_ask`, `SECRET_SHAPE_RE`, `DATA_MARKER`, `main`); `lib/session/recall/tests/test_recall.py`; `lib/session/recall/README.md`; `commands/wrap.md` step 7b "first rungs" paragraph.

## Problem

Several sessions often run in one repo at once. An operator asks "another session is on this, take a look first". The kit answers "which session did X" with `session recall <terms> --sessions`, which prints session ids. Nothing answers the next question: what is that session doing right now. On 2026-09-23 a session answered it with a hand-written `jq` over the peer transcript: the last user prompts, the last assistant text lines, and the file mtime. The same pass was needed to avoid re-running a battery, a land and a deploy that a peer had already done.

## Solution

### Approaches considered

1. **A `--tail <id>` flag on `session recall`.** Reuses `load`, project resolution, the secret redaction and the DATA marker already in the file. One more mode in one argument parser.
2. **A new `session tail` verb in `lib/session/session.sh` with its own script.** Clean verb name. Duplicates project resolution and redaction, or imports them across tools, and adds a wiring-exempt entry.
3. **Extend `--sessions` to print the last lines under each row.** No new flag. Makes the "which session" view long and mixes two questions into one output.

### Chosen approach + why

Approach 1. `precedent find` names `session-recall` as the home, and every helper the view needs already lives there. The flag is a separate mode: `--tail` takes no query, so the query-search code path does not change.

### Design record

- `--tail <prefix>`: the session id prefix (a transcript basename without `.jsonl`). Resolution uses the same file set as a query: `--file`, `--project`, `--all`, or the cwd project. A prefix matching no file exits 1. A prefix matching two or more files exits 2 and lists the matched ids. A prefix shorter than 4 characters exits 2 (usage).
- A query together with `--tail` exits 2 (usage): one mode per call.
- Kept turns, in conversation order: human prompts (a `user` turn whose content is a string, or its `text` blocks) and assistant `text` blocks. Dropped: tool calls, tool results, thinking, and any text starting with `<` (hook and system blocks), the same skip rule as `opening_ask`.
- The last `--limit` kept turns print (default 10 in this mode; the query default of 50 is unchanged).
- One line per turn: `HH:MM  user|asst  <text>`. Whitespace collapses to single spaces, lines cap at 200 characters with `…`, and `SECRET_SHAPE_RE` redacts to `[redacted]`.
- Header: `# tail of <sid>: last write <YYYY-MM-DD HH:MM>, <N>m ago`, then `DATA_MARKER`. The age is what tells a live session from a dead one.
- `--json`: `{data_marker, session, file, mtime, turns:[{ts, role, text}]}` with the same redaction and cap.

### Extensibility & boundaries

Read-only: opens transcripts, never writes. No daemon, no polling; a watcher re-runs the command. No model call.

## Picture

```
operator: "a peer is on this, take a look"
        |
        v
session recall <terms> --sessions   -->  2026-09-23 20:18  5ae3f7a2-...  15 hits  <opening ask>
        |
        v
session recall --tail 5ae3f7a2      -->  # tail of 5ae3f7a2-...: last write 20:18, 1m ago
                                         20:05  asst  Episode 1's id is pw1V2...
                                         20:09  asst  Running cli/dispatch memo ...
```

## After state

`session recall --tail <prefix>` prints the recent prompts and replies of one session with its idle age. `commands/wrap.md` step 7b names it beside `--sessions` as a first rung. The recall README documents the flag.

## Acceptance Criteria (global)

- AC1: `--tail <prefix>` on a fixture prints the header, the DATA marker, and the last N kept turns in conversation order, with `--limit N` honored and 10 as the default.
- AC2: tool calls, tool results, thinking, and `<`-prefixed text never print.
- AC3: a secret shape in a kept turn prints as `[redacted]`, in text and JSON output.
- AC4: an unknown prefix exits 1; an ambiguous prefix exits 2 and names every match; a prefix under 4 characters, a missing value, or a query beside `--tail` exits 2.
- AC5: `--json` returns the documented keys.
- AC6: every existing `test_recall.py` case still passes, and the query and `--sessions` paths print the same output as before.

## Test plan

| Case | AC | Kind |
|---|---|---|
| fixture with 14 kept turns: default prints last 10, `--limit 3` prints last 3, order ascending | AC1 | unit (subprocess) |
| fixture turns of each dropped kind are absent from output | AC2 | unit |
| a `ghp_` token and an `op://` ref in a prompt print as `[redacted]`, text and JSON | AC3 | unit |
| unknown prefix rc 1; two files sharing a prefix rc 2 with both ids; `--tail ab` rc 2; `--tail` last arg rc 2; `foo --tail x` rc 2 | AC4 | unit |
| JSON keys and turn shape | AC5 | unit |
| full existing suite | AC6 | regression |
| real run: `--tail` on a live peer session in `~/.claude/projects` | AC1 | behavioral, recorded in the proof |

## Verification

```
python3 -m unittest lib/session/recall/tests/test_recall.py -v
bash tests/test-bin-forwarders.sh
bash lib/gate/negctl.sh "$PWD" "python3 -m unittest lib/session/recall/tests/test_recall.py" "git show origin/master:lib/session/recall/session_recall.py > lib/session/recall/session_recall.py"
```

Proof of done: `docs/verification/recall-session-tail.md`.

## Edge Cases

- A transcript being written while read: `load` already skips a torn last line.
- A session with no kept turns: header plus `(no prompts or replies yet)`.
- A prefix that is a full id: matches one file.

## Out of Scope

- Mapping a `ListAgents` session name to a transcript id.
- Live follow mode.
- Showing tool calls.

## Decision Log

- Home is `session-recall`, not a new verb: precedent hit, shared helpers.
- Default limit 10 in tail mode: one screen, enough to see the current step.
