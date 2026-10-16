# SPEC-407: intake-sweep runs as bash plus jq

**Status:** VALIDATED, revision 2 (round 1 NEEDS REVISION folded; see Decision Log)
Lane: full
Type: spec-refactor
**Proof:** `docs/verification/intake-sweep-bash.md`; `tests/test-intake-sweep-parity.sh`, `tests/test-staging-format-jq.sh`, `tests/test-hook-util.sh`, `tests/test-intake-sweep.sh`.
References: `hooks/intake-sweep.py` and `lib/reflect/staging-format.py` at `b9306b37` (the behavior to reproduce); `docs/specs/SPEC-406-context-hints-bash.md` (the port before this one, and the harness it extended); `tests/lib/hook-parity.sh`.

## Problem

`hooks/intake-sweep.sh` is a shim that runs `hooks/intake-sweep.py`. `docs/PHILOSOPHY.md` rules out Python in hooks, and the operator decided on 2026-09-28 to port the Python hooks to bash plus jq, one PR per hook. intake-sweep runs at every SessionStart (through `backlog-stage.sh --surface`) and, with `BACKLOG_STAGE_AUTO` off, not at all, so its cost is one python3 start per session on a consumer that opted in.

The Python imports `lib/reflect/staging-format.py` for the staging-block grammar. A bash port cannot import it, and `backlog-stage` (the next port) needs the same grammar, so the grammar gets a jq twin that both hooks load.

## Contract

`hooks/intake-sweep.sh` does the whole job in bash and jq. It reproduces the Python hook's observable behavior: stdout, stderr, exit code, the staging file, and the swept-keys and throttle files.

