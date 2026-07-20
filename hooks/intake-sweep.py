#!/usr/bin/env python3
"""intake-sweep.py: sweep deferred-link sources into the backlog staging funnel.

backlog-stage.py harvests SESSION transcripts into `_meta/backlog-staging.md`; this is
the same funnel fed from PERSISTED "review later" stores the session harvest cannot see
(a digest keeper ledger, saved browser collections, any future source). One funnel, one
grammar (lib/learn/staging-format.py), one human promote gate (`board promote`). This
NEVER writes the board directly (propose-don't-dispose, same contract as backlog-stage).

Config-gated: the kit carries NO personal data or source paths. A consumer declares its
sources in `<repo-root>/_meta/intake-sources.json`; no config file means this whole hook
is a silent no-op, so wiring it into a shared surface path costs other consumers nothing.

Config shape (paths/commands resolved relative to the repo root):
  {"sources": [
    {"name": "<slug>", "kind": "jsonl", "path": "rel/or/abs.jsonl",
     "include": {"field": "verdict", "equals": "keep"},          # optional row filter
     "map": {"title": "title", "url": "url", "intent": "conclusion"},
     "u": "lo", "f": "hi", "home": ""},
    {"name": "<slug>", "kind": "command", "command": "bin/tool subcmd",
     "map": {"title": "title", "url": "url"}, "u": "lo", "f": "hi"}
  ]}
  kind=jsonl   : one JSON object per line.
  kind=command : argv run from the repo root, must print a JSON array of objects.

Dedup, three layers (a source is re-read whole every sweep, so dedup must be durable):
  1. normalized title already on the board or in the staging file (ALL block states);
  2. the item's URL appearing anywhere in either file (catches renamed rows);
  3. a swept-keys state file: once staged, a key is never proposed again, even after the
     staged block is promoted/renamed/rejected.

Env:
  BACKLOG_STAGE_BACKLOG / BACKLOG_STAGE_STAGING   same seam as backlog-stage.py
  REPO_ROOT                                       consumer seam for defaults + config
  INTAKE_SWEEP_CONFIG=FILE                        config path override (tests)
  INTAKE_SWEEP_MIN_INTERVAL=S                     throttle, default 86400 (daily). 0 off.
  INTAKE_SWEEP_STATE_DIR=DIR                      throttle stamp + swept-keys file
  INTAKE_SWEEP_CMD_TIMEOUT=S                      per-command adapter timeout, default 15

Flags: --force (skip throttle; manual runs + tests).
Stdlib only. Always exits 0 (a sweep never blocks a session).
"""
import importlib.util
import json
import os
import re
import shlex
import subprocess
import sys
import time

DEFAULT_STATE_DIR = os.path.expanduser("~/.claude/dwarves-kit/state/intake-sweep")


def _repo_root():
    """REPO_ROOT env wins; else git top-level; else cwd (backlog-stage.py precedent)."""
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


def _staging_format():
    """Load the ONE staging-block grammar (hyphenated filename, importlib per drain.py)."""
    here = os.path.dirname(os.path.realpath(__file__))
    path = os.path.join(here, "..", "lib", "learn", "staging-format.py")
    spec = importlib.util.spec_from_file_location("staging_format", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_config(root):
    path = os.environ.get("INTAKE_SWEEP_CONFIG") or os.path.join(
        root, "_meta", "intake-sources.json"
    )
    try:
        with open(path, encoding="utf-8") as fh:
            cfg = json.load(fh)
    except (OSError, json.JSONDecodeError):
        return []
    sources = cfg.get("sources") if isinstance(cfg, dict) else None
    return sources if isinstance(sources, list) else []


def throttled(state_dir):
    """True if a sweep ran within INTAKE_SWEEP_MIN_INTERVAL seconds (backlog-stage
    precedent: bookkeeping errors never block)."""
    try:
        interval = int(os.environ.get("INTAKE_SWEEP_MIN_INTERVAL", "86400"))
    except ValueError:
        interval = 86400
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


def _mapped(item, source):
    """Map one raw source object into a candidate {title, url, intent} via the source's
    field map. Missing title falls back to the URL (a bare saved link is still a lead)."""
    m = source.get("map") or {}
    title = str(item.get(m.get("title", "title"), "") or "")
    url = str(item.get(m.get("url", "url"), "") or "")
    intent = str(item.get(m.get("intent", ""), "") or "") if m.get("intent") else ""
    if not title.strip():
        title = url
    return {"title": title, "url": url.strip(), "intent": intent}


def read_jsonl_source(source, root):
    path = source.get("path", "")
    if not os.path.isabs(path):
        path = os.path.join(root, path)
    inc = source.get("include") or {}
    out = []
    try:
        fh = open(path, encoding="utf-8")
    except OSError:
        return out
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(item, dict):
                continue
            if inc and str(item.get(inc.get("field", ""), "")) != str(inc.get("equals", "")):
                continue
            out.append(_mapped(item, source))
    return out


def read_command_source(source, root):
    cmd = source.get("command", "")
    if not cmd:
        return []
    argv = shlex.split(cmd)
    if argv and not os.path.isabs(argv[0]) and os.path.sep in argv[0]:
        argv[0] = os.path.join(root, argv[0])
    try:
        timeout = int(os.environ.get("INTAKE_SWEEP_CMD_TIMEOUT", "15"))
        r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, cwd=root)
        items = json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else []
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError, ValueError):
        return []
    if not isinstance(items, list):
        return []
    return [_mapped(i, source) for i in items if isinstance(i, dict)]


