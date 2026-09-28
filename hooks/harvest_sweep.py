#!/usr/bin/env python3
"""harvest_sweep.py: the scheduled harvest sweep (SPEC-357).

This file grows task by task. So far it holds the claude adapter and the render step:
enumerate lead sessions cheaply (stat only), load one into the normalized transcript
(lead plus subagents interleaved by entry timestamp), and render a delta of it for the
extractor. Below them sit selection, the cursor, and the per-session loop; the extractor,
staging, and report plug into that loop in later tasks.

Env (tests point these at temp dirs):
  HARVEST_SWEEP_CLAUDE_ROOT=DIR    claude projects root (default ~/.claude/projects)
  HARVEST_SWEEP_DEVIN_DB=FILE      devin sessions db (default ~/.local/share/devin/cli/sessions.db)
  HARVEST_SWEEP_LAUNCH_RECORD=FILE worker-launch record (default ~/.local/state/worker-launch/launches.jsonl)
  HARVEST_SWEEP_SOURCE_FAIL_RUNS=N consecutive failed runs of one source that trip rc 5 (default 3)
  HARVEST_SWEEP_MIN_MESSAGES=N     a session with fewer kept user+assistant messages is trivial (default 6)
  HARVEST_STATE_DIR=DIR            harvest state dir; a session whose cwd is under it is self-harvest
  HARVEST_SWEEP_NOW=EPOCH          pin the clock (tests)
  HARVEST_SWEEP_MAX_SCAN=N         candidates scanned per source per run (default 2000)
  HARVEST_SWEEP_QUIET_MINUTES=N    a session is read only after this long without activity (default 30)
  HARVEST_MAXCHARS=N               transcript chars rendered per session (default 12000)
"""
import datetime
import glob
import importlib.util
import json
import os
import sqlite3
import sys
import time
import urllib.parse

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
    # _take_recent returns newest first; restore file order so the stable sort keeps
    # same-ts messages (a text block and its tool call share one entry ts) in order.
    picked = (_take_recent([m for m in fresh if not m["sub"]], lead_budget)[::-1]
              + _take_recent([m for m in fresh if m["sub"]], max_chars - lead_budget)[::-1])
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


# ---- devin adapter -------------------------------------------------------------------

class SourceFailure(object):
    """A source that could not be read this run. Returned, never raised, so one broken
    source cannot stop the others (SPEC-357 source drift)."""

    def __init__(self, source, exc):
        self.source = source
        self.error_class = type(exc).__name__
        self.message = str(exc)

    def state_row(self):
        return "STATE %s: %s: %s" % (self.source, self.error_class, self.message)


def _devin_db():
    return os.environ.get("HARVEST_SWEEP_DEVIN_DB",
                          os.path.expanduser("~/.local/share/devin/cli/sessions.db"))


def _devin_query(sql, params=()):
    """Rows from the devin db, opened read-only by URI so a live Devin is never disturbed.
    A locked db is retried once (Edge case: db locked by a running Devin), then raised."""
    uri = "file:%s?mode=ro" % urllib.parse.quote(_devin_db())
    for attempt in (0, 1):
        try:
            con = sqlite3.connect(uri, uri=True, timeout=1)
            try:
                return con.execute(sql, params).fetchall()
            finally:
                con.close()
        except sqlite3.OperationalError as exc:
            if attempt or not any(w in str(exc) for w in ("locked", "busy")):
                raise
            time.sleep(0.2)


def list_devin_sessions():
    """Sessions in the devin db, oldest activity first, or a SourceFailure.

    Each item: {session_id, cwd, started, last_activity, hidden, main_chain_id}. Hidden
    rows are listed, not dropped: the caller marks them done so the hwm can pass them."""
    try:
        rows = _devin_query("SELECT id, working_directory, created_at, last_activity_at, hidden, "
                            "main_chain_id FROM sessions ORDER BY last_activity_at, id")
    except (sqlite3.Error, OSError) as exc:
        return SourceFailure("devin", exc)
    return [{"session_id": r[0], "cwd": r[1] or "", "started": float(r[2] or 0),
             "last_activity": int(r[3] or 0), "hidden": bool(r[4]), "main_chain_id": r[5]}
            for r in rows]


def is_hidden(item):
    """hidden = 1: skipped rather than guessed at, since the column's meaning is undocumented (DEC-79)."""
    return bool(item.get("hidden"))


def _devin_text(content):
    if isinstance(content, list):
        content = "\n".join(b.get("text", "") for b in content
                            if isinstance(b, dict) and isinstance(b.get("text"), str))
    return content.strip() if isinstance(content, str) else ""


