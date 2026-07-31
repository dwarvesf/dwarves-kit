#!/usr/bin/env python3
"""harvest.py: PreCompact / SessionEnd hook that stages session learnings.

Ported from ops-toolkit's cc-harvest (function-named per the kit-foldin design note:
no host-agent prefix, was cc-harvest). When a session is about to compact (or ends),
the durable decisions/gotchas/concepts in it are easy to lose. This hook reads the
transcript, asks a cheap Claude model (Haiku) to extract the genuinely durable
learnings, dedups them against the existing ledger + glossary files, and appends ONLY
the new ones to a ledger as `status: queued`.

It NEVER writes to a durable home (a project's own knowledge base). The existing
manual flush stays the gate: harvest auto-STAGES, a human flushes. The transcript is
already in an Anthropic session, so using Haiku adds no new data EXPOSURE. It does,
however, consume Max-plan QUOTA: a `claude -p` call counts against the 5h + weekly
usage limits.

The LLM call is isolated behind HARVEST_EXTRACTOR (a shell command that reads the
prompt on stdin and writes a JSON array on stdout), so the dedup/append/guard logic is
testable without a live model. Default extractor: `claude -p --model haiku
--setting-sources project`. The `--setting-sources project` is load-bearing: it stops
the spawned extractor from loading the USER-level settings.json (where this hook
lives), so it cannot re-fire the SessionEnd/PreCompact hook and recurse into an
unbounded spawn storm. (`--bare` also skips hooks but additionally skips keychain
reads, breaking auth; project setting-sources keeps the keychain OAuth.)

Consumer seam (no hardcoded tenant path; per kit-foldin DECISIONS.md): the ledger,
glossary glob, and LAB_LOG draft default REPO-RELATIVE under `_meta/`/`learning/`,
resolved from REPO_ROOT (env) else `git rev-parse --show-toplevel` else $PWD,
mirroring lib/board/board.sh's own repo-root precedent. There is no ops-toolkit-specific
fallback.

Env:
  HARVEST_LEDGER=FILE        ledger to append to (default <repo-root>/_meta/learned-ledger.md)
  HARVEST_GLOSSARIES=A:B     extra dedup sources (default <repo-root>/learning/*/GLOSSARY.md)
  HARVEST_EXTRACTOR=CMD      override the LLM call (tests)
  HARVEST_FUZZY_THRESHOLD=N  optional fuzzy dedup (default 0 = OFF, exact-slug only).
                             N>0 also drops a candidate whose slug is within Levenshtein
                             distance N of a known slug. Default keeps current behavior exactly.
  HARVEST_MAXCHARS=N         transcript chars sent to the model (default 12000)
  HARVEST_LABLOG_DRAFT=FILE  --lab-log staging file (default <repo-root>/_meta/.lab-log-draft.md)
  HARVEST_STOP_TRIGGER=1     opt-in: enable the --stop-trigger per-N-turns harvest (default OFF)
  HARVEST_STOP_N=N           --stop-trigger fires the harvest every N turns (default 10)
  HARVEST_STATE_DIR=DIR      --stop-trigger counter + lock dir, AND the detached-child
                             payload handoff dir for --lab-log/no-arg/--stop-trigger
                             (default ~/.claude/dwarves-kit/state/harvest)
  HARVEST_MIN_INTERVAL=SECS  rate-limit the no-arg + --lab-log harvests to at most once per
                             SECS (default 3600 = 1h). 0 disables.
  HARVEST_SYNC=1             run the no-arg and --lab-log harvests INLINE instead of
                             detached (test seam, deterministic; default OFF = detached)
  REPO_ROOT=DIR              consumer seam for the repo-relative defaults above

Modes: no args = stage ledger learnings (PreCompact/SessionEnd). `--lab-log` = draft a
session-close LAB_LOG entry to the staging file for review (SessionEnd); it NEVER
writes the real LAB_LOG.md (propose-don't-dispose; a human moves the draft in).
`--stop-trigger` = a Stop-hook entry point that keeps a per-session turn counter and
fires the existing no-arg harvest every N turns. Opt-in (default OFF), detached/async
(never blocks the turn), single-flight (a harvest already running skips this turn's
fire). `--cleanup` = a human-run mode (NOT auto-fired) that archives every
`flushed:*` row (a learning already routed to its durable home) out of the active
ledger into a sibling append-only `<ledger-basename>.archive.md`, keeping the ledger
lean; queued rows stay, content is never deleted.

Both the no-arg and `--lab-log` modes call `claude -p` (up to a 120s budget), but the
PreCompact/SessionEnd/Stop hook slots that invoke this script are only ever given a
much shorter timeout (30s in this kit's hooks.json) -- and SessionEnd additionally
fires while the CLI process is already tearing down. Either one can get the whole
invocation killed mid-call before it writes anything. So, like `--stop-trigger`
already did, both modes spawn a detached child (`--harvest-run` / `--lab-log-run`,
same `_spawn_detached` used by stop-trigger) and return almost immediately; the actual
`claude -p` call and file write happen in that child, which outlives the invoking
hook's timeout and the parent process's exit. HARVEST_SYNC=1 opts back into the old
inline behavior (used by the test fixtures for determinism).

Stdlib only. Always exits 0 (a harvest never blocks a compaction/stop).
"""
import datetime
import fcntl
import glob
import json
import os
import re
import shlex
import subprocess
import sys
import time

