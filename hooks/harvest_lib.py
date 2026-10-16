"""harvest_lib.py: the ledger helpers the harvest sweep shares, and the sweep's operator verbs.

The PreCompact, SessionEnd, and Stop hook now lives in hooks/harvest.sh (bash plus jq,
SPEC-409). What stays here is what hooks/harvest_sweep.py imports as a library: the
state-dir resolver, the slug rules, the per-ledger fcntl locks, the dedup-and-append stager
(`_stage_candidates`), and the three operator verbs that read or rewrite the sweep ledgers
under those same locks (`--cleanup`, `--flush-list`, `--mark-flushed`). They stay Python so
they exclude the sweep's own processes with the same flock(2) locks.

`main(argv)` runs one of the three verbs, as the old `harvest.py` dispatcher did: the bash
hook routes `--cleanup`, `--flush-list`, and `--mark-flushed` to hooks/harvest_sweep.py, which
calls it. Stdlib only.
"""
import datetime
import fcntl
import json
import os
import re
import subprocess
import sys

DEFAULT_STATE_DIR = os.path.expanduser("~/.claude/dwarves-kit/state/harvest")
KINDS = {"concept", "insight", "decision"}
HOMES = {"til", "research", "glossary", "drop"}

def _repo_root():
    """REPO_ROOT env wins; else git top-level; else cwd. Mirrors lib/board/board.sh's
    repo-root precedent -- no invented tenant var."""
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

def _default_ledger():
    return os.path.join(_repo_root(), "_meta", "learned-ledger.md")

def _default_glossary_glob():
    return os.path.join(_repo_root(), "learning", "*", "GLOSSARY.md")

def slugify(s):
    s = re.sub(r"[^a-z0-9]+", "-", str(s).lower()).strip("-")
    return s[:60]

def _levenshtein(a, b):
    """Edit distance between two strings (stdlib, two-row DP)."""
    if a == b:
        return 0
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]

def _fuzzy_threshold():
    """HARVEST_FUZZY_THRESHOLD: 0 (default/unset) = OFF, exact-slug dedup only.
    N>0 = also drop a candidate within Levenshtein distance N of a known slug.
    Any non-int or negative value is treated as 0 (OFF), so the default path is unchanged."""
    try:
        return max(0, int(os.environ.get("HARVEST_FUZZY_THRESHOLD", "0")))
    except ValueError:
        return 0

def _is_fuzzy_dup(slug, known, threshold):
    """True if slug is within `threshold` edits of any known slug. Off (False) when threshold<=0."""
    if threshold <= 0:
        return False
    return any(_levenshtein(slug, k) <= threshold for k in known)

def _slugs_in_ledger_file(path):
    """Col-2 slugs of every data row in a ledger-shaped file (any status, so a flushed
    or archived row still suppresses a re-stage). Missing file -> empty set."""
    slugs = set()
    if not os.path.isfile(path):
        return slugs
    for line in open(path, encoding="utf-8"):
        cells = [c.strip() for c in line.split("|")]
        # table row: ['', date, item, kind, home, status, '']
        if len(cells) >= 4 and re.match(r"\d{4}-\d{2}-\d{2}$", cells[1] or ""):
            slugs.add(slugify(cells[2]))
    return slugs

def _covering_lock(path):
    """The .lock guarding a ledger file: <file>.lock, or for an .archive sibling the
    base ledger's .lock (learned-ledger.archive.md -> learned-ledger.md.lock)."""
    base, ext = os.path.splitext(path)
    if base.endswith(".archive"):
        path = base[:-len(".archive")] + ext
    return path + ".lock"

def _extra_known_slugs(paths, held_lock=None):
    """Slugs from extra known-files (DEC-85). Each file is read only if it exists, and
    only under its covering .lock when that lock file already exists -- opened
    read-only without O_CREAT, so a repo read never creates a file (DEC-86). With no
    lock file the read goes ahead unlocked. The caller's own held lock (the ledger's
    .lock, which also covers its .archive sibling) is skipped by realpath."""
    held = os.path.realpath(held_lock) if held_lock else None
    locks = {}
    for p in paths:
        lock = _covering_lock(p)
        rp = os.path.realpath(lock)
        if rp != held and rp not in locks and os.path.exists(lock):
            locks[rp] = lock
    fds = []
    try:
        for lock in locks.values():
            fd = os.open(lock, os.O_RDONLY)
            fcntl.flock(fd, fcntl.LOCK_SH)
            fds.append(fd)
        slugs = set()
        for p in paths:
            slugs |= _slugs_in_ledger_file(p)
        return slugs
    finally:
        for fd in fds:
            fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)

