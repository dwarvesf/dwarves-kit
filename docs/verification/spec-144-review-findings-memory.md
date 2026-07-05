# Verification: SPEC-144 review findings memory

Real dispatch, not a hand-simulated transcript: the fixture runs below are genuine
`general-purpose` subagent invocations via the Task tool, reading real fixture files on disk;
the live-emit run is a genuine `kit:code-reviewer` dispatch over this branch's actual diff. The
fixture and both prompts are reproducible from this file. Follows the same real-dispatch
precedent SPEC-143's verification doc set (`docs/verification/spec-143-stale-adr-inversion.md`).

## Fixture

```
$FIXTURE/
├── notify.py                                  # two real defects, one previously rejected
└── docs/verification/rejected-findings.md     # seeded ledger
```

`notify.py`:
```python
import sqlite3


def log_event(db_path: str, event: str) -> None:
    """Best-effort telemetry: never let a broken logger crash the caller."""
    try:
        conn = sqlite3.connect(db_path)
        conn.execute("INSERT INTO events (payload) VALUES ('%s')" % event)
        conn.commit()
        conn.close()
    except:
        pass
```
Two independent, real defects at the same file: (1) a bare `except: pass` (defect-slug
`bare-except`) -- the SEEDED, previously-rejected pattern; (2) SQL built by `%`-formatting a
caller-controlled string into a query (defect-slug `sql-injection`) -- a genuine, NOVEL defect
that shares nothing with (1) except the file path.

`docs/verification/rejected-findings.md` (fixture copy):
```
| date | lens | finding-key | verdict | reason |
|---|---|---|---|---|
| 2026-06-20 | security | bare-except:notify.py | rejected | intentional: telemetry must never crash the caller; the bare except is deliberate fail-open behavior for optional logging |
```

## Run 1: CORRECT match rule (whole finding-key: slug AND path) -- GREEN