DEFAULT_EXTRACTOR = "claude -p --model haiku --setting-sources project"
DEFAULT_STATE_DIR = os.path.expanduser("~/.claude/dwarves-kit/state/harvest")
KINDS = {"concept", "insight", "decision"}
HOMES = {"til", "research", "glossary", "drop"}

PROMPT_HEAD = (
    "You extract durable, reusable learnings from a coding/ops session transcript.\n"
    "Output ONLY a JSON array, no prose. Each element:\n"
    '  {"item": "<short-kebab-slug>", "kind": "concept|insight|decision", '
    '"home": "til|research|glossary|drop", "why": "<one sentence>"}\n'
    "Include ONLY genuinely durable, non-obvious learnings worth keeping later. "
    "Exclude chit-chat, transient state, and anything obvious. If there is nothing "
    "worth keeping, output []. Transcript follows:\n\n"
)

PROMPT_LABLOG = (
    "You draft ONE concise LAB_LOG entry for a coding/ops session, from the transcript.\n"
    "Format EXACTLY:\n"
    "## {date} - <short-kebab-slug>: <one-line what>\n"
    "then 3 to 8 single-line bullets. Rules: the log is an INDEX, not the record; no narrative "
    "arcs; do not restate commit messages; point at durable storage (PR #s / SPECs / files). "
    "If the session has nothing worth logging, output exactly: NONE.\nTranscript follows:\n\n"
)


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


def _default_lablog_draft():
    return os.path.join(_repo_root(), "_meta", ".lab-log-draft.md")


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
    cmd = os.environ.get("HARVEST_EXTRACTOR") or DEFAULT_EXTRACTOR
    # No shell: the transcript is passed on stdin, and the command (default or the
    # operator-set HARVEST_EXTRACTOR) is split with shlex so no transcript content
    # can ever be interpreted as a shell metacharacter.
    try:
        r = subprocess.run(shlex.split(cmd), input=prompt, capture_output=True, text=True, timeout=120)
        return r.stdout
    except (subprocess.SubprocessError, OSError):
        return ""


def extract_json_array(text):
    """Pull the first balanced [...] out of model output (tolerates fences/canary/prose)."""
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


def existing_slugs(ledger, glossaries):
    """Slugs already known: ledger col-2 + any glossary token that matches a slug shape."""
    slugs = set()
    if os.path.isfile(ledger):
        for line in open(ledger, encoding="utf-8"):
            cells = [c.strip() for c in line.split("|")]
            # table row: ['', date, item, kind, home, status, '']
            if len(cells) >= 4 and re.match(r"\d{4}-\d{2}-\d{2}$", cells[1] or ""):
                slugs.add(slugify(cells[2]))
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