def existing_slugs(ledger, glossaries):
    """Slugs already known: ledger col-2 + any glossary token that matches a slug shape."""
    slugs = _slugs_in_ledger_file(ledger)
    for gpath in glossaries:
        if os.path.isfile(gpath):
            # headings only (## concept), not body prose: scanning the whole body made
            # common words (error, setup, docker) silently suppress real new learnings.
            for line in open(gpath, encoding="utf-8"):
                m = re.match(r"#{2,4}\s+(.+)", line)
                if m:
                    slugs.add(slugify(m.group(1)))
    return slugs

def append_rows(ledger, rows):
    os.makedirs(os.path.dirname(ledger), exist_ok=True)
    newfile = not os.path.exists(ledger)
    with open(ledger, "a", encoding="utf-8") as fh:
        if newfile:
            fh.write("| date | item | kind | home | status |\n|---|---|---|---|---|\n")
        for r in rows:
            fh.write(f"| {r['date']} | {r['item']} | {r['kind']} | {r['home']} | queued |\n")

def _is_data_row(cells):
    """A ledger table data row: '| date | item | kind | home | status |' splits to
    ['', date, item, kind, home, status, '']. The leading date cell is the discriminator
    (same shape used by existing_slugs), so doc-prose tables and the '|---|' separator
    never match."""
    return len(cells) >= 6 and re.match(r"\d{4}-\d{2}-\d{2}$", cells[1] or "")

def _archive_path(ledger):
    """Sibling archive next to the active ledger: learned-ledger.md -> learned-ledger.archive.md.
    Override-aware: HARVEST_LEDGER=/x/foo.md archives to /x/foo.archive.md."""
    base, ext = os.path.splitext(ledger)
    return base + ".archive" + ext

def _ledger_lock_path(ledger):
    """Sibling lock file next to the active ledger: learned-ledger.md -> learned-ledger.md.lock."""
    return ledger + ".lock"

def _sweep_ledger_dir():
    """ledger/ under the sweep state dir: one <repo-slug>.md per repo plus each one's
    .archive.md sibling, .lock, and .rows.jsonl sidecar."""
    return os.path.join(_state_dir(), "sweep", "ledger")

def cmd_cleanup(ledger=None):
    """--cleanup [ledger]: move every `flushed:*` row (a learning already routed to its
    durable home) out of the active ledger into a sibling append-only archive. Queued /
    any non-flushed rows stay. Never deletes content. The ledger argument is the sweep's
    per-run archive pass over every ledger/<slug>.md; the CLI default stays HARVEST_LEDGER.
    The ledger's own .lock is held across the read, the archive append, and the rewrite,
    so a --mark-flushed that lands mid-pass is serialized, never overwritten by a stale
    keep set. Not part of the auto SessionEnd/PreCompact path."""
    ledger = ledger or os.environ.get("HARVEST_LEDGER", _default_ledger())
    if not os.path.isfile(ledger):
        print(f"harvest: --cleanup found no ledger at {ledger} (nothing to do)", file=sys.stderr)
        return 0
    # Unlocked peek: a pass that finds no flushed rows takes no lock and writes
    # nothing, so a no-op cleanup never creates a .lock beside a lockless ledger.
    def has_flushed():
        for line in open(ledger, encoding="utf-8"):
            cells = [c.strip() for c in line.split("|")]
            if _is_data_row(cells) and cells[5].startswith("flushed"):
                return True
        return False
    if not has_flushed():
        print(f"harvest: 0 archived (no flushed rows) -> {ledger}", file=sys.stderr)
        return 0
    with open(_ledger_lock_path(ledger), "a") as lockf:
        fcntl.flock(lockf, fcntl.LOCK_EX)
        try:
            # Re-read under the lock: a mark that landed between the peek and here is
            # covered by this pass; one that lands after the read is written out by the
            # rewrite below as its own flushed row, not lost.
            keep, archived = [], []
            for line in open(ledger, encoding="utf-8"):
                cells = [c.strip() for c in line.split("|")]
                if _is_data_row(cells) and cells[5].startswith("flushed"):
                    archived.append(line if line.endswith("\n") else line + "\n")
                else:
                    keep.append(line)
            if not archived:
                print(f"harvest: 0 archived (no flushed rows) -> {ledger}", file=sys.stderr)
                return 0
            archive = _archive_path(ledger)
            newfile = not os.path.exists(archive)
            with open(archive, "a", encoding="utf-8") as fh:
                if newfile:
                    fh.write("| date | item | kind | home | status |\n|---|---|---|---|---|\n")
                fh.writelines(archived)
            # Atomic rewrite of the active ledger (temp + replace) so a crash never truncates it.
            tmp = ledger + ".tmp"
            with open(tmp, "w", encoding="utf-8") as fh:
                fh.writelines(keep)
            os.replace(tmp, ledger)
        finally:
            fcntl.flock(lockf, fcntl.LOCK_UN)
    print(f"harvest: {len(archived)} archived -> {archive}", file=sys.stderr)
    return 0

