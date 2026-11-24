#!/usr/bin/env python3
# kit-verb: board state-check | validate the stored state values of a repo's own registry file; block new drift at commit, report existing drift
"""state-check: validate stored state values against a repo's own state registry (a TOML file).

  state-check --all [--strict]   report every check=true machine (strict: exit 1 on undeclared values or projection drift)
  state-check --staged           pre-commit mode: block NEW drift only; existing data is grandfathered
  state-check --fix              rewrite the leading status token of each drifted projection row to match its store; free text stays

  --repo-root DIR                the repo to check (default: STATES_ROOT, else the git root of the current directory)
  --states-file PATH             the registry (default: STATES_REGISTRY, else <repo-root>/_meta/states.toml)

Escape hatch for --staged: ALLOW_STATE_CHANGE="<reason>". Exit 0 clean, 1 blocked, 2 internal error.
Env: STATES_ROOT, STATES_REGISTRY, STATES_BASE (compare the index against another commit), STATES_PROG (the command name
printed in hints and usage), STATES_TOML=mini (force the built-in TOML reader).
"""
from __future__ import annotations

import collections
import os
import re
import subprocess
import sys
from pathlib import Path

try:
    if os.environ.get("STATES_TOML") == "mini":
        raise ImportError("mini reader forced")
    import tomllib
except ImportError:
    tomllib = None

PROG = os.environ.get("STATES_PROG") or "board state-check"
MALFORMED: list[str] = []  # table rows whose cell count differs from the header, skipped
BODY_STATUS = re.compile(r"^\W*status\W*:\s*(.*)$", re.I)


class TomlError(ValueError):
    """A TOML document the reader cannot parse."""


def _split_top(text: str) -> list[str]:
    """Split on commas that sit outside strings and brackets."""
    parts, depth, quote, cur = [], 0, "", []
    for ch in text:
        if quote:
            cur.append(ch)
            if ch == quote:
                quote = ""
        elif ch in "\"'":
            quote = ch
            cur.append(ch)
        elif ch in "[{":
            depth += 1
            cur.append(ch)
        elif ch in "]}":
            depth -= 1
            cur.append(ch)
        elif ch == "," and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    if "".join(cur).strip():
        parts.append("".join(cur))
    return parts


def _strip_comment(line: str) -> str:
    quote, i = "", 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\" and quote == '"':
                i += 1
            elif ch == quote:
                quote = ""
        elif ch in "\"'":
            quote = ch
        elif ch == "#":
            return line[:i]
        i += 1
    return line


def _value(raw: str):
    raw = raw.strip()
    if not raw:
        raise TomlError("empty value")
    if raw[0] == '"':
        if len(raw) < 2 or raw[-1] != '"' or raw.startswith('"""'):
            raise TomlError(f"unsupported string: {raw[:30]}")
        return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(m.group(1), m.group(1)), raw[1:-1])
    if raw[0] == "'":
        if len(raw) < 2 or raw[-1] != "'" or raw.startswith("'''"):
            raise TomlError(f"unsupported string: {raw[:30]}")
        return raw[1:-1]
    if raw == "true":
        return True
    if raw == "false":
        return False
    if raw[0] == "[":
        if raw[-1] != "]":
            raise TomlError(f"unterminated array: {raw[:30]}")
        return [_value(p) for p in _split_top(raw[1:-1])]
    if raw[0] == "{":
        if raw[-1] != "}":
            raise TomlError(f"unterminated inline table: {raw[:30]}")
        out: dict = {}
        for part in _split_top(raw[1:-1]):
            k, sep, v = part.partition("=")
            if not sep:
                raise TomlError(f"bad inline table entry: {part[:30]}")
            out[_key(k)] = _value(v)
        return out
    if re.fullmatch(r"[+-]?\d+", raw):
        return int(raw)
    raise TomlError(f"unsupported value: {raw[:30]}")


def _key(raw: str) -> str:
    k = raw.strip()
    if len(k) >= 2 and k[0] == k[-1] and k[0] in "\"'":
        return k[1:-1]
    if not re.fullmatch(r"[A-Za-z0-9_-]+", k):
        raise TomlError(f"unsupported key: {k[:30]}")
    return k