def cmd_cleanup():
    """--cleanup: move every `flushed:*` row (a learning already routed to its durable home) out
    of the active ledger into a sibling append-only archive. Queued / any non-flushed rows stay.
    Never deletes content. Human-run mode, NOT part of the auto SessionEnd/PreCompact path."""
    ledger = os.environ.get("HARVEST_LEDGER", _default_ledger())
    if not os.path.isfile(ledger):
        print(f"harvest: --cleanup found no ledger at {ledger} (nothing to do)", file=sys.stderr)
        return 0
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
    print(f"harvest: {len(archived)} archived -> {archive}", file=sys.stderr)
    return 0


def _clean_lablog(raw):
    raw = raw.strip()
    if not raw or raw.upper().startswith("NONE"):
        return ""
    lines = [ln for ln in raw.splitlines() if not ln.strip().startswith("```")]
    block = "\n".join(lines).strip()
    if not re.search(r"(?m)^##\s+\d{4}-\d{2}-\d{2}", block):
        return ""  # not a LAB_LOG-shaped entry: stage nothing rather than garbage
    return block


def cmd_lab_log(payload):
    """--lab-log(-run): draft a session-close LAB_LOG entry to a staging file (never the
    real LAB_LOG.md). Takes an already-parsed payload; the caller reads it from stdin
    (sync path) or a handoff file (detached child), see _dispatch."""
    tp = payload.get("transcript_path")
    if not tp:
        return 0
    text = transcript_text(tp, int(os.environ.get("HARVEST_MAXCHARS", "12000")))
    if not text.strip():
        return 0
    today = datetime.date.today().isoformat()
    block = _clean_lablog(run_extractor(PROMPT_LABLOG.format(date=today) + text))
    if not block:
        print("harvest: no LAB_LOG draft (nothing worth logging)", file=sys.stderr)
        return 0
    draft = os.environ.get("HARVEST_LABLOG_DRAFT", _default_lablog_draft())
    os.makedirs(os.path.dirname(draft), exist_ok=True)
    with open(draft, "a", encoding="utf-8") as fh:
        fh.write(f"<!-- staged {today} by harvest --lab-log; review, then move into LAB_LOG.md -->\n{block}\n\n")
    print(f"harvest: staged a LAB_LOG draft -> {draft} (review; not auto-committed)", file=sys.stderr)
    return 0


def _harvest_payload(payload):
    """The core no-arg harvest, factored out so --stop-trigger can reuse it on a payload dict
    (the no-arg main() reads the same payload from stdin)."""
    tp = payload.get("transcript_path")
    if not tp:
        return 0
    text = transcript_text(tp, int(os.environ.get("HARVEST_MAXCHARS", "12000")))
    if not text.strip():
        return 0

    raw = run_extractor(PROMPT_HEAD + text)
    candidates = extract_json_array(raw)
    if not candidates:
        return 0

    ledger = os.environ.get("HARVEST_LEDGER", _default_ledger())
    gl_env = os.environ.get("HARVEST_GLOSSARIES")
    glossaries = gl_env.split(":") if gl_env else glob.glob(_default_glossary_glob())
    fuzzy = _fuzzy_threshold()
    today = datetime.date.today().isoformat()

    # Dedup-on-append race (ID-202): harvest.sh fires on PreCompact, and a single
    # long session (or several parallel subagent sessions sharing one repo) can
    # trigger concurrent harvest.py processes against the SAME ledger. Reading
    # existing_slugs() and appending were two separate unlocked steps, so two
    # processes could both read the ledger before either had appended, both decide
    # the same slug was new, and both append it -- observed as up to 6x duplicates.
    # Fix: hold a blocking exclusive flock across read-known + append, so concurrent
    # invocations serialize instead of racing (mirrors _run_harvest_locked's fcntl
    # pattern, but blocking -- a harvest here has real work to do, unlike the
    # stop-trigger single-flight which just skips).
    os.makedirs(os.path.dirname(ledger), exist_ok=True)
    fresh = []
    with open(_ledger_lock_path(ledger), "a") as lockf:
        fcntl.flock(lockf, fcntl.LOCK_EX)
        try:
            known = existing_slugs(ledger, glossaries)
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

    print(f"harvest: staged {len(fresh)} new (of {len(candidates)} extracted) -> {ledger}", file=sys.stderr)
    return 0


# ---- --stop-trigger: per-N-turns memory-nudge cadence ----

def _truthy(v):
    return str(v or "").strip().lower() in ("1", "true", "yes", "on")