def cmd_flush_list():
    """--flush-list: the queued rows of every sweep ledger as one JSON array on stdout.
    Each ledger is read under its own .lock (shared) and joined with its .rows.jsonl
    sidecar, so a concurrent --mark-flushed or archive pass can never hand back a
    half-written file (AC17, AC29). A row whose sidecar entry is absent or unwritten
    carries null context fields -- the crash window AC29's replay repairs."""
    d = _sweep_ledger_dir()
    try:
        names = sorted(os.listdir(d))
    except OSError:
        names = []
    rows = []
    for name in names:
        if not name.endswith(".md") or name.endswith(".archive.md"):
            continue
        ledger = os.path.join(d, name)
        slug = name[:-3]
        with open(_ledger_lock_path(ledger), "a") as lockf:
            fcntl.flock(lockf, fcntl.LOCK_SH)
            try:
                side = {}
                sidecar = os.path.splitext(ledger)[0] + ".rows.jsonl"
                if os.path.isfile(sidecar):
                    for line in open(sidecar, encoding="utf-8"):
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            row = json.loads(line)
                        except ValueError:
                            continue
                        if isinstance(row, dict) and row.get("row_id"):
                            side[row["row_id"]] = row
                for line in open(ledger, encoding="utf-8"):
                    cells = [c.strip() for c in line.split("|")]
                    if not (_is_data_row(cells) and cells[5] == "queued"):
                        continue
                    ctx = side.get("%s:%s" % (slug, cells[2])) or {}
                    rows.append({"row_id": "%s:%s" % (slug, cells[2]),
                                 "ledger": ledger,
                                 "date": cells[1], "item": cells[2],
                                 "kind": cells[3], "home": cells[4],
                                 "why": ctx.get("why"),
                                 "evidence": ctx.get("evidence"),
                                 "source": ctx.get("source"),
                                 "lead_session_id": ctx.get("lead_session_id")})
            finally:
                fcntl.flock(lockf, fcntl.LOCK_UN)
    print(json.dumps(rows))
    return 0

def cmd_mark_flushed(row_id, ref):
    """--mark-flushed <row-id> <ref>: flip one sweep-ledger row from `queued` to
    `flushed:<ref>` under that ledger's .lock, rewritten through tmp + os.replace so a
    crash never leaves a half-written ledger (DEC-69, DEC-70). Exits 0 on the flip,
    1 -- with no write at all -- when the row id is unknown or the row is not queued,
    so a double mark and a stale list both stay no-ops."""
    slug, sep, item = row_id.partition(":")
    ref = re.sub(r"[|\r\n]", "", (ref or "").strip())
    if not sep or not slug or not item or not ref:
        return 1
    ledger = os.path.join(_sweep_ledger_dir(), slug + ".md")
    if not os.path.isfile(ledger):
        return 1
    with open(_ledger_lock_path(ledger), "a") as lockf:
        fcntl.flock(lockf, fcntl.LOCK_EX)
        try:
            lines = open(ledger, encoding="utf-8").readlines()
            hit = -1
            for i, line in enumerate(lines):
                cells = [c.strip() for c in line.split("|")]
                if _is_data_row(cells) and cells[2] == item:
                    hit, status = i, cells[5]
                    break
            if hit < 0 or status != "queued":
                return 1
            cells[5] = "flushed:" + ref
            lines[hit] = "| " + " | ".join(cells[1:-1]) + " |\n"
            tmp = ledger + ".tmp"
            with open(tmp, "w", encoding="utf-8") as fh:
                fh.writelines(lines)
            os.replace(tmp, ledger)
        finally:
            fcntl.flock(lockf, fcntl.LOCK_UN)
    return 0

