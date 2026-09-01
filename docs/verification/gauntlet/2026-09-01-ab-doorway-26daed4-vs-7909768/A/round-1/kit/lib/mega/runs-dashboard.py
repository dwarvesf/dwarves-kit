#!/usr/bin/env python3
"""runs-dashboard.py -- `mega runs` (SPEC-215): ONE self-contained static HTML page of run cards
over the WHOLE estate, the estate-wide sibling of `mega review --html`'s per-mega sign-off page.

Same projection discipline as SPEC-197/SPEC-182: reads only, persists nothing, safe to re-run.
A card is never fabricated -- every card is a file that exists on disk, and an absent field
renders an honest label, never a zero or a placeholder image.

Sources scanned per repo root (the three artifact shapes the estate actually uses; never a
full-tree walk, so a vendor/node_modules tree cannot blow up discovery):

  1. `_meta/megagoals/**/RUN_REPORT.md`      the mega-goal run reports, including `_archive/`
  2. `**/docs/proof-of-done.md`              the SPEC-016 table-first proofs, tool- and repo-level
  3. `docs/verification/**/runs/*.md`        the per-execution immutable run records

Roots come from a REGISTRY, never a hardcoded path list: the existing `boards.txt` format
(`<name>  <path-to-BACKLOG.md>  [bridge]`, `#` comments, `~` expands), resolved to repo roots by
`lib/sync/cockpit.py`'s own `repo_root_of()`. Unlike the sync cockpit this reads EVERY row, not
only `bridge == "on"` ones: `bridge` opts a repo into a Hermes WRITE path, which has nothing to
do with reading that repo's own reports (SPEC-215 DEC-002).

Presentation is IMPORTED from `lib/mega/mega-review.py` (`_CSS`, `_e`, `_run`) through the same
`importlib` cross-module convention mega-review.py itself uses for `lib/gate/proof-table-gen.py`,
so the two surfaces share one stylesheet and one escaper instead of two that drift. mega-review's
render loop itself is NOT reusable here: it is built around one mega's ROADMAP sub-goal rows and
the per-rid gate ledger, and has no seam that accepts an estate of unrelated documents
(SPEC-215 DEC-003).

Usage: runs-dashboard.py [--registry FILE] [--root DIR ...] [--out PATH] [--max-embed-bytes N]
"""
from __future__ import annotations

import argparse
import base64
import datetime
import html as _html
import importlib.util
import os
import re
import sys

_SELF_DIR = os.path.dirname(os.path.abspath(__file__))  # lib/mega/


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


_MR = _load(os.path.join(_SELF_DIR, "mega-review.py"), "mega_review")
_CKPT = _load(os.path.join(_SELF_DIR, "..", "sync", "cockpit.py"), "cockpit")

_e = _MR._e  # noqa: SLF001 -- the sanctioned cross-module reuse points (SPEC-215 DEC-003)
_BASE_CSS = _MR._CSS  # noqa: SLF001

# Per-image and whole-page embed budgets. A self-contained page means base64, and base64 costs
# ~4/3 the file's bytes, so an uncapped estate scan is the one way this page becomes unopenable.
# Over either budget a capture degrades to a labelled link -- honest, never a silent drop.
# 3 MB per image is calibrated to the REAL corpus, not to a round number: the estate's richest
# visual proof (tools/dictate) carries 1.0-2.0 MB retina screenshots, and a cap under that made
# the one genuinely visual tool render zero pictures. The total budget is the real backstop.
DEFAULT_MAX_EMBED_BYTES = 3 * 1024 * 1024
DEFAULT_TOTAL_EMBED_BYTES = 12 * 1024 * 1024

_IMAGE_EXT = {".png": "image/png", ".gif": "image/gif", ".jpg": "image/jpeg",
              ".jpeg": "image/jpeg", ".webp": "image/webp", ".svg": "image/svg+xml"}
_VIDEO_EXT = {".mp4", ".webm", ".mov", ".m4v"}

