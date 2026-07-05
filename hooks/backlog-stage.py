#!/usr/bin/env python3
"""backlog-stage.py: SessionEnd hook that stages backlog candidates from a session.

Ported from ops-toolkit's cc-backlog (function-named per the kit-foldin design note:
no host-agent prefix, was cc-backlog). A harvest applied to a project board instead of
a knowledge ledger. When a session ends, the action-items the user stated but did not
dictate onto the board are easy to lose. This hook reads the transcript, asks a cheap
Claude model (Haiku) to extract the genuine forward-looking work-items, dedups them
against the live board + the staging buffer, and appends ONLY the new ones to a
staging file as `[staged]` candidates.

It NEVER writes the board directly. The human gate stays: this auto-STAGES; a human
(or a separate promote tool, out of scope here) flushes chosen candidates onto the
real board with real IDs. (Propose-don't-dispose.)

The LLM call is isolated behind BACKLOG_STAGE_EXTRACTOR (a shell command that reads
the prompt on stdin and writes a JSON array on stdout), so the dedup/append logic is
testable without a live model. Default: `claude -p --model haiku --setting-sources
project`. The `--setting-sources project` is load-bearing: it stops the spawned
extractor from loading the USER settings.json (where this hook lives), so it cannot
re-fire SessionEnd and recurse.

Consumer seam (no hardcoded tenant path; per kit-foldin DECISIONS.md): the board and
staging file default REPO-RELATIVE under `_meta/`, resolved from REPO_ROOT (env) else
`git rev-parse --show-toplevel` else $PWD, mirroring lib/board/board.sh's own
`_default_repo_root`/`_resolve_repo_root` precedent for the same `_meta/BACKLOG.md`
convention. There is no ops-toolkit-specific fallback.

Env:
  BACKLOG_STAGE_BACKLOG=FILE    board to dedup against (default <repo-root>/_meta/BACKLOG.md)
  BACKLOG_STAGE_STAGING=FILE    staging buffer (default <repo-root>/_meta/backlog-staging.md)
  REPO_ROOT=DIR                 consumer seam for the two defaults above
  BACKLOG_STAGE_EXTRACTOR=CMD   override the LLM call (tests)
  BACKLOG_STAGE_MAXCHARS=N      transcript chars sent to the model (default 12000)
  BACKLOG_STAGE_MIN_INTERVAL=S  rate-limit to at most once per S seconds (default 3600). 0 off.
  BACKLOG_STAGE_STATE_DIR=DIR   throttle lock dir (default ~/.claude/dwarves-kit/state/backlog-stage)
  BACKLOG_STAGE_PREFILTER=0     disable the deterministic forward-intent pre-filter (default on)

Stdlib only. Always exits 0 (a harvest never blocks a session end).
"""
import json
import os
import re
import shlex
import subprocess
import sys
import time

DEFAULT_EXTRACTOR = "claude -p --model haiku --setting-sources project"
DEFAULT_STATE_DIR = os.path.expanduser("~/.claude/dwarves-kit/state/backlog-stage")
SECTION = "### Conversation intake (backlog-stage)"


def _repo_root():
    """REPO_ROOT env wins; else git top-level; else cwd. Mirrors lib/board/board.sh's
    _default_repo_root/_resolve_repo_root precedent -- no invented tenant var."""
    env = os.environ.get("REPO_ROOT")
    if env:
        return env
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=5
        )
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return os.getcwd()


def _default_backlog():
    return os.path.join(_repo_root(), "_meta", "BACKLOG.md")


def _default_staging():
    return os.path.join(_repo_root(), "_meta", "backlog-staging.md")


