# Verification: intake-sweep runs as bash plus jq

Verdict: PASS

Spec: `docs/specs/SPEC-407-intake-sweep-bash.md` (VALIDATED, revision 2). Change: `hooks/intake-sweep.sh` (port), `hooks/intake-sweep.py` (removed), `lib/reflect/staging-format.jq`, `lib/reflect/shlex-split.sh`, `lib/reflect/hook-util.sh` (new), `tests/lib/hook-parity.sh` (args, touch, executable seeds, today fold). One fresh Opus reviewer attacked the spec and fuzzed the port against the Python (round 1: NEEDS REVISION, 2 critical, 12 warnings, 690 cases); every finding is folded into revision 2 and pinned.

## Green run

```
Command: bash tests/test-intake-sweep-parity.sh
Exit: 0
Output:
intake-sweep parity: 160 passed, 0 failed
Verdict: PASS
```

```
Command: bash tests/test-staging-format-jq.sh
Exit: 0
Output:
  PASS casefold: every changed code point and a sample of unchanged ones
  PASS norm: casefolded letter and digit runs joined by one space
  PASS render: every candidate shape renders the same block (null for a titleless one)
  PASS keys: board rows and staging headings give the same dedup keys
  PASS shlex: argv split, unterminated quote and trailing backslash refused
staging-format-jq: 5 passed, 0 failed
Verdict: PASS
```

## Checks

| Check | Command | Result |
|---|---|---|
| Parity, every golden, UTF-8 locale | `bash tests/test-intake-sweep-parity.sh` | `160 passed, 0 failed` (goldens generated from the Python at `b9306b37` through its shim) |
| Grammar twin | `bash tests/test-staging-format-jq.sh` | `5 passed, 0 failed`: all 1,530 case-folding code points plus 400 unchanged, 38 norm strings, 16 candidates, 20 board and staging texts, 522 shlex strings, against the Python |
| Helpers | `bash tests/test-hook-util.sh` | `26 passed, 0 failed`, including a stat shim that answers like GNU stat |
| Parity under the macOS system tools | the same tests with `/bin/bash` (3.2.57) and `/usr/bin/jq` (1.7.1) first on PATH | pass |
| Real data | the real digest ledger (148 rows), board (536 lines), and staging file (970 lines) through the Python and the port, three scenarios (real files, empty board and staging, board only), compared by SHA-256 of the staging file and the swept keys | IDENTICAL in all three (20, 88, and 80 blocks staged) |
| No leaks | a command source run with `TMPDIR` pointed at an empty dir | the dir is empty afterward; no stray `sleep` |
| Fresh review | one Opus reviewer: 690 hand-picked and random hook cases, 12,000 grammar-twin cases, 3,000 shlex cases | NEEDS REVISION; all random cases matched; findings were classes nobody had written down, all folded |
| Existing hook suite | `bash tests/test-intake-sweep.sh` | `31 passed, 0 failed` |
| Foldin suite | `bash tests/test-kit-foldin-hooks.sh` | green inside `run-all --changed` |
| Contract lint | `bash tests/test-kit-contract.sh` | `25 passed, 0 failed` (C5 now allows the jq twin) |
| No Python | `grep -c python hooks/intake-sweep.sh` | the hook calls no interpreter |

## Negative controls

Each ran through `lib/gate/negctl.sh` in its own scratch clone of the final head: commit first, mutate, test red, restore with `git checkout HEAD --`, test green. NC1 to NC4 and NC6 use the parity test, NC5 and NC7 the grammar-twin test.

| # | Mutation | Under mutation | Verdict |
|---|---|---|---|
| NC1 | drop the URL-substring dedup | 4 of 160 red | PASS |
| NC2 | skip the swept-keys dedup | 5 of 160 red | PASS |
| NC3 | skip the board and staging title dedup | 12 of 160 red | PASS |
| NC4 | write the staging header even when the file exists | 6 of 160 red | PASS |
| NC5 | `ascii_downcase` in place of the casefold table (test: `test-staging-format-jq.sh`) | 3 of 5 red | PASS |
| NC6 | never record the swept keys | 81 of 160 red | PASS |
| NC7 | treat single quotes as ordinary in `shlex-split.sh` (test: `test-staging-format-jq.sh`) | 1 of 5 red | PASS |

