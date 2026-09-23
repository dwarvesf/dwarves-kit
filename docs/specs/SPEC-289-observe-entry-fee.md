# SPEC-289: session observe entry-fee

**Status**: ready
Lane: full
**Owner module**: `lib/session/observe`
**Source**: backlog row ID-878; measurement `ops-toolkit/research/2026-09-13-token-burn-optimization.md`

## Problem

Every agent turn re-reads a fixed preamble before any work: the skill listing, the
CLAUDE.md stack, the repo memory index, the agent roster, the output style, the tool
schemas. A hand measurement on 2026-09-13 put that preamble near 96,000 tokens, about
38 percent of a 400-turn builder's whole bill.

That measurement is a snapshot taken by hand with a bytes-over-four rule of thumb. It
cannot say whether the number moved, which repo pays the most, or which component grew.
`session observe` already parses the same transcripts for `cost` and `burn`, so the
entry-fee view belongs beside them.

## Scope

One new view in the existing CLI. No new script, no new data source, no writes.

```
session observe entry-fee [--days N] [--project SLUG-OR-NAME] [--root DIR] [--top N] [--trend] [--detail] [--json]
```

| Arg | Default | Meaning |
|---|---|---|
| `--days N` | 0 (all) | coarse file-mtime window, as every other view |
| `--project` | none | a project slug, or a bare repo name matched against every slug |
| `--top N` | 0 (all) | limit the per-repo and weekly tables |
| `--trend` | off | add a weekly median table, newest week first |
| `--detail` | off | add `instructions` (per file) and `hook_success` (per SessionStart hook) sub-rows to the text table; `--json` always carries them |
| `--json` | off | machine-readable output |

## Behaviour

### The measured total

One row per main session. The entry fee is the FIRST main-chain assistant turn's
`input_tokens + cache_creation_input_tokens + cache_read_input_tokens`. That sum is
exactly what the model read before it acted, so it is a measurement, not an estimate.

A transcript with no main-chain assistant turn contributes no row. That covers a
subagent's own transcript and a session that never got a reply. Both are excluded
rather than counted as a zero fee, which would drag every median down. A transcript
under a `subagents/` directory is excluded by path for the same reason.

### The estimated split

The transcript records each preamble block as an `attachment` entry whose `rendered`
field holds the text the model received. The view sizes each block at
`ENTRY_FEE_CHARS_PER_TOKEN` (4) characters per token and keys it by
`attachment.type` (`skill_listing`, `instructions`, `agent_listing_delta`,
`hook_additional_context`, ...). The remainder, `measured fee - sum of the sized
blocks`, is one `(unattributed)` row: the system prompt and the built-in tool schemas
reach the model but never appear in the transcript.

The split is labelled an estimate in the table header and in the JSON
(`components_estimated`). The same rule of thumb the hand measurement used is stated
alongside it.

Four characters per token overshoots on dense markdown and tables, so the sized blocks
can exceed the measured fee. That prints as an `(estimate over measured)` row carrying
the magnitude, never as a negative token count, and the component shares then read
above 100 percent, which is the estimate saying it broke here.

The measured total also covers the first user prompt and anything attached to it, so it
is the preamble plus turn one. The `(unattributed)` row absorbs that alongside the
system prompt and the tool schemas.

The split is reported for ONE real session, not as a per-component median. Medians of
separate components do not add up to the median fee, so a median-of-medians table
would not reconcile against a measured total. That session is the median of the
sessions that record a rendered preamble; older transcripts record none, and the
median across all sessions would often be one of those, reading as a 100 percent
unattributed fee.

### The instructions and hook_success sub-rows

`instructions` and `hook_success` are each one lumped row, but the transcript carries
enough to break them down further: which CLAUDE.md or MEMORY.md file costs what, and
which SessionStart hook injects what. `--detail` breaks both down.

`instructions`: the attachment carries a `files` list (`path`, `type`, `content`) for
every instructions file. The component's tokens are split across the files by
content-length share, largest-remainder rounding, so the sub-rows always sum to
exactly the parent row's token count, never off by a rounding error. A fixture with no
`files` list (an older shape) contributes no sub-rows for that entry; the parent row is
unaffected.

`hook_success`: one sub-row per hook, keyed by the hook's `command` truncated to 50
characters, sized by the same rendered text the parent row sizes (the content that
reached the model), so sub-rows sum to the parent row by construction (each attachment
entry contributes its own tokens to exactly one hook label, no split needed). A hook
whose `content` field carries the marker text `Output too large` had its stdout exceed
the harness's inline cap; only a preview was persisted and injected, so the hook's
sub-row is flagged `SPILLED`, at zero tokens if nothing reached the model at all. A
spilled hook still appears in the table even at zero tokens, since the flag is the
signal, not the size.