def mini_toml_loads(text: str) -> dict:
    """The TOML subset a registry and a status file use: [a] and [a.b] tables, bare or quoted keys, strings,
    integers, booleans, arrays and inline tables (which may span lines). Anything else raises TomlError."""
    root: dict = {}
    cur = root
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = _strip_comment(lines[i]).strip()
        i += 1
        if not line:
            continue
        if line.startswith("["):
            if line.startswith("[[") or not line.endswith("]"):
                raise TomlError(f"unsupported table header: {line[:30]}")
            cur = root
            for part in line[1:-1].split("."):
                cur = cur.setdefault(_key(part), {})
                if not isinstance(cur, dict):
                    raise TomlError(f"table clashes with a value: {line[:30]}")
            continue
        k, sep, v = line.partition("=")
        if not sep:
            raise TomlError(f"not a key = value line: {line[:30]}")
        v = v.strip()
        while v[:1] in ("[", "{") and _depth(v) > 0 and i < len(lines):
            v += " " + _strip_comment(lines[i]).strip()
            i += 1
        key = _key(k)
        if key in cur:
            raise TomlError(f"duplicate key: {key}")
        cur[key] = _value(v)
    return root


def _depth(text: str) -> int:
    depth, quote = 0, ""
    for ch in text:
        if quote:
            if ch == quote:
                quote = ""
        elif ch in "\"'":
            quote = ch
        elif ch in "[{":
            depth += 1
        elif ch in "]}":
            depth -= 1
    return depth


def registry_loads(text: str) -> dict:
    """The registry itself: a parse fault is an internal error (exit 2), so the reader's own error text passes through."""
    return tomllib.loads(text) if tomllib is not None else mini_toml_loads(text)


def toml_top_value(text: str, field: str):
    """A stored file's top-level `field`, as tomllib reports it; None when the file is unparseable or lacks the field.
    Without tomllib a stored file may use TOML the mini reader lacks (arrays of tables, dates), so this reads only the
    lines before the first table header and parses just the one value."""
    if tomllib is not None:
        try:
            return tomllib.loads(text).get(field)
        except tomllib.TOMLDecodeError:
            return None
    lines, i, in_text = text.splitlines(), 0, ""
    while i < len(lines):
        raw = lines[i]
        i += 1
        if in_text:
            if in_text in raw:
                in_text = ""
            continue
        line = _strip_comment(raw).strip()
        if line.startswith("["):
            return None
        k, sep, v = line.partition("=")
        if not sep:
            continue
        v = v.strip()
        for q in ('"""', "'''"):
            if v.startswith(q) and v.count(q) == 1:
                in_text = q
        if in_text:
            continue
        while v[:1] in ("[", "{") and _depth(v) > 0 and i < len(lines):
            v += " " + _strip_comment(lines[i]).strip()
            i += 1
        try:
            key = _key(k)
        except TomlError:
            continue
        if key == field:
            try:
                return _value(v)
            except TomlError:
                return None
    return None


def _find_root() -> Path:
    if os.environ.get("STATES_ROOT"):
        return Path(os.environ["STATES_ROOT"])
    top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return Path(top.stdout.strip() if top.returncode == 0 and top.stdout.strip() else os.getcwd())


ROOT = _find_root()
REGISTRY = Path(os.environ["STATES_REGISTRY"]) if os.environ.get("STATES_REGISTRY") else ROOT / "_meta" / "states.toml"


def set_paths(root: str | None, registry: str | None) -> None:
    """Point the module at another repo or registry (the --repo-root and --states-file flags)."""
    global ROOT, REGISTRY
    if root:
        ROOT = Path(root)
        if not os.environ.get("STATES_REGISTRY"):
            REGISTRY = ROOT / "_meta" / "states.toml"
    if registry:
        REGISTRY = Path(registry) if os.path.isabs(registry) else ROOT / registry


def registry_label() -> str:
    try:
        return str(REGISTRY.resolve().relative_to(ROOT.resolve()))
    except ValueError:
        return str(REGISTRY)


def git(*args: str) -> str | None:
    res = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)
    return res.stdout if res.returncode == 0 else None


