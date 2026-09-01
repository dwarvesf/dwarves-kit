#!/usr/bin/env python3
"""proof-table-gen.py -- generate the SPEC-016 table-first proof-of-done confirmation
run-table from a rid's gate/run ledger (SPEC-132). Never hand-authored; run again to
regenerate.

Hard rule (docs/verification/README.md: "Generators write run ledgers, never the
canonical"): this script refuses to write to any out-path whose basename is literally
`proof-of-done.md`, the exact filename `lib/gate/proof-ledger.sh` keys the ship-gate on.

Path safety (SPEC-134): `rid` is CALLER-controlled, so it is normalized to
`lib/gate/gate-ledger.sh`'s `runid()` charset before it touches ANY path (read ledger + default
write), and the FINAL resolved out-path is confined under `realpath(KIT_ROOT/docs/verification/generated)` --
enforced EVEN for an explicit out-path arg. So the default out-path is always under
`docs/verification/generated/`, and no `rid` or explicit path can escape it (the guarantee this docstring
makes is now enforced, not merely asserted).

Parses three ledger line shapes (space-pipe-split, the same convention
`lib/gate/gate-ledger.sh`'s own awk uses):
  TS | START | lane=<l> classified=<c> type=<t> [ctype=<ct>] repo=<r>
  TS | GATE | <phase> | ran|skipped|override | [reason]
  TS | OUTCOME | <phase> | start | at=<epoch>
  TS | OUTCOME | <phase> | end | at=<epoch> caught=<true|false> dur_s=<N>

The OUTCOME line is sub-goal 01's REAL, now-merged marker shape (gate-outcome-emit,
SPEC-129's `outcome()`/`outcome_read()` in lib/gate/gate-ledger.sh): a start/end pair per
phase (field 3 = phase, field 4 = event `start|end`); `caught=`/`dur_s=` appear only on
the `end` line, duration in SECONDS (not the `dur_ms` this parser assumed before
SPEC-129 merged). Additive-tolerant: an entirely absent OUTCOME marker degrades the
table (fewer columns), never crashes.

Usage: proof-table-gen.py <rid> [out-path]
Env (set by the lib/gate/proof-table-gen.sh wrapper, not re-derived here):
  KIT_ROOT     kit repo root
  KIT_LOG_DIR  resolved durable log dir (lib/telemetry/kit-log-dir.sh's kit_resolve_log_dir)
"""
import os
import re
import subprocess
import sys

CANONICAL_BASENAME = "proof-of-done.md"


def _normalize_rid(raw):
    """Normalize a caller-supplied rid to lib/gate/gate-ledger.sh's runid() charset (SPEC-134).
    runid() is `tr '/ ' '--' | tr -cd '[:alnum:]._-'`: replace '/' and space with '-', then
    drop every char outside [A-Za-z0-9._-]. This strips path separators (no '/' survives, so
    no `..` can act as a parent-dir step) before the rid is ever joined into a filesystem path.
    We match runid()'s ASCII intent but are DELIBERATELY STRICTER: this port is pure ASCII,
    whereas GNU tr's `[:alnum:]` is locale-aware and MAY admit multibyte alnums under a UTF-8
    locale (runid() pins no LC_ALL=C). The Python side only ever strips MORE, so this is never
    a path-escape; on an exotic multibyte rid the two could disagree on the exact filename (a
    correctness edge, not a security one). Real rids are ASCII branch slugs, so they agree."""
    swapped = raw.replace("/", "-").replace(" ", "-")
    return re.sub(r"[^A-Za-z0-9._-]", "", swapped)


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


def _kit_lib_root():
    """The REAL repo root (parent of this module's lib/ dir). SPEC-134 decouples helper-script
    location from KIT_ROOT: gate-ledger.sh is a sibling of this module and always lives in the
    real repo, whereas KIT_ROOT is now purely the output-confinement anchor (which a test may
    point at a throwaway dir). Resolving the helper via __file__ keeps `required`/`check` reading
    the real WORKFLOW.md even when KIT_ROOT is overridden.

    This module lives at lib/gate/proof-table-gen.py, so the repo root is three
    dirnames up (gate/ -> lib/ -> repo root)."""
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def gate_ledger_sh(_kit_root=None):
    # `_kit_root` is VESTIGIAL (SPEC-134): callers still pass kit_root, but it is intentionally
    # ignored -- the helper is resolved via __file__, never via the (now caller-influenceable)
    # KIT_ROOT. This also closes a latent path-hijack: the old `os.path.join(kit_root, "lib",
    # "gate-ledger.sh")` would have exec'd whatever script sat at an attacker-set KIT_ROOT/lib.
    return os.path.join(_kit_lib_root(), "lib", "gate", "gate-ledger.sh")


