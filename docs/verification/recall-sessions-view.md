# Proof of done: session recall --project <repo-name> and --sessions, hardened

Change under proof: `lib/session/recall/session_recall.py`, its tests and README. Replaces the
#482 record after the kit:battery over it: security MED 3 (`--project ..` resolved to
`~/.claude`; the guard sat after the isdir check), MED 4 (opening ask printed raw transcript
text into session context), LOW 6 (`--project` with no value fell through to the cwd project);
reviewer M5 (every transcript loaded to print a few rows), M6 (silent multi-dir union), L7
(sliced count posed as a total), L8 (list-content first turns gave an empty ask).

1. `--project` accepts a repo name resolved to every slug ending `-<name>`; the value is
   validated (no `/`, `.`, `..`, empty) BEFORE any directory check; a missing value is exit 2.
2. Unknown project is exit 1 with its own message, distinct from `no matches`.
3. `--sessions` walks transcripts newest-first and stops at `--limit` hits; the header says
   `(capped by --limit, raise it for more)` when it did; more than one matched dir is named.
4. The opening ask reads string or list content, skips hook/system blocks, redacts secret
   shapes to `[redacted]`; the block starts with a DATA marker. `--json` carries both.

## Confirmation run-table

| # | Check | Command | Result | Verdict |
|---|---|---|---|---|
| 1 | Unit tests (7 original + 7 new) | `cd lib/session/recall && python3 -m unittest discover -s tests` | `Ran 14 tests ... OK` | PASS |
| 2 | Traversal and empty names never resolve | `test_traversal_and_empty_names_never_resolve` | `..`, `.`, `../x`, `a/b`, `""` all `[]` | PASS |
| 3 | `--project` with no value is usage, exit 2 | `test_project_flag_without_value_is_usage_exit_2` | rc 2 | PASS |
| 4 | List-content ask read, hook block skipped, `op://` redacted | `test_opening_ask_list_content_and_redaction_and_hook_skip` | `rotate the key [redacted] and ship it` | PASS |
| 5 | Walk stops at `--limit`, header says so, older file never loaded | `test_sessions_view_stops_at_limit_and_says_so` | 1 row, capped header | PASS |
| 6 | Marker line under the header | `test_sessions_view_one_line_per_transcript_newest_first` | line 2 is `DATA_MARKER` | PASS |
| 7 | Live | `bin/session recall whathas --project ops-toolkit --sessions --limit 2` | 2 rows, capped header, marker | PASS |
| 8 | Live traversal | `bin/session recall x --project ..` | rc 1, `no project dir ... is '..'` | PASS |
| 9 | Shared parser untouched | `bash lib/session/tests/test-parse-transcript.sh` | all 7 passed | PASS |
| 10 | Structural suite | `bash tests/test-meta.sh` | 824/824 | PASS |

## Negative control (negctl)

Produced by `lib/gate/negctl.sh` against the unit suite, with the validate-first guard
disabled as the mutation:

```
Command: cd lib/session/recall && python3 -m unittest discover -s tests
Exit: 0 (green before mutation)
Mutation: sed -i.bak 's/^    if not slug or "\/" in slug or os.sep in slug or slug in (".", ".."):$/    if False:/' lib/session/recall/session_recall.py && rm -f lib/session/recall/session_recall.py.bak
Changed: lib/session/recall/session_recall.py
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/session/recall/session_recall.py
Exit: 0 (green after restore)
Verdict: PASS
```

## Reproduce

```
cd lib/session/recall && python3 -m unittest discover -s tests
bin/session recall whathas --project ops-toolkit --sessions --limit 5
```
