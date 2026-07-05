#!/usr/bin/env python3
"""citation-guard.py: a Stop hook that checks file:line citations in the final message.

Ported from ops-toolkit's cc-citation-guard (function-named per the kit-foldin design
note: no host-agent prefix, was cc-citation-guard). Claude Code passes a Stop hook a
JSON payload on stdin that includes `transcript_path`. This reads the last assistant
message from that transcript, extracts every `path:line` reference (ignoring fenced
code, inline code, and URLs so examples do not false-positive), and verifies each one
resolves: the file exists and has at least that many lines.

Default is log-only (append unresolved refs to a log, never block) so it is safe to
wire on day one. Set CITATION_GUARD_STRICT=1 to instead BLOCK the stop (exit 2) with
the bad refs, once the false-positive rate is tuned to your taste.

Scope: file:line refs only (the precise hallucination risk). Bare paths are too noisy
to check without false positives; out for v1. Semantic correctness ("does line 42
actually do what was claimed") needs a model and is out of scope here.

Env:
  CITATION_GUARD_STRICT=1   block instead of log-only
  CITATION_GUARD_ROOT=DIR   resolve relative refs against DIR (else transcript cwd, else $PWD)
  CITATION_GUARD_LOG=FILE   log destination (default ~/.claude/dwarves-kit/logs/citation-guard.log)

Stdlib only.
"""
import json
import os
import re
import sys
import time

DEFAULT_LOG = os.path.expanduser("~/.claude/dwarves-kit/logs/citation-guard.log")

FENCE_RE = re.compile(r"```.*?```", re.S)
INLINE_RE = re.compile(r"`[^`]*`")
URL_RE = re.compile(r"https?://\S+")
# name.ext:line -- requires a dotted extension before the colon, so clock times
# ("10:00") and bare ratios don't match. Captures (path, line).
REF_RE = re.compile(r"([A-Za-z0-9._\-/]+\.[A-Za-z0-9_]+):(\d+)\b")


def read_payload():
    try:
        return json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return {}


def last_assistant_text(transcript_path):
    """Concatenated text blocks of the LAST assistant entry in the transcript."""
    text = None
    try:
        fh = open(transcript_path, encoding="utf-8")
    except OSError:
        return None
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                o = json.loads(line)
            except json.JSONDecodeError:
                continue
            if o.get("type") != "assistant":
                continue
            msg = o.get("message") or {}
            content = msg.get("content")
            if not isinstance(content, list):
                continue
            parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
            if parts:
                text = "\n".join(parts)  # keep only the latest assistant turn
    return text


def extract_refs(text):
    """file:line refs in prose, with code fences / inline code / URLs stripped."""
    stripped = FENCE_RE.sub("", text)
    stripped = INLINE_RE.sub("", stripped)
    stripped = URL_RE.sub("", stripped)
    seen = []
    for path, line in REF_RE.findall(stripped):
        ref = (path, int(line))
        if ref not in seen:
            seen.append(ref)
    return seen


def unresolved(refs, root):
    """Return refs whose file is missing or whose line is past EOF."""
    bad = []
    for path, line in refs:
        target = path if os.path.isabs(path) else os.path.join(root, path)
        if not os.path.isfile(target):
            bad.append(f"{path}:{line} (no such file)")
            continue
        try:
            with open(target, "rb") as fh:
                n = sum(1 for _ in fh)
        except OSError:
            bad.append(f"{path}:{line} (unreadable)")
            continue
        if line > n:
            bad.append(f"{path}:{line} (file has {n} lines)")
    return bad


def log_bad(bad, payload):
    path = os.environ.get("CITATION_GUARD_LOG", DEFAULT_LOG)
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as fh:
            sid = payload.get("sessionId") or payload.get("session_id") or "?"
            fh.write(f"{int(time.time())}\t{sid}\t" + "; ".join(bad) + "\n")
    except OSError:
        pass


def main():
    payload = read_payload()
    tp = payload.get("transcript_path")
    if not tp:
        return 0  # nothing to check; never block on a malformed payload
    text = last_assistant_text(tp)
    if not text:
        return 0
    refs = extract_refs(text)
    if not refs:
        return 0
    root = os.environ.get("CITATION_GUARD_ROOT") or payload.get("cwd") or os.getcwd()
    bad = unresolved(refs, root)
    if not bad:
        return 0

    log_bad(bad, payload)
    if os.environ.get("CITATION_GUARD_STRICT") == "1":
        print("citation-guard: unresolved citations: " + "; ".join(bad), file=sys.stderr)
        return 2  # block the stop so the model fixes the refs
    return 0  # log-only default


if __name__ == "__main__":
    sys.exit(main())