def _node_messages(chat_message, ts):
    """Kept messages of one node: user/assistant/tool content, plus one tool line per call."""
    try:
        cm = json.loads(chat_message)
    except ValueError:
        return []
    role = cm.get("role") if isinstance(cm, dict) else None
    if role not in ("user", "assistant", "tool"):  # system rows are injected rules
        return []
    text = _devin_text(cm.get("content"))
    if role == "tool":
        text = text[:TOOL_INPUT_CHARS]
    msgs = [{"role": role, "text": text, "ts": ts, "sub": False}] if text else []
    for call in cm.get("tool_calls") or []:
        if not isinstance(call, dict):
            continue
        name = call.get("name") or (call.get("function") or {}).get("name")
        if name:
            msgs.append({"role": "tool", "text": str(name), "ts": ts, "sub": False})
    return msgs


def load_devin(item):
    """Normalized transcript for one list_devin_sessions item, or a SourceFailure.

    The main chain is the parent_node_id walk up from main_chain_id, root first. A null
    or dangling main_chain_id falls back to every node by node_id (DEC-16)."""
    try:
        nodes = _devin_query("SELECT node_id, parent_node_id, chat_message, created_at "
                             "FROM message_nodes WHERE session_id = ? ORDER BY node_id",
                             (item["session_id"],))
    except (sqlite3.Error, OSError) as exc:
        return SourceFailure("devin", exc)
    by_id = {n[0]: n for n in nodes}
    chain, cur = [], item["main_chain_id"]
    while cur in by_id and by_id[cur] not in chain:  # membership also stops a parent cycle
        chain.append(by_id[cur])
        cur = by_id[cur][1]
    ordered = chain[::-1] if chain else nodes
    messages = []
    for _, _, chat_message, created in ordered:
        messages.extend(_node_messages(chat_message, float(created or 0)))
    return {"source": "devin", "session_id": item["session_id"], "lead_session_id": None,
            "cwd": item["cwd"], "started": item["started"],
            "last_activity": item["last_activity"], "messages": messages}


# ---- source failure bookkeeping ------------------------------------------------------

def source_fail_update(cursor, source, failed):
    """Consecutive failed runs of `source`, kept in cursor["source_fail"]: +1 on a failed
    read, back to 0 on a good one. Returns the new count."""
    counts = cursor.setdefault("source_fail", {})
    counts[source] = counts.get(source, 0) + 1 if failed else 0
    return counts[source]


def source_fail_tripped(cursor, source):
    """True once `source` has failed HARVEST_SWEEP_SOURCE_FAIL_RUNS runs in a row (rc 5)."""
    limit = int(os.environ.get("HARVEST_SWEEP_SOURCE_FAIL_RUNS", "3"))
    return cursor.get("source_fail", {}).get(source, 0) >= limit


# ---- launch-record attribution -------------------------------------------------------

def load_launch_records():
    """Records of the worker-launch file, read once per run. A missing or unreadable file
    is an empty list and a malformed line is skipped alone: attribution never fails a run."""
    path = os.environ.get("HARVEST_SWEEP_LAUNCH_RECORD",
                          os.path.expanduser("~/.local/state/worker-launch/launches.jsonl"))
    records = []
    try:
        with open(path, errors="replace") as fh:
            for line in fh:
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if isinstance(rec, dict):
                    records.append(rec)
    except OSError:
        pass
    return records


def attribute(t, records):
    """Set t["lead_session_id"] from the launch record whose brief path the first kept user
    message names. Devin only. Nearest record ts to the session start wins (DEC-23: no
    time-window fallback). No match leaves it null. Returns the lead session id or None."""
    if t["source"] != "devin":
        return None
    first = next((m["text"] for m in t["messages"] if m["role"] == "user"), "")
    matches = [r for r in records
               if r.get("agent") == "devin"
               and any(isinstance(r.get(k), str) and r[k] and r[k] in first
                       for k in ("brief", "brief_copy"))]
    if not matches:
        return None

    def distance(rec):
        ts = _epoch(rec.get("ts"))
        # A record with no parseable ts sorts last, so a dated match always beats it.
        return float("inf") if ts is None else abs(ts - t["started"])

    best = min(matches, key=distance)
    t["lead_session_id"] = best.get("lead_session")
    sys.stderr.write("harvest-sweep: %s attributed to lead %s via %s\n"
                     % (t["session_id"], t["lead_session_id"], best.get("brief")))
    return t["lead_session_id"]


# ---- selection, cursor, and the per-session loop -------------------------------------

def _now():
    """One clock for the whole sweep; tests pin it with HARVEST_SWEEP_NOW (epoch seconds)."""
    return float(os.environ.get("HARVEST_SWEEP_NOW") or time.time())


def _cursor_path():
    return os.path.join(harvest._state_dir(), "sweep", "cursor.json")


def load_cursor():
    """cursor.json, or an empty cursor when it is absent or unreadable (first run)."""
    try:
        with open(_cursor_path()) as fh:
            cursor = json.load(fh)
        if isinstance(cursor, dict):
            return cursor
    except (OSError, ValueError):
        pass
    return {}