def _safe_session(sid):
    """Filesystem-safe per-session counter key (session_id is a UUID, but never trust it)."""
    sid = re.sub(r"[^A-Za-z0-9._-]", "_", str(sid or ""))
    return sid[:128] or "nosession"


def _state_dir():
    return os.environ.get("HARVEST_STATE_DIR", DEFAULT_STATE_DIR)


def _debounced(mode_key):
    """True if the `mode_key` harvest ran within HARVEST_MIN_INTERVAL seconds (default 3600 = 1h)
    and should be SKIPPED this fire. Per-mode stamp file under the state dir; a burst of sessions
    ending together collapses to one harvest per mode per interval. Set HARVEST_MIN_INTERVAL=0 to
    disable. Bookkeeping errors never block a harvest (returns False on any OSError)."""
    try:
        interval = int(os.environ.get("HARVEST_MIN_INTERVAL", "3600"))
    except ValueError:
        interval = 3600
    if interval <= 0:
        return False
    try:
        d = _state_dir()
        os.makedirs(d, exist_ok=True)
        stamp = os.path.join(d, "last-" + mode_key)
        now = time.time()
        if os.path.exists(stamp) and now - os.path.getmtime(stamp) < interval:
            return True
        with open(stamp, "w") as fh:
            fh.write(str(int(now)))
        return False
    except OSError:
        return False


def _bump_counter(cfile):
    """Read-increment-write the per-session turn counter atomically (temp + os.replace)."""
    try:
        cur = int((open(cfile).read().strip() or "0"))
    except (OSError, ValueError):
        cur = 0
    cur += 1
    try:
        tmp = cfile + ".tmp"
        with open(tmp, "w") as fh:
            fh.write(str(cur))
        os.replace(tmp, cfile)
    except OSError:
        pass
    return cur


