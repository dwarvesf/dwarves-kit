#!/usr/bin/env python3
"""proof-table-gen.py -- generate the SPEC-016 table-first proof-of-done confirmation
run-table from a rid's gate/run ledger (SPEC-132). Never hand-authored; run again to
regenerate.

Hard rule (docs/verification/README.md: "Generators write run ledgers, never the
canonical"): this script refuses to write to any out-path whose basename is literally
`proof-of-done.md`, the exact filename `lib/proof-ledger.sh` keys the ship-gate on. The
default out-path is always under `docs/runs/`.

Parses three ledger line shapes (space-pipe-split, the same convention
`lib/gate-ledger.sh`'s own awk uses):
  TS | START | lane=<l> classified=<c> type=<t> [ctype=<ct>] repo=<r>
  TS | GATE | <phase> | ran|skipped|override | [reason]
  TS | OUTCOME | <phase> | start | at=<epoch>
  TS | OUTCOME | <phase> | end | at=<epoch> caught=<true|false> dur_s=<N>

The OUTCOME line is sub-goal 01's REAL, now-merged marker shape (gate-outcome-emit,
SPEC-129's `outcome()`/`outcome_read()` in lib/gate-ledger.sh): a start/end pair per
phase (field 3 = phase, field 4 = event `start|end`); `caught=`/`dur_s=` appear only on
the `end` line, duration in SECONDS (not the `dur_ms` this parser assumed before
SPEC-129 merged). Additive-tolerant: an entirely absent OUTCOME marker degrades the
table (fewer columns), never crashes.

Usage: proof-table-gen.py <rid> [out-path]
Env (set by the lib/proof-table-gen.sh wrapper, not re-derived here):
  KIT_ROOT     kit repo root
  KIT_LOG_DIR  resolved durable log dir (lib/kit-log-dir.sh's kit_resolve_log_dir)
"""
import os
import re
import subprocess
import sys

CANONICAL_BASENAME = "proof-of-done.md"


def fail(msg, code=1):
    print(f"proof-table-gen: {msg}", file=sys.stderr)
    sys.exit(code)


def parse_ledger(ledger_path):
    lane = None
    gate_rows = []       # ordered list of dict(ts, phase, state, reason)
    outcomes = {}        # phase -> dict(caught, dur_s)  (last END line per phase wins)
    starts = {}          # phase -> start epoch (from the `start` line's at=), fallback-only

    if not os.path.isfile(ledger_path):
        return lane, gate_rows, outcomes

    with open(ledger_path, encoding="utf-8", errors="replace") as f:
        raw_lines = f.read().splitlines()

    for line in raw_lines:
        if not line.strip():
            continue
        parts = line.split(" | ")
        if len(parts) < 2:
            continue
        ts, marker = parts[0], parts[1]

        if marker in ("START", "START-AMEND") and len(parts) >= 3:
            m = re.search(r"lane=(\S+)", parts[2])
            if m:
                lane = m.group(1)

        elif marker == "GATE" and len(parts) >= 4:
            phase = parts[2]
            state = parts[3]
            reason = " | ".join(parts[4:]) if len(parts) > 4 else ""
            gate_rows.append({"ts": ts, "phase": phase, "state": state, "reason": reason})

        elif marker == "OUTCOME" and len(parts) >= 4:
            # Real shape (SPEC-129): field 3 = phase, field 4 = event (start|end); the
            # kv blob (caught=/dur_s=) lives only on the end line.
            phase = parts[2]
            event = parts[3]
            kv_blob = parts[4] if len(parts) > 4 else ""

            if event == "start":
                m_at = re.search(r"\bat=(\d+)", kv_blob)
                if m_at:
                    starts[phase] = m_at.group(1)
                continue

            if event != "end":
                continue

            caught = None
            dur_s = None
            mcaught = re.search(r"caught=(\S+)", kv_blob)
            if mcaught:
                caught = mcaught.group(1)
            mdur = re.search(r"dur_s=(\S+)", kv_blob)
            if mdur:
                dur_s = mdur.group(1)
            if dur_s is None:
                # Fallback: derive duration from this end line's at= minus the matching
                # start line's at=, same epoch-delta the emitter itself uses.
                m_end_at = re.search(r"\bat=(\d+)", kv_blob)
                start_epoch = starts.get(phase)
                if m_end_at and start_epoch:
                    delta = int(m_end_at.group(1)) - int(start_epoch)
                    if delta >= 0:
                        dur_s = str(delta)
            if caught is not None or dur_s is not None:
                outcomes[phase] = {"caught": caught, "dur_s": dur_s}

    return lane, gate_rows, outcomes


def gate_ledger_sh(kit_root):
    return os.path.join(kit_root, "lib", "gate-ledger.sh")


def required_phases(kit_root, lane):
    """Reuse gate-ledger.sh's own required-gate list; never re-derive it by hand."""
    try:
        res = subprocess.run(
            ["bash", gate_ledger_sh(kit_root), "required", lane],
            capture_output=True, text=True, cwd=kit_root, check=False,
        )
    except OSError:
        return None
    if res.returncode != 0:
        return None
    return sorted({p.strip() for p in res.stdout.splitlines() if p.strip()})


