# SPEC-301: session observe tools --errors groups a tool's errors by prefix

**Status:** VALIDATED (the change lands in the same PR)
Lane: full
**Board:** ID-903. **Proof:** `lib/session/observe/tests/smoke.sh` checks 80-87.

## Problem

`session-observe tools` shows a tool's error COUNT (EnterWorktree 15 percent,
ExitWorktree 17 percent in a sweep week) and nothing about WHY. A 30-line
python over `~/.claude/projects` grouping `is_error` tool_result content by
its first 160 chars answered it in one run (17 of 19 EnterWorktree errors
were subagents with a cwd override). The flag belongs on the tools view that
already owns the count, not a sibling script.

## Contract

- `session-observe tools --errors <tool>` prints a group table in place of
  the standard tools table: header `# tool errors: <tool>  (N error results
  across M transcripts)`, rows `prefix / count / share`, ranked by count,
  honouring `--top`.
- The group key is the error text's first 160 chars with whitespace runs
  collapsed to one space, so a newline-bearing message keeps one table row
  and formatting variants of the same failure merge.
- Error text comes from the `tool_result` block's `content`: the string
  itself, or the joined `text` fields of the list-of-blocks shape. The JSON
  wrapper is never the prefix.
- A tool with zero recorded errors prints `no error results recorded for
  <tool>` under the same header: an honest zero, never a fake table.
- `--errors` on any other view refuses at parse time (exit 2).
- `--json` adds `tool_error_groups` (`tool`, `total`, `groups[]` with
  prefix/count/share) when `--errors` is set; absent otherwise.
- The standard tools view and every other view are byte-identical without
  the flag.

## Design record

Grouping rides the single `collect()` pass the tools view already runs: one
extra `defaultdict(Counter)` keyed on the resolved tool name (the same
`id_tool[tid]` attribution `tool_err` uses), so an orphaned tool_result is
ignored exactly as the count is. Prefix-over-full-text is deliberate: a
30-char prefix would merge distinct failures (every `Exit code N: ...`
collapses), 160 chars keeps the discriminating part of real messages while
staying one terminal row.

## Test plan

| Case | Expected |
|---|---|
| 5 errors, two message families | two rows 3 (60%) + 2 (40%), ranked by count |
| whitespace variants (newline, multi-space) | merge into one prefix row |
| list-block content shape | text extracted, wrapper never the prefix |
| tool with no errors | honest empty state |
| no flag | standard table unchanged, no group view leaks |
| --json | tool_error_groups mirrors the table |
| --errors on skills / report | exit 2, no silent ignore |
