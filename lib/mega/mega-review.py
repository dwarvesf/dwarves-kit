#!/usr/bin/env python3
"""mega-review.py -- `mega review --html <slug>` (SPEC-197, harness-loop sub-goal 07): renders
ONE self-contained static HTML sign-off page per mega-goal, composed from THREE read-only
sources, never a fourth persisted store (SPEC-182 "stats persists nothing" discipline extended
to this surface -- a projection, always safe to re-run, never cached):

  1. ROADMAP.md truth       -- this mega's sub-goal lines + each sub-goal's own goal file
                                (**Branch:** line). Reuses `lib/mega/mega.sh status`'s OWN git-truth
                                reconciliation (OK/CLAIM-UNVERIFIED/MERGED-UNCHECKED/STALLED/
                                WIP/PENDING/INFO) by shelling out to it and parsing its stable,
                                documented per-line format -- ONE classifier, not a second one
                                reimplemented here (mega.sh's own header comment documents the
                                drift-class enum this script's regex depends on).
  2. the gate/run ledger     -- KIT_LOG_DIR/runs/<rid>.log, keyed by rid = the sub-goal's own
                                branch with its leading `type/` segment stripped (gate-ledger.sh
                                `rid()`'s transform, SPEC-070: `${branch#*/}`, then the same
                                runid() charset normalization ledger_file() applies). GATE/
                                OUTCOME line parsing is IMPORTED from `lib/gate/proof-table-gen.py`
                                (`parse_ledger`) rather than re-implemented -- one parser, two
                                consumers, the same cross-subsystem sourcing convention
                                gate-ledger.sh itself uses for lib/telemetry + lib/ledger.
                                TOKENS lines have no reader there, so this module parses them
                                locally (small, ledger-local, not worth importing for).
  3. `gh pr view`             -- PR state / merge state / CI rollup, read fresh every render
                                (never cached, matching the mega's projection discipline).

Best-effort HARNESS-WIDE footer (mega-independent; ADR-0034-adjacent "Learn leg" signals the
goal file requires surfaced HERE because the dashboard is "the one surface with a guaranteed
reader"): staged-candidate count + oldest age (`_meta/backlog-staging.md`, the existing
BACKLOG_STAGE_STAGING seam), learned-ledger queued count (the existing STATS_LEARNED_MD seam,
no kit-side default -- ops-toolkit-specific per lib/stats/src/stats/config.py), unpaid-debt
count (`bin/learn debt list`, its own default 7-day window, labeled honestly).
Every one of the three reads via its OWN pre-existing consumer-config seam; an absent/unset
source renders "-" (honest-dash), NEVER a fabricated zero -- SPEC-197 Design.

Usage: mega-review.py <slug> --megagoals-root DIR --code-root DIR [--base BRANCH] [--out PATH]
Env: KIT_LOG_DIR  the resolved durable ledger root (set by the lib/mega/mega.sh `review` launcher,
     mirroring lib/gate/proof-table-gen.sh's own KIT_ROOT/KIT_LOG_DIR export convention -- this
     script never re-resolves it itself, so there is one resolver, not two).
"""
from __future__ import annotations

import argparse
import datetime
import html as _html
import importlib.util
import json
import os
import re
import subprocess
import sys

_SELF_DIR = os.path.dirname(os.path.abspath(__file__))  # lib/ (mega.sh's own dir; orphan file)


