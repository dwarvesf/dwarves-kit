#!/usr/bin/env python3
"""context-hints.py: a UserPromptSubmit hook that injects light, cheap context.

Ported from ops-toolkit's cc-context-hooks (function-named per the kit-foldin design
note: no host-agent prefix). Two small, pure-string additions, both sub-millisecond:

  temporal   how long this session has run + how long since the last prompt
             (helps time/deadline reasoning); past NUDGE_THRESHOLD_SECONDS elapsed,
             adds a cache-hygiene nudge (suggest /clear or a handoff split) reusing
             the same elapsed value, no extra data collection. A compaction-count
             leg was in-scope per the source row but is not implemented: this hook's
             inputs (stdin payload + its own per-session {start, last} state) carry
             no compaction counter, and the only compaction signal in the repo
             (hooks/pre-compact-backup.sh's per-repo backup-file count) is not
             session-keyed, so wiring it in would be new cross-hook data collection,
             which the row explicitly ruled out.
  skill-hint keyword -> skill nudges from a small map, so a relevant skill/command is
             surfaced even if its description did not auto-fire (JIT activation)

Output goes to stdout, which UserPromptSubmit injects as context. Silent when there
is nothing useful to add. Per-session timing state lives in a tiny json file.

Kit-generic by default: the skill map ships EMPTY (a consumer's skills are unknown to
the kit), so shipping content here would be exactly the "no tenant assumption" the
kit-foldin design note forbids. A consumer wires their own map via
CONTEXT_HINTS_SKILLMAP (JSON file: {"keyword": "skill-or-command-name", ...}).

Env (the last three exist mainly so tests are deterministic):
  CONTEXT_HINTS_SKILLMAP=FILE   keyword->skill JSON (default: co-located, empty by default)
  CONTEXT_HINTS_STATE=DIR       per-session timing state dir (default ~/.claude/dwarves-kit/state/context-hints)
  CONTEXT_HINTS_NOW=EPOCH       override "now" (tests)
  CONTEXT_HINTS_TEMPORAL=0      disable the temporal line
Stdlib only. Always exit 0.
"""
import json
import os
import re
import sys
import time

# realpath (not abspath): resolve symlinks so the co-located skills-map JSON is found
# even when invoked via a symlink (abspath leaves __file__ as the symlink).
HERE = os.path.dirname(os.path.realpath(__file__))
DEFAULT_MAP = os.path.join(HERE, "context-hints-skills-map.json")
DEFAULT_STATE = os.path.expanduser("~/.claude/dwarves-kit/state/context-hints")
NUDGE_THRESHOLD_SECONDS = 6 * 3600  # ~6h elapsed: cache-hygiene rule (ID-269)


def now():
    v = os.environ.get("CONTEXT_HINTS_NOW")
    return float(v) if v else time.time()


def humanize(sec):
    sec = int(sec)
    if sec < 60:
        return f"{sec}s"
    if sec < 3600:
        return f"{sec // 60}m{sec % 60:02d}s"
    return f"{sec // 3600}h{(sec % 3600) // 60:02d}m"


def temporal_line(session_id):
    if os.environ.get("CONTEXT_HINTS_TEMPORAL") == "0":
        return None
    state_dir = os.environ.get("CONTEXT_HINTS_STATE", DEFAULT_STATE)
    path = os.path.join(state_dir, f"{session_id}.json")
    t = now()
    start, last = t, t
    try:
        with open(path, encoding="utf-8") as fh:
            s = json.load(fh)
        start, last = float(s.get("start", t)), float(s.get("last", t))
    except (OSError, ValueError):
        pass
    elapsed, idle = t - start, t - last
    try:
        os.makedirs(state_dir, exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump({"start": start, "last": t}, fh)
    except OSError:
        pass
    if elapsed < 1:
        return None  # first prompt of the session: nothing useful yet
    line = f"Session time: {humanize(elapsed)} elapsed, {humanize(idle)} since your last prompt."
    if elapsed > NUDGE_THRESHOLD_SECONDS:
        line += "\nconsider /clear or a handoff split (cache-hygiene rule)"
    return line


def skill_hints(prompt):
    path = os.environ.get("CONTEXT_HINTS_SKILLMAP", DEFAULT_MAP)
    try:
        mapping = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        return []
    low = prompt.lower()
    hits = []
    for keyword, skill in mapping.items():
        # word-boundary match, not bare substring, so short keys (e.g. "ocr") do not
        # fire inside unrelated words ("democracy", "autocracy", "socratic").
        if re.search(r"\b" + re.escape(keyword.lower()) + r"\b", low):
            hits.append(f"{skill} (keyword: {keyword})")
    return hits


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0
    prompt = payload.get("prompt") or payload.get("lastPrompt") or ""
    session_id = payload.get("session_id") or payload.get("sessionId") or "default"
    if not re.match(r"^[A-Za-z0-9_-]{1,64}$", str(session_id)):
        session_id = "default"  # a payload-supplied id must never traverse the state path

    lines = []
    tl = temporal_line(session_id)
    if tl:
        lines.append(tl)
    hints = skill_hints(prompt) if prompt.strip() else []
    if hints:
        lines.append("Maybe-relevant skills: " + "; ".join(hints))
    if lines:
        print("\n".join(lines))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)  # a context hint never blocks a prompt
