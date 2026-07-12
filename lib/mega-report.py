#!/usr/bin/env python3
"""mega-report.py -- the python half of `mega report <slug>` (the RUN_REPORT generator).

Renders the telemetry skeleton of a mega-goal's RUN_REPORT.md from the two mechanical
sources -- the rid ledgers (gate-ledger rows under $KIT_LOG_DIR/runs/) and the mega's
ROADMAP.md -- and emits labeled STUBS for the sections only the conductor knows
(worker minutes, callable stack, incidents). Markdown to stdout; --out writes a file.

Why this exists (the fold-in gap, Han 2026-07-12): /kit:mega and the mega-goal skill
both required a telemetry close ("gate matrix + callable stack, read from the rid
ledger"), but no code could RENDER it -- the presentation lived as conductor habit from
the pre-fold era and died in the migration; harness-loop's matrix got rebuilt by hand.
This makes the close mechanical: the same three blocks, every run, from the ledger.

Read-only over every source. The ONLY write is --out, and only when passed.

Rid resolution per sub-goal: the ledger rid is the branch slug (SPEC-070), which the
ROADMAP does not carry, so we match runs/<rid>.log by token: the rid must contain the
sub-goal's name tokens (the NN- prefix stripped). Ambiguity -> the longest-name match;
none -> an honest all-"-" row (never a guess). --rid-map "SG=rid,SG=rid" overrides.
"""

import argparse
import os
import re
import sys

# Column order mirrors the WORKFLOW lane x phase matrix; "validate" is the ledger's
# short name for spec-validate (both appear in live corpora, fold them together).
GATES = [
    ("gr", ["grill"]),
    ("th", ["think"]),
    ("de", ["design"]),
    ("dc", ["design-critique"]),
    ("sp", ["spec"]),
    ("sv", ["spec-validate", "validate"]),
    ("dr", ["design-record"]),
    ("tp", ["test-plan"]),
    ("bu", ["build"]),
    ("re", ["review"]),
    ("do", ["docs"]),
    ("sh", ["ship"]),
    ("rf", ["reflect"]),
]
KNOWN = {name for _, names in GATES for name in names}
LEGEND = ("gr grill · th think · de design · dc design-critique · sp spec · "
          "sv spec-validate · dr design-record · tp test-plan · bu build · "
          "re review · do docs · sh ship · rf reflect")

SUBGOAL_RE = re.compile(r"^- \[(x| )\] (\d+[A-Za-z]?)-([a-z0-9-]+)")
PR_RE = re.compile(r"PR #(\d+)")
SHA_RE = re.compile(r"merged ([0-9a-f]{7,40})")
SPEC_RE = re.compile(r"SPEC-(\d+)")
TOKENS_RE = re.compile(r"in=(\d+) out=(\d+)")


def parse_roadmap(path):
    subgoals = []
    for line in open(path, encoding="utf-8"):
        m = SUBGOAL_RE.match(line)
        if not m:
            continue
        checked, num, name = m.group(1) == "x", m.group(2), m.group(3)
        pr = PR_RE.search(line)
        sha = SHA_RE.search(line)
        subgoals.append({
            "num": num, "name": name, "checked": checked,
            "pr": pr.group(1) if pr else None,
            "sha": sha.group(1)[:7] if sha else None,
            "spec": None,  # resolved from the goal file, ROADMAP prose is unreliable
            "tag": "gate" if "`gate`" in line else ("auto" if "`auto`" in line else "?"),
            "gate": "`gate`" in line,
            "line": line.rstrip(),
        })
    return subgoals


def resolve_spec(sg, mega_dir):
    """SPEC-ref from the goal file's own **Proof:** line ONLY. Anywhere else (ROADMAP
    prose, goal-file body) names OTHER specs ('the SPEC-188 lint amended', a SPEC-097
    cross-ref) and misattributes; a spec-less sub-goal honestly renders '-'."""
    import glob as _g
    for gf in _g.glob(os.path.join(mega_dir, "goals", sg["num"] + "-*.md")):
        for line in open(gf, encoding="utf-8"):
            if line.startswith("**Proof:**"):
                m = SPEC_RE.search(line)
                return m.group(1) if m else None
    return None


def resolve_rid(sg, rids, rid_map, log_dir=""):
    key = f"{sg['num']}-{sg['name']}"
    if key in rid_map:
        return rid_map[key]
    # token match: every hyphen token of the name must appear in the rid; prefer the
    # rid sharing the most tokens, then the shortest (least extra baggage).
    tokens = sg["name"].split("-")
    num_tag = sg["num"] + "-"
    scored = []
    for rid in rids:
        hits = sum(1 for t in tokens if t in rid)
        if not hits:
            continue
        bonus = 2 if num_tag in rid else 0
        scored.append((hits + bonus, -len(rid), rid, hits))
    if not scored:
        return None
    scored.sort(reverse=True)
    top_score = scored[0][0]
    tied = [t for t in scored if t[0] == top_score]
    if len(tied) > 1 and log_dir:
        # tie-break by richest ledger: the rid with the most GATE rows is the run of
        # record (a stray same-name branch, e.g. an operator reconcile rid, has few/none)
        def gate_rows(rid):
            led = parse_ledger(log_dir, rid)
            return len(led["gates"]) if led else -1
        tied.sort(key=lambda t: gate_rows(t[2]), reverse=True)
        best, hits = tied[0][2], tied[0][3]
    else:
        best, hits = scored[0][2], scored[0][3]
    # require at least half the NAME tokens to hit, else honest-miss
    return best if hits * 2 >= len(tokens) else None


