"""The memory-verify sweep (SPEC-136): walks every memory STORE (repo `.claude/memory/`,
built-in Claude Code auto-memory `~/.claude/projects/*/memory/`), conservatively extracts
PATH references out of each note (note scanning), tests them against the LIVE environment,
and flags `MEMORY.md` index entries with no backing file (index scanning, a separate,
deliberately wider rule -- see `_extract_index_refs`).

**NEVER WRITES.** Every function here opens a memory file in read-only mode
(`Path.read_text()`) only. There is no write/append/delete path anywhere in this module --
Han's absolute NEVER-delete rule applies to this store more than any other (his own
accumulated operating knowledge). The never-delete negative control (test suite) asserts this
with a before/after shasum over a fixture store.

**Conservative extraction, on purpose (note scanning).** A false dead-ref costs trust, so
`extract_refs` restricts itself to inline code spans (`` `...` ``) and, within each span,
only the FIRST token, classified per `_classify_and_test`'s rule table. Command-testing
(`shutil.which()`) was in an earlier revision of this module and was REMOVED after the first
real `ledger memory-sweep` run against this repo's actual stores: bare words in backticks are
routinely ordinary prose emphasis (`` `README.md` ``, `` `main` ``) or shell BUILTINS/language
keywords `which()` can never find (`trap`, `export`, `const`), producing overwhelming false
dead-refs even after restricting to multi-token spans. v1 tests PATHS ONLY (home `~/...` and
absolute paths under a recognized real filesystem root); see `_classify_and_test`'s docstring
for the full real-corpus-evidence rationale (SPEC-136 DEC-008/DEC-009).

Two consumers read `scan()`'s output: `adapters.read_memories()` (the compact `memories` lens
row) and `cli.memory_sweep()` (the rich human-facing paydown report). Neither re-scans; both
call this module's `scan()` once. `anomalies._detect_memory_hygiene()` reads neither -- it
queries the already-materialized `memories` table, matching every other detector's
one-data-path contract.
"""

from __future__ import annotations

import datetime as _dt
import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from . import config

# ---- reference extraction -------------------------------------------------------------------

# Fenced ```...``` blocks are stripped before scanning (this repo's memory notes use single-
# backtick inline spans for paths/commands, never fenced blocks for them -- a defensive
# simplification, not a claim that fenced content is scanned some other way).
_FENCE_RE = re.compile(r"```.*?```", re.DOTALL)
_INLINE_CODE_RE = re.compile(r"`([^`\n]+)`")

# A template placeholder or glob/brace-expansion shape (e.g. `<name>`, `*.ts`,
# `{discord,telegram}`) -- never a literal path, whichever branch it would otherwise match.
_PLACEHOLDER_CHARS = "<>*{}"

# Recognized real filesystem root prefixes. An absolute-looking token (`token.startswith("/")`)
# is tested ONLY if it starts with one of these; real-corpus evidence (the first `ledger
# memory-sweep` run) showed the dominant false-positive source among leading-`/` tokens was
# NOT filesystem paths at all: Claude Code slash-commands (`/goal`, `/kit:spec`, `/edge-up`)
# and REST API path fragments (`/v1/chat/completions`, `/BankTransactions`) are syntactically
# identical to a real absolute path but are not one. Narrowing to a known-root allowlist is
# the same "when ambiguous, don't guess" discipline `_classify_and_test` already applies to
# builtin-store relative paths and (formerly) bare-word commands.
_REAL_PATH_PREFIXES = (
    "/Users/", "/Library/", "/Applications/", "/System/", "/private/", "/var/",
    "/etc/", "/usr/", "/opt/", "/bin/", "/sbin/", "/tmp/", "/dev/", "/mnt/", "/home/", "/root/",
)


@dataclass
class MemoryRef:
    """One conservatively-extracted candidate reference out of a memory unit's body (or, for
    an index unit, one bullet line). `kind` is `"path"` or `"index-link"`; `token` is the raw
    extracted string (or a fixed marker for an orphan index bullet); `live` is whether this
    sweep could confirm it exists on the CURRENT host."""

    kind: str
    token: str
    live: bool