Dispatched via `Agent(subagent_type: "general-purpose")`, given the fixture file, the ledger,
and the exact SPEC-144 matching rule ("match ONLY on the whole finding-key ... never on the
file path alone ... a defect with a DIFFERENT slug at the same file path is NOT a match").

Result (verbatim from the agent):
```
## Fresh findings
[1] sql-injection:notify.py -- Line 8 builds the SQL statement with `%` string formatting on
`event`, so any single quote in `event` breaks out of the string literal and allows arbitrary
SQL injection.
[2] resource-leak:notify.py -- Lines 7-10: `conn.close()` only runs on the success path; if
`execute()` or `commit()` raises, the bare `except` at line 11 swallows the error without
closing `conn`, leaking the sqlite connection/handle.

## Previously rejected
[1] bare-except:notify.py -- previously rejected 2026-06-20: intentional: telemetry must never
crash the caller; the bare except is deliberate fail-open behavior for optional logging
```

**Outcome: the previously-rejected `bare-except` is surfaced as "previously rejected", NOT
listed as a fresh finding; the novel `sql-injection` (and a bonus `resource-leak` the agent
found unprompted, also a novel finding-key) fires as fresh.** Exactly the two-sided behavior
SPEC-144 specifies. Note the agent found a THIRD, unseeded defect (`resource-leak`) entirely on
its own and correctly treated it as fresh too, further evidence the matching rule does not
over-suppress.

## Run 2: BROKEN match rule (file path alone, slug ignored) -- RED, the load-bearing NC break

Same fixture, same agent type, but the dispatch prompt's matching rule was deliberately
weakened to match on file path alone, ignoring the defect-slug ("if the ledger has ANY row
whose finding-key ends in that same file path, that counts as a match, regardless of what the
slug is") -- the exact bug SPEC-144's load-bearing property rules out.

Result (verbatim from the agent):
```
Findings from the file:
1. sql-injection (notify.py:8): `event` is interpolated directly into the SQL string via `%`
formatting instead of using a parameterized query ... allowing SQL injection or malformed-SQL
crashes.
2. bare-except (notify.py:11): bare `except:` swallows every exception ... with no logging,
masking real failures.

Ledger match check: the ledger has exactly one row, `bare-except:notify.py`. Per the literal
matching rule given ("match on file path portion only, slug irrelevant"), both candidates key
on the same file path (notify.py), so both mechanically match that single ledger row, even
though the row's actual reason only concerns the bare-except behavior and says nothing about
SQL construction.

## Fresh findings
(none)

## Previously rejected
[1] bare-except:notify.py -- previously rejected 2026-06-20: ...
[2] sql-injection:notify.py -- previously rejected 2026-06-20: ...

Flagging this rather than staying silent: the matching rule as specified (file-path-only, slug
ignored) is exploitable/wrong for real use. It let a genuine, unrelated SQL-injection defect
get suppressed under a rejection whose stated reason has nothing to do with SQL injection ...
One rejected-and-justified finding on a file should never blanket-cover every future
defect-shape in that same file.
```

**Outcome: with the match rule weakened to file-path-only, the NOVEL `sql-injection` finding
is WRONGLY suppressed** -- reported as "previously rejected" under a rejection reason that has
nothing to do with it. Zero fresh findings reach the report; a real security defect goes
silent. The agent itself flagged the bug unprompted, independent corroboration that the
file-only rule is unsound. This is the load-bearing negative control: restoring the
finding-key rule (Run 1, re-run identically above) turns the same fixture back GREEN, the novel
finding fires again.

## Run 3: pipe-anchoring fix (a SECOND, distinct load-bearing bug, caught by a live review)

A real `kit:code-reviewer` (architecture lens) dispatch over this spec's own diff (see "Live
emit" below for the full dispatch) found a CRITICAL issue independent of Run 1/Run 2 above:
`grep -F "<finding-key>"` with no anchoring is a **substring** match, not a whole-cell match,
so a SHORTER, unrelated defect-slug that happens to be a suffix of a longer rejected one
WOULD WRONGLY MATCH -- e.g. a fresh finding `except:notify.py` is a substring of the ledger row
`bare-except:notify.py` and would be wrongly suppressed, even though `except` and `bare-except`
are different defect shapes. Run 1/Run 2's fixture (`bare-except` vs `sql-injection`, no
shared suffix) never exercised this failure mode, so it slipped through undetected until a
real review looked at the literal grep invocation.

Reproduced directly (not simulated):
```
$ grep -F "except:notify.py" docs/verification/rejected-findings.md    # the ORIGINAL, buggy form
| 2026-06-20 | security | bare-except:notify.py | rejected | ...      # WRONGLY matches (exit 0)

$ grep -F "| except:notify.py |" docs/verification/rejected-findings.md   # the FIXED, pipe-anchored form
(no output, exit 1)                                                       # correctly no match

$ grep -F "| bare-except:notify.py |" docs/verification/rejected-findings.md   # the real key
| 2026-06-20 | security | bare-except:notify.py | rejected | ...           # still matches (exit 0)
```

**Fix applied:** all three consult-step instructions (`commands/review.md`,
`commands/review-team.md`, `agents/advisor.md`) and the ledger's own format doc
(`docs/verification/rejected-findings.md`) now specify `grep -F "| <finding-key> |"`
(pipe-space-key-space-pipe), anchoring the search to the whole table cell instead of a bare
substring, with an explicit "do not grep the bare finding-key" warning naming the exact
collision class (a shorter slug that is a suffix of a longer one, e.g. `auth` in
`no-auth-check`, `leak` in `secret-leak`).

## Over-test cases (deterministic, direct `grep -F`, pipe-anchored per the fix above -- the
literal mechanism the prose instructs every reviewer to run)

