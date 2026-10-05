#!/usr/bin/env python3
"""Reconcile the open Hermes cards against the hub (each repo's BACKLOG.md).

The Hermes kanban boards are a projection of the BACKLOG.md boards. This script
finds the cards that stopped matching and, with --apply, archives them. It never
deletes anything: archive is the one Hermes verb that works from every state,
and an archived card stays readable.

Classes, per open card (done and archived cards are closed and only counted):

  a  mirror of an active row (queued .. executing, parked) in the state the
     row maps to. Left alone.
  b  mirror of a row that is shipped or dropped, or that moved to the archive
     file. The card should be gone. Action: archive.
  c  mirror of a row that exists nowhere (or a mega-goal that is gone). Action:
     archive.
  d  no origin line: made by a bot, not by the mirror. Reported by kind with a
     proposed owner rule and never touched, except a decomposer child whose
     root card is being archived (the chain a stuck root leaves behind).
  e  anything else: an active row whose card sits in the wrong state (the
     pre-fix mirror recorded moves it never made), or an origin whose repo is
     not in the registry. A wrong-state card is archived and its snapshot line
     dropped, so the next mirror tick creates a fresh card in the right state.
     An unknown repo is reported only.

Class d cards are sorted into kinds by a rule list (--kinds-file, JSON). Each
rule is {"kind", "owner_rule", "match", "age_report"?}; `match` holds any of
board, created_by (a name or a list), title_prefix, body_prefix, body_contains,
and a card matches a rule when ANY listed key matches. The first matching rule
wins and a card matching none is kind "agent". Without a file the one built-in
rule is the Hermes decomposer: a child it made (created_by auto-decomposer)
belongs to its root card. A rule with "age_report" also prints the kind's age
distribution and that text as a proposed expiry (never applied).

Dry run by default. --apply archives, then drops the matching snapshot lines
(a copy of the snapshot is kept next to it first).

Row source: `git show origin/<default>:<path>` per repo, the same copy the
sweep feeds the mirror, or the working tree with --source working. Megagoal
roadmaps always come from the working tree, as in the mirror.

Usage: board mirror-cleanup [--registry F] [--snapshot F] [--hermes-home D]
         [--kinds-file F] [--source origin|working] [--board NAME]...
         [--apply] [--verbose] [--json]
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

ACTIVE_TARGET = {
    "queued": "triage",
    "claimed": "ready",
    "speccing": "ready",
    "validated": "ready",
    "executing": "ready",
    "parked": "blocked",
}
ID_RE = re.compile(r"^\|\s*([A-Z]+-[0-9]+)\s*\|")
ORIGIN_RE = re.compile(r"^origin:\s*(\S+)", re.M)

DEFAULT_KINDS = [
    {"kind": "decomposer-child",
     "owner_rule": "owned by its root mirror card: archived with the root",
     "match": {"created_by": ["auto-decomposer"]}},
]
FALLBACK_KIND = "agent"
FALLBACK_RULE = "owned by the creating profile: reported only, no automatic close"


def parse_rows(text):
    """id -> set of leading status keywords. Same split as the kit's pb_rows."""
    rows = defaultdict(set)
    for line in text.splitlines():
        m = ID_RE.match(line)
        if not m:
            continue
        cells = line.split("|")
        status = cells[-2].strip() if len(cells) >= 3 else ""
        rows[m.group(1)].add(re.split(r"[ \[(]", status, maxsplit=1)[0].lower())
    return rows


def row_state(statuses):
    """Collapse the statuses one id carries. Active beats terminal, so a
    duplicated row never gets its live card archived."""
    for st in sorted(statuses):
        if st in ACTIVE_TARGET:
            return st
    return sorted(statuses)[0] if statuses else None


def run(cmd, env=None):
    return subprocess.run(cmd, capture_output=True, text=True, env=env)


def git_show_origin(root, relpath):
    """The default-branch copy of a file, or None when there is no remote ref."""
    r = run(["git", "-C", root, "symbolic-ref", "--short", "refs/remotes/origin/HEAD"])
    branch = r.stdout.strip().removeprefix("origin/") if r.returncode == 0 else ""
    for cand in ([branch] if branch else []) + ["main", "master"]:
        r = run(["git", "-C", root, "show", f"origin/{cand}:{relpath}"])
        if r.returncode == 0:
            return r.stdout
    return None