_MD_IMAGE_RE = re.compile(r"!\[([^\]]*)\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
_DATE_RE = re.compile(r"\b(20\d{2}-\d{2}-\d{2})\b")
_H1_RE = re.compile(r"^#\s+(.+?)\s*$")
_PR_RE = re.compile(r"(?:^|[\s(\[])#(\d{1,6})\b")
_SHA_RE = re.compile(r"\b([0-9a-f]{7,40})\b")

# Status is a READ OF PROSE, not a ledger fact, so the card labels it as such and always links
# its source document. Attention words are tested FIRST: a report saying "MET, one PR HELD"
# must not classify green on the earlier word.
_ATTENTION_WORDS = ("HELD", "FAILED", "FAILING", "BLOCKED", "STALLED", "NOT MET",
                    "UNVERIFIED", "RED", "ABORTED")
_GREEN_WORDS = ("MET", "PASSED", "PASSING", "GREEN", "SHIPPED", "MERGED", "DONE", "CLOSED")


class Card:
    def __init__(self, path, repo, root):
        self.path = path
        self.repo = repo
        self.root = root
        self.title = ""
        self.date = ""
        self.date_exact = False
        self.status = "UNKNOWN"
        self.kind = ""
        self.captures = []   # [(kind, alt, payload)] kind in {embed, link, oversize}
        self.receipts = []


# ---- 1. registry -> repo roots ------------------------------------------------------------------

def parse_registry_all(text):
    """Every row of a `boards.txt` registry as (name, backlog_path). Unlike cockpit.py's
    `parse_registry` this does NOT filter on the third `bridge` column (SPEC-215 DEC-002)."""
    out = []
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        parts = s.split()
        if len(parts) < 2:
            continue
        name, path = parts[0], parts[1]
        if path.startswith("~/") or path == "~":
            path = os.path.expanduser(path)
        out.append((name, path))
    return out


def resolve_roots(registry_path, explicit_roots):
    """[(repo_name, root_path)], deduplicated by RESOLVED root so a repo registered twice under
    two names never double-cards its runs (SPEC-215 edge case 1). Explicit --root args bypass the
    registry entirely; that is the path the tests and the empty-state control use."""
    pairs = []
    for r in explicit_roots or []:
        pairs.append((os.path.basename(os.path.abspath(r)) or r, r))
    if registry_path and os.path.isfile(registry_path):
        for name, backlog in parse_registry_all(open(registry_path, encoding="utf-8", errors="replace").read()):
            if not os.path.isfile(backlog):
                print(f"runs-dashboard: skip repo {name!r}: no BACKLOG.md at {backlog}", file=sys.stderr)
                continue
            pairs.append((name, str(_CKPT.repo_root_of(_CKPT.Path(backlog)))))

    seen, out = set(), []
    for name, root in pairs:
        try:
            key = os.path.realpath(root)
        except OSError:
            continue
        if key in seen:
            continue
        seen.add(key)
        out.append((name, root))
    return out


# ---- 2. discovery ------------------------------------------------------------------------------

def _walk(start, want, max_depth=6):
    """Bounded walk under one prefix. Prunes the dirs that never hold run artifacts but do hold
    enough files to make an unbounded walk slow (SPEC-215 failure mode 3)."""
    hits = []
    if not os.path.isdir(start):
        return hits
    start_depth = start.rstrip(os.sep).count(os.sep)
    for dirpath, dirnames, filenames in os.walk(start):
        if dirpath.count(os.sep) - start_depth >= max_depth:
            dirnames[:] = []
        dirnames[:] = [d for d in dirnames
                       if d not in (".git", "node_modules", ".venv", "venv", "__pycache__",
                                    "worktrees", "target", "dist", "build")]
        for fn in filenames:
            if want(dirpath, fn):
                hits.append(os.path.join(dirpath, fn))
    return hits


def discover(root):
    """Every run artifact under one repo root, as [(path, kind)]. Honest-empty: a missing or
    empty root yields [], never an exception (SPEC-215 edge case, empty-state control)."""
    found = []
    for p in _walk(os.path.join(root, "_meta", "megagoals"),
                   lambda d, f: f == "RUN_REPORT.md"):
        found.append((p, "run report"))
    for p in _walk(root, lambda d, f: f == "proof-of-done.md" and os.path.basename(d) == "docs"):
        found.append((p, "proof of done"))
    for p in _walk(os.path.join(root, "docs", "verification"),
                   lambda d, f: f.endswith(".md") and os.path.basename(d) == "runs"):
        found.append((p, "verification run"))
    # The FLAT shape `docs/verification/<slug>.md`, which docs/verification/README.md documents as
    # still accepted by the gate. It is the majority shape in the estate today, and dropping it
    # would silently hide most of one repo's proofs. README/test-design are design docs, not runs.
    for p in _walk(os.path.join(root, "docs", "verification"),
                   lambda d, f: (f.endswith(".md") and os.path.basename(d) == "verification"
                                 and f not in ("README.md", "test-design.md")),
                   max_depth=1):
        found.append((p, "verification run"))

    seen, out = set(), []
    for p, kind in found:
        rp = os.path.realpath(p)
        if rp not in seen:
            seen.add(rp)
            out.append((p, kind))
    return out


# ---- 3. card extraction ------------------------------------------------------------------------

def classify_status(text):
    upper = text.upper()
    for w in _ATTENTION_WORDS:
        if w in upper:
            return "ATTENTION"
    for w in _GREEN_WORDS:
        if w in upper:
            return "GREEN"
    return "UNKNOWN"


def _title_from_path(path, root):
    """Path-derived fallback when a document carries no `# ` heading: the owning directory,
    which for `tools/x/docs/proof-of-done.md` and `megagoals/x/RUN_REPORT.md` alike is the run's
    real name. Never returns empty (SPEC-215 test case 2)."""
    rel = os.path.relpath(path, root)
    parts = [p for p in rel.split(os.sep) if p not in ("docs", "runs", "_meta", "megagoals", "_archive")]
    if len(parts) >= 2:
        return parts[-2]
    return os.path.splitext(os.path.basename(path))[0]


def _read_head(path, n_bytes=24000):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read(n_bytes)
    except OSError:
        return ""


def _collect_captures(text, doc_dir, budget):
    """Markdown image references resolved against the document's own directory. A reference whose
    target does not exist contributes NOTHING -- no broken <img>, no fabricated thumbnail
    (SPEC-215 test case 6, which is also what keeps template/fixture placeholders off the page)."""
    out = []
    for alt, rel in _MD_IMAGE_RE.findall(text):
        if rel.startswith(("http://", "https://", "data:", "//")):
            continue  # a remote asset would break the self-contained invariant
        target = os.path.normpath(os.path.join(doc_dir, rel))
        if not os.path.isfile(target):
            continue
        ext = os.path.splitext(target)[1].lower()
        if ext in _VIDEO_EXT:
            out.append(("link", alt or os.path.basename(target), target))
            continue
        if ext not in _IMAGE_EXT:
            continue
        try:
            size = os.path.getsize(target)
        except OSError:
            continue
        # ponytail: the total budget is spent in SCAN ORDER, so once it runs out the captures that
        # degrade are whichever repos sort last, not the least valuable ones. Acceptable while the
        # estate degrades one capture in forty; if that ratio grows, allocate per repo before
        # embedding rather than first-come.
        if size > budget.per_image or budget.spent + size > budget.total:
            out.append(("oversize", alt or os.path.basename(target), target))
            continue
        try:
            raw = open(target, "rb").read()
        except OSError:
            continue
        budget.spent += size
        uri = f"data:{_IMAGE_EXT[ext]};base64,{base64.b64encode(raw).decode('ascii')}"
        out.append(("embed", alt or os.path.basename(target), uri))
    return out


class Budget:
    def __init__(self, per_image, total):
        self.per_image = per_image
        self.total = total
        self.spent = 0


def extract_card(path, kind, repo, root, budget):
    text = _read_head(path)
    card = Card(path, repo, root)
    card.kind = kind

    for line in text.splitlines()[:80]:
        m = _H1_RE.match(line)
        if m:
            card.title = m.group(1).strip()
            break
    if not card.title:
        card.title = _title_from_path(path, root)

    m = _DATE_RE.search(text[:4000])
    if m:
        card.date, card.date_exact = m.group(1), True
    else:
        # Honest fallback: the file's own mtime, LABELLED as a file date so no reader mistakes
        # it for a date the author wrote (SPEC-215 edge case 2).
        try:
            card.date = datetime.date.fromtimestamp(os.path.getmtime(path)).isoformat()
        except OSError:
            card.date = ""

    card.status = classify_status(text[:6000])
    card.captures = _collect_captures(text, os.path.dirname(path), budget)

    prs = sorted({int(n) for n in _PR_RE.findall(text[:8000])})
    card.receipts = [f"PR #{n}" for n in prs[:6]]
    shas = [s for s in _SHA_RE.findall(text[:8000]) if len(s) >= 7 and not s.isdigit()]
    if shas:
        card.receipts.append(f"sha {shas[0]}")
    return card


def scan(roots, budget):
    cards = []
    for repo, root in roots:
        for path, kind in discover(root):
            cards.append(extract_card(path, kind, repo, root, budget))
    # Newest first. A card with no date at all sorts last rather than crashing the comparison.
    cards.sort(key=lambda c: (c.date or "", c.repo), reverse=True)
    return cards


# ---- 4. render ---------------------------------------------------------------------------------

# Layered ON TOP of the imported mega-review stylesheet, never a second copy of it: the palette,
# the dark-scheme block, and the badge colours all come from `_BASE_CSS` (SPEC-215 DEC-003).
_GRID_CSS = """
body { max-width: 78rem; }
.summary { color: #6b7280; font-size: 0.85rem; margin-bottom: 1.25rem; }
.repo-head { font-size: 1rem; margin: 1.75rem 0 0.5rem; padding-bottom: 0.25rem;
  border-bottom: 1px solid #374151; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(19rem, 1fr)); gap: 0.9rem; }
.card { border: 1px solid #374151; border-radius: 0.4rem; padding: 0.7rem 0.85rem;
  background: #ffffff; display: flex; flex-direction: column; gap: 0.4rem; }
.card.att-bad { border-left: 5px solid #dc2626; }
.card.att-ok { border-left: 5px solid #16a34a; }
.card.att-unknown { border-left: 5px solid #9ca3af; }
.card h3 { font-size: 0.95rem; margin: 0; line-height: 1.3; }
.card .line { color: #6b7280; font-size: 0.78rem; }
.shots { display: flex; flex-wrap: wrap; gap: 0.4rem; }
.shots img { max-width: 100%; max-height: 9rem; border: 1px solid #374151; border-radius: 0.25rem;
  display: block; }
.nocap { color: #6b7280; font-style: italic; font-size: 0.78rem; }
.receipts { font-size: 0.75rem; color: #6b7280; }
a { color: #1d4ed8; }
@media (prefers-color-scheme: dark) {
  .card { background: #1a2233; }
  .repo-head { border-color: #4b5563; }
  .card { border-color: #4b5563; }
  .shots img { border-color: #4b5563; }
  a { color: #93c5fd; }
}
""".strip()

_STATUS_CLASS = {"GREEN": ("att-ok", "ok"), "ATTENTION": ("att-bad", "bad"),
                 "UNKNOWN": ("att-unknown", "unknown")}


def render_captures(captures):
    if not captures:
        return '<p class="nocap">no captures in this report (text proof only)</p>'
    bits = ['<div class="shots">']
    for kind, alt, payload in captures:
        if kind == "embed":
            bits.append(f'<img src="{_e(payload)}" alt="{_e(alt)}">')
        elif kind == "link":
            bits.append(f'<span class="nocap">video: <a href="{_e(payload)}">{_e(alt)}</a></span>')
        else:
            bits.append(f'<span class="nocap">capture over embed budget, not inlined: '
                        f'<a href="{_e(payload)}">{_e(alt)}</a></span>')
    bits.append("</div>")
    return "\n".join(bits)


def render_card(card):
    css_class, badge_class = _STATUS_CLASS.get(card.status, _STATUS_CLASS["UNKNOWN"])
    date_note = "" if card.date_exact else " (file date)"
    rel = os.path.relpath(card.path, card.root)
    out = [f'<article class="card {css_class}">']
    out.append(f'<h3>{_e(card.title)}<span class="badge {badge_class}">{_e(card.status)}</span></h3>')
    out.append(f'<p class="line">{_e(card.repo)} &middot; {_e(card.date or "-")}{_e(date_note)} '
               f'&middot; {_e(card.kind)}</p>')
    out.append(render_captures(card.captures))
    out.append(f'<p class="line"><a href="{_e(card.path)}">{_e(rel)}</a></p>')
    if card.receipts:
        out.append(f'<p class="receipts">receipts: {_e(" · ".join(card.receipts))}</p>')
    else:
        out.append('<p class="receipts">receipts: <span class="nocap">-</span></p>')
    out.append("</article>")
    return "\n".join(out)


def render_page(cards, roots):
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    body = []

    if not cards:
        body.append(
            '<div class="banner">Scanned '
            f"{len(roots)} root(s) and found <strong>no run artifacts</strong> "
            "(no RUN_REPORT.md, no docs/proof-of-done.md, no docs/verification/**/runs/*.md). "
            "This is not an error: the estate simply has nothing to show yet, or the roots are "
            "not where the reports live. Nothing is fabricated to fill the page.</div>")
    else:
        n_shots = sum(1 for c in cards for k, _a, _p in c.captures if k == "embed")
        n_visual = sum(1 for c in cards if any(k == "embed" for k, _a, _p in c.captures))
        body.append(
            f'<p class="summary">{len(cards)} run card(s) across {len(roots)} root(s) &middot; '
            f'{n_visual} carry an inline capture ({n_shots} image(s) embedded) &middot; '
            f'{len(cards) - n_visual} are text-only proof. Status is read from each document\'s '
            'own prose, not from a ledger: open the linked report to confirm.</p>')
        by_repo = {}
        for c in cards:
            by_repo.setdefault(c.repo, []).append(c)
        for repo in sorted(by_repo):
            body.append(f'<h2 class="repo-head">{_e(repo)} ({len(by_repo[repo])})</h2>')
            body.append('<div class="grid">')
            body.extend(render_card(c) for c in by_repo[repo])
            body.append("</div>")

    return (
        "<!doctype html>\n"
        '<html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        "<title>estate runs dashboard</title>"
        f"<style>{_BASE_CSS}\n{_GRID_CSS}</style>"
        "</head><body>"
        "<h1>estate runs dashboard</h1>"
        f'<p class="meta">generated {_e(now)} &middot; a projection over run reports, proofs of '
        "done, and verification runs; never a stored source of truth (SPEC-215). Re-run to "
        "refresh.</p>"
        + "\n".join(body)
        + "</body></html>"
    )


# ---- CLI ---------------------------------------------------------------------------------------

def default_registry():
    """`--registry` > $KIT_BOARDS_REGISTRY > <repo-root>/_meta/boards.txt. The kit itself carries
    no personal data, so there is deliberately no hardcoded fallback to any user's workspace."""
    env = os.environ.get("KIT_BOARDS_REGISTRY")
    if env:
        return env
    res = _MR._run(["git", "rev-parse", "--show-toplevel"])  # noqa: SLF001
    if res is not None and res.returncode == 0 and res.stdout.strip():
        return os.path.join(res.stdout.strip(), "_meta", "boards.txt")
    return None


def main(argv=None):
    ap = argparse.ArgumentParser(prog="runs-dashboard.py")
    ap.add_argument("--registry", default=None, help="boards.txt-format registry of repos to scan")
    ap.add_argument("--root", action="append", default=[],
                    help="scan this repo root directly (repeatable; bypasses the registry)")
    ap.add_argument("--out", default="runs-dashboard.html")
    ap.add_argument("--max-embed-bytes", type=int, default=DEFAULT_MAX_EMBED_BYTES)
    ap.add_argument("--total-embed-bytes", type=int, default=DEFAULT_TOTAL_EMBED_BYTES)
    args = ap.parse_args(argv)

    registry = args.registry if args.registry is not None else (None if args.root else default_registry())
    roots = resolve_roots(registry, args.root)

    budget = Budget(args.max_embed_bytes, args.total_embed_bytes)
    cards = scan(roots, budget)
    page = render_page(cards, roots)

    out_dir = os.path.dirname(os.path.abspath(args.out))
    os.makedirs(out_dir, exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(page)
    print(args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