def save_cursor(cursor):
    """Atomic: a crash leaves the previous file whole, never a partial one."""
    path = _cursor_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(cursor, fh, sort_keys=True)
    os.replace(tmp, path)


def _source_state(cursor, source, initial_hwm):
    """The per-source cursor entry, every key present. Keys another task owns (fail,
    quarantined) are created empty and never touched here."""
    state = cursor.setdefault(source, {"hwm": initial_hwm})
    for key in ("done", "seen", "fail", "quarantined"):
        state.setdefault(key, {})
    return state


def _settled(state, item):
    """Done at this exact last_activity, or quarantined (T7b owns the lift): either way the
    hwm may pass it."""
    return (state["done"].get(item["session_id"]) == item["last_activity"]
            or item["session_id"] in state["quarantined"])


def _advance_hwm(state, scanned):
    """hwm moves through the longest settled prefix of the scan, never past an unsettled
    session (DEC-30). Only done{} is pruned by it: seen{} holds delta keys and ages out on
    its own (DEC-60)."""
    hwm = state["hwm"]
    for item in scanned:
        if item["last_activity"] < state["hwm"]:
            continue  # an earlier pass moved the hwm past it and pruned its done{} entry
        if not _settled(state, item):
            break
        hwm = max(hwm, item["last_activity"])
    state["hwm"] = hwm
    state["done"] = {i: la for i, la in state["done"].items() if la >= hwm}


def _sources():
    """(name, list, load) per source; devin lists a SourceFailure when its db is unreadable."""
    return [("claude", list_claude_sessions, load_claude), ("devin", list_devin_sessions, load_devin)]


def _sweep_source(cursor, source, items, load, process, now, schedule_hours, max_sessions, records):
    state = _source_state(cursor, source, int(now - schedule_hours * 3600))
    max_scan = int(os.environ.get("HARVEST_SWEEP_MAX_SCAN", "2000"))
    quiet_before = now - int(os.environ.get("HARVEST_SWEEP_QUIET_MINUTES", "30")) * 60
    max_chars = int(os.environ.get("HARVEST_MAXCHARS", "12000"))
    out = {"processed": [], "filtered": [], "failed": [], "deferred": []}

    scanned = sorted((i for i in items if i["last_activity"] >= state["hwm"]),
                     key=lambda i: (i["last_activity"], i["session_id"]))[:max_scan]
    eligible = [i for i in scanned
                if i["last_activity"] <= quiet_before
                and not _settled(state, i)]

    attempts = 0
    for pos, item in enumerate(eligible):
        sid = item["session_id"]
        if attempts >= max_sessions:
            out["deferred"] = eligible[pos:]  # stay eligible, oldest first next run (DEC-71)
            break
        skip = is_hidden(item) if source == "devin" else False
        t = None
        if not skip:
            t = load(item)
            if isinstance(t, SourceFailure):
                out["source_failure"] = t
                break
            skip = is_self_harvest(t) or is_trivial(t)
        if skip:
            state["done"][sid] = item["last_activity"]  # outside the cap
            out["filtered"].append(sid)
        else:
            attempts += 1
            if source == "devin":
                attribute(t, records)
            last_ts = state["seen"].get(sid, {}).get("last_ts", 0)
            text = render(t, last_ts, max_chars)
            # An empty delta has nothing to read; T7a's failure handling hangs off `ok`.
            ok = process(t, text) if text else True
            if not ok:
                out["failed"].append(sid)
                continue
            state["done"][sid] = item["last_activity"]
            if text:
                state["seen"][sid] = {"last_ts": newest_ts(t), "ts": int(now)}
            out["processed"].append(sid)
        _advance_hwm(state, scanned)
        save_cursor(cursor)
    return out


def run_selection(process, schedule_hours=6, max_sessions=20):
    """One pass over every source: select, then call process(t, rendered_delta) per session,
    oldest first. process returns True on success; anything else is a failed session (not
    done, hwm held back). The cursor is written after each session. Returns per-source
    {processed, filtered, failed, deferred[, source_failure]}."""
    now = _now()
    cursor = load_cursor()
    fresh = [s for s, _, _ in _sources() if s not in cursor]
    records = load_launch_records()
    result = {}
    for source, lister, loader in _sources():
        items = lister()
        if isinstance(items, SourceFailure):
            result[source] = {"processed": [], "filtered": [], "failed": [], "deferred": [],
                              "source_failure": items}
            continue
        result[source] = _sweep_source(cursor, source, items, loader, process, now,
                                       schedule_hours, max_sessions, records)
    if fresh:
        save_cursor(cursor)  # pin the first-run hwm even when nothing was selected
    return result
