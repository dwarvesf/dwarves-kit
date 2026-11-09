"""box.py -- the Python reader of the mega ROADMAP box and id grammar in lib/mega/box.tsv.

The twin of lib/mega/box.sh: the same file, the same answers (tests/test-mega-box.sh compares them).
Load it by path (importlib), as the sibling scripts do; the hyphenated readers are not importable by name.
"""
from pathlib import Path

TSV = Path(__file__).resolve().parent / "box.tsv"


def load(path=TSV):
    """The declared rows as [kind, name, token, class, aliases], in file order."""
    rows = []
    for line in Path(path).read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) >= 3:
            rows.append(f + ["-"] * (5 - len(f)))
    if not rows:
        raise SystemExit(f"FATAL: {path} has no rows")
    return rows


_ROWS = load()


def chars(*names):
    """Characters of those boxes, token then aliases, a dash last (valid in a bracket expression)."""
    out = ""
    for kind, name, token, _cls, aliases in _ROWS:
        if kind == "box" and name in names:
            out += token[1]
            if aliases != "-":
                out += "".join(a[1] for a in aliases.split())
    return out.replace("-", "") + ("-" if "-" in out else "")


def box_class(*names):
    return "[" + chars(*names) + "]"


def box_re(*names, group=False):
    """The bullet and box as a regex, anchored by the caller; no names = every box. group=True captures the box character."""
    cls = box_class(*(names or [n for k, n, *_ in _ROWS if k == "box"]))
    return r"- \[" + (f"({cls})" if group else cls) + r"\]"


def name_of(char):
    for kind, name, token, _cls, aliases in _ROWS:
        if kind == "box" and char in (token[1], *[a[1] for a in aliases.split() if aliases != "-"]):
            return name
    return ""


def id_re(*names):
    """The sub-goal id regex, every id row alternated, or only the named rows."""
    return "(?:" + "|".join(t for kind, name, t, _c, _a in _ROWS if kind == "id" and (not names or name in names)) + ")"
