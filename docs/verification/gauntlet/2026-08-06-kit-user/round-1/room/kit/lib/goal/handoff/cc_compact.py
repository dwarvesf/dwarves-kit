#!/usr/bin/env python3
"""Deterministic, no-LLM compaction of a Claude Code transcript JSONL.

Ports the pi-vcc technique (sticky-vs-volatile extraction) to Claude Code's
transcript schema. Pure extraction + formatting: same input bytes -> byte-identical
output. No model calls, no network, no clock, no randomness. Anything not extracted
here is still recoverable by the recall CLI (SG-03); fidelity, not reduction, is the bar.

ponytail: one module, stdlib only. Heuristic regex cues, not a parser framework.
"""
from __future__ import annotations

import json
import re
import sys

# --- block/content helpers ---------------------------------------------------

EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit", "Update"}

# Decision cues: a sentence carrying one of these is a load-bearing decision.
DECISION_RE = re.compile(
    r"\b(decision|decided|chose|choosing|going with|i'll use|we'll use|"
    r"will use|opting for|instead of|rather than|because)\b",
    re.IGNORECASE,
)
# Outstanding-work cues.
OUTSTANDING_RE = re.compile(
    r"\b(todo|still need|still needs|outstanding|next step|not yet|remaining|"
    r"left to do|follow.?up)\b",
    re.IGNORECASE,
)
# git output line: "[branch 1a2b3c4] subject"
COMMIT_OUT_RE = re.compile(r"^\[\S+\s+[0-9a-f]{7,40}\]\s+(.+)$", re.MULTILINE)
# `git commit -m "subject"` (first line only)
COMMIT_CMD_RE = re.compile(r"git\s+commit\b[^\n]*?-m\s+(['\"])(.+?)\1", re.DOTALL)

SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+|\n+")


def _text_blocks(entry):
    """Yield text strings from an entry's message content (text blocks only)."""
    msg = entry.get("message") or {}
    content = msg.get("content")
    if isinstance(content, str):
        yield content
        return
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                t = block.get("text")
                if isinstance(t, str):
                    yield t


def _tool_uses(entry):
    """Yield (name, input_dict) for each tool_use block in an entry."""
    msg = entry.get("message") or {}
    content = msg.get("content")
    if not isinstance(content, list):
        return
    for block in content:
        if isinstance(block, dict) and block.get("type") == "tool_use":
            yield block.get("name") or "?", block.get("input") or {}


def _tool_results(entry):
    """Yield result-content strings from tool_result blocks in an entry."""
    msg = entry.get("message") or {}
    content = msg.get("content")
    if not isinstance(content, list):
        return
    for block in content:
        if isinstance(block, dict) and block.get("type") == "tool_result":
            rc = block.get("content")
            if isinstance(rc, str):
                yield rc
            elif isinstance(rc, list):
                for sub in rc:
                    if isinstance(sub, dict) and sub.get("type") == "text":
                        t = sub.get("text")
                        if isinstance(t, str):
                            yield t


def _is_user(entry):
    return entry.get("type") == "user" or (entry.get("message") or {}).get("role") == "user"


def _is_assistant(entry):
    return entry.get("type") == "assistant" or (entry.get("message") or {}).get("role") == "assistant"


