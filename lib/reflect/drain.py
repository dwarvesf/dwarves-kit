#!/usr/bin/env python3
"""drain.py -- `learn drain` (SPEC-196, ADR-0034 decision 1): the staging-review render for
`_meta/backlog-staging.md`. Pure read + render, with exactly ONE write: rows staged longer
than the expiry window get relabeled in place (header token only, `## [staged]` ->
`## [expired]`), signalling "past due for a decision" -- never deleted.

`lib/board/bin/add-backlog` already only lists `state == "staged"` blocks (`board promote`),
so an `[expired]` row is automatically unselectable there -- no index-skip change needed.

Usage:
  drain.py [--days N]
    -> renders currently-staged candidates grouped by Home (alphabetical), oldest-first
       within each group, numbered in FILE ORDER over the staged subset -- the exact
       numbering `board promote <n>` already reads. Moves any staged candidate older than
       N days (default: DEFAULT_EXPIRE_DAYS) to [expired] first.

Env: BACKLOG_STAGE_STAGING (same name + repo-relative default as hooks/backlog-stage.py /
lib/board/bin/add-backlog: <repo-root>/_meta/backlog-staging.md).

The expiry window is a plain CONSTANT with a --days override (ADR-0034 pin: never a
kit.toml key -- this is what keeps SG-06 file-disjoint from SG-05's kit.toml edit).

The write is guarded by a blocking exclusive `fcntl.flock` on a sibling `<staging>.lock`
file: the same idiom hooks/harvest.py's post-#226 dedup-on-append fix uses for the
learned-ledger (open/create the lock, acquire, read + mutate + write, release in `finally`),
adapted here to the staging file. bash(1) `flock` itself is not used anywhere in this repo
(absent on macOS, per lib/queue/orchestrate.sh's own note) -- this is the same Python
fcntl.flock idiom harvest.py already established, not a new locking primitive.
"""
import fcntl
import importlib.util
import os
import re
import subprocess
import sys

DEFAULT_EXPIRE_DAYS = 30

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load_staging_format():
    spec = importlib.util.spec_from_file_location(
        "staging_format", os.path.join(_HERE, "staging-format.py")
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


sf = _load_staging_format()


def _repo_root():
    try:
        r = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=5
        )
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return os.getcwd()


def _staging_path():
    return os.environ.get(
        "BACKLOG_STAGE_STAGING", os.path.join(_repo_root(), "_meta/backlog-staging.md")
    )


def _lock_path(staging):
    return staging + ".lock"


def expire_stale(text, days):
    """Relabel every `[staged]` block older than `days` to `[expired]`, in place (header
    token only -- content, position, and every other block stay byte-identical). Returns
    (new_text, expired_count). A block with no parseable Source date is left alone (age
    unknown is never treated as expired)."""
    blocks = sf.parse_blocks(text)
    expired = 0
    for b in blocks:
        if b["state"] != "staged":
            continue
        age = sf.age_days(b["fields"])
        if age is not None and age > days:
            new_raw = re.sub(r"^##\s*\[staged\]", "## [expired]", b["raw"], count=1)
            text = text.replace(b["raw"], new_raw, 1)
            expired += 1
    return text, expired


def render(blocks):
    """Group the CURRENTLY-staged blocks by Home (alphabetical), oldest-first within each
    group (unknown age last); number 1..K over the staged subset in file order -- the exact
    numbering `board promote <n>` already reads. Phone-legible: one line per candidate, no
    forced truncation (matches lib/stats/src/stats/render.py::render_terminal's stated
    policy)."""
    staged_blocks = [b for b in blocks if b["state"] == "staged"]
    if not staged_blocks:
        return "no staged candidates."

    indexed = list(enumerate(staged_blocks, 1))  # mirrors add-backlog's enumerate(staged, 1)

    groups = {}
    for idx, b in indexed:
        home = b["fields"].get("Home", "").strip() or "(no home)"
        groups.setdefault(home, []).append((idx, b))

    def _sort_key(pair):
        age = sf.age_days(pair[1]["fields"])
        return (age is None, -(age or 0))  # unknown-age last; oldest (largest age) first

    lines = []
    for home in sorted(groups):
        items = sorted(groups[home], key=_sort_key)
        lines.append(f"## Home: {home} ({len(items)} staged)")
        for idx, b in items:
            age = sf.age_days(b["fields"])
            age_s = f"{age}d" if age is not None else "age?"
            tags = b["fields"].get("Tags", "").strip()
            evidence = b["fields"].get("Source", "").strip() or "(no source)"
            lines.append(f"{idx:>3}. {b['title']}  {age_s}  {tags}  {evidence}")
        lines.append("")
    lines.append(f"({len(staged_blocks)} staged candidate{'s' if len(staged_blocks) != 1 else ''})")
    lines.append("promote with: board promote <n>...  |  board promote all  |  board promote reject <n>")
    return "\n".join(lines).rstrip()


def main(argv):
    days = DEFAULT_EXPIRE_DAYS
    if "--days" in argv:
        i = argv.index("--days")
        try:
            days = int(argv[i + 1])
        except (IndexError, ValueError):
            print("usage: learn drain [--days N]", file=sys.stderr)
            return 2

    staging = _staging_path()
    if not os.path.isfile(staging):
        print(f"no staging file ({staging}); nothing staged.")
        return 0

    os.makedirs(os.path.dirname(staging) or ".", exist_ok=True)
    with open(_lock_path(staging), "a") as lockf:
        fcntl.flock(lockf, fcntl.LOCK_EX)
        try:
            text = open(staging, encoding="utf-8").read()
            new_text, expired = expire_stale(text, days)
            if new_text != text:
                open(staging, "w", encoding="utf-8").write(new_text)
                text = new_text
        finally:
            fcntl.flock(lockf, fcntl.LOCK_UN)

    blocks = sf.parse_blocks(text)
    print(render(blocks))
    if expired:
        s = "s" if expired != 1 else ""
        print(f"\n{expired} candidate{s} staged >{days}d moved to [expired] (never deleted).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
