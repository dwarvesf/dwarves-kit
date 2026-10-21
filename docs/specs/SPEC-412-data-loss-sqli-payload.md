# SPEC-412: an SQL injection test payload is not a data-loss line

Generated: 2026-10-21
Status: DRAFT
Lane: full
Depth: blind-spot (failure: a carve-out in the data-loss scan that also hides a real destructive statement)
Type: spec-fix
References: `lib/classify/lane-classify.sh:121-125` (the `_HL_*` added-line signatures), `lib/classify/lane-classify.sh:720-741` (the data-loss scan in `_floor_scan`); `tests/test-lanes-data.sh:178-209` (`case_floor_data_loss`, imitate its table); SPEC-368 (the data-loss row), SPEC-400 DEC-10 (data-loss ignores every exemption), SPEC-410 (data-loss still reads comment lines).

## Problem

The ship-gate forced the full lane on an ops-toolkit PR (#4630) that added a `--rule` flag to a small script and a sandbox test for it. The floor printed `full data-loss: tools/vps-mon/scripts/test/test-hb-ack.sh`.

The path did not match anything. The data-loss scan reads ADDED LINES, then prints the file name. The test added a negative case that feeds a classic SQL injection string to the script and checks that the script rejects it:

```
for bad in "x'; DROP TABLE alerts;--" "Kit_Regression" ""; do
```

`DROP TABLE alerts` matches `_HL_common`. The line is test data. It destroys nothing: the script exits 64 before any SQL runs, and the test stubs wrangler.

Every validation test for an SQL-facing input meets this. A rejection test needs a hostile string, and the canonical hostile string is `'; DROP TABLE <name>;--`. The scan thus charges the full lane exactly when an author adds input validation, which is the behaviour the kit wants to encourage.

## Terms

- data-loss scan: the added-line pass at the end of `_floor_scan`. It emits `path<TAB>line` records for every added line in a non-doc file and greps them against the `_HL_*` signatures.
- injection payload: a span inside one added line with this shape, case-insensitive: a quote (`'`, `"` or a backtick), an optional `)`, a `;`, then a destructive verb (`drop table|column|database|schema`, `delete from`, `truncate` or `truncate table`), one bare name (`[a-z0-9_.]+`), an optional `;`, then `--`. Whitespace is allowed between each part. The quote that closes a value, the `;` that ends the statement, and the trailing `--` that comments out the rest are the three marks of an injection string. A real destructive statement in code carries all three only by design.
- test path: `_HP_testpath` at `lib/classify/lane-classify.sh:118`. This spec does not use or change it (see Decision Log).

## Solution

### Approaches considered

1. **Skip the data-loss scan on test paths.** Reuse `_HP_testpath`. Tradeoff: it does not fix the sample. `tools/vps-mon/scripts/test/test-hb-ack.sh` has a singular `test/` directory and a `test-` prefix, and `_HP_testpath` matches neither. Widening `_HP_testpath` also widens the auth exemption, which SPEC-400 fixed in code on purpose. A test can also run real destructive SQL against a shared database (an integration teardown against staging). SPEC-400 DEC-10 kept data-loss free of every exemption for this reason. Rejected.
2. **Neutralize an injection payload span before the scan, on every path.** Replace each payload span in the content field of `$tmp/added` with a fixed placeholder, then run the existing grep chain unchanged. Tradeoff: one regex and one awk pass. The span is removed, not the line, so a second, real destructive statement on the same line still hits. An author can still dodge the scan by writing the payload shape on purpose. The scan is already dodgeable by string concatenation (`"DROP " + "TABLE"`), so this adds no new class of bypass.
3. **Approach 2, but only on test paths.** Tradeoff: needs a second test-path definition for the data-loss scan, because `_HP_testpath` misses the sample. Two test-path definitions drift. It buys little: the payload shape is already narrow. Rejected.
4. **Drop the line when it holds a payload anywhere.** Same as the CSS `truncate` exclusion at `:739`. Tradeoff: simpler, but a line with a payload and a real `DROP TABLE users` would pass. Rejected.

### Chosen approach + why

Approach 2. It fixes the observed class with the smallest change, keeps every signature and every existing case as is, and never drops a whole line. The payload shape requires the quote, the `;` and the trailing `--`, so a payload without the trailing comment (`"x'; DROP TABLE alerts"`) still hits. Strict wins on doubt.

### Extensibility & boundaries

- One new constant `_HL_sqli_payload` beside `_HL_common`. One awk pass rewrites `$tmp/added` in place before line 735. Nothing else in the floor changes.
- The awk pass matches on a lowercased copy of the content field under `LC_ALL=C` and replaces the same byte span in the original. ASCII lowercasing keeps byte offsets, so the span lines up. Only the content after the first TAB is touched. The path field never changes, so the printed `full data-loss: <path>` contract holds.
- Cost: one awk pass over the added lines, linear in diff size. `floor-timing-30k` must stay green.

### Architecture

```
 git diff -U0 base..head
        |
        v
 awk: path<TAB>added-line          ($tmp/added, docs skipped)
        |
        v
 NEW awk: replace each injection-payload span in the content field with " sqli-payload "
        |
        v
 grep chain, unchanged: _HL_common -> delete-from-no-where -> where 1=1 -> .sql truncate -> code truncate
        |
        v
 "full data-loss: <path>"  or nothing
```

## Technical Design

### Interfaces (I/O contract)

- `lane-classify.sh floor <root> [<base> [<head>]]`: stdout contract unchanged. A diff whose only destructive-shaped added text is injection payload spans prints nothing for data-loss. Any other destructive added text prints `full data-loss: <path>` as today.
- `_HL_sqli_payload` (ERE, matched case-insensitively): `['"\`][[:space:]]*\)?[[:space:]]*;[[:space:]]*(drop[[:space:]]+(table|column|database|schema)|delete[[:space:]]+from|truncate([[:space:]]+table)?)[[:space:]]+[a-z0-9_.]+[[:space:]]*;?[[:space:]]*--`
- No config key. No CLI flag. A PR cannot widen the shape.

### Data model changes

None.

## Task Breakdown

### Phase 1: Core

| Task | Files | Acceptance |
|---|---|---|
| T1: neutralize payload spans | `lib/classify/lane-classify.sh` | AC1 to AC4 hold; the comment above `_HL_common` names the payload rule in one line |
| T2: cases | `tests/test-lanes-data.sh` | the new rows in `case_floor_data_loss` and the new case `floor-data-loss-sqli-payload` go red on the pre-change lib |

## After state

A sandbox test that feeds `x'; DROP TABLE alerts;--` to an input validator owes the lane its own change earns. Every destructive statement that is not an injection-payload span still forces the full lane, on any path, test paths included.

## Acceptance Criteria (global)

| AC | Rule | Check |
|---|---|---|
| AC1 | The live sample no longer hits | `lane-classify.sh floor <ops-toolkit> ce61e16c3^ ce61e16c3` prints nothing (run by hand, recorded in the proof file; a fixture repeats it in T2) |
| AC2 | Payload spans never hit | new `case_floor_data_loss` rows, want `miss`: `tests/v.sh` with `for bad in "x'; DROP TABLE alerts;--" ""; do`; `app/t.py` with `name = "Robert'); DROP TABLE Students;--"`; `app/t.py` with `p = "x'; DELETE FROM users;--"`; `app/t.py` with `p = "x'; TRUNCATE TABLE users; --"` |
| AC3 | Near-misses of the payload shape still hit | new rows, want `hit`: `app/t.py` with `p = "x'; DROP TABLE alerts"` (no `--`); `app/db.py` with `db.execute("SELECT 1; DROP TABLE users;--")` (no quote before `;`); `app/db.py` with `p = 'x"; DROP TABLE "users";--'` (a quoted identifier is outside the name class); `tests/t.sh` with `DROP TABLE users;` (a test path is not exempt) |
| AC4 | A real statement beside a payload still hits | `floor-data-loss-sqli-payload`: one added line `x = "a'; DROP TABLE t;--"; db.execute("DROP TABLE users")` in `app/m.py` prints `full data-loss: app/m.py` |
| AC5 | No regression | every existing row in `case_floor_data_loss` keeps its verdict; `floor-where-boundary`, `floor-plus-line`, `floor-non-ascii`, `floor-exempt-data-loss-still-hits`, `ship-data-loss`, `floor-timing-30k` stay green; `floor-data-loss-still-hits-in-comments` in `tests/test-ceremony-fits-diff.sh` stays green |

## Verification

`bash tests/test-lanes-data.sh floor-data-loss floor-data-loss-sqli-payload floor-where-boundary floor-plus-line floor-non-ascii floor-exempt-data-loss-still-hits ship-data-loss floor-timing-30k && bash tests/test-ceremony-fits-diff.sh floor-data-loss-still-hits-in-comments && bash tests/run-all.sh --changed`

Negative control through `lib/gate/negctl.sh`, test command `bash tests/test-lanes-data.sh floor-data-loss floor-data-loss-sqli-payload`: restore `lib/classify/lane-classify.sh` from the merge base. The AC2 rows go red.

## Edge Cases

- The payload sits in a comment line (`# x'; DROP TABLE t;--`): neutralized, no hit. A comment holding a bare `DROP TABLE users;` still hits, as SPEC-410 requires.
- Two payloads on one line: both spans are replaced (the awk loops until no match).
- A payload in a `.sql` file: neutralized like anywhere else. A `.sql` file that runs `'; DROP TABLE t;--` is not a statement SQL can parse after a bare quote; the `.sql` `truncate` branch still reads the rest of the line.
- A non-ASCII byte before the span: `LC_ALL=C` keeps `tolower` byte-for-byte, so offsets stay aligned.

## Failure modes

| Class | Mitigation |
|---|---|
| An author writes a real drop in payload shape to dodge the floor (`run("SELECT ''; DROP TABLE users;--")`) | accepted residual. It needs a deliberate quote, `;` and trailing `--`. The scan is already dodgeable by concatenation; it is an accident net, not an adversary gate. Review lenses still read the diff |
| The span replace eats a neighbouring real statement | only the matched span is replaced, and the name class stops at the first `;`, space or quote. AC4 covers a real statement on the same line |
| The rewrite changes the path field | the awk splits at the first TAB and rewrites only the content; every existing `full data-loss: <path>` assertion (non-ASCII, spaces, quotes in names) guards it |
| Cost on a large diff | one linear awk pass; `floor-timing-30k` guards it |

## Out of Scope

- `_HP_testpath` and the auth test-path default.
- Any per-repo exemption for data-loss. SPEC-400 DEC-10 stands.
- Other injection families (`OR 1=1`, `UNION SELECT`). They do not match a data-loss signature today.

## Touches

`lib/classify/lane-classify.sh`, `tests/test-lanes-data.sh`, the verification record for this spec.

## Grounding

Live sample (read-only, ops-toolkit):

- Commit `ce61e16c3` ("fix(vps-mon): hb-ack --rule acks a job's stale rows of one non-heartbeat rule (#4630)") adds 28 lines to `tools/vps-mon/scripts/test/test-hb-ack.sh`. The only added line matching any `_HL_*` signature is file line 116: `for bad in "x'; DROP TABLE alerts;--" "Kit_Regression" ""; do`. Command: `git show ce61e16c3 -- tools/vps-mon/scripts/test/test-hb-ack.sh | grep -iE '^\+.*(drop[[:space:]]+(table|column|database|schema)|deletemany|delete[[:space:]]+from|truncate)'`.
- The file header says no real Cloudflare call happens: `HB_ACK_WRANGLER` points at a stub. The case asserts a bad `rule_id` exits 64 before wrangler runs.
- Reproduction with this worktree's lib: `bash lib/classify/lane-classify.sh floor ~/workspace/tieubao/ops-toolkit ce61e16c3^ ce61e16c3` prints `full data-loss: tools/vps-mon/scripts/test/test-hb-ack.sh`.
- Matching rule: `_HL_common='drop[[:space:]]+(table|column|database|schema)|...'` at `lib/classify/lane-classify.sh:121`, applied by the first grep of the chain at `lib/classify/lane-classify.sh:735`, printed at `:740`.
- Not a path rule. `_HP_testpath` (`:118`) is `(^|/)(tests|__tests__|fixtures|cases)/|\.(test|spec)\.[^/]+$`; the sample path has `scripts/test/test-hb-ack.sh` and matches neither branch, and no `_HP_*` kind matches it either (the floor reached the data-loss scan, which runs only after no path hit).

The `_HL_sqli_payload` ERE above, run against representative lines (scratch `grep -Eiq -f`): the sample, Bobby Tables, the `DELETE FROM` and `TRUNCATE TABLE ... ; --` payloads matched. `DROP TABLE users;`, `db.execute("TRUNCATE users;")`, `DELETE FROM users -- everywhere`, `x("DROP TABLE users")`, `db.execute("SELECT 1; DROP TABLE users;--")`, `p="x'; DROP TABLE alerts"`, `db.execute("DROP TABLE users")`, `# DROP TABLE users;` and `p = 'x"; DROP TABLE "users";--'` did not. The AC4 line matched (it holds a span), and its second statement survives the span replace.

Dry trace of the negative control (real data-loss lines that must still hit, taken from the rule's own tests):

| Existing case (file:line) | Content | Payload span? | Grep that still fires | Verdict after change |
|---|---|---|---|---|
| `tests/test-lanes-data.sh:186` | `DROP TABLE users;` | no quote before `;` | `_HL_common` | hit |
| `:187` | `db.execute("TRUNCATE users;")` | no `;` between quote and verb | `_HL_truncate_code` | hit |
| `:188` | `await db.users.deleteMany({})` | no verb in shape | `_HL_common` | hit |
| `:189` | `TRUNCATE users` in `db/reset.sql` | no quote | `_HL_truncate_sql` | hit |
| `:190` | `DELETE FROM users` | no quote | delete-from-no-where | hit |
| `:192` | `DELETE FROM users WHERE 1=1` | no quote | where-1=1 | hit |
| `:193` | `x("DROP  TABLE users")` | quote, no `;` | `_HL_common` | hit |
| `:198` | ``sql`TRUNCATE sessions;` `` | backtick, no `;` before verb | `_HL_truncate_code` | hit |
| `:199` | `run('TRUNCATE TABLE audit_log')` | quote, no `;` | `_HL_truncate_code` | hit |
| `:830` | `DELETE FROM users -- everywhere` | has `--`, no quote and `;` before verb | delete-from-no-where | hit |
| `:477`, `:479`, `:482` | `db.execute("DROP TABLE users")` in non-ASCII, spaced and quoted file names | quote, no `;` | `_HL_common` | hit, path field untouched |
| `:814` | `x("DROP TABLE users")` after a `++ a.md` string | quote, no `;` | `_HL_common` | hit |
| `:1208` | `DROP TABLE users;` in an auth-exempt path | no quote | `_HL_common` | hit (DEC-10 holds) |
| `tests/test-ceremony-fits-diff.sh:391` | `# DROP TABLE users;` | no quote | `_HL_common` | hit (SPEC-410 holds) |

Mutation trace: restore `lane-classify.sh` from the merge base. `$tmp/added` keeps the raw payload line. `_HL_common` matches `DROP TABLE alerts` at `:735`. `floor_out` prints `full data-loss: tests/v.sh` for the first AC2 row, whose want is `miss`. `case_floor_data_loss` appends to `bad` and fails `floor-data-loss`. `floor-data-loss-sqli-payload` stays green on the old lib (its line holds a real `DROP TABLE users`), so the red comes from the AC2 rows.

## Decision Log

- DEC-1: neutralize the span, never drop the line. A line can hold a payload and a real statement (AC4).
- DEC-2: require the trailing `--`. It is the mark that the string is built to break out of a quoted value. Without it the scan cannot tell a payload from a statement, so it hits.
- DEC-3: no test-path condition. `_HP_testpath` misses the sample, and a second test-path definition for one scan would drift from the first. The payload shape alone is narrow enough.
- DEC-4: the name class is bare (`[a-z0-9_.]+`). A quoted identifier in a payload still hits. Strict wins on doubt.
- DEC-5: all three destructive verbs share the shape. A rejection test for `'; DELETE FROM users;--` is the same false positive as the sample.
