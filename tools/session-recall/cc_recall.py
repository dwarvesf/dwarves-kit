#!/usr/bin/env python3
"""Lossless, turn-grouped recall over Claude Code transcripts.

Read-only structure-preserving search over raw `~/.claude/projects/<slug>/*.jsonl`.
Ports pi-vcc's `vcc_recall`: a session can retrieve a prior decision/fact straight from
the source transcript , even across compactions , without re-reading whole files. The
raw JSONL is the source of truth, so nothing is ever lost; this never mutates a transcript.

ponytail: structure-preserving substring grep grouped by turn. NOT an embedding index
(prose-rag already does semantic search); NOT a daemon. Stdlib only.
"""
from __future__ import annotations

import json
import os
import sys

PROJECTS = os.path.expanduser("~/.claude/projects")


def _repo_root():
    """Walk up from this file to find the kit repo root (the dir holding
    lib/session/). Repo-relative per DECISIONS.md's adapter-default invariant:
    no hardcoded ops-toolkit/personal path, no CONSUMER_ROOT env."""
    d = os.path.dirname(os.path.abspath(__file__))
    for _ in range(8):
        if os.path.isdir(os.path.join(d, "lib", "session")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    raise RuntimeError("cc-recall: cannot locate the kit repo root (lib/session not found)")


sys.path.insert(0, os.path.join(_repo_root(), "lib", "session"))
from parse_transcript import load  # noqa: E402  (re-exported: cc-recall's own public `load`)


# --- parsing --------------------------------------------------------------
# `load()` is the shared lib/session/parse_transcript.py routine (kit-foldin
# SG-03): the JSONL-turn-parsing that used to be duplicated with cc-observe's
# own `iter_entries` now lives in ONE place. `_role`/`_ts`/`searchable_text`
# below stay cc-recall's own logic -- they are not duplicated in cc-observe,
# which never needs a per-turn role/text accessor the way point-lookup search
# does.


def _role(entry):
    return (entry.get("message") or {}).get("role") or entry.get("type") or "?"


def _ts(entry):
    return entry.get("timestamp") or ""


def searchable_text(entry) -> str:
    """All human-meaningful text in a turn: prose, thinking, tool inputs, tool results."""
    parts = []
    msg = entry.get("message") or {}
    content = msg.get("content")
    if isinstance(content, str):
        parts.append(content)
    elif isinstance(content, list):
        for b in content:
            if not isinstance(b, dict):
                continue
            t = b.get("type")
            if t == "text":
                parts.append(b.get("text") or "")
            elif t == "thinking":
                parts.append(b.get("thinking") or "")
            elif t == "tool_use":
                parts.append(f"[{b.get('name')}] " + json.dumps(b.get("input") or {}, ensure_ascii=False))
            elif t == "tool_result":
                rc = b.get("content")
                if isinstance(rc, str):
                    parts.append(rc)
                elif isinstance(rc, list):
                    for s in rc:
                        if isinstance(s, dict) and s.get("type") == "text":
                            parts.append(s.get("text") or "")
    return "\n".join(p for p in parts if p)


# --- search ------------------------------------------------------------------

def search(entries, query: str):
    """Return [(turn_index, entry, match_count)] for turns whose text contains `query`
    (case-insensitive). Order preserved (= conversation order)."""
    q = query.lower()
    if not q:
        return []
    hits = []
    for i, entry in enumerate(entries):
        text = searchable_text(entry)
        n = text.lower().count(q)
        if n:
            hits.append((i, entry, n))
    return hits


def _snippet(text: str, query: str, width: int = 160) -> str:
    """A one-line window around the first match, with the match marked »...«."""
    low = text.lower()
    pos = low.find(query.lower())
    if pos < 0:
        return ""
    start = max(0, pos - width // 2)
    end = min(len(text), pos + len(query) + width // 2)
    frag = text[start:end].replace("\n", " ")
    # mark every occurrence of the query in this fragment (case-preserving)
    out, i = [], 0
    fl = frag.lower()
    ql = query.lower()
    while True:
        j = fl.find(ql, i)
        if j < 0:
            out.append(frag[i:])
            break
        out.append(frag[i:j])
        out.append("»" + frag[j:j + len(query)] + "«")
        i = j + len(query)
    marked = "".join(out).strip()
    prefix = "…" if start > 0 else ""
    suffix = "…" if end < len(text) else ""
    return prefix + marked + suffix


def render(hits, query: str) -> str:
    """Turn-grouped, structure-preserving rendering."""
    lines = []
    for idx, entry, n in hits:
        more = f" ({n} matches)" if n > 1 else ""
        lines.append(f"── turn {idx} · {_role(entry)} · {_ts(entry)}{more} ──")
        lines.append("  " + _snippet(searchable_text(entry), query))
    return "\n".join(lines)


# --- project/file resolution -------------------------------------------------

def _cwd_slug() -> str:
    return os.path.abspath(os.getcwd()).replace("/", "-")


def resolve_files(file=None, project=None, search_all=False):
    """Which transcript files to search."""
    if file:
        return [file]
    if search_all:
        if not os.path.isdir(PROJECTS):
            return []
        out = []
        for d in sorted(os.listdir(PROJECTS)):
            pd = os.path.join(PROJECTS, d)
            if os.path.isdir(pd):
                out += sorted(os.path.join(pd, f) for f in os.listdir(pd) if f.endswith(".jsonl"))
        return out
    slug = project or _cwd_slug()
    pd = os.path.join(PROJECTS, slug)
    if not os.path.isdir(pd):
        return []
    return sorted(os.path.join(pd, f) for f in os.listdir(pd) if f.endswith(".jsonl"))


# --- CLI ---------------------------------------------------------------------

def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    file = project = None
    search_all = as_json = False
    limit = 50
    query_parts = []
    it = iter(argv)
    for a in it:
        if a == "--file":
            file = next(it, None)
        elif a == "--project":
            project = next(it, None)
        elif a == "--all":
            search_all = True
        elif a == "--json":
            as_json = True
        elif a == "--limit":
            limit = int(next(it, "50") or 50)
        elif a in ("-h", "--help"):
            sys.stderr.write("usage: cc-recall <query> [--file F | --project SLUG | --all] "
                             "[--limit N] [--json]\n")
            return 0
        else:
            query_parts.append(a)
    query = " ".join(query_parts).strip()
    if not query:
        sys.stderr.write("usage: cc-recall <query> [--file F | --project SLUG | --all] "
                         "[--limit N] [--json]\n")
        return 2

    files = resolve_files(file=file, project=project, search_all=search_all)
    all_hits = []
    for f in files:
        try:
            entries = load(f)
        except OSError:
            continue
        for idx, entry, n in search(entries, query):
            all_hits.append((f, idx, entry, n))
            if len(all_hits) >= limit:
                break
        if len(all_hits) >= limit:
            break

    if as_json:
        payload = [{"file": f, "turn": idx, "role": _role(e), "timestamp": _ts(e),
                    "matches": n, "snippet": _snippet(searchable_text(e), query)}
                   for f, idx, e, n in all_hits]
        sys.stdout.write(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    else:
        text = render([(idx, e, n) for _, idx, e, n in all_hits], query)
        if text:
            sys.stdout.write(text + "\n")
        if not all_hits:
            sys.stderr.write(f"no matches for {query!r}\n")
    return 0  # clean exit even on no match (recall is advisory, not a test)


if __name__ == "__main__":
    raise SystemExit(main())