@dataclass
class MemoryUnit:
    """One memory FILE: either a note (`kind="note"`) or its store's own `MEMORY.md` index
    (`kind="index"`). `dead_ref_count` is derived, never stored twice."""

    store: str
    slug: str
    kind: str
    written: str
    refs: list[MemoryRef] = field(default_factory=list)

    @property
    def dead_ref_count(self) -> int:
        return sum(1 for r in self.refs if not r.live)


def _classify_and_test(token: str) -> tuple[str, bool] | None:
    """Classify ONE head token from an inline code span and test it against the live
    environment. Returns `(kind, live)` or `None` when the token is deliberately not a
    verifiable reference. v1 tests PATHS ONLY (home `~/...`, or an absolute path under a
    recognized real filesystem root) -- see the module docstring for the real-corpus evidence
    that narrowed this from the original paths/flags/commands design (SPEC-136 DEC-008,
    DEC-009):

    - A flag (leading `-`, e.g. `--dry-run`): never tested (flag validity needs invoking
      `--help` against a specific command, too fragile/risky for a hygiene sweep).
    - A URL or `op://...` credential reference (contains `://`): never a local reference.
    - A template placeholder or glob/brace-expansion shape (`<name>`, `*.ts`,
      `{discord,telegram}`): never a literal path, whatever else it looks like.
    - `~<username>`: tested via `Path.expanduser().exists()`. A username that does not resolve
      on THIS host (e.g. a note written about a different machine's account, confirmed real on
      the live corpus: `` `~server/...` ``) raises `RuntimeError`, not `OSError`/`ValueError` --
      a third exception shape, caught here rather than crashing the whole sweep.
    - An absolute path (leading `/`) under a recognized real filesystem root
      (`_REAL_PATH_PREFIXES`): tested via `Path.exists()`. Anything else starting with `/`
      (a Claude Code slash-command, a REST API path fragment) is left untested -- the dominant
      false-positive source in the real-corpus run, per the module docstring.
    - A bare word or a relative path (contains `/` but no recognized root, or no `/` at all):
      NOT tested in v1. A relative path cannot be reliably attributed to the note's OWN store
      repo (real-corpus evidence: even repo-store notes routinely reference OTHER projects'
      source trees), and command-testing was removed entirely (see module docstring)."""
    if any(c in token for c in _PLACEHOLDER_CHARS):
        return None
    if token.startswith("-"):
        return None
    if "://" in token:
        return None
    if token.startswith("~"):
        try:
            return ("path", Path(token).expanduser().exists())
        except RuntimeError:
            return ("path", False)
        except OSError:
            # exists() can RAISE instead of returning False when a parent dir is
            # unreadable on this host (e.g. a note quoting /var/root/...): that is
            # "untestable here", not "dead", so skip rather than report a false
            # dead-ref or crash the sweep.
            return None
    if token.startswith("/"):
        if not token.startswith(_REAL_PATH_PREFIXES):
            return None
        try:
            return ("path", Path(token).exists())
        except OSError:
            return None
    return None


def extract_refs(text: str) -> list[MemoryRef]:
    """Conservative extraction: scan ONLY inline code spans (fenced blocks stripped first),
    and within each span classify + test ONLY the first whitespace-delimited token. One
    candidate per span, never a general prose scan -- the whole conservative-extraction rule
    (a false dead-ref costs trust more than a missed one)."""
    stripped = _FENCE_RE.sub(" ", text)
    refs: list[MemoryRef] = []
    for span in _INLINE_CODE_RE.findall(stripped):
        tokens = span.strip().split()
        if not tokens:
            continue
        classified = _classify_and_test(tokens[0])
        if classified is not None:
            kind, live = classified
            refs.append(MemoryRef(kind=kind, token=tokens[0], live=live))
    return refs


# ---- MEMORY.md index parsing ------------------------------------------------------------------