PROMPT_HEAD = (
    "You extract FORWARD-LOOKING work-items from a coding/ops session transcript: things the user "
    "said they want to DO LATER but did not necessarily file yet.\n"
    "Output ONLY a JSON array, no prose. Each element:\n"
    '  {"title": "<short imperative title>", "intent": "<one sentence: the outcome wanted>", '
    '"approach": "<1-2 key steps or the open question>", "u": "hi|mid|lo", "f": "hi|mid|lo", '
    '"home": "<repo/tool guess or empty>"}\n'
    "Include ONLY items with explicit forward intent (add to backlog, we should, let's later, TODO, "
    "next time, remind me to, follow up). EXCLUDE: things already done this session, idle musings, "
    "questions, and anything already obviously tracked. If there is nothing, output []. "
    "u=urgency (cost of delay), f=feasibility (doable now). Transcript follows:\n\n"
)


def read_payload():
    try:
        return json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return {}


def transcript_text(path, max_chars):
    """User+assistant text blocks, most-recent-kept up to max_chars."""
    parts = []
    try:
        fh = open(path, encoding="utf-8")
    except OSError:
        return ""
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                o = json.loads(line)
            except json.JSONDecodeError:
                continue
            if o.get("type") not in ("user", "assistant"):
                continue
            for b in (o.get("message") or {}).get("content", []) or []:
                if isinstance(b, dict) and b.get("type") == "text" and b.get("text"):
                    parts.append(b["text"])
    text = "\n".join(parts)
    return text[-max_chars:] if len(text) > max_chars else text


def run_extractor(prompt):
    cmd = os.environ.get("BACKLOG_STAGE_EXTRACTOR") or DEFAULT_EXTRACTOR
    # No shell: prompt on stdin, command split with shlex so transcript content can never be
    # interpreted as a shell metacharacter.
    try:
        r = subprocess.run(shlex.split(cmd), input=prompt, capture_output=True, text=True, timeout=120)
        return r.stdout
    except (subprocess.SubprocessError, OSError):
        return ""


def extract_json_array(text):
    """First balanced [...] out of model output (tolerates fences/canary/prose)."""
    start = text.find("[")
    if start < 0:
        return []
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "[":
            depth += 1
        elif text[i] == "]":
            depth -= 1
            if depth == 0:
                try:
                    val = json.loads(text[start : i + 1])
                    return val if isinstance(val, list) else []
                except json.JSONDecodeError:
                    return []
    return []


def norm(s):
    """Normalize a title for dedup: lowercase alphanumeric words."""
    return " ".join(re.findall(r"[a-z0-9]+", str(s).lower()))


def existing_titles(backlog, staging):
    """Normalized titles already on the board (Item col) or already staged."""
    titles = set()
    if os.path.isfile(backlog):
        for line in open(backlog, encoding="utf-8"):
            # board rows: | ID-NNN | Item | Notes | Status |
            m = re.match(r"\s*\|\s*[A-Z]+-\d+\s*\|\s*([^|]+)\|", line)
            if m:
                titles.add(norm(m.group(1)))
    if os.path.isfile(staging):
        for line in open(staging, encoding="utf-8"):
            m = re.match(r"##\s*\[[^\]]+\]\s*(.+)", line)
            if m:
                titles.add(norm(m.group(1)))
    return titles


def throttled(state_dir):
    """True if a harvest ran within BACKLOG_STAGE_MIN_INTERVAL seconds. Bookkeeping errors
    never block (returns False)."""
    try:
        interval = int(os.environ.get("BACKLOG_STAGE_MIN_INTERVAL", "3600"))
    except ValueError:
        interval = 3600
    if interval <= 0:
        return False
    stamp = os.path.join(state_dir, "last-run")
    try:
        os.makedirs(state_dir, exist_ok=True)
        if os.path.isfile(stamp) and (time.time() - os.path.getmtime(stamp)) < interval:
            return True
        open(stamp, "w").close()
        os.utime(stamp, None)
    except OSError:
        return False
    return False