READERS = {"jsonl": read_jsonl_source, "command": read_command_source}


def _read_text(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return ""


def _swept_file(state_dir):
    return os.path.join(state_dir, "swept-keys.txt")


def load_swept(state_dir):
    return set(_read_text(_swept_file(state_dir)).splitlines())


def sweep(root, sources, sf, state_dir):
    """Return (blocks, keys_staged, per_source_counts). Pure over its file inputs."""
    backlog = os.environ.get("BACKLOG_STAGE_BACKLOG", os.path.join(root, "_meta", "BACKLOG.md"))
    staging = os.environ.get(
        "BACKLOG_STAGE_STAGING", os.path.join(root, "_meta", "backlog-staging.md")
    )
    known_titles = sf.existing_keys(("board", backlog), ("staging", staging))
    known_text = _read_text(backlog) + _read_text(staging)
    swept = load_swept(state_dir)

    date = time.strftime("%Y-%m-%d")
    blocks, staged_keys, counts = [], [], {}
    for source in sources:
        if not isinstance(source, dict):
            continue
        reader = READERS.get(source.get("kind", ""))
        name = source.get("name", "?")
        if reader is None:
            continue
        n = 0
        for c in reader(source, root):
            key = c["url"] or sf.norm(c["title"])
            if not key or key in swept:
                continue
            if sf.norm(c["title"]) in known_titles:
                continue
            if c["url"] and c["url"] in known_text:
                continue
            block = sf.render_block(
                {
                    "title": c["title"],
                    "intent": c["intent"] or c["url"],
                    "approach": c["url"] or "(no url)",
                    "u": source.get("u", "lo"),
                    "f": source.get("f", "hi"),
                    "home": source.get("home", ""),
                    "source": f"intake-sweep {name} {date}",
                }
            )
            if not block:
                continue
            blocks.append(block)
            staged_keys.append(key)
            swept.add(key)
            known_titles.add(sf.norm(c["title"]))
            n += 1
        counts[name] = n
    return blocks, staged_keys, counts, staging


def append_staged(staging, blocks):
    header = "" if os.path.isfile(staging) else (
        "# Backlog staging (auto, via backlog-stage)\n\n"
        "Candidates auto-extracted from sessions. Review + promote by hand.\n"
        "Gitignored: may name unfiled work. NEVER the source of truth.\n\n"
    )
    os.makedirs(os.path.dirname(staging), exist_ok=True)
    with open(staging, "a", encoding="utf-8") as fh:
        fh.write(header + "".join(blocks))


def record_swept(state_dir, keys):
    try:
        os.makedirs(state_dir, exist_ok=True)
        with open(_swept_file(state_dir), "a", encoding="utf-8") as fh:
            fh.writelines(k + "\n" for k in keys)
    except OSError:
        pass


def main():
    force = "--force" in sys.argv[1:]
    root = _repo_root()
    sources = load_config(root)
    if not sources:
        return 0  # no consumer config -> silent no-op

    state_dir = os.environ.get("INTAKE_SWEEP_STATE_DIR", DEFAULT_STATE_DIR)
    if not force and throttled(state_dir):
        return 0

    sf = _staging_format()
    blocks, keys, counts, staging = sweep(root, sources, sf, state_dir)
    if blocks:
        append_staged(staging, blocks)
        record_swept(state_dir, keys)
        per = ", ".join(f"{k}: {v}" for k, v in counts.items() if v)
        print(f"\U0001F9F2 intake-sweep: staged {len(blocks)} candidate(s) ({per}) in {staging}.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)  # a sweep never blocks a session
