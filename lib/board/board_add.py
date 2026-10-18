#!/usr/bin/env python3
"""board_add.py -- the writer for NEW board rows (`backlog.sh add`).

Every caller that files one row goes through `add_rows` / `add_rows_locked`: `board capture`,
`board promote`, `/kit:assign` freeform, `/kit:wayfind`'s umbrella row, and `web-drift`'s
consumer rows. (`board sync` intake mints a bulk batch in sync_core under the same lock.) The id is minted from a fresh read INSIDE the board lock (sync_core.board_lock:
the same address set/dedupe/capture/sync flock), so two sessions can never mint one id. The
row is written in the target table's OWN column count, read from its header, so a 6-column
board is not handed 4-cell rows.

  board_add.py add <board.md> <title> [--mid VALUE]... [--notes TEXT] [--status STATE]
                                       [--section HEADING]
      Prints the minted id. Put `--` before the title when it comes from untrusted text, so a
      leading dash cannot read as a flag. `--mid` fills the cells between Title and Status in order (a
      4-column board has one, a 6-column board has three); `--notes` is the first `--mid`.
      Cells left unfilled stay empty. More values than the table has middle cells is a
      usage error. `--section` targets the table under that exact heading line (created
      from the board's primary table header when absent; it must be a one-line `#`-heading
      with no pipe); without it the row lands at the top of the board's first `| ID |` table.
      `--status` must be one word; the BOARD_ADD_STATES env var (space-separated, set by
      backlog.sh) narrows it to the board's legal states.

Library use: `add_rows_locked(path, specs, section=None)` assumes the caller already holds
`board_lock(path)` (promote does, together with the staging lock); `add_rows` takes it.
flock is not re-entrant across file descriptors, so a caller holding the lock must use the
`_locked` form or it deadlocks against itself. Stdlib plus sync_core.
"""
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "sync"))
from sync_core import board_lock, detect_prefix, escape, history_max_id, parse_board  # noqa: E402

DEFAULT_HEADER = "| ID | Item | Notes & source | Status |"
DEFAULT_RULE = "|---|---|---|---|"
_UNESC_PIPE = re.compile(r"(?<!\\)\|")
_ID_HEADER = re.compile(r"^\s*\|\s*ID\s*\|")
_RULE = re.compile(r"^\s*\|[\s:|-]*-[\s:|-]*\|?\s*$")


def column_count(header_line):
    """Cells in a table header row: unescaped pipes minus one."""
    return len(_UNESC_PIPE.findall(header_line.rstrip("\n"))) - 1


def _primary_table(lines):
    """(header_idx, rule_idx) of the board's first `| ID |` table, else the first rule line
    with a header above it, else None."""
    for i, ln in enumerate(lines[:-1]):
        if _ID_HEADER.match(ln) and _RULE.match(lines[i + 1]):
            return i, i + 1
    for i, ln in enumerate(lines):
        if _RULE.match(ln) and i > 0 and lines[i - 1].lstrip().startswith("|"):
            return i - 1, i
    return None


def _section_table(lines, heading):
    """(header_idx, rule_idx) of the first table after the line equal to `heading`, else None."""
    for i, ln in enumerate(lines):
        text = ln.rstrip("\n").strip()
        # the heading as written, or with a suffix after it (`### Conversation intake (auto)`)
        if text != heading and not text.startswith(heading + " "):
            continue
        for j in range(i + 1, len(lines) - 1):
            if lines[j].startswith("#"):
                return None
            if lines[j].lstrip().startswith("|") and _RULE.match(lines[j + 1]):
                return j, j + 1
        return None
    return None


_HEADING_OK = re.compile(r"^#{1,6} [^|\n\r\x00-\x1f]+$")
_STATUS_OK = re.compile(r"^[A-Za-z][A-Za-z-]*$")


def _refuse(message):
    sys.stderr.write(f"board add: {message}\n")
    raise SystemExit(64)


def _check_section(section):
    if section is not None and not _HEADING_OK.match(section):
        _refuse(f"--section must be a one-line heading like '### Name' with no pipe: {section!r}")


def _check_status(status):
    if not _STATUS_OK.match(status):
        _refuse(f"status must be one word: {status!r}")
    legal = os.environ.get("BOARD_ADD_STATES", "").split()
    if legal and status not in legal:
        _refuse(f"unknown status '{status}' (states: {' '.join(legal)})")


def _id_width(text, prefix):
    """Zero-pad width for minted ids: the widest zero-padded id the board already carries,
    else 1 (bare numbers) when it has ids, else 3 on an empty board."""
    nums = re.findall(r"^\| " + re.escape(prefix) + r"-(\d+) \|", text, flags=re.M)
    if not nums:
        return 3
    padded = [len(n) for n in nums if len(n) > 1 and n.startswith("0")]
    return max(padded) if padded else 1


def _ensure_eol(lines):
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"