| Observable | Rule |
|---|---|
| Exit code | always 0. A shape the Python crashed on stages nothing, writes no swept keys, and prints nothing; the throttle stamp it had already written stays |
| Root | `$REPO_ROOT` when set and non-empty, else `git rev-parse --show-toplevel`, else the physical cwd. A path joined to the root (`_meta/...`, a jsonl `path`, a command's first word) is joined as `os.path.join` does: a trailing slash on the root is not doubled. The `--check` message prints `<root>/_meta/intake-sources.json` with a plain slash |
| Config | `$INTAKE_SWEEP_CONFIG` when non-empty, else `<root>/_meta/intake-sources.json`. It must hold exactly one JSON object whose `sources` is a list; anything else, a missing file, invalid UTF-8, or a BOM means no sources |
| No sources | exit 0 with no output, before the throttle, so no stamp is written |
| `--check` | prints per source `  ok   <name> (<kind>): N item(s), T titled, U with url` (`WARN` and counted when N is 0), `  FAIL <name>: unknown kind '<kind>' (expected: command/jsonl)` for an unknown kind, `  ?  (malformed source entry, not an object)` for a non-object, then `intake-sweep check: <n> source(s), <b> needing attention`. With no sources: `intake-sweep: no sources configured (looked in <root>/_meta/intake-sources.json)`. It ignores the throttle and writes nothing |
| Throttle | skipped by `--force`. `$INTAKE_SWEEP_MIN_INTERVAL` as an integer (blanks and a sign allowed; more than 18 digits clamps), default 86400 for an unset value or one that is not an integer; zero or negative turns it off. The stamp's age comes from GNU `stat` first and BSD `stat` second, so the throttle works on Linux. Otherwise the stamp `<state dir>/last-run`: when it exists and is younger than the interval, exit 0; else create it and go on. A state dir that cannot be created means no throttling |
| State dir | `$INTAKE_SWEEP_STATE_DIR` when SET (empty means the cwd, and the directory cannot be created), else `~/.claude/dwarves-kit/state/intake-sweep` |
| Sources | each entry that is an object, in order. `kind` `jsonl` or `command`; any other kind prints `intake-sweep: source '<name>' has unknown kind '<kind>' (expected: command/jsonl), skipped` on stderr and is skipped (no count entry). `name` defaults to `?`; Python's `str()` of a non-string scalar name (`7`, `None`). A `kind` that is a list or object, and (in a sweep, not in `--check`) a `name` that is, crash the Python: nothing is staged |
| jsonl | `path` (relative to the root unless absolute); a missing, unreadable, or non-file path gives no items; a file that is not valid UTF-8 ends the run. Each non-blank line (surrounding blanks stripped) that parses as one JSON object is an item; others are skipped, a first line that starts with a BOM included. `include` `{field, equals}`, when a non-empty object, keeps the item when `str(item[field])` equals `str(equals)`, a missing field counting as `""`; an `include` that is truthy and not an object ends the run only when an object line reaches it (an empty file, or a file of non-objects, never does) |
| command | `command` is split like Python's `shlex.split` (quotes, backslashes, no globbing, no shell) and run from the root, its first word joined to the root when it contains a `/` and is not absolute. Exit 0 and a stdout that is exactly one JSON array (valid UTF-8, no BOM) give its object items; anything else gives none. The timeout is `$INTAKE_SWEEP_CMD_TIMEOUT` seconds (default 15; a value that is not an integer gives no items, read before an empty command fails; zero or less starts the command and kills it at once); a command that overruns is killed. An empty command string gives no items; a command string that is only blanks ends the run |
| Item mapping | `map` `{title, url, intent}` names the item's fields (defaults `title`, `url`, no intent); a key that is a list or object ends the run when an item reaches it. A value is Python's `str()` of it when truthy, else `""`. A title that is blank becomes the url; the url is stripped |
| Dedup | the board and staging files are read as Python reads text (invalid UTF-8, or a file that exists and cannot be read, ends the run); `\r\n` and a lone `\r` are line breaks everywhere, and the board and swept-keys files also break at `\v`, `\f`, `\x1c`-`\x1e`, `\x85`, and U+2028/2029. An item is skipped when its key (the url, else its normalized title) is empty or already in the swept-keys file; when its normalized title is on the board (`\| ID-N \| Item \|` rows) or in any staging block heading; or when its url occurs anywhere in the board text or the staging text. Within a run, a staged item adds its key and its title to the known sets |
| Block | the shared grammar: title, intent (else the url), approach (the url, else `(no url)`), `#u-` and `#f-` from the source (`hi`, `mid`, `lo`, else `lo` and `mid`), home, and `Source: intake-sweep <name> <date>`; every field's whitespace collapsed to single spaces |
| Files | the board is `$BACKLOG_STAGE_BACKLOG` (default `<root>/_meta/BACKLOG.md`), staging `$BACKLOG_STAGE_STAGING` (default `<root>/_meta/backlog-staging.md`); a set-but-empty value is the empty path. Staging gets a four-line header when the file is new, then the blocks, appended. A staging path with no directory part, or one that cannot be written, stages nothing and records nothing |
| Swept keys | after a successful append, one line per staged key appended to `<state dir>/swept-keys.txt` (a failure is silent) |
| Output | `🧲 intake-sweep: staged N candidate(s) (<name>: n, ...) in <staging>.`, naming only sources that staged something |
| jq missing | exit 0 and print one line to stderr naming the missing tool (the sweep is off) |

`hooks/intake-sweep.py` is deleted. `lib/reflect/staging-format.py` stays: `drain.py`, `propose.py`, `wrap`, and the stats code import it. New: `lib/reflect/staging-format.jq` (the grammar's jq twin) and `lib/reflect/shlex-split.sh` (`shlex.split` in bash), both pinned to their Python by `tests/test-staging-format-jq.sh`.

## Picture

```
 SessionStart --> backlog-stage.sh --surface --> hooks/intake-sweep.sh
                                                      |
                                _meta/intake-sources.json (none: exit 0)
                                                      |
                      throttle stamp <--- interval --->|
                                                      v
        per source:  jsonl file --jq--+--> items {title, url, intent}
                     command (shlex) -+
                                                      |
        board + staging + swept keys --> dedup (lib/reflect/staging-format.jq: norm, keys, render)
                                                      |
                              append blocks to staging, append keys, print one line
```

## Design

The per-source reading stays in bash (file tests, the command run with a timeout, the stderr warning), and one jq program does the dedup and the rendering for all sources at once, so a crash shape in any source stops the whole run before a byte is written, as the Python did.

`lib/reflect/staging-format.jq` is a twin, not a replacement: four Python modules import `staging-format.py` as a library, and rewriting them is out of scope. The twin is small and a test pins it to the Python on a shared corpus, so the grammar still has one definition in effect.

Three details that decide parity:

| Detail | Choice |
|---|---|
| Case folding for the dedup key | `str.casefold` is full Unicode folding. A table of 195 ranges and 104 multi-character entries, generated from Python 3.12, reproduces it; `test-staging-format-jq.sh` pins every changed code point. `ascii_downcase` would split `ĐÀ NẴNG` from `đà nẵng` |
| Word runs | `[^\\W_]+` equals `[\\p{L}\\p{N}]+` on every code point Python 3.12 knows; Oniguruma also knows the newer ones |
| Staging headings | Python reads a block from its heading to the next one, and a bare `## [staged]` heading borrows the next line as its title. The twin splits blocks at heading starts and applies the heading pattern to each block alone, so it borrows the same line |

## Failure modes

| Class | Mitigation |
|---|---|
| A rule differs from Python | the parity corpus (goldens from Python) and `test-staging-format-jq.sh` fail |
| Out of parity, no realistic input | invalid UTF-8 in a source file; a JSON line with `NaN`; a map value, name, or kind that is a list or object (Python prints its repr); `\\r` alone as a line break in a jsonl file; a Unicode character assigned after Python 3.12's database; `str.strip()` whitespace that Oniguruma's `\\s` omits (`\\x1c` to `\\x1f`, folded in by hand) |
| The command inherits stdin | the Python let the command read the hook's stdin; the port runs it in the background, where bash gives it `/dev/null`. No source command reads stdin |
| A grandchild that keeps stdout open | the Python waits for the pipe to close and times out with no items; the port reads the file once the command exits and keeps the items |
| Read order | the Python reads the board and staging before the sources run; the port reads them after |
| A command that forks and outlives the timeout | the port kills the process it started, as Python's `subprocess.run` does; grandchildren survive in both |
| No lock on the staging file | as in Python; two sweeps at once can interleave blocks. The daily throttle makes it rare |
| jq missing | exits 0 and names the missing tool on stderr |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: harness | `tests/lib/hook-parity.sh`, `tests/test-hook-parity-lib.sh` | `args`, executable seeds, `touch`, `@TODAY@`, and `HP_EXTRA_FILES` work and are self-tested |
| T2: grammar twin and helpers | `lib/reflect/staging-format.jq`, `lib/reflect/shlex-split.sh`, `lib/reflect/hook-util.sh`, `tests/test-hook-util.sh`, `tests/fixtures/staging-format-jq/`, `tests/test-staging-format-jq.sh` | the five checks pass |
| T3: goldens | `tests/fixtures/intake-sweep-parity/` | cases and goldens generated from the Python at `b9306b37` before the port |
| T4: port | `hooks/intake-sweep.sh`; delete `hooks/intake-sweep.py` | `bash tests/test-intake-sweep-parity.sh` passes; no `python` in the hook |
| T5: references | `hooks/backlog-stage.sh`, `docs/hooks.md`, `lib/reflect/README.md`, `lib/reflect/staging-format.py` header, `tests/test-intake-sweep.sh`, install and adopt lists | no live doc or test names `intake-sweep.py` as current code; backlog-stage calls the bash hook |
| T6: records | `docs/CHANGELOG.md`, `docs/verification/intake-sweep-bash.md`, `docs/implementation-notes/intake-sweep-bash.md`, `docs/retro/`, `docs/FEATURES.md` (regenerated) | CHANGELOG names the port |

## Test plan

| # | Check | Expect |
|---|---|---|
| P1 | `bash tests/test-intake-sweep-parity.sh` | every case passes, `0 failed` |
| P2 | `bash tests/test-staging-format-jq.sh`, `bash tests/test-hook-util.sh` | all checks pass, the Linux `stat` case included |
| P3 | P1 and P2 under `/bin/bash` (3.2) and `/usr/bin/jq` (1.7.1) | pass |
| P4 | `bash tests/test-intake-sweep.sh`, `bash tests/test-kit-foldin-hooks.sh`, `bash tests/test-hook-parity-lib.sh` | exit 0 |
| P5 | the real digest ledger, board, and staging file through the Python and the port, three scenarios | identical stdout, staging bytes, and swept keys |
| P6 | `grep -c python hooks/intake-sweep.sh` | 0 |

Negative controls, through `lib/gate/negctl.sh` with P1 as the test command:

| Control | Mutation | Must go red |
|---|---|---|
| NC1 | drop the URL-substring dedup | `dup-board-url-in-notes`, `dup-board-url-is-substring`, `dup-staging-rejected-and-promoted`, `url-found-across-cr-in-board` |
| NC2 | skip the swept-keys file | `dup-swept-url`, `dup-swept-title-key` |
| NC3 | skip the board and staging title dedup | `dup-board-title`, `dup-staging-staged` |
| NC4 | write the staging header even when the file exists | `staging-append-existing` |
| NC5 | `ascii_downcase` in place of the casefold table (test: `test-staging-format-jq.sh`) | the casefold check |
| NC6 | never record the swept keys | `swept-keys-appended`, `jsonl-basic` |
| NC7 | treat single quotes as ordinary in `shlex-split.sh` (test: `test-staging-format-jq.sh`) | the shlex check |

## Verification

P1 to P6 hold and NC1 to NC7 report PASS. `bash tests/run-all.sh --changed` exits 0.

## After state

intake-sweep runs with no Python, and the staging grammar has a jq twin pinned to the Python. Its output, staging file, and state match the Python on the parity corpus and on the real consumer data. Two Python hooks remain (backlog-stage, harvest).

## Decision Log

- Goldens come from the Python hook at `b9306b37`, run through that revision's shim, before the port was written.
- The staging grammar gets a jq twin and a pinning test rather than a rewrite of its four Python importers.
- The Python swallowed a crash (`|| true`), so a crash case's golden is a silent exit 0 plus whatever the Python had already written (the throttle stamp); the port matches both.
- Revision 2 (round 1 of the fresh review, NEEDS REVISION, two critical findings): the stamp's age is read with GNU `stat` first (BSD `stat -f %m` on Linux prints several lines and exits 1, so the throttle died after its first stamp); the command source's temp file and its watchdog `sleep` are cleaned up; the items and the batch go to jq through files, not arguments (a 6,000-row ledger overran the argument limit); `include`, `kind`, `name`, and the map keys crash where Python crashes; a BOM and invalid UTF-8 are read as Python reads them; line breaks follow `splitlines` and universal newlines; a joined root path is not doubled; an unset `HOME` no longer stops the hook. 27 corpus cases pin these and `tests/test-hook-util.sh` pins the helpers (new `lib/reflect/hook-util.sh`, shared by the three staging hooks).