def _stage_candidates(ledger, glossaries, candidates, extra_known=()):
    """Dedup candidates against the ledger + glossaries, append the fresh rows, return them.

    Dedup-on-append race (ID-202): harvest.sh fires on PreCompact, and a single
    long session (or several parallel subagent sessions sharing one repo) can
    trigger concurrent harvest processes against the SAME ledger. Reading
    existing_slugs() and appending were two separate unlocked steps, so two
    processes could both read the ledger before either had appended, both decide
    the same slug was new, and both append it -- observed as up to 6x duplicates.
    Fix: hold a blocking exclusive flock across read-known + append, so concurrent
    invocations serialize instead of racing (mirrors _run_harvest_locked's fcntl
    pattern, but blocking -- a harvest here has real work to do, unlike the
    stop-trigger single-flight which just skips).

    extra_known: extra ledger-shaped files whose rows count as known slugs (the
    sweep passes its ledger's .archive.md plus the repo's _meta/learned-ledger.md
    pair). Each is read only if it exists, under its covering .lock when that file
    exists, opened read-only without O_CREAT (DEC-86).
    """
    fuzzy = _fuzzy_threshold()
    today = datetime.date.today().isoformat()
    os.makedirs(os.path.dirname(ledger), exist_ok=True)
    fresh = []
    with open(_ledger_lock_path(ledger), "a") as lockf:
        fcntl.flock(lockf, fcntl.LOCK_EX)
        try:
            known = existing_slugs(ledger, glossaries)
            known |= _extra_known_slugs(extra_known,
                                        held_lock=_ledger_lock_path(ledger))
            seen = set()
            for c in candidates:
                if not isinstance(c, dict):
                    continue
                slug = slugify(c.get("item", ""))
                kind = c.get("kind") if c.get("kind") in KINDS else "insight"
                home = c.get("home") if c.get("home") in HOMES else "drop"
                if not slug or slug in known or slug in seen:
                    continue
                if _is_fuzzy_dup(slug, known, fuzzy) or _is_fuzzy_dup(slug, seen, fuzzy):
                    continue
                seen.add(slug)
                fresh.append({"date": today, "item": slug, "kind": kind, "home": home})

            if fresh:
                append_rows(ledger, fresh)
        finally:
            fcntl.flock(lockf, fcntl.LOCK_UN)
    return fresh

def _truthy(v):
    return str(v or "").strip().lower() in ("1", "true", "yes", "on")

def _safe_session(sid):
    """Filesystem-safe per-session counter key (session_id is a UUID, but never trust it)."""
    sid = re.sub(r"[^A-Za-z0-9._-]", "_", str(sid or ""))
    return sid[:128] or "nosession"

def _state_dir():
    return os.environ.get("HARVEST_STATE_DIR", DEFAULT_STATE_DIR)


def main(argv):
    """The operator verbs, with the same precedence and return codes the old dispatcher had.
    Returns None when argv holds none of them."""
    if "--cleanup" in argv:
        i = argv.index("--cleanup")
        nxt = argv[i + 1] if i + 1 < len(argv) else ""
        return cmd_cleanup(nxt if nxt and not nxt.startswith("--") else None)
    if "--flush-list" in argv:
        return cmd_flush_list()
    if "--mark-flushed" in argv:
        i = argv.index("--mark-flushed")
        rid = argv[i + 1] if i + 1 < len(argv) else ""
        ref = argv[i + 2] if i + 2 < len(argv) else ""
        if not rid or not ref:
            sys.stderr.write("usage: harvest_sweep.py --mark-flushed <row-id> <ref>\n")
            return 2
        return cmd_mark_flushed(rid, ref)
    return None