def _run_harvest_locked(payload, lockpath):
    """Single-flight: take a non-blocking exclusive lock; if held, skip (a harvest is already in
    flight). Otherwise run the harvest while holding the lock for its whole lifetime."""
    try:
        lf = open(lockpath, "w")
    except OSError:
        return
    try:
        fcntl.flock(lf, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("harvest: stop-trigger skip (harvest already in flight)", file=sys.stderr)
        lf.close()
        return
    try:
        _harvest_payload(payload)
    finally:
        fcntl.flock(lf, fcntl.LOCK_UN)
        lf.close()


def _spawn_detached(mode_flag, payload, sdir):
    """Write payload to a state-dir file and spawn a detached child (start_new_session)
    that re-invokes this script as `mode_flag <payload-file>`, then return immediately.
    The child is reparented into its own process session, so it outlives both the
    invoking hook's own timeout AND (for SessionEnd) the CLI process's exit teardown --
    a `claude -p` extractor call can take up to its own 120s budget, well past any
    SessionEnd/PreCompact/Stop hook timeout, and SessionEnd fires while the process is
    already tearing down. Returns True if the spawn succeeded.

    If Popen itself fails AFTER the payload file was already written, there is no child
    left to clean it up -- remove it here so a spawn failure never leaks a payload file
    (the file is otherwise reaped only by the detached child's own reader, e.g.
    cmd_lab_log_run/cmd_harvest_run/cmd_stop_harvest)."""
    pf = None
    try:
        os.makedirs(sdir, exist_ok=True)
        pf = os.path.join(sdir, f"payload-{mode_flag.lstrip('-')}-{os.getpid()}.json")
        with open(pf, "w") as fh:
            json.dump(payload, fh)
        subprocess.Popen(
            [sys.executable, os.path.abspath(__file__), mode_flag, pf],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,  # detach from the hook's process group; survives the turn
        )
    except OSError:
        if pf:
            try:
                os.remove(pf)
            except OSError:
                pass
        return False
    return True


def _fire_harvest(payload, sdir):
    """Run the harvest off the turn's critical path. Default: spawn a detached child
    and return immediately, so a slow harvest never blocks the turn.
    HARVEST_STOP_SYNC=1 runs it inline (test seam, deterministic)."""
    if _truthy(os.environ.get("HARVEST_STOP_SYNC")):
        _run_harvest_locked(payload, os.path.join(sdir, "harvest.lock"))
        return
    if _spawn_detached("--stop-harvest", payload, sdir):
        print("harvest: stop-trigger fire (detached harvest)", file=sys.stderr)


def cmd_stop_trigger():
    """Stop hook: bump the per-session turn counter; every Nth turn, fire the existing harvest.
    Opt-in (default OFF), async, single-flight, always exit 0."""
    if not _truthy(os.environ.get("HARVEST_STOP_TRIGGER")):
        return 0  # opt-in default off -> zero behavior change
    payload = read_payload()
    try:
        n = max(1, int(os.environ.get("HARVEST_STOP_N", "10")))
    except ValueError:
        n = 10
    sdir = _state_dir()
    try:
        os.makedirs(os.path.join(sdir, "turns"), exist_ok=True)
    except OSError:
        return 0
    count = _bump_counter(os.path.join(sdir, "turns", _safe_session(payload.get("session_id"))))
    if count % n != 0:
        print(f"harvest: stop-trigger skip (turn {count}, fires every {n})", file=sys.stderr)
        return 0
    if not payload.get("transcript_path"):
        return 0
    _fire_harvest(payload, sdir)
    return 0


def _read_and_run(pf, work):
    """Shared shape for every detached child's entry point: read the payload handoff
    file, call work(payload), and ALWAYS remove pf afterward -- whether the read, the
    work, or nothing at all failed. One `finally` wrapping both steps (not just the
    second) so a corrupt/truncated payload file doesn't leak forever; the prior
    per-caller versions only cleaned up if the read succeeded."""
    try:
        try:
            payload = json.load(open(pf))
        except (OSError, ValueError):
            return 0
        work(payload)
    finally:
        try:
            os.remove(pf)
        except OSError:
            pass
    return 0


def cmd_stop_harvest(pf):
    """Internal: the detached child spawned by --stop-trigger. Runs the
    single-flight-guarded harvest against the handed-off payload."""
    return _read_and_run(pf, lambda payload: _run_harvest_locked(payload, os.path.join(_state_dir(), "harvest.lock")))


def cmd_lab_log_run(pf):
    """Internal: the detached child spawned for --lab-log. Runs cmd_lab_log against the
    handed-off payload."""
    return _read_and_run(pf, cmd_lab_log)


def cmd_harvest_run(pf):
    """Internal: the detached child spawned for the plain PreCompact/SessionEnd harvest.
    Mirrors cmd_stop_harvest (same lock) so a --stop-trigger fire and a
    PreCompact/SessionEnd fire against the same ledger never race each other either."""
    return _read_and_run(pf, lambda payload: _run_harvest_locked(payload, os.path.join(_state_dir(), "harvest.lock")))


def _dispatch(argv):
    if "--cleanup" in argv:
        return cmd_cleanup()
    if "--lab-log-run" in argv:
        i = argv.index("--lab-log-run")
        return cmd_lab_log_run(argv[i + 1] if i + 1 < len(argv) else "")
    if "--lab-log" in argv:
        if _debounced("lablog"):
            return 0
        payload = read_payload()
        if not payload.get("transcript_path"):
            return 0
        if _truthy(os.environ.get("HARVEST_SYNC")):
            return cmd_lab_log(payload)
        if _spawn_detached("--lab-log-run", payload, _state_dir()):
            print("harvest: --lab-log fired detached (draft lands after this hook returns)", file=sys.stderr)
        return 0
    if "--stop-trigger" in argv:
        return cmd_stop_trigger()
    if "--stop-harvest" in argv:
        i = argv.index("--stop-harvest")
        return cmd_stop_harvest(argv[i + 1] if i + 1 < len(argv) else "")
    if "--harvest-run" in argv:
        i = argv.index("--harvest-run")
        return cmd_harvest_run(argv[i + 1] if i + 1 < len(argv) else "")
    if _debounced("ledger"):
        return 0
    payload = read_payload()
    if not payload.get("transcript_path"):
        return 0
    if _truthy(os.environ.get("HARVEST_SYNC")):
        return _harvest_payload(payload)
    if _spawn_detached("--harvest-run", payload, _state_dir()):
        print("harvest: fired detached (ledger lands after this hook returns)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(_dispatch(sys.argv[1:]))