def _new_section(lines, heading, header_line):
    """Lines with a new `heading` + table (header copied from the board's primary table)
    placed before `## Recently closed` when present, else at the end."""
    rule = "|" + "|".join(["---"] * column_count(header_line)) + "|\n"
    block = [heading + "\n", "\n", header_line.rstrip("\n") + "\n", rule]
    for i, ln in enumerate(lines):
        if ln.startswith("## Recently closed"):
            lead = [] if i == 0 or not lines[i - 1].strip() else ["\n"]
            return lines[:i] + lead + block + ["\n"] + lines[i:]
    _ensure_eol(lines)
    return lines + ["\n"] + block


def _render_row(bid, title, mids, status, ncols):
    cells = [bid, escape(" ".join(title.split()))]
    cells += [escape(" ".join(str(m).split())) for m in mids]
    cells += [""] * (ncols - 3 - len(mids))
    cells.append(status)
    return "| " + " | ".join(cells) + " |\n"


def history_floor(path):
    """The highest id git history knows for this board (0 when git cannot answer). Slow (a
    fetch and a `git log -p`), so a caller holding a second lock computes it BEFORE taking
    that lock and passes it to add_rows_locked."""
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    return history_max_id(path, detect_prefix(text))


def add_rows_locked(path, specs, section=None, floor=None):
    """Mint and write one row per spec; the caller holds board_lock(path). A spec is a dict:
    title (required), mids (list of middle-cell values), status (default queued). Returns the
    minted ids in order. The board is written once, atomically (tmp + replace). `floor` is a
    precomputed `history_floor(path)`; omitted, it is computed here."""
    _check_section(section)
    for spec in specs:
        _check_status(spec.get("status", "queued"))
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    lines = text.splitlines(keepends=True)
    prefix = detect_prefix(text)
    width = _id_width(text, prefix)
    # One mint floor per batch: the highest id in play (parsed rows, row-shaped lines, git
    # history) plus one. Per-row recomputation would re-scan history for every row.
    row_nums = [int(r.rsplit("-", 1)[1]) for r in parse_board(text, prefix=prefix)]
    line_nums = [int(m) for m in re.findall(
        r"^\| " + re.escape(prefix) + r"-(\d+) \|", text, flags=re.M)]
    if floor is None:
        floor = history_max_id(path, prefix)
    nid = max(row_nums + line_nums + [floor], default=0) + 1

    primary = _primary_table(lines)
    if section:
        found = _section_table(lines, section)
        if found is None:
            header = lines[primary[0]] if primary else DEFAULT_HEADER + "\n"
            lines = _new_section(lines, section, header)
            found = _section_table(lines, section)
        table = found
    else:
        table = primary
    if table is None:
        raise SystemExit(f"no table header found in {path}")
    ncols = column_count(lines[table[0]])
    if ncols < 3:
        raise SystemExit(f"board table has {ncols} columns, need at least ID, Item, Status")

    ids, rows = [], []
    for spec in specs:
        mids = list(spec.get("mids") or [])
        if len(mids) > ncols - 3:
            raise SystemExit(
                f"{len(mids)} middle values for a {ncols}-column table "
                f"(it has {ncols - 3} middle cell(s))")
        bid = f"{prefix}-{nid:0{width}d}"
        nid += 1
        ids.append(bid)
        rows.append(_render_row(bid, spec["title"], mids, spec.get("status", "queued"), ncols))
    at = table[1] + 1
    lines[at:at] = reversed(rows)  # newest on top, as every earlier writer left them

    target = os.path.realpath(path)  # a symlinked board is written through, not replaced
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(target), prefix=f".{os.path.basename(target)}.")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write("".join(lines))
    os.chmod(tmp, os.stat(target).st_mode & 0o7777)
    os.replace(tmp, target)
    return ids


def add_rows(path, specs, section=None):
    with board_lock(path):
        return add_rows_locked(path, specs, section)


def _usage():
    sys.stderr.write(
        "usage: board_add.py add <board.md> <title> [--mid VALUE]... [--notes TEXT] "
        "[--status STATE] [--section HEADING]\n")
    return 64


def main(argv):
    if len(argv) < 3 or argv[0] != "add":
        return _usage()
    path, rest = argv[1], argv[2:]
    title, mids, notes, status, section = [], [], None, "queued", None
    i = 0
    while i < len(rest):
        a = rest[i]
        if a == "--":
            title.extend(rest[i + 1:])
            break
        if a in ("--mid", "--notes", "--status", "--section"):
            if i + 1 >= len(rest):
                return _usage()
            v = rest[i + 1]
            if a == "--mid":
                mids.append(v)
            elif a == "--notes":
                notes = v
            elif a == "--status":
                status = v
            else:
                section = v
            i += 2
        elif a.startswith("--"):
            sys.stderr.write(f"board_add.py add: unknown flag '{a}'\n")
            return 64
        else:
            title.append(a)
            i += 1
    if notes is not None:
        mids.insert(0, notes)
    title = " ".join(" ".join(title).split())
    if not title:
        return _usage()
    if not os.path.isfile(path):
        sys.stderr.write(f"board add: no board at {path} (run `board init`)\n")
        return 2
    ids = add_rows(path, [{"title": title, "mids": mids, "status": status}], section)
    print(ids[0])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
