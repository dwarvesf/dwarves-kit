#!/usr/bin/env python3
"""staging-format.py -- the ONE definition of the `_meta/backlog-staging.md` block grammar
(shared by `reflect drain` and `reflect propose`; whichever of the two sub-goals
merged first landed it, since `staging-format*`
did not exist yet on this branch's history).

Five verbs on the CLI: `parse <file>` (read blocks back as JSON), `render` (render one
candidate from stdin JSON), `stage` (dedupe + render + append in a single process, used
directly and by `wrap stage`), and `append <file> [--header TEXT]` (append the blocks read
on stdin; the path the bash hooks use, since they render in jq and cannot import this module).

One lock domain for the whole file. `staging_lock(path)` is a blocking flock on a lock file
in the tmpdir, keyed by the buffer's realpath like the board lock. `append_blocks` and `rewrite`
take it, and so do `reflect drain` and `board promote`. Every writer of the buffer goes through
those two functions: a raw `>>` or an open-for-write elsewhere is the lost-append bug this exists
to prevent. Lock order where two are held: the board lock (sync_core.board_lock) first, then
this one.

A staging file is a sequence of `## [<state>] <title>` blocks, each followed by `- Field:
value` lines (Intent, Approach, Tags, Home, Source, ...). `lib/board/bin/add-backlog` (the
promoter) reads blocks through `parse_blocks` here; the only second copy of the grammar is the
jq twin below.

Filename is deliberately hyphenated (matches the `staging-format*` file-fence token both
sub-goal files use); a plain `import staging_format` cannot see it, so importers load it via
`importlib.util.spec_from_file_location` (see `drain.py`).

The bash hooks (intake-sweep, backlog-stage) cannot import this module, so
lib/reflect/staging-format.jq carries a twin of norm, render_block, and the existing_keys
parsers. tests/test-staging-format-jq.sh pins the twin to this file on goldens generated from
it; change the grammar here, regenerate with tests/fixtures/staging-format-jq/gen-expected.sh,
and the test names what the twin must follow.

Stdlib only.
"""
import contextlib
import fcntl
import hashlib
import json
import os
import sys
import re
import tempfile
from datetime import date, datetime

# A block starts at a line beginning with '## [' -- the one boundary definition every reader
# (drain, propose, and eventually add-backlog) must agree on.
_BLOCK_START_RE = re.compile(r"(?m)^##\s*\[")
_HEAD_RE = re.compile(r"##\s*\[([^\]]+)\]\s*(.+)")
_FIELD_RE = re.compile(r"(?m)^-\s*([A-Za-z]+):\s*(.+)$")
_SOURCE_DATE_RE = re.compile(r"(\d{4}-\d{2}-\d{2})")


def parse_blocks(text):
    """Return an ordered list of dicts (file order preserved, never re-sorted here):
    {raw, start, end, state, title, fields}. `state` is the bracket token
    ('staged' | 'expired' | 'rejected' | 'promoted ID-NNN' | ...), `fields` is a dict of the
    block's `- Field: value` lines (last write wins per key, same as `dict(re.findall(...))`)."""
    blocks = []
    idxs = [m.start() for m in _BLOCK_START_RE.finditer(text)]
    for i, s in enumerate(idxs):
        e = idxs[i + 1] if i + 1 < len(idxs) else len(text)
        raw = text[s:e]
        head = _HEAD_RE.match(raw)
        if not head:
            continue
        fields = dict(_FIELD_RE.findall(raw))
        blocks.append(
            {
                "raw": raw,
                "start": s,
                "end": e,
                "state": head.group(1).strip(),
                "title": head.group(2).strip(),
                "fields": fields,
            }
        )
    return blocks


def source_date(fields):
    """Best-effort `date.date` parsed out of the `Source` field (e.g. 'session 2026-06-29').
    None if missing/unparseable -- callers must treat that as "age unknown", never 0."""
    src = fields.get("Source", "")
    m = _SOURCE_DATE_RE.search(src)
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1), "%Y-%m-%d").date()
    except ValueError:
        return None


def age_days(fields, today=None):
    """Whole days between `today` (default: real today) and the block's Source date.
    None if the date is missing/unparseable."""
    d = source_date(fields)
    if d is None:
        return None
    today = today or date.today()
    return (today - d).days