def read_index(path: str) -> str | None:
    return git("show", f":{path}")


BASE = os.environ.get("STATES_BASE", "HEAD")  # replays compare the index against another commit


def read_head(path: str) -> str | None:
    return git("show", f"{BASE}:{path}")


def read_disk(path: str) -> str | None:
    p = ROOT / path
    return p.read_text(errors="replace") if p.is_file() else None


def glob_re(glob: str) -> re.Pattern:
    return re.compile("^" + re.escape(glob).replace(r"\*", "[^/]*") + "$")


def cells(line: str) -> list[str]:
    return [c.strip() for c in re.split(r"(?<!\\)\|", line.strip().strip("|"))]


def parse_table(text: str, key_cols: list[str], field: str) -> dict[str, tuple[str, str]]:
    """Every table whose header has the key columns and the field. key -> (raw value, row text)."""
    out: dict[str, tuple[str, str]] = {}
    lines = text.splitlines()
    want = [c.lower() for c in key_cols] + [field.lower()]
    i = 0
    while i < len(lines) - 1:
        head = [c.lower() for c in cells(lines[i])] if lines[i].startswith("|") else []
        sep = lines[i + 1].startswith("|") and set(lines[i + 1].replace("|", "").strip()) <= set("-: ")
        if not (sep and all(w in head for w in want)):
            i += 1
            continue
        idx = {w: head.index(w) for w in want}
        i += 2
        while i < len(lines) and lines[i].startswith("|"):
            row = cells(lines[i])
            if len(row) != len(head):
                MALFORMED.append(lines[i][:80])
            else:
                key = "/".join(re.sub(r"^\[([^\]]*)\]\(.*\)$", r"\1", row[idx[w]]) for w in want[:-1])
                while key in out:
                    key += "#"
                out[key] = (row[idx[want[-1]]], lines[i])
            i += 1
    return out


def frontmatter_value(text: str, field: str, body_fallback: bool) -> str | None:
    lines = text.splitlines()
    if lines and lines[0].strip() == "---":
        for line in lines[1:]:
            if line.strip() == "---":
                break
            m = re.match(rf"^{re.escape(field)}:\s*(.*)$", line)
            if m:
                return m.group(1)
    if body_fallback:
        for line in lines[:60]:
            m = BODY_STATUS.match(line)
            if m:
                return m.group(1)
    return None


def values(m: dict, path: str, text: str) -> dict[str, tuple[str, str]]:
    """Stored values of one file: key -> (raw value, row text). An absent or empty field gives no entry."""
    if m["kind"] == "table":
        return parse_table(text, m["key"], m["field"])
    if m["kind"] == "toml":
        raw = toml_top_value(text, m["field"])
    else:
        raw = frontmatter_value(text, m["field"], m.get("body_fallback", False))
    return {path: (str(raw), "")} if raw not in (None, "") else {}


def norm(raw: str, ignore_case: bool = False) -> str:
    """Leading token of a stored value; a `:<ref>` suffix is kept as a trailing colon."""
    v = re.sub(r"\s+#.*$", "", raw).strip().strip("*`\"'").strip()
    v = re.sub(r"(?<=\S)\s*\(.*\)\s*$", "", v).lstrip("([")
    m = re.match(r"[\w][\w-]*:?", v)
    tok = m.group(0) if m else v
    return tok.lower() if ignore_case else tok


def classify(m: dict, state: str) -> str:
    fold = (lambda s: s.lower()) if m.get("ignore_case") else (lambda s: s)
    if fold(state) in {fold(s) for s in m["states"]}:
        return "ok"
    return "legacy" if fold(state) in {fold(s) for s in m.get("legacy", [])} else "undeclared"


def drift(m: dict, reader, only: set[str] | None = None) -> set[tuple[str, str, str, str]]:
    """Projection rows whose leading token disagrees with the store: (file, key, projected, stored)."""
    found = set()
    ic = m.get("ignore_case", False)
    for proj in m.get("projections", []):
        text = reader(proj["file"])
        for key, (raw, _) in parse_table(text or "", [proj["key"]], proj["field"]).items():
            path = m["glob"].replace("*", key, 1)
            if only is not None and path not in only and proj["file"] not in only:
                continue
            stored = reader(path)
            got = values(m, path, stored).get(path) if stored else None
            if got and norm(raw, ic) != norm(got[0], ic):
                found.add((proj["file"], key, norm(raw, ic), norm(got[0], ic)))
    return found


