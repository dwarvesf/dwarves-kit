#!/usr/bin/env python3
"""staging_format.py -- the ONE definition of the backlog-staging block edges.

SG-05 (`learn propose`) and SG-06 (`learn drain`) both read and write the staging
file `_meta/backlog-staging.md`. Per the shared-fixture rule (goal 05/06, ADR-0034),
whichever of the two merges first lands this helper; the second consumes it. It exists
so there is exactly ONE place that knows where a `## [staged]` block starts and ends,
matching the three pre-existing writers/readers byte-for-byte:

  - writer: hooks/backlog-stage.py render_candidate()
  - writer: lib/stats/src/stats/anomalies.py render_block()
  - reader: lib/board/bin/add-backlog parse_staging()   (the human gate; NEVER edited here)

Block shape (trailing blank line included, `- Home:` conditional):

    ## [staged] <title>
    - Intent: <intent>
    - Approach: <approach>
    - Tags: #u-<hi|mid|lo> #f-<hi|mid|lo>
    - Home: <home>            <- emitted only when non-empty
    - Source: <origin> <date> <- always last before the blank line

Block edges: a block starts at any line matching `^## [` and runs to the NEXT such
header (or EOF), exactly as add-backlog's parse_staging() delimits them. Field keys
are a single `[A-Za-z]+` run (Intent/Approach/Tags/Source/Home); a hyphen or space in a
key would not parse under the reader, so this module never emits one.

Usable two ways: `import`ed by a Python consumer (propose.py), or driven as a thin CLI
(`staging_format.py parse <file>` -> JSON blocks; `staging_format.py render` <- JSON
candidate on stdin -> a block) by a non-Python consumer. Stdlib only.
"""
import json
import re
import sys

# The header that opens every block. Anchored to line start (MULTILINE). This is the
# single source of truth for "where a block begins" -- add-backlog uses the identical
# `^##\s*\[` finditer to delimit blocks.
_HEADER_RE = re.compile(r"(?m)^##\s*\[")
# Header line -> (state, title). State is `staged` | `rejected` | `expired` | `promoted NNN`.
_HEADER_PARSE_RE = re.compile(r"##\s*\[([^\]]+)\]\s*(.+)")
# A `- Key: value` field line. Key is one alpha run (reader contract).
_FIELD_RE = re.compile(r"(?m)^-\s*([A-Za-z]+):\s*(.+)$")
# Title normalization for dedup: lowercase alphanumeric words joined by single spaces.
# Exact-set membership over these keys is the ANCHORED dedup form (SPEC-144): a short key
# is never a substring/suffix match of a longer one, because membership is equality, not
# containment. Identical to backlog-stage.py:norm and anomalies.py:_norm.
_NORM_RE = re.compile(r"[a-z0-9]+")


def norm(title):
    """Normalize a title into a dedup key: lowercase alphanumeric words."""
    return " ".join(_NORM_RE.findall(str(title).lower()))


def render_block(candidate):
    """Render one candidate dict as a `## [staged]` block string (trailing blank line).

    Byte-identical to hooks/backlog-stage.py:render_candidate / anomalies.py:render_block.
    Required: title. Optional: intent, approach, u, f, home, source. Returns None if the
    title is empty (a titleless block is unparseable and never emitted).
    """
    title = str(candidate.get("title", "")).strip()
    if not title:
        return None
    intent = str(candidate.get("intent", "")).strip() or "(no intent extracted)"
    approach = str(candidate.get("approach", "")).strip() or "(no approach extracted)"
    u = candidate.get("u") if candidate.get("u") in ("hi", "mid", "lo") else "lo"
    f = candidate.get("f") if candidate.get("f") in ("hi", "mid", "lo") else "mid"
    home = str(candidate.get("home", "")).strip()
    # Source carries the origin + date; propose folds the lens/figure/rids citation onto
    # this ONE line so it rides into the board Notes column on promote.
    source = str(candidate.get("source", "")).strip() or "unknown"
    home_line = f"- Home: {home}\n" if home else ""
    return (
        f"## [staged] {title}\n"
        f"- Intent: {intent}\n"
        f"- Approach: {approach}\n"
        f"- Tags: #u-{u} #f-{f}\n"
        f"{home_line}"
        f"- Source: {source}\n\n"
    )


def parse_blocks(text):
    """Parse staging text into a list of block dicts.

    Each block: {"state": <staged|rejected|expired|promoted NNN>, "title": str,
    "fields": {Intent, Approach, Tags, Source, Home, ...}, "raw": str}. Block edges are
    next-`## [`-header delimited (or EOF), matching add-backlog.parse_staging exactly.
    """
    starts = [m.start() for m in _HEADER_RE.finditer(text)]
    blocks = []
    for i, start in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(text)
        raw = text[start:end]
        header = _HEADER_PARSE_RE.match(raw)
        if not header:
            continue
        blocks.append({
            "state": header.group(1).strip(),
            "title": header.group(2).strip(),
            "fields": dict(_FIELD_RE.findall(raw)),
            "raw": raw,
        })
    return blocks


def existing_keys(*sources):
    """Build the dedup key SET from any number of (kind, path) sources.

    kind == "staging" -> parse `## [<state>] <title>` blocks (ALL states: staged,
    rejected, expired, promoted -- a rejected/expired proposal must never be re-proposed).
    kind == "board"   -> parse board rows `| ID-NNN | Item | ... |` (the Item cell).
    A missing file contributes nothing. Keys are norm()'d titles; membership is EXACT
    (the anchored dedup form).
    """
    import os
    keys = set()
    board_row = re.compile(r"\s*\|\s*[A-Z]+-\d+\s*\|\s*([^|]+)\|")
    for kind, path in sources:
        if not path or not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        if kind == "staging":
            for b in parse_blocks(text):
                if b["title"]:
                    keys.add(norm(b["title"]))
        elif kind == "board":
            for line in text.splitlines():
                m = board_row.match(line)
                if m:
                    keys.add(norm(m.group(1)))
    return keys


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
    sys.stderr.write("usage: staging_format.py {parse <file>|render <stdin-json>}\n")
    return 64


if __name__ == "__main__":
    sys.exit(_main(sys.argv))