def parse_ledger(log_dir, rid):
    rows, tok_in, tok_out = {}, 0, 0
    path = os.path.join(log_dir, "runs", rid + ".log")
    if not os.path.isfile(path):
        return None
    for line in open(path, encoding="utf-8", errors="replace"):
        parts = [c.strip() for c in line.split("|")]
        if len(parts) >= 5 and parts[1] == "GATE":
            rows[parts[2]] = parts[3]  # last write wins (append-only, last is current)
        elif len(parts) >= 3 and parts[1] == "TOKENS":
            m = TOKENS_RE.search(line)
            if m:
                tok_in += int(m.group(1)); tok_out += int(m.group(2))
    return {"gates": rows, "tok_in": tok_in, "tok_out": tok_out}


def cell(rows, names):
    for n in names:
        v = rows.get(n)
        if v == "ran":
            return "●"
        if v in ("skipped", "override"):
            return "○"
    return "-"


def main():
    ap = argparse.ArgumentParser(prog="mega report")
    ap.add_argument("slug")
    ap.add_argument("--megagoals-root", required=True)
    ap.add_argument("--log-dir", default=os.environ.get("KIT_LOG_DIR", ""))
    ap.add_argument("--rid-map", default="", help="NN-name=rid,... overrides")
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    mega_dir = os.path.join(args.megagoals_root, args.slug)
    roadmap = os.path.join(mega_dir, "ROADMAP.md")
    if not os.path.isfile(roadmap):
        sys.stderr.write(f"mega report: no ROADMAP.md at {roadmap}\n")
        return 1
    if not args.log_dir:
        sys.stderr.write("mega report: KIT_LOG_DIR unresolved (pass --log-dir)\n")
        return 1

    rid_map = dict(kv.split("=", 1) for kv in args.rid_map.split(",") if "=" in kv)
    runs_dir = os.path.join(args.log_dir, "runs")
    rids = [f[:-4] for f in os.listdir(runs_dir)] if os.path.isdir(runs_dir) else []

    subgoals = parse_roadmap(roadmap)
    if not subgoals:
        sys.stderr.write("mega report: no sub-goal lines parsed from ROADMAP.md\n")
        return 1

    built = sum(1 for s in subgoals if s["checked"])
    merged = sum(1 for s in subgoals if s["sha"])
    held = [s for s in subgoals if s["pr"] and not s["sha"]]
    held_note = f" · #{held[-1]['pr']} final open + held" if held else ""

    out = []
    out.append(f"`RUN_REPORT , {args.slug} ({built}/{len(subgoals)} built · {merged} merged{held_note})`")
    out.append("")
    out.append("### Worker minutes by model")
    out.append("")
    out.append("```")
    out.append("<model> |<bar>| ~Nm (N%)  <runs> , <what ran there>   [FILL: conductor knowledge;")
    out.append("token totals below come from the ledger where TOKENS rows exist, honest-dash otherwise]")

    tok_lines = []
    for sg in subgoals:
        rid = resolve_rid(sg, rids, rid_map, args.log_dir)
        led = parse_ledger(args.log_dir, rid) if rid else None
        sg["rid"], sg["led"] = rid, led
        if led and (led["tok_in"] or led["tok_out"]):
            tok_lines.append(f"{sg['num']}-{sg['name']}: in={led['tok_in']} out={led['tok_out']} (rid {rid})")
    out.extend(tok_lines if tok_lines else ["ledgered tokens: , (no TOKENS rows in any matched rid)"])
    out.append("```")
    out.append("")
    out.append("### Gate coverage (● recorded-ran · ○ skipped/override-with-reason · - n/a), from each rid's gate-ledger rows")
    out.append("")
    out.append("```")
    header = " " * 20 + " ".join(ab for ab, _ in GATES) + "   tag   SPEC"
    out.append(header)
    extras = []
    for sg in subgoals:
        led = sg["led"]
        if led is None:
            cells = "  ".join("-" for _ in GATES)
            note = "(no rid ledger matched)" if sg["rid"] is None else f"(rid {sg['rid']}: no log)"
        else:
            cells = "  ".join(cell(led["gates"], names) for _, names in GATES)
            unknown = sorted(set(led["gates"]) - KNOWN)
            note = ""
            if unknown:
                extras.append(f"{sg['num']}-{sg['name']}: extra ledger gates {unknown}")
        label = f"{sg['num']} {sg['name']}"[:19]
        tag = sg["tag"].ljust(5)
        spec = resolve_spec(sg, mega_dir) or "-"
        flag = "  (GATE)" if sg["gate"] else ""
        out.append(f"{label:<20}{cells}   {tag} {spec}{flag} {note}".rstrip())
    out.append("```")
    out.append(LEGEND + ".")
    for e in extras:
        out.append(f"note: {e}")
    out.append("[FILL: one line , did any gate REQUIREMENT change anywhere? it should read \"none\".]")
    out.append("")
    out.append("### Callable stack")
    out.append("")
    out.append("```")
    out.append("[FILL: conductor tree , run mode line (subagent-delegate / claude -p / inline),")
    out.append("one node per wave, one child per worker. Mechanical skeleton from the ROADMAP:]")
    for sg in subgoals:
        pr = f"#{sg['pr']}" if sg["pr"] else "PR ,"
        sha = f"merged {sg['sha']}" if sg["sha"] else ("open + held" if sg["pr"] else ",")
        out.append(f"├─ {sg['num']} {sg['name']:<22} <model>  {pr:<6} {sha}")
    out.append("```")
    out.append("")
    out.append("### Incidents & lessons")
    out.append("")
    out.append("[FILL from NOTES.md ## Event log + ## Active blockers: only what the harness")
    out.append("actually caught, numbered, each ending in the lesson baked forward.]")
    out.append("")

    text = "\n".join(out) + "\n"
    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(text)
        print(f"mega report: wrote {args.out}")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
