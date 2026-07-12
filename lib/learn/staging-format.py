#!/usr/bin/env python3
"""staging-format.py -- the ONE definition of the `_meta/backlog-staging.md` block grammar
(SPEC-196/SPEC-195, ADR-0034 decision 1: shared by `learn drain` and `learn propose`, landed
by whichever of the two sub-goals merges first; SG-06 landed it -- SG-05's `staging-format*`
did not exist yet on this branch's history).

A staging file is a sequence of `## [<state>] <title>` blocks, each followed by `- Field:
value` lines (Intent, Approach, Tags, Home, Source, ...). This mirrors
`lib/board/bin/add-backlog`'s private `parse_staging()` (that reader is settled, working, and
NOT on this sub-goal's touch list -- it keeps its own copy for now; a future cleanup can point
it at this module instead of maintaining the grammar twice).

Filename is deliberately hyphenated (matches the `staging-format*` file-fence token both
sub-goal files use); a plain `import staging_format` cannot see it, so importers load it via
`importlib.util.spec_from_file_location` (see `drain.py`).

Stdlib only.
"""
import re
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