def _collapse_ws(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


# --- load --------------------------------------------------------------------

def load(path: str):
    """Parse a JSONL transcript. Unparseable lines are skipped deterministically."""
    entries = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except (json.JSONDecodeError, ValueError):
                continue
    return entries


# --- extractors (each is a pure function of the entry list) ------------------

def session_goal(entries) -> str:
    """First substantive user prose (skips system-reminders, slash-command stdout,
    and tool_result-only turns)."""
    for entry in entries:
        if not _is_user(entry):
            continue
        # Skip turns that are purely tool results.
        if any(True for _ in _tool_results(entry)):
            continue
        for text in _text_blocks(entry):
            t = text.strip()
            if not t:
                continue
            if t.startswith("<"):  # <system-reminder>, <command-name>, <local-...>
                continue
            return _collapse_ws(t)[:600]
    return "(no user goal found)"


def files_changed(entries):
    """Ordered list of (path, edit_count) for mutating tool calls, sorted by path."""
    counts: dict[str, int] = {}
    for entry in entries:
        if not _is_assistant(entry):
            continue
        for name, inp in _tool_uses(entry):
            if name not in EDIT_TOOLS:
                continue
            path = inp.get("file_path") or inp.get("notebook_path") or inp.get("path")
            if isinstance(path, str) and path:
                counts[path] = counts.get(path, 0) + 1
    return sorted(counts.items())


def decisions(entries, cap: int = 20):
    """Decision-cue sentences from assistant prose, first-seen order, deduped."""
    out = []
    seen = set()
    for entry in entries:
        if not _is_assistant(entry):
            continue
        for text in _text_blocks(entry):
            for sentence in SENTENCE_SPLIT_RE.split(text):
                s = _collapse_ws(sentence)
                if not s or not DECISION_RE.search(s):
                    continue
                key = s.lower()
                if key in seen:
                    continue
                seen.add(key)
                out.append(s[:300])
                if len(out) >= cap:
                    return out
    return out


def commits(entries):
    """Commit subjects, first-seen order, deduped. From git output lines and
    `git commit -m` commands."""
    out = []
    seen = set()

    def add(subject: str):
        s = _collapse_ws(subject)
        if s and s.lower() not in seen:
            seen.add(s.lower())
            out.append(s[:200])

    for entry in entries:
        # commands the assistant ran
        if _is_assistant(entry):
            for name, inp in _tool_uses(entry):
                if name == "Bash":
                    cmd = inp.get("command") or ""
                    for m in COMMIT_CMD_RE.finditer(cmd):
                        add(m.group(2).splitlines()[0])
        # git's own confirmation lines in results
        for rc in _tool_results(entry):
            for m in COMMIT_OUT_RE.finditer(rc):
                add(m.group(1))
    return out


def outstanding(entries, cap: int = 15):
    """Outstanding-work cue sentences (any role), first-seen order, deduped."""
    out = []
    seen = set()
    for entry in entries:
        for text in _text_blocks(entry):
            if text.strip().startswith("<"):
                continue
            for sentence in SENTENCE_SPLIT_RE.split(text):
                s = _collapse_ws(sentence)
                if not s or not OUTSTANDING_RE.search(s):
                    continue
                if s.lower() in seen:
                    continue
                seen.add(s.lower())
                out.append(s[:300])
                if len(out) >= cap:
                    return out
    return out


def tool_summary(entries):
    """(name, count) for every tool_use, sorted by name. The volatile tool I/O is
    collapsed to these counts , the biggest token saving."""
    counts: dict[str, int] = {}
    for entry in entries:
        if not _is_assistant(entry):
            continue
        for name, _ in _tool_uses(entry):
            counts[name] = counts.get(name, 0) + 1
    return sorted(counts.items())


# --- render ------------------------------------------------------------------

def _bullets(items, empty="(none)"):
    if not items:
        return f"- {empty}\n"
    return "".join(f"- {it}\n" for it in items)


def compact(entries) -> str:
    """Assemble the deterministic compacted markdown view."""
    goal = session_goal(entries)
    files = files_changed(entries)
    decs = decisions(entries)
    cmts = commits(entries)
    outs = outstanding(entries)
    tools = tool_summary(entries)
    total_tools = sum(c for _, c in tools)

    lines = []
    lines.append("# Compacted session view\n")
    lines.append(f"_Deterministic no-LLM compaction of {len(entries)} transcript entries._\n")

    lines.append("\n## Session goal\n")
    lines.append(f"{goal}\n")

    lines.append("\n## Files + changes\n")
    if files:
        lines.append("".join(f"- `{p}` ({n} edit{'s' if n != 1 else ''})\n" for p, n in files))
    else:
        lines.append("- (none)\n")

    lines.append("\n## Decisions\n")
    lines.append(_bullets(decs))

    lines.append("\n## Commits\n")
    lines.append(_bullets(cmts))

    lines.append("\n## Outstanding context\n")
    lines.append(_bullets(outs))

    lines.append(f"\n## Collapsed tool calls ({total_tools} total)\n")
    if tools:
        lines.append("".join(f"- {name}: {n}\n" for name, n in tools))
    else:
        lines.append("- (none)\n")

    return "".join(lines)


def est_tokens(text: str) -> int:
    """Char/4 token proxy (tiktoken unavailable; matches token-forensic's heuristic)."""
    return (len(text) + 3) // 4


# --- CLI ---------------------------------------------------------------------

def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    stats = False
    if "--stats" in argv:
        stats = True
        argv.remove("--stats")
    if len(argv) != 1:
        sys.stderr.write("usage: extract [--stats] <transcript.jsonl>\n")
        return 2
    path = argv[0]
    entries = load(path)
    out = compact(entries)
    sys.stdout.write(out)
    if stats:
        with open(path, "r", encoding="utf-8") as fh:
            raw = fh.read()
        ti, to = est_tokens(raw), est_tokens(out)
        red = 100.0 * (1 - to / ti) if ti else 0.0
        sys.stderr.write(
            f"[stats] entries={len(entries)} in_tok={ti} out_tok={to} reduction={red:.1f}%\n"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
