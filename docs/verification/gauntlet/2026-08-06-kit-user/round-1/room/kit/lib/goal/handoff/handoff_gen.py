#!/usr/bin/env python3
"""Deterministically generate the orchestrator's two-tier feed-forward handoff
(SPEC-087 Mechanism B) from the finishing sub-goal session's transcript.

WHY: today HANDOFF.md / DECISIONS.md are written BY the LLM sub-goal session, so a
good handoff depends on the model remembering to write one well. This makes the
handoff a deterministic, always-produced FUNCTION of the transcript instead. The
hot/warm CONTRACT (the fields) is unchanged; only the GENERATOR changes
(token-optim-v3 SG-02; the extractor core is ported verbatim from ops-toolkit
SG-01 `experiments/cc-deterministic-compaction/cc_compact.py`).

Pure function of (transcript bytes, next-sub-goal args, --date): no model call, no
network, no clock, no randomness -> same inputs produce byte-identical HANDOFF.md.
DECISIONS.md is append-only and idempotent (a content-hash marker means re-running
on the same transcript appends nothing).

ponytail: stdlib only; reuses SG-01's extractors rather than reimplementing them.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cc_compact as cc  # noqa: E402  (sibling module, ported SG-01 extractor)

# Read-pointers are grounded in files the run actually touched. We emit `path`,
# not `path:line`: a line number would be fabricated (the extractor has no line
# data), and the handoff must stay grounded (SPEC-087: "cannot become an
# optimistic lie"). Cap so a runaway file list cannot bloat the HOT handoff.
READ_POINTER_CAP = 8


def sum_usage(transcript_path: str) -> dict:
    """Sum token usage across ASSISTANT entries only (SPEC-110).

    A real `claude --output-format stream-json` run ends with a `type:"result"`
    event carrying CUMULATIVE usage; summing every usage block would double-count
    it, so we sum assistant-message usage only (reusing cc._is_assistant, the
    kit's canonical assistant detector). User turns carry no usage; result/system
    events are skipped by the same filter.
    """
    def _int(x):
        try:
            return int(x or 0)
        except (TypeError, ValueError):
            return 0   # a malformed usage value is skipped, not a crash (defensive; review LOW-3)
    entries = cc.load(transcript_path)
    tot = {"in": 0, "out": 0, "cache_read": 0, "cache_create": 0}
    for e in entries:
        if not cc._is_assistant(e):
            continue
        u = (e.get("message") or {}).get("usage") or {}
        tot["in"] += _int(u.get("input_tokens"))
        tot["out"] += _int(u.get("output_tokens"))
        tot["cache_read"] += _int(u.get("cache_read_input_tokens"))
        tot["cache_create"] += _int(u.get("cache_creation_input_tokens"))
    return tot


def build_handoff(entries, next_id: str, next_title: str) -> str:
    """HOT tier: overwritten each transition, injected in full (capped upstream)."""
    files = cc.files_changed(entries)
    outs = cc.outstanding(entries)
    first_action = outs[0] if outs else (
        f"read the goal file goals/{_nn(next_id)}-*.md and take the first step"
    )

    lines = ["# HOT HANDOFF (overwritten each sub-goal transition)\n\n"]
    title = (next_title or "").strip()
    lines.append(f"Next sub-goal: {next_id}{(' ' + title) if title else ''}.\n")
    lines.append(f"First action: {first_action}\n\n")

    lines.append("Read-pointers (files this run actually touched):\n")
    if files:
        for path, n in files[:READ_POINTER_CAP]:
            lines.append(f"- `{path}` -- touched ({n} edit{'s' if n != 1 else ''})\n")
        if len(files) > READ_POINTER_CAP:
            lines.append(f"- (+{len(files) - READ_POINTER_CAP} more; see DECISIONS.md)\n")
    else:
        lines.append("- (none located this run)\n")

    if len(outs) > 1:
        lines.append(
            f"\nOutstanding hit this run: {outs[1]}. See DECISIONS.md for the full ledger.\n"
        )
    return "".join(lines)


def build_decisions_block(entries, next_id: str, date: str) -> str:
    """WARM tier: one append-only dated block of durable invariants + dead-ends.

    Wrapped in a content-hash marker so re-running on the same transcript is a
    no-op (append-only stays honest, and the determinism check holds)."""
    goal = cc.session_goal(entries)
    decs = cc.decisions(entries)
    outs = cc.outstanding(entries)
    cmts = cc.commits(entries)

    body = [f"## {date} {next_id} (deterministic handoff)\n\n"]
    body.append(f"### What this run was\n- {goal}\n\n")
    body.append("### Invariants / decisions (from this run)\n")
    body.append(cc._bullets(decs))
    body.append("\n### Commits this run\n")
    body.append(cc._bullets(cmts))
    body.append("\n### Dead-ends / outstanding\n")
    body.append(cc._bullets(outs))
    block = "".join(body)

    digest = hashlib.sha256(block.encode("utf-8")).hexdigest()[:12]
    return f"<!-- handoff-gen:{digest} -->\n{block}"


DECISIONS_HEADER = (
    "# WARM LEDGER (append-only: invariants + dead-ends, read on demand)\n\n"
    "Never inlined into the prompt; the orchestrator injects only a pointer to this file.\n"
    "Blocks below are generated deterministically from each sub-goal's transcript.\n\n"
)


def _nn(sg_id: str) -> str:
    """`SG-04` -> `04` for the goal-file pointer; passthrough on odd input."""
    n = sg_id.split("-")[-1] if "-" in sg_id else sg_id
    return n


def write_outputs(transcript: str, out_dir: str, next_id: str, next_title: str, date: str):
    entries = cc.load(transcript)

    handoff = build_handoff(entries, next_id, next_title)
    with open(os.path.join(out_dir, "HANDOFF.md"), "w", encoding="utf-8") as fh:
        fh.write(handoff)

    block = build_decisions_block(entries, next_id, date)
    marker = block.splitlines()[0]  # the <!-- handoff-gen:... --> line
    dpath = os.path.join(out_dir, "DECISIONS.md")
    existing = ""
    if os.path.exists(dpath):
        with open(dpath, "r", encoding="utf-8") as fh:
            existing = fh.read()
    if marker in existing:
        return  # idempotent: this exact block already appended
    with open(dpath, "a", encoding="utf-8") as fh:
        if not existing:
            fh.write(DECISIONS_HEADER)
        elif not existing.endswith("\n"):
            fh.write("\n")
        fh.write(block)


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    # sum-usage mode (SPEC-110): a distinct subcommand so the existing positional
    # `handoff_gen.py <transcript> --dir ...` interface stays byte-compatible.
    if argv and argv[0] == "sum-usage":
        if len(argv) < 2 or not os.path.isfile(argv[1]):
            sys.stderr.write("handoff-gen sum-usage: transcript not found\n")
            return 2
        u = sum_usage(argv[1])
        print(f"in={u['in']} out={u['out']} cache_read={u['cache_read']} cache_create={u['cache_create']}")
        return 0
    p = argparse.ArgumentParser(prog="handoff-gen", description=__doc__)
    p.add_argument("transcript", help="the finishing session's transcript JSONL")
    p.add_argument("--dir", required=True, help="mega-goal dir to write HANDOFF.md/DECISIONS.md into")
    p.add_argument("--next-id", required=True, help="next sub-goal id, e.g. SG-04")
    p.add_argument("--next-title", default="", help="next sub-goal human title")
    p.add_argument("--date", required=True, help="YYYY-MM-DD stamp (passed in; no clock here)")
    args = p.parse_args(argv)

    if not os.path.isfile(args.transcript):
        sys.stderr.write(f"handoff-gen: transcript not found: {args.transcript}\n")
        return 2
    if not os.path.isdir(args.dir):
        sys.stderr.write(f"handoff-gen: --dir not a directory: {args.dir}\n")
        return 2
    write_outputs(args.transcript, args.dir, args.next_id, args.next_title, args.date)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
