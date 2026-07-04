---
description: "Assemble an outward buy-in doc from what a gated run already produced: the spec, the proof-of-done, the implementation-notes, and the gate ledger's grill/DEBT records. Outcome-first, 5 sections, ending in an ask. Never generates new analysis; a missing source is reported honestly, never invented."
---

You are an assembler, not a writer. Your job is to turn `$ARGUMENTS` (a `<rid>` -- the branch
slug, which is also the spec slug and the `docs/implementation-notes/<slug>.md` filename,
SPEC-070) into the doc a THIRD PARTY reads to decide whether to say yes: a teammate, a
client, or an approver who was not in the room. This is the OUTWARD twin of `/kit:explain`
(SPEC-124, ADR-0031 §2): explain teaches the OPERATOR to understand a change and ends in a
quiz; pitch persuades a THIRD PARTY to approve it and ends in an ask. Same underlying
artifacts, different audience -- pitch never re-explains a hunk, it references the spec /
proof / implementation-notes verbatim.

## The hard constraint (the whole point of this sub-goal, SPEC-140)

**Never fabricate.** Every claim in the assembled doc traces to a file on disk (the spec, the
proof-of-done, `docs/implementation-notes/<rid>.md`) or a line in `bash lib/gate-ledger.sh show
<rid>`. When a source is missing, the doc says so explicitly (e.g. "no grill record for this
run") -- it never invents a plausible-sounding substitute. This is enforced mechanically:
`lib/pitch.sh` is the ONLY thing that touches those files, and its only inputs are "does this
file exist" / "does this ledger line exist", so there is no channel through which an invented
narrative could leak in (the same discipline `lib/explain.sh` uses for the diff, SPEC-124).

## Process

### Step 1: Run the engine

```bash
bash lib/pitch.sh render "$ARGUMENTS" --out docs/verification/pitch-command/pitch-<rid>.md
```

(Or omit `--out` to print to stdout only, when you just want to read it or hand it to the
user without committing a file.) Read what it produced: the 5 sections in outcome-first
order (Outcome, Unknowns we accounted for, Evidence, Cost / not shipped, The ask). This is
the whole artifact -- there is no prose-enrichment pass on top of it, unlike `/kit:explain`'s
narrate-log composition. If a section reads as an absence line ("no grill record for this
run", "[no spec found for '<rid>'; outcome not assembled]", etc.), that is the correct,
grounded output for a run missing that source -- do NOT replace it with your own guess at
what the missing content might have said.

### Step 2: Present it

Show the assembled doc to the user. It is meant to be pasted by hand into wherever the
approver actually is (Discord, a PR description, a client email) -- this command NEVER posts
it anywhere itself. There is no auto-send path; if the user wants it sent, that is their
action with their own tool (Discord skill, `gh pr comment`, email), not this command's.

### Step 3: Record the run

`pitch` carries no matrix row of its own (RUN_REPORT observability only, the same bespoke,
non-matrix convention `/kit:explain` and `/kit:verify` already use -- never a new required
gate):

```bash
bash lib/gate-ledger.sh record <rid> pitch ran "ref=<rid>"
```

## Rules

- Ground every section in a real file or a real ledger line. A missing source is reported
  honestly; it is never invented, paraphrased into existing, or silently dropped.
- Never re-explain a hunk or a diff -- that is `/kit:explain`'s job. Reference the spec /
  proof / implementation-notes verbatim; do not restate their content in new prose.
- Never post the assembled doc anywhere (no Discord, no Slack, no `gh pr comment`, no email).
  Output is stdout or `--out <file>`, full stop. Sending it is a human action.
- Do not compute a new verdict, severity, or synthesis. If the sources are silent on
  something, the doc says so instead of guessing.

## Source

SPEC-140 (`research/2026-07-04-fable-unknowns-absorption.md` Design 4). Engine:
`lib/pitch.sh`. Proof: `tests/test-pitch.sh` (real-sample render against a shipped rid, the
two load-bearing degrade-gracefully fixtures, and the never-auto-post grep negative control).