def all_files(m: dict) -> list[str]:
    rx = glob_re(m["glob"])
    base = ROOT / (m["glob"].split("*")[0].rstrip("/") or ".")
    rels = (str(p.relative_to(ROOT)) for p in (base.rglob("*") if base.is_dir() else [base]) if p.is_file())
    return sorted(r for r in rels if rx.match(r))


def report_all(machines: dict, strict: bool) -> int:
    bad = 0
    for name, m in machines.items():
        if not m.get("check"):
            continue
        counts: collections.Counter = collections.Counter()
        undeclared: dict[str, list[str]] = collections.defaultdict(list)
        for path in all_files(m):
            for key, (raw, _) in values(m, path, read_disk(path) or "").items():
                st = norm(raw, m.get("ignore_case", False))
                kind = classify(m, st)
                counts[(st, kind)] += 1
                if kind == "undeclared":
                    undeclared[st].append(key)
        rows = drift(m, read_disk)
        tag = {"ok": "", "legacy": "(legacy)", "undeclared": "(UNDECLARED)"}
        print(f"[{name}] " + ", ".join(f"{s}={n}{tag[k]}" for (s, k), n in sorted(counts.items())))
        for st, keys in undeclared.items():
            print(f"  undeclared {st!r}: {len(keys)}, e.g. {keys[0]}")
        for f, key, got, want in sorted(rows):
            print(f"  drift {f}: {key} says {got!r}, store says {want!r}")
        bad += len(undeclared) + len(rows)
    for row in dict.fromkeys(MALFORMED):
        print(f"  skipped malformed table row: {row}")
    print(f"summary: {bad} undeclared value kinds and projection drift rows")
    return 1 if strict and bad else 0


def retoken(cell: str, want: str) -> str | None:
    """A stored value with its leading status token replaced by want; decorators and free text stay. None: no token."""
    m2 = re.match(r"([\s*`\"'(\[]*)([\w][\w-]*:?)(.*)$", cell, re.S)
    return f"{m2.group(1)}{want}{m2.group(3)}" if m2 else None


def retoken_row(lines: list[str], at: int, field: str, want: str) -> bool:
    """Replace the leading token of the field cell of the table row lines[at], in place."""
    row = lines[at].rstrip("\r\n")
    top = at
    while top > 0 and lines[top - 1].startswith("|"):
        top -= 1
    col = [c.lower() for c in cells(lines[top])].index(field.lower())
    parts = re.split(r"(?<!\\)\|", row)
    cell = retoken(parts[col + 1], want)
    if cell is None:
        return False
    parts[col + 1] = cell
    lines[at] = "|".join(parts) + lines[at][len(row):]
    return True


def move_problem(m: dict, where: str, old: str | None, new: str) -> str | None:
    """Why moving a stored value from old (None: no value yet) to new is refused, or None. Shared by --staged and set-state."""
    kind = classify(m, new)
    if kind == "undeclared":
        return f"{where}: {new!r} is not a declared state"
    if kind == "legacy":
        return f"{where}: {new!r} is a legacy value, refused when newly written"
    if old is not None and "transitions" in m and classify(m, old) == "ok":
        allowed = m["transitions"].get(old, [])
        if new not in allowed:
            return f"{where}: {old!r} -> {new!r} is not a declared transition (allowed from {old!r}: {allowed or 'none, terminal'})"
    return None