One block as `lib/gate/negctl.sh` printed it (NC3):

```
## Negative control (negctl)
Command: bash tests/test-intake-sweep-parity.sh
Exit: 0 (green before mutation)
Output:
  intake-sweep parity: 160 passed, 0 failed

Mutation: bash <scratch>/is-nc.sh 3
Changed: hooks/intake-sweep.sh
Exit: 1 (under mutation, RED expected)
Output:
    FAIL board-cr-line-breaks
      want: {"name":"board-cr-line-breaks","rc":0,"stdout":"🧲 intake-sweep: staged 1 candidate(s) (links: 1) in @CWD@/_meta/backlog-staging.md.","stderr":"","log":"","stray":"cwd/_meta/BACKLOG.md,cwd/_meta/backlog-staging.md,cwd/_meta/intake-sources.json,cwd/data/links.jsonl,home/is/last-run,home/is/swept-keys.txt","files":{"cwd/_meta/backlog-staging.md":"# Backlog staging (auto, via backlog-stage)\n\nCandidates auto-extracted from sessions. Review + promote by hand.\nGitignored: may name unfiled work. NEVER the source of truth.\n\n## [staged] Vietnamese tax\n- Intent: https://ex.com/tax\n- Approach: https://ex.com/tax\n- Tags: #u-hi #f-mid\n- Home: ops\n- Source: intake-sweep links @TODAY@","home/is/swept-keys.txt":"https://ex.com/tax"}}
      got:  {"name":"board-cr-line-breaks","rc":0,"stdout":"🧲 intake-sweep: staged 3 candidate(s) (links: 3) in @CWD@/_meta/backlog-staging.md.","stderr":"","log":"","stray":"cwd/_meta/BACKLOG.md,cwd/_meta/backlog-staging.md,cwd/_meta/intake-sources.json,cwd/data/links.jsonl,home/is/last-run,home/is/swept-keys.txt","files":{"cwd/_meta/backlog-staging.md":"# Backlog staging (auto, via backlog-stage)\n\nCandidates auto-extracted from sessions. Review + promote by hand.\nGitignored: may name unfiled work. NEVER the source of truth.\n\n## [staged] Rust ownership\n- Intent: learn the borrow checker\n- Approach: https://ex.com/rust\n- Tags: #u-hi #f-mid\n- Home: ops\n- Source: intake-sweep links @TODAY@\n\n## [staged] Pick a DB\n- Intent: compare engines\n- Approach: https://ex.com/db\n- Tags: #u-hi #f-mid\n- Home: ops\n- Source: intake-sweep links @TODAY@\n\n## [staged] Vietnamese tax\n- Intent: https://ex.com/tax\n- Approach: https://ex.com/tax\n- Tags: #u-hi #f-mid\n- Home: ops\n- Source: intake-sweep links @TODAY@","home/is/swept-keys.txt":"https://ex.com/rust\nhttps://ex.com/db\nhttps://ex.com/tax"}}
    FAIL board-vt-line-breaks
      want: {"name":"board-vt-line-breaks","rc":0,"stdout":"🧲 intake-sweep: staged 1 candidate(s) (links: 1) in @CWD@/_meta/backlog-staging.md.","stderr":"","log":"","stray":"cwd/_meta/BACKLOG.md,cwd/_meta/backlog-staging.md,cwd/_meta/intake-sources.json,cwd/data/links.jsonl,home/is/last-run,home/is/swept-keys.txt","files":{"cwd/_meta/backlog-staging.md":"# Backlog staging (auto, via backlog-stage)\n\nCandidates auto-extracted from sessions. Review + promote by hand.\nGitignored: may name unfiled work. NEVER the source of truth.\n\n## [staged] Vietnamese tax\n- Intent: https://ex.com/tax\n- Approach: https://ex.com/tax\n- Tags: #u-hi #f-mid\n- Home: ops\n- Source: intake-sweep links @TODAY@","home/is/swept-keys.txt":"https://ex.com/tax"}}
      got:  {"name":"board-vt-line-breaks","rc":0,"stdout":"🧲 intake-sweep: staged 3 candidate(s) (links: 3) in @CWD@/_meta/backlog-staging.md.","stderr":"","log":"","stray":"cwd/_meta/BACKLOG.md,cwd/_meta/backlog-staging.md,cwd/_meta/intake-sources.json,cwd/data/links.jsonl,home/is/last-run,home/is/swept-keys.txt","files":{"cwd/_meta/backlog-staging.md":"# Backlog staging (auto, via backlog-stage)\n\nCandidates auto-extracted from sessions. Review + promote by hand.\nGitignored: may name unfiled work. NEVER the source of truth.\n\n## [staged] Rust ownership\n- Intent: learn the borrow checker\n- Approach: https://ex.com/rust\n- Tags: #u-hi #f-mid\n- Home: ops\n- Source: intake-sweep links @TODAY@\n\n## [staged] Pick a DB\n- Intent: compare engines\n- Approach: https://ex.com/db\n- Tags: #u-hi #f-mid\n- Home: ops\n- Source: intake-sweep links @TODAY@\n\n## [staged] Vietnamese tax\n- Intent: https://ex.com/tax\n- Approach: https://ex.com/tax\n- Tags: #u-hi #f-mid\n- Home: ops\n- Source: intake-sweep links @TODAY@","home/is/swept-keys.txt":"https://ex.com/rust\nhttps://ex.com/db\nhttps://ex.com/tax"}}
    FAIL staging-cr-line-breaks
      want: {"name":"staging-cr-line-breaks","rc":0,"stdout":"🧲 intake-sweep: staged 1 candidate(s) (links: 1) in @CWD@/_meta/backlog-staging.md.","stderr":"","log":"","stray":"cwd/_meta/backlog-staging.md,cwd/_meta/intake-sources.json,cwd/data/links.jsonl,home/is/last-run,home/is/swept-keys.txt","files":{"cwd/_meta/backlog-staging.md":"## [staged] Rust ownership\r- Intent: x\r## [staged] Pick a DB\r## [staged] Vietnamese tax\n- Intent: https://ex.com/tax\n- Approach: https://ex.com/tax\n- Tags: #u-hi #f-mid\n- Home: ops\n- Source: intake-sweep links @TODAY@","home/is/swept-keys.txt":"https://ex.com/tax"}}
      got:  {"name":"staging-cr-line-breaks","rc":0,"stdout":"🧲 intake-sweep: staged 3 candidate(s) (links: 3) in @CWD@/_meta/backlog-staging.md.","stderr":"","log":"","stray":"cwd/_meta/backlog-staging.md,cwd/_meta/intake-sources.json,cwd/data/links.jsonl,home/is/last-run,home/is/swept-keys.txt","files":{"cwd/_meta/backlog-staging.md":"## [staged] Rust ownership\r- Intent: x\r## [staged] Pick a DB\r## [staged] Rust ownership\n- Intent: learn the borrow checker\n- Approach: https://ex.com/rust\n- Tags: #u-hi #f-mid\n- Home: ops\n- Source: intake-sweep links @TODAY@\n\n## [staged] Pick a DB\n- Intent: compare engines\n- Approach: https://ex.com/db\n- Tags: #u-hi #f-mid\n- Home: ops\n- Source: intake-sweep links @TODAY@\n\n## [staged] Vietnamese tax\n- Intent: https://ex.com/tax\n- Approach: https://ex.com/tax\n- Tags: #u-hi #f-mid\n- Home: ops\n- Source: intake-sweep links @TODAY@","home/is/swept-keys.txt":"https://ex.com/rust\nhttps://ex.com/db\nhttps://ex.com/tax"}}
  intake-sweep parity: 148 passed, 12 failed

Restore: git checkout HEAD -- hooks/intake-sweep.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Not proven

- A real SessionStart payload was not captured live; the hook ignores its stdin, so the payload shape is not part of the behavior.
- The real command source (`tools/safari-tabs/bin/safari-tabs collections`) needs Safari and was replaced by a stub that prints two items; its reader path is the same one the corpus exercises.
- The recorded divergences (spec, Failure modes) are the known and judged unrealistic ones: leading-zero numbers, Python's float `str()`, a `\u0001` in a name, characters newer than Python 3.12's Unicode data.
- jq 1.6 is untested; the floor is the two versions run here.