def render_candidate(c, date):
    title = str(c.get("title", "")).strip()
    if not title:
        return None
    intent = str(c.get("intent", "")).strip() or "(no intent extracted)"
    approach = str(c.get("approach", "")).strip() or "(no approach extracted)"
    u = c.get("u", "lo") if c.get("u") in ("hi", "mid", "lo") else "lo"
    f = c.get("f", "mid") if c.get("f") in ("hi", "mid", "lo") else "mid"
    home = str(c.get("home", "")).strip()
    home_line = f"- Home: {home}\n" if home else ""
    return (
        f"## [staged] {title}\n"
        f"- Intent: {intent}\n"
        f"- Approach: {approach}\n"
        f"- Tags: #u-{u} #f-{f}\n"
        f"{home_line}"
        f"- Source: session {date}\n\n"
    )


# Deterministic pre-filter: forward-intent markers. If a transcript has NONE of these, it has no
# "do this later" signal, so the model call is skipped entirely (saves a model invocation + quota).
# Generous + biased to NOT skip: bare "should"/"later" are excluded (too common); multi-word
# deferral phrases + strong singles only. Set BACKLOG_STAGE_PREFILTER=0 to disable.
INTENT_RE = re.compile(
    r"\b(?:to-?do|backlog|we should|i should|should we|let'?s\b|next time|follow[- ]?up|"
    r"remind me|reminder|need to|have to|going to|gonna|plan to|want to|in the future|"
    r"revisit|circle back|action item|down the line|later on|come back to|for later)\b",
    re.IGNORECASE,
)


def has_intent(text):
    """True if the transcript shows any forward-looking 'do this later' signal."""
    return bool(INTENT_RE.search(text))


def surface():
    """SessionStart surfacing (not wired by default): print one line if candidates are
    waiting for review. Fast + synchronous (no model call)."""
    staging = os.environ.get("BACKLOG_STAGE_STAGING", _default_staging())
    if not os.path.isfile(staging):
        return 0
    n = sum(1 for line in open(staging, encoding="utf-8") if line.startswith("## [staged]"))
    if n:
        s = "s" if n != 1 else ""
        print(f"\U0001F4CB {n} backlog candidate{s} staged in {staging}.")
    return 0


def main():
    if "--surface" in sys.argv[1:]:
        return surface()

    payload = read_payload()
    tp = payload.get("transcript_path")
    if not tp:
        return 0  # no transcript, nothing to do

    state_dir = os.environ.get("BACKLOG_STAGE_STATE_DIR", DEFAULT_STATE_DIR)
    if throttled(state_dir):
        return 0

    backlog = os.environ.get("BACKLOG_STAGE_BACKLOG", _default_backlog())
    staging = os.environ.get("BACKLOG_STAGE_STAGING", _default_staging())

    text = transcript_text(tp, int(os.environ.get("BACKLOG_STAGE_MAXCHARS", "12000")))
    if not text.strip():
        return 0

    # Skip the model call on sessions with no forward-intent signal (deterministic gate).
    if os.environ.get("BACKLOG_STAGE_PREFILTER", "1") != "0" and not has_intent(text):
        return 0

    candidates = extract_json_array(run_extractor(PROMPT_HEAD + text))
    if not candidates:
        return 0

    known = existing_titles(backlog, staging)
    date = payload.get("_today") or time.strftime("%Y-%m-%d")
    new_blocks = []
    for c in candidates:
        if not isinstance(c, dict):
            continue
        if norm(c.get("title", "")) in known or not norm(c.get("title", "")):
            continue
        block = render_candidate(c, date)
        if block:
            new_blocks.append(block)
            known.add(norm(c.get("title", "")))  # dedup within this batch too

    if new_blocks:
        header = "" if os.path.isfile(staging) else (
            "# Backlog staging (auto, via backlog-stage)\n\n"
            "Candidates auto-extracted from sessions. Review + promote by hand.\n"
            "Gitignored: may name unfiled work. NEVER the source of truth.\n\n"
        )
        os.makedirs(os.path.dirname(staging), exist_ok=True)
        with open(staging, "a", encoding="utf-8") as fh:
            fh.write(header + "".join(new_blocks))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)  # a harvest never blocks a session end
