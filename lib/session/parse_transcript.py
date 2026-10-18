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
  parse_lines(lines) -> Iterator[dict]
      The inner loop of `iter_entries`, factored out so a caller with lines
      from somewhere other than a whole open file (session-recall's tail
      chunk reader: a byte-range read, decoded with errors="replace" before
      splitting) gets the same blank/decode-error/non-dict skip rules instead
      of a hand-copied loop.

  iter_entries(path) -> Iterator[dict]
      Stream one parsed JSON *object* per valid line, in file order. A blank
      line is skipped. A line that fails `json.loads`, OR that decodes to
      valid JSON that is not an object (a bare array/string/number/bool/null,
      e.g. `["x"]`), is skipped silently (this matches BOTH source tools'
      pre-extraction behavior byte-for-byte; the schema is untrusted input, so
      a single bad line must never abort the scan). Every caller treats an
      entry as a dict (`entry.get(...)`), so a non-object line is exactly as
      unusable to them as a malformed one. Raises FileNotFoundError / OSError
      if `path` itself cannot be opened -- the CALLER decides what that means
      (session-observe's many-file scan lets a missing file just contribute
      zero entries; session-recall's single --file mode wants to surface it).
      Yields nothing for an empty file (honest-zero, not an error).

  load(path) -> list[dict]
      `list(iter_entries(path))` -- for a caller that needs random-access
      indexing (session-recall's turn index) rather than a stream.

Both are driven off the SAME inner loop, so the parsing behavior (encoding,
blank-line skip, decode-skip) can only drift in one place.

Also runnable as a CLI (see `lib/session/parse-transcript.sh`, its thin bash
launcher):
  parse-transcript.sh <transcript.jsonl>
      one JSON object per successfully-parsed line to stdout (NDJSON), so the
      shared parser is exercisable and testable as a standalone unit.
  parse-transcript.sh --tail-text K <transcript.jsonl>
      the last K user+assistant turns that carry text, as "[role] text" blocks
      joined by blank lines (the skill-curator reviewer summary).
  parse-transcript.sh --harvest-text MAX <transcript.jsonl>
      the text blocks of every user+assistant turn, newline-joined, the last MAX
      characters kept, followed by an `x` sentinel (hooks/harvest.sh). Strict:
      a shape the original harvest crashed on (invalid UTF-8, a non-object line,
      a non-object message, a non-string text block) prints nothing, exit 1.
The two text modes are the shell callers' only view of a transcript, so the
schema knowledge lives here once and not in jq copies.
"""
from __future__ import annotations

import json
import sys
from typing import Iterator


def parse_lines(lines, strict: bool = False) -> Iterator[dict]:
    """The shared inner loop: parse an iterable of text lines into JSON objects.
    A blank line is skipped. A line that fails `json.loads`, or that decodes to
    valid JSON that is not an object, is skipped too (untrusted input; every
    caller reads an entry as a dict). Takes any iterable of str (a file handle,
    a list from a raw byte chunk) -- callers own how the lines were produced
    and how decode errors in that step are handled. With `strict`, valid JSON
    that is not an object raises TypeError instead of being skipped (the harvest
    text mode's crash shape)."""
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(entry, dict):
            if strict:
                raise TypeError("transcript line is not an object")
            continue
        yield entry


def iter_entries(path: str, strict: bool = False, errors: str = "strict") -> Iterator[dict]:
    """Yield each successfully-parsed JSON *object* in `path`, in file order.

    Malformed / blank lines are skipped, never raised. A line that decodes to
    non-object JSON (e.g. `["x"]`, a bare string/number) is skipped too: every
    caller reads an entry as a dict, so a non-object line would otherwise crash
    the first `.get()` downstream instead of being treated as the untrusted
    input it is. A missing or unreadable `path` raises (FileNotFoundError /
    PermissionError / OSError) so the caller can decide whether that is a
    per-file skip or a reported error. Invalid UTF-8 raises by default; a
    caller that wants to read past it passes errors="replace".
    """
    with open(path, "r", encoding="utf-8", errors=errors) as fh:
        yield from parse_lines(fh, strict)


def load(path: str) -> list:
    """Materialize iter_entries(path) into a list (for random-access callers)."""
    return list(iter_entries(path))


def _is_turn(entry: dict) -> bool:
    return entry.get("type") in ("user", "assistant")


def tail_text(path: str, k: int) -> str:
    """The last `k` user+assistant turns that carry non-blank text, rendered as
    "[role] text" blocks joined by a blank line, plus a trailing newline. The role
    is `message.role`, falling back to the entry type. Thinking, tool and summary
    entries have no text block and drop out. Tolerant: a malformed entry is skipped
    and an invalid UTF-8 byte becomes U+FFFD, as the old jq filter did."""
    turns = []
    for entry in iter_entries(path, errors="replace"):
        message = entry.get("message")
        if not _is_turn(entry) or not isinstance(message, dict):
            continue
        content = message.get("content")
        blocks = content if isinstance(content, list) else []
        text = "\n".join(
            b["text"] for b in blocks
            if isinstance(b, dict) and b.get("type") == "text" and isinstance(b.get("text"), str))
        if text.strip():
            turns.append("[%s] %s" % (message.get("role") or entry["type"], text))
    kept = turns[-k:] if k > 0 else []
    return "\n\n".join(kept) + "\n"


def harvest_text(path: str, max_chars: int) -> str:
    """The text blocks of every user+assistant entry, newline-joined, the last
    `max_chars` characters kept (0 keeps all, a negative value drops the head),
    followed by an `x` sentinel that survives shell command substitution.
    Raises ValueError/TypeError/OSError on the shapes the original harvest
    crashed on; the caller treats that as "nothing to send"."""
    parts = []
    for entry in iter_entries(path, strict=True):
        if not _is_turn(entry):
            continue
        message = entry.get("message") or {}
        if not isinstance(message, dict):
            raise TypeError("message is not an object")
        content = message.get("content") or []
        if isinstance(content, (str, dict)):
            continue
        if not isinstance(content, list):
            raise TypeError("content is not a list")
        parts.extend(
            b["text"] for b in content
            if isinstance(b, dict) and b.get("type") == "text" and b.get("text"))
    if not all(isinstance(p, str) for p in parts):
        raise TypeError("text block is not a string")
    text = "\n".join(parts)
    if len(text) > max_chars:
        text = text[-max_chars:]
    return text + "x"


def _emit(text: str) -> None:
    sys.stdout.buffer.write(text.encode("utf-8"))


def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else list(argv)
    if argv[:1] in (["--tail-text"], ["--harvest-text"]):
        if len(argv) != 3:
            sys.stderr.write("usage: parse-transcript.sh %s N <transcript.jsonl>\n" % argv[0])
            return 2
        try:
            number = int(argv[1])
            out = tail_text(argv[2], number) if argv[0] == "--tail-text" \
                else harvest_text(argv[2], number)
            _emit(out)
        except (ValueError, TypeError, OSError):
            return 1
        return 0
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
