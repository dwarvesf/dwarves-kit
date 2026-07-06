# Proof of done, kit-foldin SG-03: session-tools

**Task:** move `cc-{observe,recall,intel}` into the kit as `tools/session-{observe,recall,intel}`
(drop `cc-`), extract the ONE genuinely-duplicated JSONL turn-parser to
`lib/session/parse_transcript.py` (+ `parse-transcript.sh` launcher), rewire both
`session-observe` (all 3 bins) and `session-recall` to call it; keep the two
CLIs separate.
**Class:** behavioral, untrusted input (parses attacker/error-shaped transcript
JSONL) · **Lane:** normal · **rid/slug:** `kit-foldin-03-session`
**Branch:** `feat/kit-foldin-03-session`

## Design: the shared-parser interface (bearing)

`lib/session/parse_transcript.py` exposes exactly two functions, both operating
on the RAW parsed entry (a plain `dict`), not a new wrapper type:

```python
def iter_entries(path: str) -> Iterator[dict]:
    """Stream one parsed JSON object per valid line, in file order.
    Blank lines skipped. A line that fails json.loads is skipped silently
    (never raised -- the schema is untrusted input). Raises FileNotFoundError /
    OSError if `path` itself cannot be opened; empty file yields nothing
    (honest-zero, not an error)."""

def load(path: str) -> list[dict]:
    """list(iter_entries(path)) -- for a caller that needs random access."""
```

**Why this shape and not a `Turn` dataclass with role/ts/text fields.** The
literal duplication between the two source tools was ONLY the file-open /
strip-blank-lines / `json.loads` / skip-malformed loop (`cc-observe`'s
`iter_entries` vs `cc-recall`'s `load`) -- byte-identical logic, two copies.
Everything downstream of "here is one parsed JSON object" is NOT duplicated:
`session-observe`'s `collect()` inspects `hookInfos`, `message.usage`,
`isSidechain`, `isCompactSummary`, and walks every content block by `type`
(`tool_use`/`tool_result`/`text`) doing tool/skill/hook tallying that
`session-recall` never needs; `session-recall`'s `_role()`/`_ts()`/
`searchable_text()` render a turn as a human-readable snippet that
`session-observe` never needs. Wrapping the raw dict in a `Turn(role=, ts=,
text=)` object would force EVERY caller to pay for accessors only one of them
uses, and would still leave `session-observe`'s real per-block logic
untouched, i.e. it would look like a bigger merge without actually resolving
more duplication than the plain-dict version does. The plain-dict interface
is the maximal shared surface with zero forced abstraction on either side,
which is the point open-Q 1 resolved (b) for: extract the parser, not the
capability.

**Streaming vs. materializing** stays a caller choice, not the shared module's:
`session-observe` streams (`iter_entries`, one file at a time, across
possibly hundreds of transcripts under `~/.claude/projects`) so it never holds
more than one file in memory; `session-recall` materializes (`load`) because
point-lookup search needs `entries[i]` random access for its turn index. Both
functions share ONE inner loop (`load = list(iter_entries(...))`), so the
parsing behavior itself (encoding, blank-line skip, decode-skip) can only
drift in one place even though the two callers consume it differently.

**A third call site found and fixed in the same pass:** `session-observe`'s
own `cc-semantic` bin (LLM topic-drift signal) and `session-intel`'s
`repeat_detect()` (bash-3-gram extraction) each carried their OWN copy of the
identical loop (a `for line in open(...): json.loads(line)` with a
try/except). Neither was named in the design note's disposition table (only
`cc-observe`+`cc-recall` were flagged as the "earned" merge), but leaving them
as unconverted third/fourth copies would make the Done gate's "no duplicate
turn-parser remains" claim false by omission. Both now call
`parse_transcript.iter_entries` too.

## `lib/session/parse-transcript.sh`: why a bash launcher over Python logic

