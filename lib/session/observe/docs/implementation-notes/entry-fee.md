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

## 2026-09-23 Per-component detail: instructions and hook_success sub-rows

**Context**: a real session had to hand-roll python over transcripts four times to
answer "which CLAUDE.md/MEMORY.md file costs what" and "which SessionStart hook injects
what", because `instructions` and `hook_success` were single lumped rows. Separately,
a hook whose stdout exceeds the harness's inline cap gets persisted to a file with only
a preview injected (its `hook_success.content` carries the marker text `Output too
large`), silently dropping content with no flag in the view.

**Decision**: `instructions` sub-splits across the attachment's `files` list
(`path`/`type`/`content`) by content-length share, largest-remainder rounding so
sub-rows always sum to exactly the parent row's tokens (never off by a rounding error,
never requiring a second reconciliation). `hook_success` sub-splits by `command`
truncated to 50 characters (the literal command string, not the `hooks` view's grouped
`hook_label()`, since here the ask is "which hook", not "which script basename groups
several hooks"); each attachment entry contributes its own tokens to exactly one label,
so parent-equals-sum holds by construction with no split math needed. A hook is flagged
`SPILLED` when its `content` carries the marker text, shown even at zero tokens since
the flag itself is the signal.

**Why not filter hook_success to SessionStart explicitly**: `entry_fee_session` already
returns at the first main-chain assistant turn, so every attachment entry it has seen
by then is, in practice, a SessionStart-time one. Adding an explicit `hookEvent ==
"SessionStart"` filter on top would either be redundant or, if a stray non-SessionStart
attachment ever preceded the first assistant turn, break the sum-to-parent invariant
(the parent's existing, unchanged accumulation would count it; a filtered sub-row list
would not). Left the parent computation untouched (no change to measured-fee logic) and
let the same entries that already feed the parent also feed the sub-rows.

**Impact**: `--detail` gates the sub-rows in the text table (default output stays one
row per component, per the spec's non-goal against inflating the standard table);
`--json` carries `split_components[].files` / `.hooks` unconditionally, since a machine
reader has no readability concern to gate behind a flag.

**Also fixed**: the header claimed the split was "ESTIMATED from disk (component size,
e.g. SKILL.md text)". The code has never read disk; it sizes the transcript's rendered
`attachment` text. Reworded to "ESTIMATED from the transcript's rendered attachment
text", same 4 chars/token, same "estimate" label. `tests/smoke.sh` test 92 updated to
match (it grepped the old wrong wording).