def required_phases(kit_root, lane):
    """Reuse gate-ledger.sh's own required-gate list; never re-derive it by hand."""
    try:
        res = subprocess.run(
            ["bash", gate_ledger_sh(kit_root), "required", lane],
            capture_output=True, text=True, cwd=_kit_lib_root(), check=False,
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
            capture_output=True, text=True, cwd=_kit_lib_root(), check=False,
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
        "> GENERATED by `lib/gate/proof-table-gen.sh` from the gate/run ledger "
        f"(`{ledger_path}`). Do NOT hand-edit -- regenerate instead. Companion "
        "run-table, not the canonical `proof-of-done.md` (SPEC-016: generators write "
        "under `docs/verification/generated/`, never the canonical)."
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
        f"| {accept_status} | `bash lib/gate/gate-ledger.sh check {lane_line} {rid}` |"
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
    out.append(f"`bash lib/gate/proof-table-gen.sh {rid}`")
    out.append(f"(reads `{ledger_path}`; regenerating overwrites only this generated file, never the canonical.)")
    out.append("")
    return "\n".join(out) + "\n"


def main(argv):
    if len(argv) < 2:
        fail("usage: proof-table-gen.py <rid> [out-path]", 64)
    # SPEC-134: rid is caller-controlled; normalize it before it touches ANY path.
    raw_rid = argv[1]
    rid = _normalize_rid(raw_rid)
    if not rid:
        fail(f"rid {raw_rid!r} normalizes to empty (no [A-Za-z0-9._-] chars); refusing", 64)

    kit_root = os.environ.get("KIT_ROOT")
    log_dir = os.environ.get("KIT_LOG_DIR")
    if not kit_root or not log_dir:
        fail(
            "KIT_ROOT and KIT_LOG_DIR must be set (invoke via lib/gate/proof-table-gen.sh, "
            "not this script directly)",
            64,
        )

    # SPEC-134: the ONLY tree this generator may write into. realpath resolves symlinks +
    # `..`, and needs no existence, so it is a portable confinement anchor.
    runs_root = os.path.realpath(os.path.join(kit_root, "docs", "verification", "generated"))
    out_path = argv[2] if len(argv) > 2 else os.path.join(runs_root, f"{rid}.md")

    # Hard backstop (SPEC-016 / SPEC-132 AC5): refuse the canonical filename regardless of
    # caller intent -- a code-level guard, not just a convention followed by discipline.
    # Runs BEFORE the confinement check so the canonical-file case keeps its specific message.
    if os.path.basename(out_path) == CANONICAL_BASENAME:
        fail(
            f"refusing to write '{out_path}': basename is the canonical "
            f"'{CANONICAL_BASENAME}' (see docs/verification/README.md); this generator "
            "only writes run-table companions under docs/verification/generated/",
            1,
        )

    # SPEC-134: confine the FINAL resolved out-path under docs/verification/generated/. Enforced
    # for BOTH the default path and an explicit out-path arg -- the explicit branch no longer
    # bypasses this.
    resolved_out = os.path.realpath(out_path)
    if resolved_out != runs_root and not resolved_out.startswith(runs_root + os.sep):
        fail(
            f"refusing to write '{out_path}': resolves to '{resolved_out}', outside the "
            f"allowed run-table tree '{runs_root}' (this generator only writes under "
            "docs/verification/generated/)",
            1,
        )

    ledger_path = os.path.join(log_dir, "runs", f"{rid}.log")
    lane, gate_rows, outcomes = parse_ledger(ledger_path)
    content = render(rid, ledger_path, kit_root, lane, gate_rows, outcomes)

    # SPEC-134: write to the ALREADY-RESOLVED path (not the unresolved out_path), and open the
    # final component with O_NOFOLLOW. The confinement check above validated `resolved_out`; using
    # a bare `open(out_path)` would re-resolve symlink components at write time, so a concurrent
    # local process could swap a final-component symlink in the check->write gap (TOCTOU) and land
    # the write outside runs_root. Writing `resolved_out` + refusing to follow a final-component
    # symlink closes that gap for the realistic local-race model.
    out_dir = os.path.dirname(resolved_out)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(resolved_out, flags, 0o644)
    except OSError as e:
        fail(f"refusing to write '{resolved_out}': {e.strerror} (final component may be a symlink)", 1)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(content)

    print(
        f"wrote {resolved_out} (rid={rid}, lane={lane or 'unknown'}, "
        f"gates={len(gate_rows)}, outcomes={len(outcomes)})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