_INDEX_LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def _extract_index_refs(text: str, memory_dir: Path) -> list[MemoryRef]:
    """One `MemoryRef` per bullet line (`- ...`) in a MEMORY.md that is a LINK INDEX. A
    `[title](slug.md)` link resolves against the SAME directory the MEMORY.md lives in
    (unambiguous, no repo-root guessing needed). A bullet with NO link at all, when the file
    is a link index, is flagged dead (a "(no linked file)" orphan/tombstone, e.g. Han's own
    "MIGRATED to repo memory: ..." lines) -- an index entry claiming a memory exists with
    nothing backing it is exactly the signal this sweep exists to surface (SPEC-136 DEC-006);
    the sweep PROPOSES, a human confirms or dismisses.

    IS-IT-AN-INDEX gate (SPEC-136 DEC-010, a real-corpus precision fix): a MEMORY.md with ZERO
    markdown-link bullets is NOT a broken index -- it is a free-prose scratchpad that merely
    happens to be named MEMORY.md (confirmed real: `claude-guardrails`'s MEMORY.md is 39 prose
    bullets, none a link). Flagging every one of its bullets as a dead orphan is exactly the
    "a false dead-ref costs trust" noise this sweep must avoid, so a file with no link bullets
    at all contributes ZERO index refs. Only once a file proves it IS a link index (>= 1 real
    `[..](..)` bullet) does a sibling no-link bullet read as a genuine orphan."""
    parsed: list[tuple[str, str | None]] = []  # (line, link-target or None)
    has_any_link = False
    for line in text.splitlines():
        s = line.strip()
        if not s.startswith("- "):
            continue
        m = _INDEX_LINK_RE.search(s)
        if m is None:
            parsed.append((s, None))
        else:
            has_any_link = True
            parsed.append((s, m.group(2)))
    if not has_any_link:
        return []  # a prose scratchpad, not a link index -- flag nothing (DEC-010).
    refs: list[MemoryRef] = []
    for _s, target in parsed:
        if target is None:
            refs.append(MemoryRef(kind="index-link", token="(no linked file)", live=False))
            continue
        if target.startswith(("http://", "https://")):
            continue  # an external link, not a local memory file -- not a reference to test.
        refs.append(MemoryRef(kind="index-link", token=target,
                               live=(memory_dir / target).exists()))
    return refs


# ---- written (the staleness signal) -----------------------------------------------------------

_STALE_DAYS = 180