# --- write side (from `reflect propose`; unified here:
# ONE staging-block definition, shared by drain, propose, and the `stage` verb below) ---

# Unicode word runs (letters and digits in any script, underscore excluded): an ASCII-only
# class turned every CJK title into an empty key that skipped dedupe (battery probe).
_NORM_RE = re.compile(r"[^\W_]+")

def norm(title):
    """Normalize a title into a dedup key: casefolded word runs in any script."""
    return " ".join(_NORM_RE.findall(str(title).casefold()))

def render_block(candidate):
    """Render one candidate dict as a `## [staged]` block string (trailing blank line).

    Byte-identical to hooks/backlog-stage.sh (through staging-format.jq) / anomalies.py:render_block.
    Required: title. Optional: intent, approach, u, f, home, source. Returns None if the
    title is empty (a titleless block is unparseable and never emitted).
    """
    # Collapse ALL whitespace (newlines included) in every rendered field. A block is a
    # line-oriented grammar: an embedded "\n\n## [staged] ..." in a field forges a SECOND
    # proposal that parse_blocks() reads as real. The fields now carry LLM-authored text
    # derived from transcripts (session-audit), i.e. attacker-influenceable content, and
    # More of it routes through this one renderer over time. Sanitize at the ONE
    # place every writer shares (review finding).
    def _flat(v, fallback=""):
        s = re.sub(r"\s+", " ", str(v)).strip()
        return s or fallback

    title = _flat(candidate.get("title", ""))
    if not title:
        return None
    intent = _flat(candidate.get("intent", ""), "(no intent extracted)")
    approach = _flat(candidate.get("approach", ""), "(no approach extracted)")
    u = candidate.get("u") if candidate.get("u") in ("hi", "mid", "lo") else "lo"
    f = candidate.get("f") if candidate.get("f") in ("hi", "mid", "lo") else "mid"
    home = _flat(candidate.get("home", ""))
    # Source carries the origin + date; propose folds the lens/figure/rids citation onto
    # this ONE line so it rides into the board Notes column on promote.
    source = _flat(candidate.get("source", ""), "unknown")
    home_line = f"- Home: {home}\n" if home else ""
    return (
        f"## [staged] {title}\n"
        f"- Intent: {intent}\n"
        f"- Approach: {approach}\n"
        f"- Tags: #u-{u} #f-{f}\n"
        f"{home_line}"
        f"- Source: {source}\n\n"
    )

_BOARD_ROW_RE = re.compile(r"\s*\|\s*[A-Z]+-\d+\s*\|\s*([^|]+)\|")
# `- [ ] title` / `- [x] title`. A CHECKED item counts for dedup too: it is finished work,
# and re-proposing finished work is the second-largest false-positive class.
_CHECKBOX_RE = re.compile(r"(?m)^\s*[-*]\s*\[[ xX]\]\s*(.+?)\s*$")
# A cockpit registry line: `<name>  <path-to-BACKLOG.md>`, `#` comments, `~` expands.
_REGISTRY_RE = re.compile(r"^([^\s#]+)\s+(\S.*)$")


def _registry_boards(path):
    """The board files a cockpit registry points at. Unreadable lines contribute nothing."""
    out = []
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                m = _REGISTRY_RE.match(line)
                if m:
                    out.append(os.path.expanduser(m.group(2).strip()))
    except OSError:
        return []
    return out


