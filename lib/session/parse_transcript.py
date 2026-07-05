#!/usr/bin/env python3
"""parse_transcript.py -- the shared JSONL turn-parser for Claude Code transcripts
(~/.claude/projects/<slug>/*.jsonl).

This is the ONE genuinely-duplicated routine between session-observe (aggregate
usage/latency stats, streamed across many files) and session-recall (point-lookup
search, materialized per file for indexed access): open a transcript, read it line
by line, skip blank lines, `json.loads` each remaining line, and skip -- never
crash on -- a malformed line. That is the full scope of the shared contract.

Everything past that point (role/timestamp extraction, hook/tool/skill tallying,
searchable-text rendering, the whole aggregate `collect()` pass) stays each
caller's OWN business logic. Forcing that into one shape would be the artificial
merge open-Q 1 explicitly rejected (resolved (b): extract the parser, keep two
CLIs) -- session-observe answers "what happened across N sessions" (a table);
session-recall answers "find me this one past thing" (a snippet). One entry
schema, two different questions asked of it.

Contract:
  iter_entries(path) -> Iterator[dict]
      Stream one parsed JSON object per valid line, in file order. A blank line
      is skipped. A line that fails `json.loads` is skipped silently (this
      matches BOTH source tools' pre-extraction behavior byte-for-byte; the
      schema is untrusted input, so a single bad line must never abort the scan).
      Raises FileNotFoundError / OSError if `path` itself cannot be opened --
      the CALLER decides what that means (session-observe's many-file scan
      lets a missing file just contribute zero entries; session-recall's
      single --file mode wants to surface it). Yields nothing for an empty
      file (honest-zero, not an error).

  load(path) -> list[dict]
      `list(iter_entries(path))` -- for a caller that needs random-access
      indexing (session-recall's turn index) rather than a stream.

Both are driven off the SAME inner loop, so the parsing behavior (encoding,
blank-line skip, decode-skip) can only drift in one place.

Also runnable as a CLI (see `lib/session/parse-transcript.sh`, its thin bash
launcher): `parse-transcript.sh <transcript.jsonl>` prints one JSON object per
successfully-parsed line to stdout (NDJSON), so the shared parser is exercisable
and testable as a standalone unit, independent of either CLI that embeds it.
"""
from __future__ import annotations

import json
import sys
from typing import Iterator


def iter_entries(path: str) -> Iterator[dict]:
    """Yield each successfully-parsed JSON object in `path`, in file order.

    Malformed / blank lines are skipped, never raised. A missing or unreadable
    `path` raises (FileNotFoundError / PermissionError / OSError) so the caller
    can decide whether that is a per-file skip or a reported error.
    """
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def load(path: str) -> list:
    """Materialize iter_entries(path) into a list (for random-access callers)."""
    return list(iter_entries(path))


def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else list(argv)
    if not argv:
        sys.stderr.write("usage: parse-transcript.sh <transcript.jsonl>\n")
        return 2
    path = argv[0]
    try:
        for entry in iter_entries(path):
            sys.stdout.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError as e:
        sys.stderr.write(f"parse-transcript: {e}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