def parse_registry(path):
    out = []
    for line in Path(path).read_text().splitlines():
        parts = line.split()
        if not parts or parts[0].startswith("#"):
            continue
        out.append((parts[0],
                    os.path.expanduser(parts[1]) if len(parts) > 1 else "",
                    len(parts) > 2 and parts[2] == "on"))
    return out


def repo_root_of(path):
    r = run(["git", "-C", str(Path(path).parent), "rev-parse", "--show-toplevel"])
    return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else str(Path(path).parent)


def load_sources(registry, source):
    """repo -> rows, archive-file rows, mega activity, and which copy was read."""
    repos = {}
    for name, bpath, bridged in parse_registry(registry):
        if not bridged:
            continue
        p = Path(bpath)
        if not p.is_file():
            repos[name] = {"missing": True}
            continue
        root = repo_root_of(bpath)
        text, used = None, "working"
        if source == "origin":
            rel = os.path.relpath(os.path.realpath(bpath), os.path.realpath(root))
            text = git_show_origin(root, rel)
            used = "origin" if text is not None else "working (no origin ref)"
        if text is None:
            text = p.read_text()
        archive = p.parent / "BACKLOG-archive.md"
        megas = {}
        mg = Path(root) / "_meta" / "megagoals"
        if mg.is_dir():
            for d in sorted(mg.iterdir()):
                rf = d / "ROADMAP.md"
                if rf.is_file():
                    t = rf.read_text()
                    megas[d.name] = len(re.findall(r"^- \[ \]", t, re.M)) > 0
        repos[name] = {
            "rows": parse_rows(text),
            "archive": parse_rows(archive.read_text()) if archive.is_file() else {},
            "megas": megas,
            "source": used,
        }
    return repos


def hermes(args, home, hermes_bin):
    return run([hermes_bin, "kanban"] + args, env=dict(os.environ, HERMES_HOME=home))


def hermes_json(args, home, hermes_bin):
    r = hermes(args, home, hermes_bin)
    if r.returncode != 0:
        detail = (r.stderr or r.stdout).strip()[:300]
        raise SystemExit(f"hermes kanban {' '.join(args)} failed: {detail}")
    raw = r.stdout.strip()
    return json.loads(raw) if raw else []


def load_kinds(path):
    """The class d rule list: the file when given, else the built-in decomposer rule."""
    if not path:
        return DEFAULT_KINDS
    kinds = json.loads(Path(path).read_text())
    if not isinstance(kinds, list) or not all(isinstance(k, dict) and k.get("kind") for k in kinds):
        raise SystemExit(f"--kinds-file {path}: expected a JSON list of rules, each with a kind")
    return kinds


def rule_matches(match, card, board):
    body = card.get("body") or ""
    title = card.get("title") or ""
    by = card.get("created_by") or ""
    creators = match.get("created_by", [])
    if isinstance(creators, str):
        creators = [creators]
    return any((
        "board" in match and board == match["board"],
        bool(creators) and by in creators,
        "title_prefix" in match and title.startswith(match["title_prefix"]),
        "body_prefix" in match and body.startswith(match["body_prefix"]),
        "body_contains" in match and match["body_contains"] in body,
    ))


def kind_of(card, board, kinds):
    for rule in kinds:
        if rule_matches(rule.get("match", {}), card, board):
            return rule["kind"]
    return FALLBACK_KIND


def classify(card, board, repos, kinds):
    """-> (class, sub-class, detail)"""
    m = ORIGIN_RE.search(card.get("body") or "")
    if not m:
        return "d", kind_of(card, board, kinds), ""
    origin = m.group(1)
    status = card["status"]
    if origin.startswith("megagoals:"):
        repo, _, slug = origin[len("megagoals:"):].partition("/")
        src = repos.get(repo)
        if src is None or src.get("missing"):
            return "e", "repo-not-in-registry", ""
        if slug not in src["megas"]:
            return "c", "mega-roadmap-gone", ""
        if not src["megas"][slug]:
            return "b", "mega-finished", ""
        return ("a", "mega", "") if status == "ready" else ("e", "state-drift", f"{status}->ready")
    repo, _, rid = origin.partition(":")
    src = repos.get(repo)
    if src is None or src.get("missing"):
        return "e", "repo-not-in-registry", ""
    st = row_state(src["rows"].get(rid, set()))
    if st is None:
        if row_state(src["archive"].get(rid, set())) is not None:
            return "b", "in-archive-file", ""
        return "c", "no-row-anywhere", ""
    if st in ACTIVE_TARGET:
        if status == ACTIVE_TARGET[st]:
            return "a", st, ""
        return "e", "state-drift", f"{status}->{ACTIVE_TARGET[st]}"
    return "b", f"row-{st}", ""