Same shape as the pre-existing `lib/gate/proof-table-gen.sh` (bash launcher,
`exec python3 <sibling>.py "$@"`): the parsing logic is Python because both
CLIs that need it are Python (JSONL parsing in bash means re-implementing
`json.loads` or shelling to `jq` per line -- slower, and a second
implementation of the exact routine this file exists to de-duplicate). Neither
CLI shells out to `parse-transcript.sh` at runtime; each `import`s the sibling
`.py` module directly (in-process, no subprocess per file). The `.sh` launcher
exists so the parser is independently invocable/testable as a standalone unit
(`bash lib/session/parse-transcript.sh <file.jsonl>` -> NDJSON to stdout),
per the goal's "unit test exercising `lib/session/parse-transcript.sh`
directly" requirement.

## session-intel's `deploy/` disposition: stayed in ops-toolkit

`cc-intel`'s `deploy/macos/{cc-intel-weekly.plist, cc-intel-weekly, cc-intel-runbook.md}`
did NOT move. The plist hardcodes `ProgramArguments[0]` to an absolute
`/Users/tieubao/workspace/tieubao/ops-toolkit/...` path and the runbook assumes
an ops-toolkit checkout; unlike `skill-curator`'s `deploy/install.sh`
(SG-04), there is no generic install script inside `cc-intel`'s `deploy/` to
separate out -- the WHOLE directory is the personal launchd cron. Per the
`deploy-follows-source` rule, that only applies when the deploy is generic;
here it is not, so it stays in ops-toolkit (same judgment call SG-04 recorded
for `cc-self-improve`'s personal plist). SG-07 must preserve it when it hard-
removes the rest of `ops-toolkit/tools/cc-intel/`.

## Confirmation run-table (green run, over the committed synthetic fixture)

Fixture: `lib/session/tests/fixtures/sample.jsonl` (9 synthetic JSONL turns: a
user prompt, 3 `Bash` tool_use/result pairs forming a non-benign 3-gram, one
`Skill` tool_use that errors, one assistant text turn with a findable phrase).
No real personal content.

| # | Check | Command | Exit | Verdict |
|---|---|---|---|---|
| 1 | session-observe aggregate table (skills) | `python3 tools/session-observe/bin/cc-observe skills --file lib/session/tests/fixtures/sample.jsonl` | 0 | PASS -- `knowledge-capture 1 1 100%` |
| 2 | session-observe aggregate table (tools) | `python3 tools/session-observe/bin/cc-observe tools --file lib/session/tests/fixtures/sample.jsonl` | 0 | PASS -- `Bash 3 0 0%`, `Skill 1 1 100%` |
| 3 | session-recall point-lookup hit | `python3 tools/session-recall/bin/cc-recall thundering-herd --file lib/session/tests/fixtures/sample.jsonl` | 0 | PASS -- turn 8, snippet marks `»thundering-herd«` |
| 4 | session-intel digest (cross-tool, over the fixture) | `CC_INTEL_OBSERVE_CMD="python3 tools/session-observe/bin/cc-observe report --file lib/session/tests/fixtures/sample.jsonl" CC_INTEL_SWEEP_CMD=false python3 tools/session-intel/bin/cc-intel run --out <tmp> --transcripts lib/session/tests/fixtures --min 1 --ledger "" --glossaries ""` | 0 | PASS -- digest has all 4 sections; observe section populated live, repo-sweep honest `_unavailable_`, repeat-detect flags `git status => git diff => git commit -m wip` |
| 5 | parser unit test (`lib/session/parse-transcript.sh` directly) | `bash lib/session/tests/test-parse-transcript.sh` | 0 | PASS -- 7/7 (golden 9-in/9-out, all-valid-JSON, 3 NCs, Python API contract) |
| 6 | session-observe existing suite, unmodified | `bash tools/session-observe/tests/smoke.sh && bash tools/session-observe/tests/test-vps-report.sh` | 0 | PASS -- 40/40 + 6/6 (identical to pre-extraction) |
| 7 | session-recall existing suite, unmodified | `python3 -m unittest discover -s tools/session-recall/tests` | 0 | PASS -- 7/7 |
| 8 | session-intel existing suite, unmodified | `bash tools/session-intel/tests/smoke.sh` | 0 | PASS -- 8/8 |
| 9 | kit-wide meta suite, unaffected | `bash tests/test-meta.sh` | 0 | PASS -- 672/672 |

```
Command: bash lib/session/tests/test-parse-transcript.sh
[1] golden path: 9 turns in, 9 valid JSON objects out ... ok
[2] golden path: every emitted line is valid JSON ... ok
[3] NC malformed: one bad line skipped, the two good ones survive, exit 0 ... ok
[4] NC empty transcript: honest-zero (0 lines, exit 0, no crash) ... ok
[5] NC missing file: clean one-line stderr message, exit 1, no Python traceback ... ok
[6] NC no argument: usage + exit 2 (not a crash) ... ok
[7] Python API: iter_entries generator, load list, content preserved ... ok
smoke: all 7 passed
Exit: 0
Verdict: PASS
```

## LOAD-BEARING negative controls (untrusted-input parsing)

### NC1, empty transcript = honest-zero, not a crash
```
Command: bash lib/session/parse-transcript.sh lib/session/tests/fixtures/empty.jsonl; echo "rc=$?"
(no output)
rc=0
```
Also exercised end-to-end: `cc-observe report --file <empty>` prints every
section as `(none)` / `0 transcripts`-shaped output, never a traceback (this
was already the tools' own pre-extraction behavior; the shared parser
preserves it -- `iter_entries` on an empty file is simply an exhausted
generator, zero iterations, zero exceptions).
Verdict: PASS

### NC2, one malformed JSONL line is skipped, not fatal
`lib/session/tests/fixtures/malformed.jsonl` = 1 valid line, 1 line that is
not valid JSON, 1 valid line.
```
Command: bash lib/session/parse-transcript.sh lib/session/tests/fixtures/malformed.jsonl | wc -l
2
Command: bash lib/session/parse-transcript.sh lib/session/tests/fixtures/malformed.jsonl >/dev/null; echo "rc=$?"
rc=0
```
Verdict: PASS (2 of 3 lines survive; the bad line is silently skipped, exactly
the pre-extraction behavior of both `cc-observe`'s `iter_entries` and
`cc-recall`'s `load`)

### NC3, missing transcript file/dir = a clean error, never a raw traceback
```
Command: bash lib/session/parse-transcript.sh /no/such/dir/file.jsonl; echo "rc=$?"
parse-transcript: [Errno 2] No such file or directory: '/no/such/dir/file.jsonl'
rc=1
```
Verdict: PASS (one-line stderr message, exit 1, no `Traceback (most recent
call last)`)

### NEGATIVE CONTROL, the extraction is load-bearing (revert it -> the duplicate reappears)
Reverted `tools/session-observe/bin/cc-observe`'s `iter_entries` in place to
its pre-extraction inline body (the shared parser and every other caller left
untouched) and re-ran the grep the Done gate keys on, then restored via
`git checkout --`:
```
Command: <edit cc-observe's iter_entries back to its own open/strip/json.loads/except loop>
Command: grep -rn "JSONDecodeError" tools/session-observe tools/session-recall lib/session
tools/session-observe/bin/cc-observe:150:            except json.JSONDecodeError:
tools/session-observe/bin/cc-semantic:112:    except json.JSONDecodeError:
lib/session/parse_transcript.py:64:            except json.JSONDecodeError:
Verdict: RED (expected -- reverting one caller reintroduces a second copy of the loop; 3 sites, not 2)

Command: git checkout -- tools/session-observe/bin/cc-observe
Command: grep -rn "JSONDecodeError" tools/session-observe tools/session-recall lib/session
tools/session-observe/bin/cc-semantic:112:    except json.JSONDecodeError:
lib/session/parse_transcript.py:64:            except json.JSONDecodeError:
Verdict: PASS (restored -- exactly one JSONL-line-decode site left outside cc-semantic's
unrelated LLM-response-parsing `parse_json()`, which is a different concern, not a transcript parser)

Command: bash tools/session-observe/tests/smoke.sh | tail -2
smoke: all 40 passed
Verdict: PASS (restore did not regress the suite)
```
The grep flips exactly with the extraction's presence: the Done gate's
"no duplicate turn-parser remains" claim is load-bearing, not decorative.

**Overall Verdict: PASS**

## COVERAGE-DELTA: what the shared parser covers vs. what stays per-CLI

| Concern | Covered by `lib/session/parse_transcript.py` | Stays in the calling CLI |
|---|---|---|
| Open file, decode UTF-8 | yes | |
| Skip blank lines | yes | |
| `json.loads` one line | yes | |
| Skip a line that fails to parse | yes | |
| Missing-file error shape | yes (raises; caller decides per-file-skip vs. reported) | |
| Streaming vs. materializing | yes (`iter_entries` / `load`, one inner loop) | |
| Directory/file-set resolution (`--root`/`--project`/`--all`, mtime cutoff, cwd-slug) | | session-observe's `iter_files`, session-recall's `resolve_files` (different resolution rules per tool, never shared) |
| Role/timestamp extraction | | session-recall's `_role`/`_ts` (session-observe inlines its own `type=="user"` / `ts=entry.get(...)` checks -- never needed a named helper) |
| Searchable-text rendering, snippet marking | | session-recall's `searchable_text`/`_snippet`/`render` |
| Aggregate tallying (skills/tools/hooks/subagents/friction/sessions/cost) | | session-observe's `collect()` -- the entire reason it stays a separate CLI from session-recall |
| Bash-command 3-gram extraction | | session-intel's `_bash_cmds`/`repeat_detect` (built on top of `iter_entries`, but the gram logic itself is intel's own) |

## Reproduce

```bash
cd <dwarves-kit-worktree>
bash lib/session/tests/test-parse-transcript.sh
bash tools/session-observe/tests/smoke.sh
bash tools/session-observe/tests/test-vps-report.sh
python3 -m unittest discover -s tools/session-recall/tests
bash tools/session-intel/tests/smoke.sh
bash tests/test-meta.sh

python3 tools/session-observe/bin/cc-observe skills --file lib/session/tests/fixtures/sample.jsonl
python3 tools/session-recall/bin/cc-recall thundering-herd --file lib/session/tests/fixtures/sample.jsonl
d=$(mktemp -d)
CC_INTEL_OBSERVE_CMD="python3 tools/session-observe/bin/cc-observe report --file lib/session/tests/fixtures/sample.jsonl" \
CC_INTEL_SWEEP_CMD=false \
python3 tools/session-intel/bin/cc-intel run --out "$d" --transcripts lib/session/tests/fixtures --min 1 --ledger "" --glossaries ""
cat "$d"/intel-*.md

grep -rn "JSONDecodeError" tools/session-observe tools/session-recall lib/session   # exactly 2 sites, one is parse_transcript.py, the other cc-semantic's unrelated parse_json()
grep -rn "workspace/tieubao" tools/session-observe tools/session-recall tools/session-intel lib/session   # empty
```

## What moved (folded from prior docs/proof/kit-foldin-session-tools.md)

`ops-toolkit/tools/cc-observe` -> `tools/session-observe/` (3 bins: `cc-observe`,
`cc-semantic`, `cc-vps-report`, unchanged names). `ops-toolkit/tools/cc-recall`
-> `tools/session-recall/` (`bin/cc-recall`, `cc_recall.py`, unchanged names).
`ops-toolkit/tools/cc-intel` -> `tools/session-intel/` (`bin/cc-intel`, unchanged
name) MINUS its `deploy/` (a personal launchd cron with a hardcoded
`/Users/tieubao/...` plist path and an ops-toolkit-assuming runbook -- it is not
a generic install script the way skill-curator's was, so deploy-follows-source
does not pull it into the kit; it stays in ops-toolkit for SG-07 to preserve).

History carried over per-commit via `git format-patch --relative` +
`git am --directory` (18 commits total: 12 for observe, 1 for recall, 5 for
intel), the same technique SG-04 used for skill-curator -- `git log --follow`
on the new kit path still walks back through the ops-toolkit-era commits.

## Gate ledger

`bash lib/gate/gate-ledger.sh show kit-foldin-03-session` records: START (lane
normal), GATE design (ran -- Design: bearing, the interface decision above),
GATE build (ran -- move + extraction + rewire, 40+6+7+8 = 61 pre-existing
tests green unmodified + 7 new parser-unit tests), GATE review (dispatched
`kit:code-reviewer`, security lens, over untrusted-input parsing), GATE
recheck (dispatched `kit:recheck-verifier`, fresh-context re-run of the
run-table + NCs), GATE ship (this PR).
