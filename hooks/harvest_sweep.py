#!/usr/bin/env python3
"""harvest_sweep.py: the scheduled harvest sweep (SPEC-357).

This file grows task by task. So far it holds the claude adapter and the render step:
enumerate lead sessions cheaply (stat only), load one into the normalized transcript
(lead plus subagents interleaved by entry timestamp), and render a delta of it for the
extractor. Selection, the cursor, and the extractor call come in later tasks.

Env (tests point these at temp dirs):
  HARVEST_SWEEP_CLAUDE_ROOT=DIR    claude projects root (default ~/.claude/projects)
  HARVEST_SWEEP_MIN_MESSAGES=N     a session with fewer kept user+assistant messages is trivial (default 6)
  HARVEST_STATE_DIR=DIR            harvest state dir; a session whose cwd is under it is self-harvest
"""
import datetime
import glob
import importlib.util
import json
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
import harvest  # noqa: E402  (shared state-dir default lives there)

# The shared JSONL parser lives outside hooks/, so load it by path.
_spec = importlib.util.spec_from_file_location(
    "parse_transcript", os.path.join(_HERE, "..", "lib", "session", "parse_transcript.py"))
_parse = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_parse)

TOOL_INPUT_CHARS = 200
LEAD_SHARE = 0.6


def _claude_root():
    return os.environ.get("HARVEST_SWEEP_CLAUDE_ROOT", os.path.expanduser("~/.claude/projects"))


def _min_messages():
    return int(os.environ.get("HARVEST_SWEEP_MIN_MESSAGES", "6"))


def list_claude_sessions():
    """Lead sessions under the claude root, stat only, oldest activity first.

    Each item: {session_id, path, subagent_paths, last_activity}. last_activity is the
    max mtime over the lead file and its subagent files, so a subagent still writing
    keeps its lead "active". Nothing is opened, so a scan of thousands stays cheap."""
    out = []
    for lead in glob.glob(os.path.join(_claude_root(), "*", "*.jsonl")):
        sid = os.path.basename(lead)[:-len(".jsonl")]
        subs = sorted(glob.glob(os.path.join(os.path.dirname(lead), sid, "subagents", "agent-*.jsonl")))
        try:
            mtimes = [os.stat(p).st_mtime for p in [lead] + subs]
        except OSError:
            continue  # vanished between glob and stat
        out.append({"session_id": sid, "path": lead, "subagent_paths": subs,
                    "last_activity": int(max(mtimes))})
    out.sort(key=lambda s: (s["last_activity"], s["session_id"]))
    return out


def _epoch(iso):
    """Claude timestamps are ISO 8601 with a trailing Z; None when absent or unparseable."""
    if not isinstance(iso, str):
        return None
    try:
        return datetime.datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def _entry_messages(entry, ts, sub):
    """Kept messages of one transcript entry: text blocks and tool_use calls."""
    if entry.get("type") not in ("user", "assistant"):
        return []
    role = entry["type"]
    content = (entry.get("message") or {}).get("content")
    if isinstance(content, str):  # a typed user prompt is a bare string, not a block list
        content = [{"type": "text", "text": content}]
    prefix = "subagent: " if sub else ""
    msgs = []
    for block in content or []:
        if not isinstance(block, dict):
            continue
        if block.get("type") == "text" and isinstance(block.get("text"), str):
            text, r = block["text"].strip(), role
        elif block.get("type") == "tool_use":
            args = json.dumps(block.get("input"), ensure_ascii=False)[:TOOL_INPUT_CHARS]
            text, r = "%s %s" % (block.get("name", ""), args), "tool"
        else:
            continue
        if text:
            msgs.append({"role": r, "text": prefix + text, "ts": ts, "sub": sub})
    return msgs


def _read_file(path, sub, mtime):
    """(messages, cwd) of one transcript file. An entry with no usable timestamp inherits
    the previous entry's, else the file mtime, so it still sorts near where it was written."""
    msgs, cwd, last_ts = [], None, mtime
    try:
        for entry in _parse.iter_entries(path):
            if cwd is None and isinstance(entry.get("cwd"), str):
                cwd = entry["cwd"]
            last_ts = _epoch(entry.get("timestamp")) or last_ts
            msgs.extend(_entry_messages(entry, last_ts, sub))
    except OSError:
        pass
    return msgs, cwd


def load_claude(item):
    """Normalized transcript (SPEC-357 Technical Design) for one list_claude_sessions item."""
    lead_msgs, cwd = _read_file(item["path"], False, os.stat(item["path"]).st_mtime)
    messages = list(lead_msgs)
    for p in item["subagent_paths"]:
        try:
            mt = os.stat(p).st_mtime
        except OSError:
            continue
        sub_msgs, sub_cwd = _read_file(p, True, mt)
        messages.extend(sub_msgs)
        cwd = cwd or sub_cwd
    messages.sort(key=lambda m: m["ts"])  # stable: the lead file comes first on a tie
    return {"source": "claude", "session_id": item["session_id"], "lead_session_id": None,
            "cwd": cwd or "", "started": messages[0]["ts"] if messages else item["last_activity"],
            "last_activity": item["last_activity"], "messages": messages}


def newest_ts(t):
    """Newest kept-entry timestamp: the value a later run stores as seen{id}.last_ts."""
    return max((m["ts"] for m in t["messages"]), default=None)


def _take_recent(msgs, budget):
    """Most recent whole messages that fit `budget` chars (a joining newline counts). When
    even the newest alone does not fit, keep its tail rather than nothing."""
    kept, used = [], 0
    for m in reversed(msgs):
        line = "%s: %s" % (m["role"], m["text"])
        if used + len(line) + 1 > budget:
            if not kept and budget > 0:
                kept.append((m, line[-budget:]))
            break
        kept.append((m, line))
        used += len(line) + 1
    return kept


def render(t, after_ts, max_chars):
    """Messages with ts > after_ts as `<role>: <text>` lines in ts order. The lead keeps a
    fixed 60% of max_chars and subagents 40%, each share keeping its most recent messages.
    A share one side leaves unused is not lent to the other: a huge subagent must never
    push the lead out, and the budget stays a hard cap for the prompt-size bound."""
    fresh = [m for m in t["messages"] if m["ts"] > after_ts]
    lead_budget = int(max_chars * LEAD_SHARE)
    picked = (_take_recent([m for m in fresh if not m["sub"]], lead_budget)
              + _take_recent([m for m in fresh if m["sub"]], max_chars - lead_budget))
    picked.sort(key=lambda p: p[0]["ts"])
    return "\n".join(line for _, line in picked)


def is_trivial(t):
    """Fewer than HARVEST_SWEEP_MIN_MESSAGES kept user+assistant messages, subagents included."""
    return sum(1 for m in t["messages"] if m["role"] in ("user", "assistant")) < _min_messages()


def is_self_harvest(t):
    """cwd at or under the harvest state dir: the extractor's own calls run there (DEC-44)."""
    if not t["cwd"]:
        return False
    state = os.path.realpath(harvest._state_dir())
    cwd = os.path.realpath(t["cwd"])
    return cwd == state or cwd.startswith(state + os.sep)
