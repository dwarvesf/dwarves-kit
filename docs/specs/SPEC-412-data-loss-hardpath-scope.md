# SPEC-412: a canonical SQL injection test literal is not a data-loss line

Generated: 2026-10-21
Status: DRAFT
Lane: full
Depth: blind-spot (failure: a carve-out in the data-loss scan that also hides a real destructive statement)
Type: spec-fix
References: `lib/classify/lane-classify.sh:121-125` (the `_HL_*` added-line signatures), `lib/classify/lane-classify.sh:720-741` (the data-loss scan in `_floor_scan`), `lib/gate/ship-rules.sh:119-142` (`_sr_relay`, the floor-exempt notice relay); `tests/test-lanes-data.sh:178-209` (`case_floor_data_loss`, imitate its table) and `:690` (the PATH shim pattern); SPEC-368 (the data-loss row), SPEC-400 DEC-10 and DEC-15 (no exemption skips data-loss; every skip is visible), SPEC-410 (data-loss still reads comment lines).

## Problem

The ship-gate forced the full lane on an ops-toolkit PR (#4630) that added a `--rule` flag to a small script and a sandbox test for it. The floor printed `full data-loss: tools/vps-mon/scripts/test/test-hb-ack.sh`.

No path rule fired. The data-loss scan reads ADDED LINES, then prints the file name. The test added a rejection case that feeds the canonical SQL injection string to the script:

```
for bad in "x'; DROP TABLE alerts;--" "Kit_Regression" ""; do
```

`DROP TABLE alerts` matches `_HL_common`. The line is test data. The script exits 64 before any SQL runs, and the test stubs wrangler.

This spec covers that one canonical form only: a double-quoted code literal whose whole content is `<word>'; DROP TABLE <name>;--`. Other injection spellings keep hitting (see Failure modes, "Residual spellings").

## Terms

- data-loss scan: the added-line pass at the end of `_floor_scan`. It writes `path<TAB>line` records for every added line in a non-doc file to `$tmp/added`, then greps them against the `_HL_*` signatures.
- canonical payload literal: a span in one added line that matches `_HL_sqli_payload` (below) AND passes every line guard in the Contract. The span is a whole double-quoted literal: opening `"`, a bare word, `'`, `;`, optional whitespace, `DROP TABLE`, a bare name, `;--`, closing `"`.
- test path: `_HP_testpath` at `lib/classify/lane-classify.sh:118`. This spec does not use or change it (DEC-3).

## Contract

A canonical payload literal is replaced by `"sqli-payload"` before the grep chain runs, only when every guard holds. Any guard that fails leaves the line as it is, so the scan reads the raw line.

| Guard | Rule | Why it is fail-closed |
|---|---|---|
| G1 path | the path does not end in `.sql` (case-insensitive) | a `.sql` file is executed as SQL; nothing in it is test data |
| G2 one quote | the content holds exactly one `'` byte | a real statement that reaches `DROP` after a string needs a `'` to open that string. With one `'`, the only `'` is the payload's, and SQL that starts reading at it sees an unterminated string |
| G3 no escapes | the content holds no `\` and no backtick | escaped quotes and template literals break quote parity |
| G4 shape | the lowercased content matches `_HL_sqli_payload` | the span is one whole double-quoted literal, `;--` closes it with no gap |
| G5 opener | the count of `"` bytes before the span is even | the span's first `"` opens a code literal, so the payload sits inside a code string, not in SQL text |
| G6 one span | G2 allows at most one span per line; only that span is replaced | a second, real statement on the same line still hits |

Shipped regex bytes (an ERE, matched against the lowercased content, written here inside a fenced block so no markdown escaping applies):

```
"[a-z0-9_]*';[[:space:]]*drop[[:space:]]+table[[:space:]]+[a-z0-9_]+;--"
```

Every replaced span prints one stderr notice in the SPEC-400 shape: `floor-exempt<TAB>data-loss<TAB>sqli-payload<TAB>-<TAB>built-in sqli-payload literal<TAB>-<TAB><path>`. `_sr_relay` prints its reason field (`$5`) instead of the fixed text `built-in test-path default`; the test-path notice carries that same text in `$5`, so its output is unchanged.

## Picture

```
 git diff -U0 base..head
        |
        v
 producer awk (LC_ALL=C) --> $tmp/added   path<TAB>line   (unchanged format)
                         \-> $tmp/plen    byte length of each record's path
        |
        v
 neutralizer awk (LC_ALL=C, regex from ENVIRON) --> $tmp/added.n
        |                                     \--> stderr: floor-exempt data-loss sqli-payload <path>
        |
   awk exit 0 AND same line count? --no--> keep $tmp/added (raw, stricter)
        | yes
        v
   mv -f added.n added
        |
        v
 grep chain, unchanged: _HL_common -> delete-from-no-where -> where 1=1 -> .sql truncate -> code truncate
        |
        v
 "full data-loss: <path>"  or nothing
```

## Design

### Approaches considered + chosen

1. **Skip the data-loss scan on test paths.** Does not fix the sample: `scripts/test/test-hb-ack.sh` has a singular `test/` and a `test-` prefix, and `_HP_testpath` matches neither. Widening `_HP_testpath` widens the auth exemption too. A test can run real destructive SQL against a shared database. Rejected (DEC-3, SPEC-400 DEC-10).
2. **Neutralize any quote-semicolon-verb-dash span (round 1 draft).** Rejected: it matched real SQL such as `UPDATE t SET a='x'; DROP TABLE b; -- reset`.
3. **Tighten `_HL_common` itself** with a negative condition for the payload. Rejected: POSIX ERE has no lookaround, so the condition needs the same quote counting in a second tool; one pre-scan keeps the five signatures byte-for-byte as they are.
4. **Chosen: a guarded pre-scan rewrite of the canonical literal only.** Every guard in the Contract must hold, and any failure leaves the raw line. Tradeoff: it fixes the canonical form only; other spellings keep the full lane.

ADR: none. The change is reversible (one constant, one awk pass, one relay field), and DEC-1 to DEC-6 hold the record.

### Mechanics

- The producer awk (`:722-732`) runs under `LC_ALL=C` and also writes `$tmp/plen`: the byte length of `cur` for each record. A path that holds a TAB therefore splits at the right byte.
- The neutralizer reads `plen` and `added`, takes `path = substr(line, 1, n)` and `content = substr(line, n + 2)`, and applies G1 to G6. The regex comes from `ENVIRON`, never `-v`, so awk does no escape processing on it.
- One left-to-right pass, one `match()` per qualifying line. G2 caps a line at one span, so there is no rescan loop.
- `tolower` under `LC_ALL=C` touches ASCII bytes only, so match offsets on the lowercased copy align with the original bytes, including after multibyte UTF-8.
- Fail-closed: the neutralizer writes `$tmp/added.n`. The scan moves it over `$tmp/added` only when awk exits 0 and the line counts are equal. Otherwise the raw file stays.
- Verified flavours (scratch prototype, all fixture rows below): macOS BWK awk 20200816, gawk and mawk from Homebrew.

### Boundaries & failure modes

See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- `lane-classify.sh floor <root> [<base> [<head>]]`: stdout contract unchanged. A diff whose only destructive-shaped added text is canonical payload literals prints nothing for data-loss. Every other destructive added text prints `full data-loss: <path>` as today. Stderr gains one `floor-exempt ... sqli-payload` line per replaced span.
- `_HL_sqli_payload`: the regex above. No config key, no CLI flag. A PR cannot widen it.

### Data model changes

None.

## Task Breakdown

### Phase 1: Core

| Task | Files | Acceptance |
|---|---|---|
| T1: neutralizer | `lib/classify/lane-classify.sh` | AC1 to AC5 hold; the comment above `_HL_common` names the payload rule in one line |
| T2: relay | `lib/gate/ship-rules.sh` | the `else` branch of `_sr_relay` prints `fold($5)`; `ship-test-path-skip-visible` stays green; AC6 holds |
| T3: cases | `tests/test-lanes-data.sh` | the new rows and cases go red under both negative controls in `## Verification` |

## After state

A sandbox test that feeds `"x'; DROP TABLE alerts;--"` to an input validator owes the lane its own change earns, and the push output names the skip. Every other destructive added line still forces the full lane, on any path, test paths included.

## Acceptance Criteria (global)

All rows are in-repo fixtures. Rows go into `case_floor_data_loss` (`path|content|want`) unless a dedicated case is named.

| AC | Rule | Rows or case |
|---|---|---|
| AC1 | The live sample no longer hits | `tools/vps-mon/scripts/test/test-hb-ack.sh\|for bad in "x'; DROP TABLE alerts;--" "Kit_Regression" ""; do\|miss` (the exact line from #4630, as a fixture) |
| AC2 | Canonical literals never hit | `app/t.py\|p = "1'; drop table users;--"\|miss`; `app/db.py\|db.execute("x'; DROP TABLE users;--")\|miss`; `app/é.py\|s = "é" + "x'; DROP TABLE t;--"\|miss` (multibyte before the span) |
| AC3 | Real SQL and near-misses still hit | `want hit`, `app/db.py` unless noted: `INSERT INTO t VALUES ('a'); DROP TABLE old; -- legacy`; `UPDATE t SET a='x'; DROP TABLE b; -- reset`; `SELECT 'done'; TRUNCATE TABLE tmp_load; -- nightly`; `db.exec("SELECT '1'; TRUNCATE users;--")`; `db.execute("a"); DROP TABLE users; -- x`; `db/seed.sql\|SELECT "x'; DROP TABLE t;--"` (G1); ``q = `x'; DROP TABLE t;--` `` (G3, backtick); `p = "a \"q\" x'; DROP TABLE t;--"` (G3, backslash); `q = "SELECT '" + "x'; DROP TABLE t;--"` (G2, concatenation); `p = "say "x'; DROP TABLE t;--"` (G5, odd parity); `p = "x'; DROP TABLE alerts; --"` (gap before `--`); `p = "x'; DROP TABLE alerts"` (no `--`); `p = "x'; DROP TABLE IF EXISTS alerts;--"`; `name = "Robert'); DROP TABLE Students;--"` (`)` variant); `p = 'x"; DROP TABLE "users";--'`; `p = "x'; DELETE FROM users;--"`; `tests/t.sh\|DROP TABLE users;\|hit` (a test path is not exempt) |
| AC4 | A real statement beside a literal still hits | `floor-data-loss-sqli-payload`: `app/m.py` line `x = "a'; DROP TABLE t;--"; db.execute("DROP TABLE users")` prints `full data-loss: app/m.py` |
| AC5 | TAB in a path splits right | `floor-data-loss-sqli-tab-path`: path `app/a<TAB>b.py` with a canonical literal prints no data-loss line; the same path with `DROP TABLE users;` prints a `full data-loss:` line (the existing `${rec%%$T*}` path print is unchanged and out of scope) |
| AC6 | The skip is visible | `floor-data-loss-sqli-notice`: AC1's fixture writes exactly one `floor-exempt<TAB>data-loss<TAB>sqli-payload` stderr line naming the path; `ship_rule_floor` relays it as `[advisory] hard-path skip data-loss: <path> (built-in sqli-payload literal)` |
| AC7 | Awk failure keeps the floor | `floor-data-loss-sqli-awk-fails`: a PATH shim `awk` exits 2 when `ENVIRON` holds the neutralizer's regex variable and execs the real awk otherwise (the `:690` shim pattern). With AC4's line, stdout is `full data-loss: app/m.py`; with AC1's line, stdout is `full data-loss: tools/vps-mon/scripts/test/test-hb-ack.sh` (raw kept) |
| AC8 | Long line stays linear | `floor-data-loss-sqli-long-line`: one added line of about 170,000 bytes (20,000 short literals, then one canonical literal) finishes the floor within the existing `floor-timing` budget and prints nothing |
| AC9 | No regression | every existing row in `case_floor_data_loss` keeps its verdict; `floor-where-boundary`, `floor-plus-line`, `floor-non-ascii`, `floor-exempt-data-loss-still-hits`, `ship-data-loss`, `ship-test-path-skip-visible`, `floor-test-path-notice`, `floor-timing`, `floor-timing-30k` stay green; `floor-data-loss-still-hits-in-comments` in `tests/test-ceremony-fits-diff.sh` stays green |

## Verification

`bash tests/test-lanes-data.sh floor-data-loss floor-data-loss-sqli-payload floor-data-loss-sqli-tab-path floor-data-loss-sqli-notice floor-data-loss-sqli-awk-fails floor-data-loss-sqli-long-line floor-where-boundary floor-plus-line floor-non-ascii floor-exempt-data-loss-still-hits ship-data-loss ship-test-path-skip-visible floor-test-path-notice floor-timing floor-timing-30k && bash tests/test-ceremony-fits-diff.sh floor-data-loss-still-hits-in-comments && bash tests/run-all.sh --changed`

Two negative controls through `lib/gate/negctl.sh`, test command `bash tests/test-lanes-data.sh floor-data-loss floor-data-loss-sqli-payload`:

- NC1: restore `lib/classify/lane-classify.sh` from the merge base. The AC1 and AC2 rows go red (`floor-data-loss`).
- NC2: mutate the neutralizer to replace the whole content field instead of the span. AC4 goes red (`floor-data-loss-sqli-payload`).

## Edge Cases

- The literal sits in a comment line (`# "x'; DROP TABLE t;--"`): replaced, no hit. A comment holding a bare `DROP TABLE users;` still hits, as SPEC-410 requires.
- Two canonical literals on one line: G2 fails (two `'`), the line hits. Accepted.
- A non-ASCII byte before the span: `LC_ALL=C` keeps byte offsets aligned (AC2 multibyte row).
- A path with a TAB: split by the byte length from `plen` (AC5).

## Failure modes

| Class | Mitigation | Detection signal |
|---|---|---|
| Real SQL is neutralized | G1 to G5 together: SQL that reaches `DROP` after a string needs a second `'` (G2), a `.sql` file never qualifies (G1), the literal must open a code string (G5). Every round-1 counterexample is an AC3 row | AC3 rows red; the stderr notice names every replaced path |
| The neutralizer awk fails or truncates | temp file, `mv` only on exit 0 and equal line counts; raw file kept otherwise | AC7 |
| A long line or many literals | one `match()` per line, no rescan; G2 caps spans at one | AC8 |
| A TAB in a path misaligns the split | byte length from the producer, not a TAB search | AC5 |
| Awk flavour or locale differences | `LC_ALL=C` on both awks; regex via `ENVIRON`; prototype verified on BWK awk, gawk, mawk | AC2 multibyte row, `floor-non-ascii` |
| Deliberate dodge by an unattended agent (SPEC-400 DEC-10) | DEC-10 bars config exemptions a PR can steer. This carve-out is fixed in code and holds only a string SQL cannot run on its own line (G2). Building a real drop from it needs the SQL split across lines or literals, which the line scan already misses today (`"DROP " +` newline `"TABLE x"`). So the carve-out adds no new dodge class. The skip is never silent: AC6 puts it in the push output, and the review lenses read the diff | AC6 advisory line; `ship-gate.log` EXEMPT entry |
| Residual spellings that still hit | `IF EXISTS`, a numeric context (`1; DROP TABLE t`), no trailing `--`, a space before `--`, `)` variants, `DELETE`/`TRUNCATE` payloads, single-quoted or backtick literals, `OR 1=1` (not a data-loss signature at all). Each keeps the full lane; widening needs a new sample and a new spec | AC3 rows pin each as a hit |

## Out of Scope

- `_HP_testpath` and the auth test-path default.
- Any per-repo exemption for data-loss. SPEC-400 DEC-10 stands.
- The pre-existing `${rec%%$T*}` path print for a path that holds a TAB.

## Touches

`lib/classify/lane-classify.sh`, `lib/gate/ship-rules.sh`, `tests/test-lanes-data.sh`, the verification record for this spec.

## Grounding

Live sample (read-only, ops-toolkit; AC1 copies it into an in-repo fixture, so no test depends on this commit):

- Commit `ce61e16c3` ("fix(vps-mon): hb-ack --rule acks a job's stale rows of one non-heartbeat rule (#4630)") adds 28 lines to `tools/vps-mon/scripts/test/test-hb-ack.sh`. The only added line matching any `_HL_*` signature is file line 116: `for bad in "x'; DROP TABLE alerts;--" "Kit_Regression" ""; do`.
- The file header says no real Cloudflare call happens: `HB_ACK_WRANGLER` points at a stub. The case asserts a bad `rule_id` exits 64 before wrangler runs.
- Reproduction with this worktree's lib: `bash lib/classify/lane-classify.sh floor ~/workspace/tieubao/ops-toolkit ce61e16c3^ ce61e16c3` prints `full data-loss: tools/vps-mon/scripts/test/test-hb-ack.sh`.
- Matching rule: `_HL_common='drop[[:space:]]+(table|column|database|schema)|...'` at `lib/classify/lane-classify.sh:121`, applied by the first grep of the chain at `:735`, printed at `:740`.
- Not a path rule. `_HP_testpath` (`:118`) is `(^|/)(tests|__tests__|fixtures|cases)/|\.(test|spec)\.[^/]+$`; the sample path matches neither branch, and the floor reached the data-loss scan only because no path kind hit (`:716-719` returns first on a path hit).

Prototype run (scratch awk implementing G1 to G6 with `plen`, regex from `ENVIRON`, `LC_ALL=C`): all 21 AC1 to AC4 rows gave the wanted verdict after the existing grep chain, on `/usr/bin/awk` (BWK 20200816), `gawk` and `mawk`, each exit 0 with 21 output lines. The TAB path `app/a<TAB>b.py` split correctly and printed one notice. A 168,911-byte line with one canonical literal finished in under one second on all three.

Dry trace of the negative controls (real data-loss lines from the rule's own tests that must still hit):

| Existing case (file:line) | Content | Guard that fails | Grep that still fires | Verdict |
|---|---|---|---|---|
| `tests/test-lanes-data.sh:186` | `DROP TABLE users;` | G2 (no `'`) | `_HL_common` | hit |
| `:187` | `db.execute("TRUNCATE users;")` | G2 | `_HL_truncate_code` | hit |
| `:188` | `await db.users.deleteMany({})` | G2 | `_HL_common` | hit |
| `:189` | `TRUNCATE users` in `db/reset.sql` | G1 | `_HL_truncate_sql` | hit |
| `:190`, `:192` | `DELETE FROM users`, `... WHERE 1=1` | G2 | delete-from greps | hit |
| `:193`, `:196`, `:197` | `x("DROP  TABLE users")` and truncate strings | G2 | `_HL_common`, `_HL_truncate_code` | hit |
| `:198` | ``sql`TRUNCATE sessions;` `` | G2, G3 | `_HL_truncate_code` | hit |
| `:199` | `run('TRUNCATE TABLE audit_log')` | G2 (two `'`) | `_HL_truncate_code` | hit |
| `:830` | `DELETE FROM users -- everywhere` | G2 | delete-from-no-where | hit |
| `:477`, `:479`, `:482` | `db.execute("DROP TABLE users")` in non-ASCII, spaced and quoted file names | G2 | `_HL_common` | hit, path field untouched |
| `:814` | `x("DROP TABLE users")` after a `++ a.md` string | G2 | `_HL_common` | hit |
| `:1208` | `DROP TABLE users;` in an auth-exempt path | G2 | `_HL_common` | hit (DEC-10 holds) |
| `tests/test-ceremony-fits-diff.sh:391` | `# DROP TABLE users;` | G2 | `_HL_common` | hit (SPEC-410 holds) |

NC1 trace: with the merge-base lib, `$tmp/added` keeps the raw AC1 line. `_HL_common` matches `DROP TABLE alerts` at `:735`. `floor_out` prints `full data-loss: tools/vps-mon/.../test-hb-ack.sh` for a `miss` row, so `case_floor_data_loss` appends to `bad` and fails `floor-data-loss`.

NC2 trace: the mutated neutralizer replaces the whole AC4 content with `"sqli-payload"`. The record holds no `drop table`. No grep fires, stdout is empty, and `floor-data-loss-sqli-payload` (want `full data-loss: app/m.py`) fails.

## Decision Log

- DEC-1: replace the span, never the line. A line can hold a literal and a real statement (AC4, NC2).
- DEC-2: scope to the canonical form, `;--` with no gap, `DROP TABLE` only, inside a double-quoted literal. Each widening (other verbs, `)`, gaps, other quotes) lacks a sample and is pinned as a hit in AC3.
- DEC-3: no test-path condition. `_HP_testpath` misses the sample, and a second test-path definition for one scan would drift from the first.
- DEC-4: the name class is bare (`[a-z0-9_]+`). A quoted identifier stays a hit. Strict wins on doubt.
- DEC-5: fail closed on every doubt: any guard failing, any awk error, any line-count mismatch leaves the raw line.
- DEC-6: the skip is visible in the SPEC-400 notice shape and relayed by `_sr_relay`, so a reviewer sees each one (SPEC-400 DEC-15).