def fix_projections(machines: dict) -> int:
    """Rewrite only the leading status token of each drifted projection row, on disk. The store, the other cells,
    the free text after the token and the row set are never touched."""
    fixed = 0
    for m in (m for m in machines.values() if m.get("check")):
        for f, key, got, want in sorted(drift(m, read_disk)):
            proj = next(p for p in m["projections"] if p["file"] == f)
            text = read_disk(f) or ""
            row = parse_table(text, [proj["key"]], proj["field"])[key][1]
            lines = text.splitlines(keepends=True)
            at = next(i for i, ln in enumerate(lines) if ln.rstrip("\r\n") == row)
            if not retoken_row(lines, at, proj["field"], want):
                continue
            (ROOT / f).write_text("".join(lines))
            print(f"fixed {f}: {key} {got!r} -> {want!r}")
            fixed += 1
    if not fixed:
        print("no projection drift to fix")
    return 0


def check_staged(machines: dict) -> int:
    names = [n for n in (git("diff", "--cached", "--name-only", "--diff-filter=ACMRD", BASE) or "").splitlines() if n]
    problems: list[str] = []
    for name, m in machines.items():
        if not m.get("check"):
            continue
        ic, rx = m.get("ignore_case", False), glob_re(m["glob"])
        for path in (n for n in names if rx.match(n)):
            new_vals = values(m, path, read_index(path) or "")
            old_vals = values(m, path, read_head(path) or "")
            for key, (raw, row) in new_vals.items():
                new, old_entry = norm(raw, ic), old_vals.get(key)
                old = norm(old_entry[0], ic) if old_entry else None
                if old == new and not (m.get("append_only") and old_entry[1] != row):
                    continue
                where = f"{key} [{name}]"
                if m.get("append_only") and old_entry:
                    problems.append(f"{where}: past row edited (append-only)")
                elif problem := move_problem(m, where, old, new):
                    problems.append(problem)
            if m.get("append_only"):
                problems += [f"{k} [{name}]: past row removed (append-only)" for k in old_vals.keys() - new_vals.keys()]
        files = {p["file"] for p in m.get("projections", [])}
        touched = {n for n in names if n in files or rx.match(n)}
        if touched:
            for f, key, got, want in sorted(drift(m, read_index, touched)):
                path = m["glob"].replace("*", key, 1)
                if (f, key, got, want) not in drift(m, read_head, {path}):
                    problems.append(f"{f}: {key} says {got!r} but {path} says {want!r} (projection drift [{name}])")
    if not problems:
        return 0
    reason = os.environ.get("ALLOW_STATE_CHANGE")
    title = "state-registry: ALLOWED by ALLOW_STATE_CHANGE" if reason else f"BLOCKED: state registry ({registry_label()})"
    print(f"============ {title} ============", file=sys.stderr)
    print("\n".join("  " + p for p in problems), file=sys.stderr)
    if reason:
        print(f"reason: {reason}", file=sys.stderr)
        return 0
    if any("projection drift" in p for p in problems):
        print(f"Projection drift: `{PROG} --fix` rewrites the INDEX status to match the store; then `git add` the INDEX.", file=sys.stderr)
    print("Fix the value, or the registry. Deliberate change: ALLOW_STATE_CHANGE='<reason>' git commit ...", file=sys.stderr)
    return 1


def take_flag(argv: list[str], name: str) -> str | None:
    """Remove `name VALUE` from argv and return VALUE; None when absent. A flag with no value is a usage error."""
    if name not in argv:
        return None
    at = argv.index(name)
    if at + 1 >= len(argv):
        raise SystemExit(usage(2))
    value = argv[at + 1]
    del argv[at:at + 2]
    return value


def usage(code: int) -> int:
    print((__doc__ or "").replace("state-check", PROG), file=sys.stdout if code == 0 else sys.stderr)
    return code


def main(argv: list[str]) -> int:
    argv = list(argv)
    if "-h" in argv or "--help" in argv:
        return usage(0)
    set_paths(take_flag(argv, "--repo-root"), take_flag(argv, "--states-file"))
    if not any(f in argv for f in ("--all", "--staged", "--fix")):
        return usage(2)
    machines = registry_loads(REGISTRY.read_text())
    if "--all" in argv:
        return report_all(machines, "--strict" in argv)
    if "--staged" in argv:
        return check_staged(machines)
    return fix_projections(machines)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as exc:  # internal fault: the hook passes on any code but 1
        print(f"{os.path.basename(PROG)}: internal error: {exc!r}", file=sys.stderr)
        sys.exit(2)