def _git_commit_ts(repo_dir: Path, path: Path) -> str | None:
    """The file's most recent commit timestamp, or `None` if the path is outside `repo_dir`,
    `repo_dir` is not a git repo, `git` fails, or there is no commit for it. Never raises."""
    try:
        rel = str(path.relative_to(repo_dir))
    except ValueError:
        return None
    if not (repo_dir / ".git").exists():
        return None
    try:
        out = subprocess.run(
            ["git", "-C", str(repo_dir), "log", "-1", "--format=%aI", "--", rel],
            capture_output=True, text=True, timeout=30,
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None
    return out or None


def _mtime_ts(path: Path) -> str:
    try:
        ts = path.stat().st_mtime
    except OSError:
        return ""
    return _dt.datetime.fromtimestamp(ts, tz=_dt.timezone.utc).isoformat()


def written_ts(path: Path, git_repo_dir: Path | None) -> str:
    """"written" = the most recent modification signal (SPEC-136 DEC-004: tracks "has anyone
    touched/reconfirmed this recently," not "how old is this note"). A git commit timestamp
    for the git-tracked repo store; `path.stat().st_mtime` fallback for the non-git builtin
    store (or when git yields nothing)."""
    if git_repo_dir is not None:
        got = _git_commit_ts(git_repo_dir, path)
        if got:
            return got
    return _mtime_ts(path)


def is_stale(written: str, now: _dt.datetime | None = None) -> bool:
    """QUERY-TIME predicate (never a stored column, matching `defect-correlation`'s fix()
    classification and `deviation-rate`'s UNDER-SPECCED/CLEAN/SUSPECT convention): more than
    `_STALE_DAYS` days between `written` and `now`. Returns False on anything unparsable,
    never raises."""
    if not written:
        return False
    try:
        ts = _dt.datetime.fromisoformat(written.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return False
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=_dt.timezone.utc)
    now = now or _dt.datetime.now(tz=_dt.timezone.utc)
    return (now - ts).days > _STALE_DAYS


# ---- scan: discover units across every store --------------------------------------------------

# A memory note is hand-authored prose (typically a few KB); a file past this size is almost
# certainly not one (a mis-placed binary, a symlink to a device/log file) -- skipped (empty
# text) rather than read in full, a `kit:code-reviewer` hardening suggestion on the finished
# diff (a LOW finding, no functional defect: this store is self-authored local content, not
# adversarial input, but the cap costs nothing and removes the unbounded-read risk outright).
_MAX_FILE_BYTES = 2_000_000


def _read_text(path: Path) -> str:
    """Read a memory file's text, tolerantly. A malformed file (unreadable, oversized, OR
    undecodable -- `OSError` and `UnicodeDecodeError` are DIFFERENT exception classes, the
    latter a `ValueError` subclass, a `/kit:spec-validate` finding on the draft) contributes
    empty text (zero refs), never crashes the whole scan -- the same "one bad file never drops
    a sibling" contract every other adapter in this tool already honors."""
    try:
        if path.stat().st_size > _MAX_FILE_BYTES:
            return ""
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return ""


def _scan_note(path: Path, store: str, git_repo: Path | None) -> MemoryUnit:
    refs = extract_refs(_read_text(path))
    return MemoryUnit(store=store, slug=path.stem, kind="note",
                       written=written_ts(path, git_repo), refs=refs)


def _scan_index(path: Path, store: str, git_repo: Path | None) -> MemoryUnit:
    refs = _extract_index_refs(_read_text(path), path.parent)
    return MemoryUnit(store=store, slug=path.stem, kind="index",
                       written=written_ts(path, git_repo), refs=refs)


def _discover_repo_store(repo_dir: Path) -> tuple[str, Path] | None:
    d = repo_dir / ".claude" / "memory"
    if not d.is_dir():
        return None
    return (f"repo:{repo_dir.name}", d)


def _discover_builtin_stores(projects_root: Path) -> list[tuple[str, Path]]:
    if not projects_root.is_dir():
        return []
    out = []
    for proj_dir in sorted(p for p in projects_root.iterdir() if p.is_dir()):
        mem_dir = proj_dir / "memory"
        if mem_dir.is_dir():
            out.append((f"builtin:{proj_dir.name}", mem_dir))
    return out


def scan(repo_dir: Path | None = None, projects_root: Path | None = None) -> list[MemoryUnit]:
    """Discover + scan every memory unit across the repo store and every builtin store.
    Skip-safe: a missing repo/projects root simply contributes zero units from that side,
    never raises (matches every other adapter's missing-source contract)."""
    repo_dir = repo_dir or config.memory_repo_dir()
    projects_root = projects_root or config.memory_projects_root()

    # (store label, memory dir, git repo root or None -- the repo store is git-tracked, the
    # builtin store is not; see written_ts). No base_dir for relative-path resolution: v1
    # tests only home/known-root-absolute paths, never a relative path (SPEC-136 DEC-009).
    stores: list[tuple[str, Path, Path | None]] = []
    repo_store = _discover_repo_store(repo_dir)
    if repo_store is not None:
        label, d = repo_store
        stores.append((label, d, repo_dir))
    for label, d in _discover_builtin_stores(projects_root):
        stores.append((label, d, None))

    units: list[MemoryUnit] = []
    for store, mem_dir, git_repo in stores:
        for f in sorted(mem_dir.glob("*.md")):
            if f.name == "MEMORY.md":
                units.append(_scan_index(f, store, git_repo))
            else:
                units.append(_scan_note(f, store, git_repo))
    units.sort(key=lambda u: (u.store, u.slug))
    return units
