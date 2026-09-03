> Renamed 2026-07-11 (kit naming invariant, function-named callables): the CLI
> names below read `cc-*` historically; the shipped callables are now
> `session-intel` / `session-observe` / `session-semantic` / `session-report` /
> `session-recall`, env knobs `SESSION_INTEL_*` / `SESSION_SEMANTIC_*` / `SESSION_REPORT_*`.

# session-recall

Lossless, turn-grouped **recall** over Claude Code transcripts. A read-only,
structure-preserving substring search over the raw `~/.claude/projects/<slug>/*.jsonl`
files, so a live session can retrieve a prior decision or fact straight from the source
transcript , even across compactions , without re-reading whole files or repeating work.

Ports pi-vcc's `vsession_recall`. Companion to [`cc-deterministic-compaction`](../../experiments/cc-deterministic-compaction/)
(the compactor that drops volatile detail; recall gets it back) and to `prose-rag`
(semantic search over prose, which this deliberately does **not** duplicate , this is
exact structure-preserving grep over transcript JSONL).

## Why it is lossless

The raw JSONL is the source of truth and is never mutated. Compaction can drop a tool
result or an intermediate decision from the working context; recall still finds it,
because it searches the file on disk, not the compacted view.

## Use

```
session-recall "<query>"                      # search the current project (slug from cwd)
session-recall "<query>" --project <slug>     # a specific ~/.claude/projects/<slug>
session-recall "<query>" --project ops-toolkit  # or the repo name: every slug ending in -ops-toolkit
session-recall "<query>" --all                # every project
session-recall "<query>" --project ops-toolkit --sessions   # WHICH sessions: one line per
                                              # transcript, newest first, hit count + opening ask
session-recall "<query>" --file <path.jsonl>  # one transcript file
session-recall "<query>" --json --limit 20    # machine-readable, capped
```

Output is **grouped by turn** , each hit shows the turn index, role, timestamp, and a
one-line snippet with the match marked `»…«`:

```
── turn 2 · assistant · 2026-06-29T09:00:02Z ──
  Going with a »manual backoff loop because we avoid« adding a new dependency…
```

Matching is case-insensitive phrase substring over each turn's full text (prose,
thinking, tool inputs, tool results). No match -> empty stdout, clean exit (advisory tool).

## Layout

```
bin/session-recall        executable CLI wrapper
session_recall.py         the search module (stdlib only; shares SG-01's JSONL parser)
fixtures/seed.jsonl  synthetic seed transcript (zero PII; shared with SG-01)
tests/test_recall.py
docs/proof-of-done.md
```

## Scope

Read-only. Never mutates a transcript. Not an embedding index (use `prose-rag` for
semantic search), not a daemon, not cross-project fuzzy ranking. Part of token-optim-v3.
