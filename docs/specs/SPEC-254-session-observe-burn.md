# Spec: session observe burn, live per-session token burn

Generated: 2026-09-10
Status: VALIDATED
Lane: normal (classifier said full; chosen normal per the SPEC-240 precedent: read-only projection, no store, no schema change)
References: `lib/session/observe/bin/session-observe` (the view host); `lib/session/parse_transcript.py` (shared parser); `docs/PHILOSOPHY.md` "Bash over binaries" (hooks bash+jq, lib CLIs stdlib Python); the operator's burn check of 2026-09-10 (four parallel sessions at 300k to 420k context).

**Scope:** one new read-only view in an existing stdlib-only CLI. No new tool, no new dependency, no daemon, no hook.

## Problem

The operator ran several Claude Code sessions in parallel and burned tokens fast. No kit surface could say which session was burning them. `session observe cost` rolls tokens up by model over whole days (`--days` filters on file mtime), so it cannot answer "which session, in the last hour". The answer took a hand-written script over `~/.claude/projects`.

## Solution

### Approaches considered

1. **A `burn` view inside `session-observe`** (chosen). The host already reads the same transcripts and `message.usage` blocks, and stays stdlib-only.
2. A new `lib/session/burn/` tool: a second transcript walker for one view; rejected (rung 2, the reader exists).
3. A `stats` query: `stats` materializes whole-session rows with no per-entry timestamps, so a minutes window cannot be expressed; rejected.

### Chosen approach + why

Add `burn` to the `cmd` choices. It gets its own collector, because `collect()` aggregates by model and day and a burn row is keyed by session with an entry-timestamp window.

## Picture

```
~/.claude/projects/<proj>/<sid>.jsonl ────────────┐
~/.claude/projects/<proj>/<sid>/subagents/*.jsonl ─┼─► burn_collect(since) ─► rank ─► table | --json
~/.claude/sessions/<pid>.json (sessionId) ─────────┘      (dedup by message.id+requestId)
```

## Design

| Decision | Why |
|---|---|
| `burn` lives inside `session-observe` as a view, not a new tool or a `stats` query | The host already parses the same transcripts and usage blocks; see Approaches considered above. |
| Rank key: `input + cache_create + cache_read/10 + output*5` | List-price ratios per token type collapsed into one sortable number, so a session is ranked by cost weight, not raw token count. Attribution, not a bill. |
| `ctx` is the last main-chain assistant usage entry, in file order | A subagent's sidechain turn can carry a different context size. Reading only the main chain keeps `ctx` a true read of the parent session's own live context, not a subagent's. |
| `burn` stays out of `report` | `report` is the weekly digest, built to answer "how did this week go". `burn` answers a live, different question: "what's burning right now". Merging the two would blur two separate check cadences. |

## Technical Design

### Interfaces (I/O contract)

- `session observe burn [--since MIN] [--top N] [--json] [--root DIR | --project SLUG | --file PATH]`.
- `--since` (minutes, default 60) applies to `burn` only. A file whose mtime predates the cutoff is skipped. An entry whose `timestamp` predates the cutoff is not counted.
- One row per top-level session. A subagent transcript at `<sid>/subagents/*.jsonl` rolls into its parent `<sid>`.
- Usage is deduplicated by `(message.id, requestId)`: streamed chunks repeat the same usage block.
- Columns: `session` (first 8 chars), `pid` (live PID whose `~/.claude/sessions/<pid>.json` names this `sessionId`, else `-`), `cwd` (from the first entry carrying `cwd`, shortened), `reqs` (deduplicated assistant usage entries in window), `subs` (subagent transcripts with activity in window), `ctx` (live context: `input + cache_creation + cache_read` of the LAST main-chain assistant usage in the file, regardless of window), `cache-wr`, `cache-rd`, `out`, `idle` (minutes since the last counted entry), `models`, `title` (latest `ai-title`/`summary`/`custom-title` text, truncated).
- Rank key, descending: `input + cache_create + cache_read/10 + output*5` (the list-price ratios; attribution, not a bill). Sessions with zero counted entries are omitted.
- Header line: window minutes, session count, totals for cache-wr, cache-rd, out.
- `--json`: `{"window_min": N, "sessions": [{session_id, pid, cwd, reqs, subagents, ctx, input, cache_create, cache_read, output, idle_min, models, title}]}` in rank order. `burn --json` emits only this shape; other views' JSON is unchanged.
- `report` does NOT include `burn`: report is the weekly digest, burn is a live check.
- Test seams: `SESSION_OBSERVE_NOW` (epoch seconds) replaces the clock; `SESSION_OBSERVE_PIDS_DIR` replaces `~/.claude/sessions`. PID liveness is `os.kill(pid, 0)`; under `SESSION_OBSERVE_PIDS_DIR` the liveness check is skipped so fixtures stay deterministic.

### Data model changes

None.

### API / UI / Infrastructure changes

None.

## Task Breakdown

### Phase 1

- TASK-001: `burn` collector, rank, table, `--since`, `--json`, the two env seams in `session-observe`.
- TASK-002: fixtures under `tests/fixtures/burn/` and smoke cases in `tests/smoke.sh`.
- TASK-003: `lib/session/observe/README.md` view list + usage line; any MANUAL surface that lists observe views.

## Verification

Run `bash lib/session/observe/tests/smoke.sh`. All cases pass, including new cases that prove:

1. An entry older than `--since` is not counted (negative control: the same fixture with a wider `--since` counts it).
2. A subagent transcript rolls into its parent row, and `subs` counts it.
3. A duplicated `(message.id, requestId)` usage block counts once.
4. `ctx` ignores sidechain usage (a sidechain turn with a larger context does not change it).
5. Rank order follows the rank key (a high cache-write session outranks a higher-reqs low-token one).
6. The PID column maps through `SESSION_OBSERVE_PIDS_DIR`; an unmapped session shows `-`.
7. `burn --json` is valid JSON with `window_min` and ranked `sessions`.
8. `report` output has no burn section (existing views unchanged).

Live check on the operator host: `session observe burn --since 60` finishes in under 5 seconds and names the same top session as a hand check.

## After state

- `session observe burn` answers "which session is burning tokens right now" in one command.
- The hand-written burn script is retired; the kit view replaces it.