def existing_keys(*sources):
    """Build the dedup key SET from any number of (kind, path) sources.

    kind == "staging" -> parse `## [<state>] <title>` blocks (ALL states: staged,
    rejected, expired, promoted -- a rejected/expired proposal must never be re-proposed).
    kind == "board"   -> parse board rows `| ID-NNN | Item | ... |` (the Item cell).
    kind == "cockpit" -> a `name  path/to/BACKLOG.md` registry; every board it lists.
    kind == "roadmap" -> a megagoal ROADMAP/TODO: its checkbox items and any board rows.
    A missing file contributes nothing. Keys are norm()'d titles; membership is EXACT
    (the anchored dedup form).

    The last two kinds close the anchor gap a prior measurement found: 28 of 69 staged candidates
    duplicated work already tracked on a cross-repo cockpit board or a megagoal TODO,
    surfaces this set never read, so that work re-entered staging as new.
    """
    keys = set()
    for kind, path in sources:
        if not path or not os.path.isfile(path):
            continue
        if kind == "cockpit":
            for board in _registry_boards(path):
                keys |= existing_keys(("board", board))
            continue
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        if kind == "staging":
            for b in parse_blocks(text):
                if b["title"]:
                    keys.add(norm(b["title"]))
        elif kind == "board":
            for line in text.splitlines():
                m = _BOARD_ROW_RE.match(line)
                if m:
                    keys.add(norm(m.group(1)))
        elif kind == "roadmap":
            for m in _CHECKBOX_RE.finditer(text):
                # `change -- owner: x -- deadline: y`: the change alone is the title a
                # proposal would carry, so the trailing metadata must not join the key.
                keys.add(norm(re.split(r"\s+--\s+", m.group(1))[0]))
            for line in text.splitlines():
                m = _BOARD_ROW_RE.match(line)
                if m:
                    keys.add(norm(m.group(1)))
    return keys


# --- the one locked write path ------------------------------------------------------------

def staging_lock_path(staging):
    """The one lock address every staging writer shares: tmpdir + md5 of the buffer's realpath,
    the same scheme as sync_core.board_lock_path. Outside the repo on purpose: a lock file
    beside a gitignored buffer still shows up as an untracked file in the consumer's checkout."""
    return os.path.join(
        tempfile.gettempdir(),
        "staging-%s.lock" % hashlib.md5(os.path.realpath(staging).encode()).hexdigest())