Sub-rows print in the text table only behind `--detail`, so the default table stays
one row per component. `--json` carries them unconditionally, under
`split_components[].files` (instructions) and `split_components[].hooks`
(hook_success), since a machine reader has no readability concern to gate.

### The per-repo and weekly figures

Per repo: one row per repo with the session count and the median measured fee, largest
median first, ties broken by session count. The memory index and the CLAUDE.md stack
differ per checkout, so this is the actionable cut.

A worktree gets its own project slug. The worktree convention is
`<repo>/.claude/worktrees/<name>`, so the slug carries a `--claude-worktrees-` marker
and the repo name sits before it. Rows key on the part before that marker, which folds
a repo's worktrees into one row. Without the fold, a one-session worktree slug ranks
above the many-session checkout of the same repo, which reads as a comparison when it
is one codebase twice.

`--trend`: ISO-week buckets of the median measured fee, newest week first, so a
reduction from a cleanup lands as a visible drop.

### Project resolution

`--project` takes the exact slug directory when it exists. Otherwise it matches every
slug containing the given string, so a bare repo name resolves without the full
cwd-derived slug. One repo's worktrees each get their own slug and a per-repo figure
wants them together, so all matches are walked. This resolution is shared with the
other views through `project_roots()`.

A substring matching more than one slug prints the resolved list to stderr. Before the
fallback existed, a wrong `--project` walked nothing and the empty output said so; a
silent multi-match would instead merge unrelated repos into one plausible figure.

## Non-goals

- Not part of `report`. `report` is the weekly digest of behaviour; the entry fee is a
  standing cost measurement, and its per-repo table would double the digest's length.
- No per-component token measurement. The API reports one usage block per turn, so a
  per-component count does not exist in the data.
- No subagent entry fee. A subagent pays the same preamble, but its transcript has no
  main-chain turn, and counting it would mix two populations in one median.
- No writes. Read-only, like every other view.

## Verification (acceptance criteria)

Exercised by `tests/smoke.sh` against `tests/fixtures/entryfee/` (proj-alpha with fees
1000, 2000, 3000; proj-beta with fee 500; a `subagents/` transcript at 99999; a
sidechain-only transcript):

62. header reports 4 sessions, 2 projects, median 2000.
63. the split sizes `instructions` (800 chars) at 200 and `skill_listing` (400) at 100.
64. `(unattributed)` is the measured fee minus the sized blocks (2000 - 350 = 1650).
65. negative control: the `subagents/` transcript is excluded (its 99999 fee absent).
66. negative control: the sidechain-only transcript contributes no session.
67. negative control: a later, larger turn does not replace the first-turn fee.
68. per repo: proj-beta is its own row at 1 session, median 500.
69. `--trend`: 2026-W37 (3, 2000) prints above 2026-W36 (1, 1000).
70. negative control: without `--trend` the weekly table is absent.
71. `--project alpha` resolves the bare name to proj-alpha only.
72. `--json` is valid, carries median_fee 2000 and the estimate flag.
73. negative control: `report` prints no entry-fee section.

Plus, against `tests/entryfee-edge/` (an overshooting session, an untrusted-field
session, a repo with one worktree slug):

74. an estimate above the measured fee prints as `(estimate over measured)`, never a
    negative token count.
75. the overshooting component's share reads above 100 percent.
76. untrusted fields (numeric timestamp, dict attachment type, numeric rendered content,
    non-dict message) do not crash the scan; the valid turn's fee is still measured.
77. negative control: the dict-typed attachment contributes no component row.
78. a worktree slug folds into its repo row (one row, two sessions).
79. a multi-slug `--project` match is announced on stderr.

Plus, against `tests/fixtures/entryfee-detail/` (one session: two instruction files,
three SessionStart hooks, two spilled, one of those at zero measured tokens):

98. `--detail`: `instructions` sub-rows print per file (A.md 150, B.md 50), summing to
    the parent row (200).
99. `--detail`: `hook_success` sub-rows print per SessionStart hook (tool-first.sh 90,
    repo-memory.sh 58), summing to the parent row (148); repo-memory.sh is flagged
    `SPILLED`.
99b. `--detail`: a hook whose stdout spilled to a file but never reached the model at
     all (no rendered content) still prints, at 0 tokens, flagged `SPILLED`; the flag
     is the signal, not the size.
100. negative control: without `--detail`, no sub-rows print in the text table.
101. `--json`: `split_components[].files` and `.hooks` carry the same sub-rows
     unconditionally, `--detail` or not, including the zero-token spilled hook.

Plus a real run over the live transcripts, recorded in
`lib/session/observe/docs/verification/entry-fee.md`.
