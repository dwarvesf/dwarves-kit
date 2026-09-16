# Implementation notes: entry-fee

Delta against `docs/specs/SPEC-289-observe-entry-fee.md`. The spec was written after
the transcript shape was confirmed, so these entries record the decisions the backlog
row left open, not deviations from the written spec.

## 2026-09-16 10:00 Which number counts as the measured fee

**Context**: the backlog row cites a hand measurement of about 96,000 tokens built from
a bytes-over-four estimate of four named components. The transcript offers no
per-component token count anywhere.

**Decision**: the first main-chain assistant turn's
`input_tokens + cache_creation_input_tokens + cache_read_input_tokens` is the measured
whole. The per-component split stays an estimate at four characters per token over the
`rendered` text of each `attachment` entry.

**Why**: that sum is what the API charged for the first turn, before the agent did any
work, so it is the preamble by definition. Presenting a bytes-over-four figure as the
headline would repeat the hand measurement rather than improve on it.

**Impact**: the view carries two units side by side. Every header and the JSON label
the split an estimate, and the gap between the two appears as one `(unattributed)`
row rather than being hidden.

**Alternatives**: size everything from bytes (loses the measurement); report only the
total (loses the per-component ask on the row).

## 2026-09-16 10:20 The split comes from one session, not a per-component median

**Context**: a first pass took the median of each component series independently.

**Decision**: report one real session's split, chosen as the median of the sessions
whose transcript records a rendered preamble.

**Why**: component medians do not sum to the median fee, so the table would not
reconcile against the measured total and the `(unattributed)` row would be an
artifact. A real session's rows always sum to its own measured fee.

**Impact**: the header states which session's fee the split belongs to and how many
sessions could be split at all.

**Open question**: older transcripts record no rendered preamble. On the live 14-day
window, 108 of 435 sessions carried one. If that share falls, the split loses its
base, and the view should say so louder than a count in the header.

## 2026-09-16 10:35 --project resolution moved into a shared helper

**Context**: `--project` took an exact cwd-derived slug. A per-repo question is asked
by repo name, and one repo's worktrees each own a separate slug.

**Decision**: `project_roots()` returns the exact slug dir when it exists, else every
slug containing the given string. `iter_files()` and `_burn_files()` both route
through it.

**Why**: fixing it only for the new view would leave `cost` and `burn` with the old
behaviour for the same question. One helper, both callers.

**Impact**: a `--project` string that matches several slugs now walks all of them.
An exact slug still resolves to exactly itself, so no invocation that already named a
valid slug changes. A typo or a partial name used to walk nothing and say so through an
empty report; it now returns a merged figure, so a multi-slug match announces its
resolved list on stderr.

## 2026-09-16 12:10 Review fixes

The architecture and correctness review found three unguarded crash paths and two
outputs that read as a measurement when they were not. All are fixed on this branch.

- Three untrusted fields were sliced or hashed without a guard: a numeric `timestamp`,
  a numeric `rendered[].content`, and a dict `attachment.type`. Each aborted the whole
  scan, not just that file, while every sibling collector in the module guards the same
  shapes. Now each contributes nothing and the scan continues.
- The remainder row went negative when the four-characters-per-token estimate overshot
  the measured fee, printing `-900` and `-900%` as if they were measurements. It now
  prints `(estimate over measured)` with the magnitude, and the component shares above
  100 percent carry the signal.
- The per-repo table keyed on the raw project slug, so a repo's worktrees each ranked as
  a separate repo and a one-session worktree slug sorted above the many-session checkout
  of the same codebase. Rows now fold on the `--claude-worktrees-` marker.

One review point stays a documentation fix rather than a code one: the measured fee also
covers the first user prompt, not the preamble alone. The `(unattributed)` row absorbs
it, which matters at the 51 percent unattributed share the live run shows. Stated in the
spec and the README instead of subtracted, because the transcript gives no way to
separate the two.