@contextlib.contextmanager
def staging_lock(staging, required=False):
    """Blocking exclusive flock on `staging_lock_path(staging)`: the one lock every staging
    writer shares (append, drain's expiry, promote's relabel). bash has no flock on macOS, so
    the bash hooks reach this through the `append` CLI verb rather than locking themselves.

    A lock file that cannot be opened (tmpdir unwritable) degrades to an unlocked write with a
    warning when `required` is False: for an append, losing the caller's block is worse than the
    rare race. A read-modify-write (`rewrite`) passes required=True and fails instead, since an
    unlocked whole-file rewrite is what drops concurrent appends. Writers must agree on TMPDIR:
    two processes with different values hold different lock files and exclude nothing."""
    parent = os.path.dirname(staging)
    if parent:
        os.makedirs(parent, exist_ok=True)
    try:
        fd = os.open(staging_lock_path(staging), os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    except OSError as e:
        if required:
            raise
        sys.stderr.write(f"staging-format.py: no lock ({e}); writing unlocked\n")
        yield
        return
    with os.fdopen(fd, "r+") as lockf:
        fcntl.flock(lockf, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lockf, fcntl.LOCK_UN)


def _append_locked(staging, data, header, nofollow):
    flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT
    if nofollow:
        # closes the window between a caller's symlink check and this append: a symlink swapped
        # in after that check raises ELOOP here instead of redirecting the write
        flags |= os.O_NOFOLLOW
    fd = os.open(staging, flags, 0o644)
    with os.fdopen(fd, "ab") as fh:
        if header and fh.tell() == 0:
            fh.write(header)
        fh.write(data)


def append_blocks(staging, blocks, header="", nofollow=False):
    """Append already-rendered block text to the staging buffer, under the staging lock.
    `header` is written once, only when the file is new or empty (decided inside the lock, so
    two first writers cannot both write it). `blocks` and `header` may be str or bytes."""
    enc = lambda v: v if isinstance(v, bytes) else str(v).encode("utf-8", "surrogateescape")
    data = enc("".join(blocks) if isinstance(blocks, (list, tuple)) else blocks)
    with staging_lock(staging):
        _append_locked(staging, data, enc(header) if header else b"", nofollow)


def rewrite(staging, fn):
    """Read-modify-write the staging buffer under the staging lock. `fn(text)` returns
    `(new_text, result)`; the file is replaced atomically only when the text changed, so a
    reader outside the lock never sees a half-written buffer. Returns `result`. The text is
    read INSIDE the hold: a block appended since the caller last looked is in `text`."""
    with staging_lock(staging, required=True):
        try:
            with open(staging, encoding="utf-8") as fh:
                text = fh.read()
        except FileNotFoundError:
            text = ""
        new_text, result = fn(text)
        if new_text != text:
            target = os.path.realpath(staging)
            try:
                mode = os.stat(target).st_mode & 0o7777  # keep the buffer's mode (it may be 0600)
            except FileNotFoundError:
                mode = 0o644
            fd, tmp = tempfile.mkstemp(dir=os.path.dirname(target) or ".", prefix=".staging.")
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(new_text)
            os.chmod(tmp, mode)
            os.replace(tmp, target)
        return result


def cmd_stage():
    """`staging-format.py stage`: read one JSON object on stdin (title, intent, home,
    staging, backlog?) and either report a duplicate or append one block. See the
    `### Interfaces` `staging-format.py stage` paragraph. The dedupe
    check runs immediately before the append, in this same process -- there is no window
    between "is it staged" and "stage it" for another writer to land in."""
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.stderr.write(
            "usage: staging-format.py stage: expects one JSON object on stdin "
            "({title, intent, home, staging, backlog?})\n"
        )
        return 64
    # Valid JSON but not an object (a list, string, number, or null) is the same usage
    # error, not an AttributeError from `.get()` on the wrong type a few lines down.
    if not isinstance(data, dict):
        sys.stderr.write(
            "usage: staging-format.py stage: expects one JSON object on stdin "
            "({title, intent, home, staging, backlog?})\n"
        )
        return 64

    title = data.get("title", "")
    staging = data.get("staging", "")
    key = norm(title)

    block = render_block({
        "title": title,
        "intent": data.get("intent", ""),
        "home": data.get("home", ""),
        "u": "lo",
        "f": "mid",
        "source": f"session {date.today().isoformat()}",
    })
    if block is None:
        sys.stderr.write("usage: staging-format.py stage: title is required\n")
        return 64

    header = "# Backlog staging\n\n"
    try:
        # dedupe and append share one lock hold: no window between "is it staged" and
        # "stage it" for another writer to land in
        with staging_lock(staging):
            if key and key in existing_keys(("staging", staging), ("board", data.get("backlog"))):
                print(f"stage: already staged: {title}")
                return 0
            _append_locked(staging, block.encode("utf-8"), header.encode("utf-8"), True)
    except OSError as e:
        print(f"FAILED: {e}")
        return 2

    print(block.splitlines()[0])
    return 0


def cmd_append(argv):
    """`staging-format.py append <staging> [--header TEXT]`: append the rendered blocks read on
    stdin, under the staging lock. The bash hooks render in jq and write through this."""
    args = list(argv)
    header = ""
    if "--header" in args:
        i = args.index("--header")
        if i + 1 >= len(args):
            sys.stderr.write("usage: staging-format.py append <staging> [--header TEXT]\n")
            return 64
        header = args[i + 1]
        del args[i:i + 2]
    if len(args) != 1:
        sys.stderr.write("usage: staging-format.py append <staging> [--header TEXT]\n")
        return 64
    data = sys.stdin.buffer.read()
    if not data:
        return 0
    try:
        data.decode("utf-8")
    except UnicodeDecodeError:
        # one invalid byte would make every later strict-UTF-8 reader (promote, drain) crash
        sys.stderr.write("staging-format.py append: stdin is not valid UTF-8; nothing written\n")
        return 65
    try:
        append_blocks(args[0], data, header)
    except OSError as e:
        sys.stderr.write(f"staging-format.py append: {e}\n")
        return 2
    return 0


def _main(argv):
    if len(argv) >= 2 and argv[1] == "parse":
        with open(argv[2], encoding="utf-8") as fh:
            print(json.dumps(parse_blocks(fh.read()), ensure_ascii=False, indent=2))
        return 0
    if len(argv) >= 2 and argv[1] == "render":
        block = render_block(json.load(sys.stdin))
        if block is None:
            return 1
        sys.stdout.write(block)
        return 0
    if len(argv) >= 2 and argv[1] == "stage":
        return cmd_stage()
    if len(argv) >= 2 and argv[1] == "append":
        return cmd_append(argv[2:])
    sys.stderr.write("usage: staging_format.py {parse <file>|render <stdin-json>|stage|append <file>}\n")
    return 64


if __name__ == "__main__":
    sys.exit(_main(sys.argv))