def acceptance_status(kit_root, lane, rid):
    """Reuse gate-ledger.sh check -- the exact pass/fail contract ship-gate enforces."""
    try:
        res = subprocess.run(
            ["bash", gate_ledger_sh(kit_root), "check", lane, rid],
            capture_output=True, text=True, cwd=kit_root, check=False,
        )
    except OSError:
        return "n/a (gate-ledger.sh unavailable)"
    return "PASS" if res.returncode == 0 else "FAIL"


def render(rid, ledger_path, kit_root, lane, gate_rows, outcomes):
    has_outcomes = len(outcomes) > 0

    covered = sorted({r["phase"] for r in gate_rows if r["state"] in ("ran", "override")})
    lane_line = lane if lane else "n/a (no START line for this rid; lane unknown)"
    uncovered = None
    if lane:
        req = required_phases(kit_root, lane)
        if req is not None:
            uncovered = sorted(set(req) - set(covered))

    accept_status = acceptance_status(kit_root, lane, rid) if lane else "n/a (lane unknown)"

    out = []
    out.append(f"# Generated proof-table: {rid}")
    out.append("")
    out.append(
        "> GENERATED by `lib/proof-table-gen.sh` from the gate/run ledger "
        f"(`{ledger_path}`). Do NOT hand-edit -- regenerate instead. Companion "
        "run-table, not the canonical `proof-of-done.md` (SPEC-016: generators write "
        "under `docs/runs/`, never the canonical)."
    )
    out.append("")
    out.append(f"Lane: {lane_line}")
    out.append("")
    out.append("## 1. Acceptance criteria")
    out.append("")
    out.append("| # | Criterion | Status | Evidence |")
    out.append("|---|---|---|---|")
    out.append(
        f"| 1 | Every required gate for lane `{lane_line}` has a ran/override entry "
        f"| {accept_status} | `bash lib/gate-ledger.sh check {lane_line} {rid}` |"
    )
    out.append("")
    out.append("## 2. Confirmation (gate runs)")
    out.append("")
    if has_outcomes:
        out.append("| # | Phase | When (ISO8601) | State | Reason | Caught | Duration (s) |")
        out.append("|---|---|---|---|---|---|---|")
    else:
        out.append("| # | Phase | When (ISO8601) | State | Reason |")
        out.append("|---|---|---|---|---|")
    if gate_rows:
        for i, r in enumerate(gate_rows, 1):
            reason = r["reason"] or ""
            if has_outcomes:
                o = outcomes.get(r["phase"])
                caught = o["caught"] if o and o["caught"] else "n/a"
                dur = o["dur_s"] if o and o["dur_s"] else "n/a"
                out.append(f"| {i} | {r['phase']} | {r['ts']} | {r['state']} | {reason} | {caught} | {dur} |")
            else:
                out.append(f"| {i} | {r['phase']} | {r['ts']} | {r['state']} | {reason} |")
    else:
        cols = 7 if has_outcomes else 5
        out.append("| " + " | ".join(["(none -- empty ledger)"] + [""] * (cols - 1)) + " |")
    out.append("")
    out.append("## 3. Coverage-delta")
    out.append("")
    out.append(f"- Covered: {', '.join(covered) if covered else '(none)'}")
    if uncovered is not None:
        out.append(f"- Uncovered: {', '.join(uncovered) if uncovered else '(none -- every required gate covered)'}")
    else:
        out.append("- Uncovered: n/a (lane unknown; no START line for this rid)")
    out.append("")
    out.append("## 4. Reproduce")
    out.append("")
    out.append(f"`bash lib/proof-table-gen.sh {rid}`")
    out.append(f"(reads `{ledger_path}`; regenerating overwrites only this generated file, never the canonical.)")
    out.append("")
    return "\n".join(out) + "\n"


def main(argv):
    if len(argv) < 2:
        fail("usage: proof-table-gen.py <rid> [out-path]", 64)
    rid = argv[1]

    kit_root = os.environ.get("KIT_ROOT")
    log_dir = os.environ.get("KIT_LOG_DIR")
    if not kit_root or not log_dir:
        fail(
            "KIT_ROOT and KIT_LOG_DIR must be set (invoke via lib/proof-table-gen.sh, "
            "not this script directly)",
            64,
        )

    out_path = argv[2] if len(argv) > 2 else os.path.join(kit_root, "docs", "runs", f"{rid}.md")

    # Hard backstop (SPEC-016 / SPEC-132 AC5): refuse the canonical filename regardless of
    # caller intent -- a code-level guard, not just a convention followed by discipline.
    if os.path.basename(out_path) == CANONICAL_BASENAME:
        fail(
            f"refusing to write '{out_path}': basename is the canonical "
            f"'{CANONICAL_BASENAME}' (see docs/verification/README.md); this generator "
            "only writes run-table companions under docs/runs/",
            1,
        )

    ledger_path = os.path.join(log_dir, "runs", f"{rid}.log")
    lane, gate_rows, outcomes = parse_ledger(ledger_path)
    content = render(rid, ledger_path, kit_root, lane, gate_rows, outcomes)

    out_dir = os.path.dirname(out_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(content)

    print(
        f"wrote {out_path} (rid={rid}, lane={lane or 'unknown'}, "
        f"gates={len(gate_rows)}, outcomes={len(outcomes)})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