def _load_proof_table_gen():
    """Import lib/gate/proof-table-gen.py's `parse_ledger` + `_normalize_rid` directly (same
    cross-subsystem sourcing convention gate-ledger.sh itself uses for lib/telemetry + lib/ledger
    siblings) instead of re-implementing GATE/OUTCOME line parsing a second time."""
    path = os.path.join(_SELF_DIR, "..", "gate", "proof-table-gen.py")
    spec = importlib.util.spec_from_file_location("proof_table_gen", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


_PTG = _load_proof_table_gen()

_SUBGOAL_LINE_RE = re.compile(r"^- \[(.)\] ([0-9]+-[A-Za-z0-9_-]+)(.*)$")
_STATUS_LINE_RE = re.compile(
    r"^\s*\S\s+(?P<sub>[0-9]+-[A-Za-z0-9_-]+)\s+"
    r"(?P<label>OK|CLAIM-UNVERIFIED|MERGED-UNCHECKED|STALLED|WIP|PENDING|INFO)(?P<extra>.*)$"
)


def _run(argv, cwd=None):
    try:
        return subprocess.run(argv, capture_output=True, text=True, cwd=cwd, check=False, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None


# ---- 1. ROADMAP truth + git-truth classification (delegates to lib/mega/mega.sh status) -----------

def parse_roadmap(roadmap_path):
    """[(box, sub_slug, prose)] in file order. Honest-empty: no matching lines -> []."""
    rows = []
    if not os.path.isfile(roadmap_path):
        return rows
    with open(roadmap_path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = _SUBGOAL_LINE_RE.match(line.rstrip("\n"))
            if m:
                rows.append((m.group(1), m.group(2), m.group(3).strip(" ,")))
    return rows


def git_truth_status(mega_slug, megagoals_root, code_root, base):
    """Shells out to the ALREADY-SHIPPED `lib/mega/mega.sh status` (one classifier, not a second one)
    and parses its stable per-line format into {sub_slug: {label, pr, prstate, branch, commits,
    openpr}}. Never fatal: a `mega.sh status` failure (e.g. no ROADMAP.md) degrades to an empty
    map -- every sub-goal then renders with git-truth fields honest-dash, not a crash."""
    mega_sh = os.path.join(_SELF_DIR, "mega.sh")
    argv = ["bash", mega_sh, "status", mega_slug,
            "--megagoals-root", megagoals_root, "--code-root", code_root, "--base", base]
    res = _run(argv)
    out = {}
    if res is None or not res.stdout:
        return out
    for line in res.stdout.splitlines():
        m = _STATUS_LINE_RE.match(line)
        if not m:
            continue
        extra = m.group("extra")
        pr = re.search(r"PR#(\d+)", extra)
        prstate = re.search(r"PR#\d+\s+\((\w+)\)", extra)
        branch = re.search(r"branch=(\S+)", extra)
        commits = re.search(r"commits=(\d+)", extra)
        openpr = re.search(r"open-PR#(\d+)", extra)
        out[m.group("sub")] = {
            "label": m.group("label"),
            "pr": pr.group(1) if pr else None,
            "prstate": prstate.group(1) if prstate else None,
            "branch": branch.group(1) if branch else None,
            "commits": commits.group(1) if commits else None,
            "openpr": openpr.group(1) if openpr else None,
        }
    return out


_ATTENTION = {
    # label -> (css class, needs-eyes bool: open the <details> by default)
    "OK": ("att-ok", False),
    "INFO": ("att-info", False),
    "WIP": ("att-wip", True),
    "PENDING": ("att-pending", True),
    "CLAIM-UNVERIFIED": ("att-bad", True),
    "MERGED-UNCHECKED": ("att-bad", True),
    "STALLED": ("att-bad", True),
    None: ("att-unknown", True),
}


# ---- 2. the gate/run ledger --------------------------------------------------------------------

def _sanitize_branch_to_rid(branch):
    """gate-ledger.sh `rid()`'s transform (SPEC-070): the branch with its leading `type/`
    segment stripped (`${branch#*/}` -- a no-op if there is no slash at all), then normalized to
    the ledger filename charset via proof-table-gen.py's port of runid()."""
    if not branch:
        return None
    slug = branch.split("/", 1)[-1]
    return _PTG._normalize_rid(slug)  # noqa: SLF001 -- the one sanctioned cross-module reuse point


def ledger_path_for(rid, kit_log_dir):
    if not rid or not kit_log_dir:
        return None
    return os.path.join(kit_log_dir, "runs", f"{rid}.log")


def parse_tokens(ledger_path):
    """Sum every `| TOKENS |` line in the rid's ledger (a sub-goal may build/retry more than
    once; the total is the honest cost, not just the last attempt). None (not zeros) when the
    ledger carries no TOKENS line at all -- honest-absence, never a fabricated 0."""
    totals = {"in": 0, "out": 0, "cache_read": 0, "cache_create": 0}
    if not ledger_path or not os.path.isfile(ledger_path):
        return None
    found = False
    with open(ledger_path, encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.rstrip("\n").split(" | ")
            if len(parts) >= 3 and parts[1] == "TOKENS":
                found = True
                for kv in parts[2].split():
                    if "=" not in kv:
                        continue
                    k, v = kv.split("=", 1)
                    if k in totals:
                        try:
                            totals[k] += int(v)
                        except ValueError:
                            pass
    return totals if found else None


# ---- 3. gh PR / CI / merge state ---------------------------------------------------------------

def pr_state(pr_number, code_root):
    if not pr_number:
        return None
    res = _run(
        ["gh", "pr", "view", str(pr_number), "--json", "state,url,mergedAt,statusCheckRollup,title"],
        cwd=code_root,
    )
    if res is None or res.returncode != 0 or not res.stdout.strip():
        return None
    try:
        data = json.loads(res.stdout)
    except json.JSONDecodeError:
        return None
    rollup = data.get("statusCheckRollup") or []
    ci = "no checks"
    if rollup:
        concl = [str((c.get("conclusion") or c.get("state") or "")).upper() for c in rollup]
        if any(s in ("FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED") for s in concl):
            ci = "failing"
        elif any(s in ("", "PENDING", "IN_PROGRESS", "QUEUED", "EXPECTED") for s in concl):
            ci = "pending"
        else:
            ci = "passing"
    return {
        "state": data.get("state"),
        "url": data.get("url"),
        "mergedAt": data.get("mergedAt"),
        "ci": ci,
        "title": data.get("title"),
    }


# ---- proof-of-done link (best-effort; never fabricated) ----------------------------------------

def find_proof_link(sub_slug, rid, code_root):
    bare = re.sub(r"^[0-9]+-", "", sub_slug)
    candidates = [
        f"docs/verification/generated/{rid}.md" if rid else None,
        f"docs/verification/{rid}.md" if rid else None,
        f"docs/verification/{rid}/proof-of-done.md" if rid else None,
        f"docs/verification/{bare}.md",
        f"docs/verification/{bare}/proof-of-done.md",
    ]
    for c in candidates:
        if c and os.path.isfile(os.path.join(code_root, c)):
            return c
    return None


# ---- footer: harness-wide, best-effort, honest-dash when absent --------------------------------

def _staging_counts(code_root):
    path = os.environ.get("BACKLOG_STAGE_STAGING", os.path.join(code_root, "_meta", "backlog-staging.md"))
    if not os.path.isfile(path):
        return None
    text = open(path, encoding="utf-8", errors="replace").read()
    idxs = [m.start() for m in re.finditer(r"(?m)^##\s*\[", text)]
    n_staged = 0
    dates = []
    for i, s in enumerate(idxs):
        e = idxs[i + 1] if i + 1 < len(idxs) else len(text)
        block = text[s:e]
        head = re.match(r"##\s*\[([^\]]+)\]", block)
        if not head or head.group(1).strip() != "staged":
            continue
        n_staged += 1
        dm = re.search(r"Source:\s*session\s*(\d{4}-\d{2}-\d{2})", block)
        if dm:
            dates.append(dm.group(1))
    if n_staged == 0:
        return {"n": 0, "oldest_days": None}
    oldest_days = None
    if dates:
        oldest = min(dates)
        try:
            d = datetime.date.fromisoformat(oldest)
            # LOCAL date, not UTC: the staging file's `Source: session <date>` is written by
            # hooks/backlog-stage.py via `time.strftime("%Y-%m-%d")` with no explicit UTC
            # conversion, i.e. the writer's OWN local calendar date -- matching that here (rather
            # than a UTC "today") avoids an off-by-one near either day boundary.
            oldest_days = (datetime.date.today() - d).days
        except ValueError:
            oldest_days = None
    return {"n": n_staged, "oldest_days": oldest_days}


def _learned_queued():
    path_env = os.environ.get("STATS_LEARNED_MD")
    if not path_env or not os.path.isfile(path_env):
        return None
    in_ledger = False
    seen_header = False
    n_queued = 0
    with open(path_env, encoding="utf-8", errors="replace") as f:
        for line in f:
            s = line.strip()
            if s.startswith("## "):
                in_ledger = s.lower().startswith("## ledger")
                seen_header = False
                continue
            if not in_ledger or not s.startswith("|"):
                continue
            cells = [c.strip() for c in s.strip("|").split("|")]
            if not seen_header:
                seen_header = True
                continue
            if set("".join(cells)) <= set("-: "):
                continue
            if len(cells) >= 5 and cells[4] == "queued":
                n_queued += 1
    return {"n": n_queued}


def _unpaid_debt_count(code_root):
    wb = os.path.join(_SELF_DIR, "..", "learn", "weekend-batch.sh")
    if not os.path.isfile(wb):
        return None
    res = _run(["bash", wb, "list", "--all-repos"], cwd=code_root)
    if res is None or res.returncode != 0:
        return None
    n = len([ln for ln in res.stdout.splitlines() if ln.strip()])
    return {"n": n}


def footer_counters(code_root):
    return {
        "staged": _staging_counts(code_root),
        "learned_queued": _learned_queued(),
        "unpaid_debt": _unpaid_debt_count(code_root),
    }


# ---- render -------------------------------------------------------------------------------------

_CSS = """
:root { color-scheme: light dark; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  background: #fafafa; color: #111827; margin: 2rem; line-height: 1.4; max-width: 72rem;
}
h1 { font-size: 1.4rem; margin-bottom: 0.25rem; }
h2 { font-size: 1.05rem; margin: 0; }
.meta { color: #6b7280; font-size: 0.85rem; margin-bottom: 1.5rem; }
table { border-collapse: collapse; width: 100%; font-size: 0.85rem; margin: 0.5rem 0 1rem; }
th, td { border: 1px solid #374151; padding: 0.35rem 0.55rem; text-align: left; }
th { background: #f0f0f0; font-weight: 600; }
tr:nth-child(even) { background: #f5f5f5; }
.empty { color: #6b7280; font-style: italic; }
.badge { display: inline-block; padding: 0.1rem 0.5rem; border-radius: 0.75rem; font-size: 0.75rem;
  font-weight: 600; margin-left: 0.5rem; }
.att-ok .badge, .badge.ok { background: #dcfce7; color: #166534; }
.att-info .badge, .badge.info { background: #e5e7eb; color: #374151; }
.att-wip .badge, .badge.wip { background: #dbeafe; color: #1e40af; }
.att-pending .badge, .badge.pending { background: #e5e7eb; color: #374151; }
.att-bad .badge, .badge.bad { background: #fee2e2; color: #991b1b; }
.att-unknown .badge, .badge.unknown { background: #fef3c7; color: #92400e; }
details { border: 1px solid #374151; border-radius: 0.4rem; margin-bottom: 0.6rem; padding: 0.4rem 0.7rem; }
details.att-bad, details.att-unknown { border-left: 5px solid #dc2626; }
details.att-wip, details.att-pending { border-left: 5px solid #2563eb; }
details.att-ok { border-left: 5px solid #16a34a; }
details.att-info { border-left: 5px solid #9ca3af; }
summary { cursor: pointer; font-weight: 600; }
.subline { color: #6b7280; font-size: 0.85rem; margin: 0.3rem 0; }
.banner { background: #fef3c7; color: #92400e; border: 1px solid #f59e0b; border-radius: 0.4rem;
  padding: 0.6rem 0.9rem; margin-bottom: 1rem; }
footer { margin-top: 2rem; padding-top: 0.75rem; border-top: 1px solid #374151; font-size: 0.85rem; }
@media (prefers-color-scheme: dark) {
  body { background: #111827; color: #f9fafb; }
  th { background: #1f2937; }
  tr:nth-child(even) { background: #1a2233; }
  th, td { border-color: #4b5563; }
  details { border-color: #4b5563; }
  .banner { background: #422006; color: #fde68a; border-color: #b45309; }
  footer { border-color: #4b5563; }
}
""".strip()


def _e(v):
    return _html.escape("" if v is None else str(v))


def render_gate_table(gate_rows, outcomes, tokens):
    if not gate_rows:
        # Honest-empty (SPEC-197): distinguish "no ledger at all" from the narrower "ledger
        # exists but carries no GATE row" (e.g. a rid whose file has only OUTCOME/TOKENS lines)
        # -- never claim "no ledger rows" when rows of a DIFFERENT marker type are present.
        if outcomes:
            return '<p class="empty">(no GATE rows recorded for this sub-goal -- OUTCOME markers exist with no paired GATE row)</p>'
        return '<p class="empty">(no ledger rows for this sub-goal)</p>'
    has_outcomes = bool(outcomes)
    cols = ["Phase", "When", "State", "Reason"] + (["Caught", "Duration (s)"] if has_outcomes else [])
    out = ["<table>", "<thead><tr>" + "".join(f"<th>{_e(c)}</th>" for c in cols) + "</tr></thead>", "<tbody>"]
    for r in gate_rows:
        cells = [r["phase"], r["ts"], r["state"], r["reason"] or ""]
        if has_outcomes:
            o = outcomes.get(r["phase"]) or {}
            cells += [o.get("caught") or "n/a", o.get("dur_s") or "n/a"]
        out.append("<tr>" + "".join(f"<td>{_e(c)}</td>" for c in cells) + "</tr>")
    out.append("</tbody></table>")
    if tokens:
        out.append(
            f'<p class="subline">tokens: in={tokens["in"]} out={tokens["out"]} '
            f'cache_read={tokens["cache_read"]} cache_create={tokens["cache_create"]}</p>'
        )
    else:
        out.append('<p class="subline">tokens: <span class="empty">-</span> (no TOKENS line recorded)</p>')
    return "\n".join(out)


def render_subgoal(box, sub_slug, prose, truth, ledger_path, code_root):
    lane, gate_rows, outcomes = (None, [], {})
    if ledger_path and os.path.isfile(ledger_path):
        lane, gate_rows, outcomes = _PTG.parse_ledger(ledger_path)
    tokens = parse_tokens(ledger_path)

    label = truth.get("label") if truth else None
    css_class, open_by_default = _ATTENTION.get(label, _ATTENTION[None])
    pr = truth.get("pr") if truth else None
    prstate = truth.get("prstate") if truth else None
    branch = truth.get("branch") if truth else None
    prinfo = pr_state(pr, code_root) if pr else None

    rid = _sanitize_branch_to_rid(branch) if branch else None
    proof = find_proof_link(sub_slug, rid, code_root)

    badge = f'<span class="badge {css_class.replace("att-", "")}">{_e(label or "UNKNOWN")}</span>'
    open_attr = " open" if open_by_default else ""

    lines = [f'<details class="{css_class}"{open_attr}>']
    lines.append(f"<summary><h2 style=\"display:inline\">[{_e(box)}] {_e(sub_slug)}</h2>{badge}</summary>")
    if prose:
        lines.append(f'<p class="subline">{_e(prose)}</p>')

    pr_bits = []
    if pr:
        pr_bits.append(f"PR #{_e(pr)}" + (f" ({_e(prstate)})" if prstate else ""))
    if prinfo:
        merged = f", merged {_e(prinfo['mergedAt'])}" if prinfo.get("mergedAt") else ""
        pr_bits.append(f"CI: {_e(prinfo['ci'])}{merged}")
        if prinfo.get("url"):
            pr_bits.append(f'<a href="{_e(prinfo["url"])}">{_e(prinfo["url"])}</a>')
    if branch:
        pr_bits.append(f"branch={_e(branch)}")
    lines.append(f'<p class="subline">{" &middot; ".join(pr_bits) if pr_bits else "<span class=\'empty\'>no PR/branch data</span>"}</p>')

    lines.append(render_gate_table(gate_rows, outcomes, tokens))

    if proof:
        lines.append(f'<p class="subline">proof-of-done: <a href="{_e(proof)}">{_e(proof)}</a></p>')
    else:
        lines.append('<p class="subline">proof-of-done: <span class="empty">(unlinked -- best-effort search found no file; check RUN_REPORT.md)</span></p>')

    lines.append("</details>")
    return "\n".join(lines), bool(gate_rows)


def render_footer(counters):
    def fmt_staged(v):
        if v is None:
            return "staged candidates: -"
        if v["n"] == 0:
            return "staged candidates: 0"
        age = f", oldest {v['oldest_days']}d" if v["oldest_days"] is not None else ""
        return f"staged candidates: {v['n']}{age}"

    def fmt_learned(v):
        return f"learned-ledger queued: {v['n']}" if v else "learned-ledger queued: -"

    def fmt_debt(v):
        return f"unpaid debt (7d window): {v['n']}" if v else "unpaid debt: -"

    return (
        "<footer>"
        f"<div>{_e(fmt_staged(counters['staged']))}</div>"
        f"<div>{_e(fmt_learned(counters['learned_queued']))}</div>"
        f"<div>{_e(fmt_debt(counters['unpaid_debt']))}</div>"
        "</footer>"
    )


def render_html(slug, roadmap_rows, truth_map, kit_log_dir, code_root, footer):
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    body = []
    any_ledger = False

    if not roadmap_rows:
        body.append(
            '<div class="banner">No sub-goal lines found in this mega\'s ROADMAP.md. '
            "Nothing to compose -- this is not an error, the mega may not exist yet or its "
            "ROADMAP grammar does not match the documented `- [ ] NN-slug ...` shape.</div>"
        )
    else:
        for box, sub_slug, prose in roadmap_rows:
            truth = truth_map.get(sub_slug)
            branch = truth.get("branch") if truth else None
            rid = _sanitize_branch_to_rid(branch) if branch else None
            ledger_path = ledger_path_for(rid, kit_log_dir)
            html_chunk, had_ledger = render_subgoal(box, sub_slug, prose, truth, ledger_path, code_root)
            any_ledger = any_ledger or had_ledger
            body.append(html_chunk)
        if not any_ledger:
            body.insert(
                0,
                '<div class="banner">No ledger rows found for ANY sub-goal in this mega yet. '
                "Every group below reflects ROADMAP + git-truth only; re-render once gates have "
                "been recorded. Never fabricated.</div>",
            )

    return (
        "<!doctype html>\n"
        '<html><head><meta charset="utf-8">'
        f"<title>mega review: {_e(slug)}</title>"
        f"<style>{_CSS}</style>"
        "</head><body>"
        f"<h1>mega review: {_e(slug)}</h1>"
        f'<p class="meta">generated {_e(now)} &middot; a projection over the run ledger + gh + '
        "proof paths, never a stored source of truth (SPEC-197). Re-render to refresh.</p>"
        + "\n".join(body)
        + render_footer(footer)
        + "</body></html>"
    )


def main(argv=None):
    ap = argparse.ArgumentParser(prog="mega-review.py")
    ap.add_argument("slug")
    ap.add_argument("--megagoals-root", required=True)
    ap.add_argument("--code-root", required=True)
    ap.add_argument("--base", default="master")
    ap.add_argument("--out", default=None)
    args = ap.parse_args(argv)

    # Security hardening (review finding, non-exploitable today -- the only two callers are
    # lib/queue/orchestrate.sh's own locally-derived basename and a trusted local CLI
    # invocation, never a webhook/network trigger -- but cheap and worth closing): a slug
    # carrying a path separator could otherwise write REVIEW.html outside megagoals-root via
    # os.path.join's own "absolute/.. wins" semantics. Same charset lib/mega/mega.sh's ROADMAP
    # sub-goal regex already requires (`[0-9]+-[A-Za-z0-9_-]+`), loosened only to allow the
    # mega SLUG shape (letters/digits/dot/underscore/dash, no leading number requirement).
    if not re.match(r"^[A-Za-z0-9._-]+$", args.slug):
        print(f"mega-review: slug '{args.slug}' contains characters outside [A-Za-z0-9._-]", file=sys.stderr)
        return 64

    mega_dir = os.path.join(args.megagoals_root, args.slug)
    roadmap_path = os.path.join(mega_dir, "ROADMAP.md")
    if not os.path.isfile(roadmap_path):
        print(f"mega-review: no ROADMAP.md at {roadmap_path}", file=sys.stderr)
        return 1

    kit_log_dir = os.environ.get("KIT_LOG_DIR")
    roadmap_rows = parse_roadmap(roadmap_path)
    truth_map = git_truth_status(args.slug, args.megagoals_root, args.code_root, args.base)
    footer = footer_counters(args.code_root)

    out_html = render_html(args.slug, roadmap_rows, truth_map, kit_log_dir, args.code_root, footer)

    out_path = args.out or os.path.join(mega_dir, "REVIEW.html")
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(out_html)
    print(out_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
