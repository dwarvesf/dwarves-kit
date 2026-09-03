# Proof of done: session recall takes a repo name and adds a --sessions view

Change under proof: `lib/session/recall/session_recall.py`.
1. `--project` accepts a repo name (`ops-toolkit`), resolved to every `~/.claude/projects`
   slug ending in `-ops-toolkit`; that suffix rule excludes the repo's worktree slugs
   (`...-ops-toolkit--claude-worktrees-...`). A full slug still resolves to itself.
2. An unknown project is exit 1 with `no project dir under ... is 'X' or ends in '-X'`,
   distinct from the query's own `no matches`. Before, the query silently ran against
   nothing and printed `no matches`.
3. `--sessions` prints one line per transcript with hits, newest mtime first: `YYYY-MM-DD
   HH:MM  <session-id>  <n> hits  <opening ask>`. `--json` gives the same rows as objects.

Motivation: a session asked "which session this evening worked on X" and hand-rolled `jq`
over the raw JSONL four times, because `session recall X --project ops-toolkit` printed
`no matches` (the slug never resolved) and the turn view never names the transcript.

## Confirmation run-table

| # | Check | Command | Result | Verdict |
|---|---|---|---|---|
| 1 | Unit tests (7 prior + 3 new) | `cd lib/session/recall && python3 -m unittest discover -s tests` | `Ran 10 tests ... OK` | PASS |
| 2 | Short name resolves to the main slug only | test `test_short_project_name_resolves_to_suffix_match_only` | main slug returned, worktree slug and unknown name excluded | PASS |
| 3 | Unknown project is exit 1, own message | test `test_unknown_project_is_exit_1_not_no_matches` | rc 1, stderr `no project dir`, no `no matches` | PASS |
| 4 | Sessions view, newest first, worktree slug excluded | test `test_sessions_view_one_line_per_transcript_newest_first` | header `# sessions matching 'backoff': 2`, new before old | PASS |
| 5 | Live | `bin/session recall whathas --project ops-toolkit --sessions --limit 5` | 5 rows, newest `2026-09-04 00:10`, each with hit count and opening ask | PASS |
| 6 | Live unknown | `bin/session recall whathas --project nosuchrepo-zz` | rc 1, `no project dir under /Users/tieubao/.claude/projects is 'nosuchrepo-zz' or ends in '-nosuchrepo-zz'` | PASS |
| 7 | Shared parser untouched | `bash lib/session/tests/test-parse-transcript.sh` | `smoke: all 7 passed` | PASS |

## Negative control

Command: append `return []` after `suffix = "-" + slug` in `resolve_project_dirs`, so a
short name never resolves.
Exit: unit suite `FAILED (failures=2)` (tests 2 and 4 above); live query prints the
unknown-project message for `ops-toolkit`.
Restore: `git checkout -- session_recall.py`, suite `OK`.
Verdict: PASS (revert -> RED -> restore -> GREEN).

## Reproduce

```
cd lib/session/recall && python3 -m unittest discover -s tests
bin/session recall whathas --project ops-toolkit --sessions --limit 5
```