| Case | Command | Result | Interpretation |
|---|---|---|---|
| T4: missing ledger | `grep -F "\| bare-except:notify.py \|" nonexistent-ledger.md` | exit 2, no crash, no output | fail-open: reviewer treats any non-match/error as "no memory" and proceeds normally |
| T5: empty ledger (header only) | `grep -F "\| bare-except:notify.py \|" empty-ledger.md` | exit 1 (no match) | fail-open: zero rows means zero matches, review proceeds unaffected |
| T6a: malformed row does not block a real match | `grep -F "\| bare-except:notify.py \|" malformed-ledger.md` (file has one garbage non-table line above the real row) | exit 0, matching row printed | a malformed row is inert; the well-formed row below it still matches |
| T6b: malformed-row file, different slug | `grep -F "\| sql-injection:notify.py \|" malformed-ledger.md` | exit 1 (no match) | confirms T6a is a real match on the real row, not an accidental match on the garbage line |
| T7: cross-lens collision | `grep -F "\| bare-except:notify.py \|" collision-ledger.md` (row's `lens` column is `security`; a hypothetical `architecture`-lens re-encounter of the same finding-key) | exit 0, matches | the match key has no lens partition -- the SAME finding-key surfaces as previously-rejected no matter which lens raises it again, exactly as SPEC-144's Design section states |
| T11: substring-collision (the Run 3 bug), NEGATIVE control | `grep -F "except:notify.py" rejected-findings.md` (bare, unanchored) | exit 0, WRONGLY matches `bare-except:notify.py` | reproduces the bug exactly as the live review found it |
| T11: substring-collision, fix confirmed | `grep -F "\| except:notify.py \|" rejected-findings.md` (pipe-anchored) | exit 1, correctly no match | the fix; `except` is no longer confused with `bare-except` |

Raw commands + output: this file's Run 3 section above and the session transcript;
reproducible verbatim via the "Reproduce" section below.

## T10: coverage-delta advisory (SPEC-130, informational only)

```
$ bash lib/gate/coverage-delta.sh check "$(git rev-parse --show-toplevel)" --rid review-findings-memory
[coverage-delta] exempt: no source change (docs/test/generated only)
```
Expected and correct: this sub-goal changes `commands/*.md`, `agents/advisor.md`, and
`docs/verification/*.md` -- prose/prompt surfaces, not application source -- so the heuristic
correctly classifies the diff as exempt rather than warning `under-tested`. Never blocks either
way (advisory).

## Live emit + kit_gates parse (AC6)

A real `kit:code-reviewer` (architecture lens) dispatch reviewed this branch's actual diff
(`git diff master`, 5 files, +371/-7) -- the dispatch that found the Run 3 pipe-anchoring bug
above. Its verdict was recorded to the real gate-ledger for this rid:

```
$ bash lib/gate/gate-ledger.sh record review-findings-memory review ran \
    "FIX THEN SHIP findings=4 rejected=0 actor=$(git config user.name)"
```

Appended line (`~/.local/state/dwarves-kit/logs/runs/review-findings-memory.log`):
```
2026-07-04T15:01:04Z | GATE | review | ran | FIX THEN SHIP findings=4 rejected=0 actor=Han Ngo
```

Parsed via the `ledger-observatory` `kit_gates` table (`tools/ledger-observatory` in
ops-toolkit, real `uv run` invocations, not simulated):

```
$ uv run ledger rebuild
$ uv run ledger query "SELECT rid, gate, outcome, reason FROM kit_gates \
    WHERE rid = 'review-findings-memory' ORDER BY reason" --table
+------------------------+----------------+---------+--------------------------------------------------------------+
| rid                    | gate           | outcome | reason                                                        |
+------------------------+----------------+---------+--------------------------------------------------------------+
| review-findings-memory | review         | ran     | FIX THEN SHIP findings=4 rejected=0 actor=Han Ngo             |
| review-findings-memory | coverage-delta | ran     | exempt src=0 test=0                                           |
| review-findings-memory | build          | ran     | ledger file + pre-flag check ...                              |
| review-findings-memory | grill          | skipped | reason=operator-wave: ...                                     |
| review-findings-memory | spec           | ran     | review findings memory spec drafted ...                       |
+------------------------+----------------+---------+--------------------------------------------------------------+
```

`reason` carries the emitted string byte-for-byte (unsurprising, since `read_kit_gates()`
stores the post-4th-pipe remainder as one opaque VARCHAR, per `adapters.py`'s own docstring --
this is WHY no reader change was needed). A stronger check -- that the individual KVs are
independently extractable, not just present as a substring -- also passes, with a real DuckDB
`regexp_extract` over the same live row:

```
$ uv run ledger query "SELECT rid, \
    regexp_extract(reason, 'findings=([0-9]+)', 1) AS findings, \
    regexp_extract(reason, 'rejected=([0-9]+)', 1) AS rejected, \
    regexp_extract(reason, 'actor=(.*)\$', 1) AS actor \
    FROM kit_gates WHERE rid = 'review-findings-memory' AND gate = 'review'" --table
+------------------------+----------+----------+---------+
| rid                    | findings | rejected | actor   |
+------------------------+----------+----------+---------+
| review-findings-memory | 4        | 0        | Han Ngo |
+------------------------+----------+----------+---------+
```

`actor` extracts correctly even though `git config user.name` ("Han Ngo") contains a space --
confirming a space-bearing actor name does not break parsing, since `reason` is stored as one
opaque field, never tokenized on whitespace by the reader.

**Honest note on the `spec`/`build`/`review` ordering above:** the `spec` GATE line was
recorded AFTER `build` and `review` in wall-clock time (a first attempt to record it was
blocked pre-execution by this repo's own `commit-format` PreToolUse hook, which inspects the
whole shell command line for a disallowed commit-subject pattern before any part of the
command runs, including an unrelated `record` call chained before it with `&&`; backfilled
once noticed). `bash lib/gate/gate-ledger.sh descent review-findings-memory normal` correctly
flags this as an advisory out-of-order descent (`DESCENT: build recorded before spec disposed`,
`DESCENT: review recorded before spec disposed`) -- exactly the ADVISORY-ONLY behavior
WORKFLOW.md's V-model descent contract specifies (detected, never blocked). Left as-is rather
than edited away, since editing a ledger line after the fact would be worse than an honest,
explained anomaly.

## Reproduce

```bash
# 1. Recreate the fixture (notify.py + the seeded ledger) exactly as shown above, under any
#    temp dir $FIXTURE.
# 2. Dispatch a general-purpose agent with the exact "correct match rule" prompt (whole
#    finding-key, slug AND path) -> expect Run 1's output (bare-except surfaced,
#    sql-injection + resource-leak fresh).
# 3. Dispatch the same agent type with the rule weakened to file-path-only -> expect Run 2's
#    output (sql-injection wrongly suppressed too).
# 4. Over-test: run the grep -F commands in the table above against the small fixture ledger
#    variants (empty / malformed / collision), described inline.
# 5. Live emit: bash lib/gate/gate-ledger.sh record <rid> review ran "<verdict> findings=<K>
#    rejected=<M> actor=$(git config user.name)"; then, from ops-toolkit's
#    tools/ledger-observatory, `uv run ledger rebuild && uv run ledger query "select rid, gate,
#    outcome, reason from kit_gates where rid='<rid>' and gate='review'"`.
```

## Verdict

PASS. Run 1 proves the specified behavior (previously-rejected surfaced-not-suppressed; novel
finding fires). Run 2 proves the load-bearing property is load-bearing: weakening the match
rule to file-path-only actually breaks it (a real defect goes silent), not a hypothetical risk.
Run 3 proves a SECOND, independent way the same property can silently break (unanchored
substring matching) was caught by a real review before it shipped, and confirms the fix. The
over-test table proves fail-open on a missing/empty ledger, tolerance of a malformed row,
correct cross-lens behavior, and the substring-collision fix. The live-emit section closes AC6
(a real `findings=/rejected=/actor=` line, parsed byte-for-byte and via independent KV
extraction through the `ledger-observatory` `kit_gates` reader with zero reader changes).