def age_buckets(cards, now):
    edges = [(2, "0-1d"), (4, "2-3d"), (8, "4-7d"), (15, "8-14d"), (10**9, "15d+")]
    counts = Counter()
    for card in cards:
        days = (now - (card.get("created_at") or now)) / 86400
        for edge, label in edges:
            if days < edge:
                counts[label] += 1
                break
    return [(label, counts.get(label, 0)) for _, label in edges]


def find_chain(actions, d_cards, args):
    """Decomposer children whose root card is being archived. A decomposed root
    lists its children as `parents`, and `complete` on it fails until they finish,
    which is how a stuck root outlives its row."""
    kids = {c["id"]: b for b, c in d_cards.get("decomposer-child", [])}
    if not kids:
        return []
    archiving = {(a["board"], a["id"]) for a in actions}
    chain = []
    for a in actions:
        if a["board"] not in set(kids.values()):
            continue
        r = hermes(["--board", a["board"], "show", a["id"], "--json"], args.hermes_home, args.hermes)
        if r.returncode != 0:
            continue
        try:
            parents = json.loads(r.stdout).get("parents") or []
        except ValueError:
            continue
        for p in parents:
            kid = p["id"] if isinstance(p, dict) else p
            if kids.get(kid) == a["board"] and (a["board"], kid) not in archiving:
                archiving.add((a["board"], kid))
                chain.append({"board": a["board"], "id": kid, "origin": "",
                              "why": f"d decomposer-child of {a['id']}", "snapshot": False})
    return chain


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    root = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or os.getcwd()
    ap.add_argument("--registry", default=str(Path(root) / "_meta" / "boards.txt"))
    ap.add_argument("--snapshot", default=str(Path(root) / "_meta" / ".board-mirror-snapshot.jsonl"))
    ap.add_argument("--hermes-home", default=os.environ.get("HERMES_HOME"),
                    help="the kanban store to reconcile; default $HERMES_HOME, no other default")
    ap.add_argument("--kinds-file", help="JSON rule list that sorts bot-made (class d) cards into kinds")
    ap.add_argument("--hermes", default=os.environ.get("HERMES_BIN", "hermes"))
    ap.add_argument("--source", choices=("origin", "working"), default="origin")
    ap.add_argument("--board", action="append", help="limit to this board (repeatable); default every board")
    ap.add_argument("--apply", action="store_true", help="archive the cards; default is a dry run")
    ap.add_argument("--verbose", action="store_true", help="list every card with an action")
    ap.add_argument("--json", action="store_true", help="print the summary as JSON")
    args = ap.parse_args(argv)
    if not args.hermes_home:
        raise SystemExit("board mirror-cleanup: need --hermes-home or HERMES_HOME (no default store)")
    kinds = load_kinds(args.kinds_file)
    rules = {k["kind"]: k for k in kinds}

    repos = load_sources(args.registry, args.source)
    boards = hermes_json(["boards", "list", "--json"], args.hermes_home, args.hermes)
    slugs = [b["slug"] for b in boards if not b.get("archived")]
    if args.board:
        slugs = [s for s in slugs if s in args.board]
    now = time.time()

    per_board, closed = {}, Counter()
    actions = []
    d_cards = defaultdict(list)
    for slug in slugs:
        counts = Counter()
        for card in hermes_json(["--board", slug, "list", "--json"], args.hermes_home, args.hermes):
            if card["status"] in ("done", "archived"):
                closed[slug] += 1
                continue
            cls, sub, detail = classify(card, slug, repos, kinds)
            counts[cls] += 1
            counts[f"{cls}:{sub}"] += 1
            if detail:
                counts[f"{cls}:{sub} {detail}"] += 1
            origin = (ORIGIN_RE.search(card.get("body") or "") or [None, ""])[1]
            if cls == "d":
                d_cards[sub].append((slug, card))
            elif cls in ("b", "c") or (cls == "e" and sub == "state-drift"):
                actions.append({"board": slug, "id": card["id"], "origin": origin,
                                "why": f"{cls} {sub} {detail}".strip(), "snapshot": True})
        per_board[slug] = counts
    chain = find_chain(actions, d_cards, args)
    actions.extend(chain)

    open_total = sum(sum(c[k] for k in "abcde") for c in per_board.values())
    if args.json:
        print(json.dumps({
            "open_cards": open_total,
            "actions": len(actions),
            "boards": {s: dict(sorted(c.items())) for s, c in per_board.items()},
            "closed": dict(closed),
            "d_kinds": {k: len(v) for k, v in d_cards.items()},
        }, indent=1, sort_keys=True))
    else:
        print(f"board-mirror-cleanup ({'APPLY' if args.apply else 'DRY RUN'}) registry={args.registry} source={args.source}")
        for name, src in repos.items():
            print(f"  rows {name}: {'MISSING' if src.get('missing') else src['source']}")
        print()
        print(f"{'board':14} {'open':>5} {'a':>5} {'b':>5} {'c':>5} {'d':>5} {'e':>5}  {'closed':>6}")
        tot = Counter()
        for slug in slugs:
            c = per_board[slug]
            for k in "abcde":
                tot[k] += c[k]
            print(f"{slug:14} {sum(c[k] for k in 'abcde'):>5} {c['a']:>5} {c['b']:>5} {c['c']:>5} {c['d']:>5} {c['e']:>5}  {closed[slug]:>6}")
        print(f"{'TOTAL':14} {open_total:>5} {tot['a']:>5} {tot['b']:>5} {tot['c']:>5} {tot['d']:>5} {tot['e']:>5}  {sum(closed.values()):>6}")
        print()
        sub = Counter()
        for c in per_board.values():
            for k, v in c.items():
                if ":" in k:
                    sub[k] += v
        print("sub-classes, all boards:")
        for k, v in sorted(sub.items()):
            print(f"  {k:32} {v}")
        print()
        if d_cards:
            print("class d, bot-made cards, by kind (reported, not touched):")
            for kind, items in sorted(d_cards.items()):
                print(f"  {kind:17} {len(items):>4}  boards={dict(Counter(b for b, _ in items))}")
                rule = rules.get(kind, {})
                print(f"    owner rule: {rule.get('owner_rule', FALLBACK_RULE)}")
                if rule.get("age_report"):
                    print("    age distribution: " + ", ".join(f"{l}={n}" for l, n in age_buckets([c for _, c in items], now)))
                    print(f"    proposed expiry: {rule['age_report']}")
            print()
        stale = sum(1 for a in actions if a["why"][0] in "bc")
        drift = sum(1 for a in actions if a["why"].startswith("e"))
        print(f"actions: {len(actions)} archive ({stale} stale, {drift} wrong-state, {len(chain)} decomposer chain)")
        shown = actions if args.verbose else actions[:12]
        for a in shown:
            print(f"  archive {a['board']}/{a['id']}  {a['origin'] or '-':28} {a['why']}")
        if len(shown) < len(actions):
            print(f"  ... {len(actions) - len(shown)} more (--verbose lists all)")

    if not args.apply:
        return 0

    dropped, errors, archived = set(), 0, 0
    for a in actions:
        r = hermes(["--board", a["board"], "archive", a["id"]], args.hermes_home, args.hermes)
        if r.returncode != 0:
            errors += 1
            print(f"  ERROR archive {a['board']}/{a['id']}: {(r.stderr or r.stdout).strip()[:200]}", file=sys.stderr)
            continue
        archived += 1
        if a["snapshot"] and a["origin"]:
            dropped.add((a["origin"], a["id"]))
    snap = Path(args.snapshot)
    if dropped and snap.is_file():
        backup = snap.with_name(snap.name + f".pre-cleanup-{time.strftime('%Y%m%dT%H%M%S')}")
        shutil.copy2(snap, backup)
        keep, n_dropped = [], 0
        for line in snap.read_text().splitlines():
            if not line.strip():
                continue
            try:
                j = json.loads(line)
            except ValueError:
                keep.append(line)
                continue
            if (j.get("origin"), j.get("hermes_id")) in dropped:
                n_dropped += 1
                continue
            keep.append(line)
        tmp = snap.with_name(snap.name + ".tmp")
        tmp.write_text("\n".join(keep) + ("\n" if keep else ""))
        os.replace(tmp, snap)
        print(f"snapshot: dropped {n_dropped} lines (backup {backup.name})")
    print(f"applied: {archived} archived, {errors} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
