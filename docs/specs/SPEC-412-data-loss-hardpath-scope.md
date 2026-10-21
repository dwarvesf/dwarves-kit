# SPEC-412: a canonical SQL injection literal in a test file is not a data-loss line

Generated: 2026-10-21
Status: DRAFT
Lane: full
Depth: blind-spot (failure: a carve-out in the data-loss scan that also hides a real destructive statement)
Type: spec-fix
References: `lib/classify/lane-classify.sh:121-125` (the `_HL_*` added-line signatures), `:619` (`_FLOOR_DATA_OPENER`, reused as is), `:720-741` (the data-loss scan in `_floor_scan`); `lib/gate/ship-rules.sh:115-142` (`_sr_relay`); `docs/MANUAL.md:138` (the diff-floor sentence); `tests/test-lanes-data.sh:178-209` (`case_floor_data_loss`, imitate its table), `:465` and `:846` (timing cases, imitate), `:690` (the PATH shim pattern); SPEC-368 (the data-loss row), SPEC-400 DEC-10 and DEC-15, SPEC-410 (data-loss still reads comment lines).

## Problem

The ship-gate forced the full lane on an ops-toolkit PR (#4630) that added a `--rule` flag to a small script and a sandbox test for it. The floor printed `full data-loss: tools/vps-mon/scripts/test/test-hb-ack.sh`.

No path rule fired. The data-loss scan reads ADDED LINES, then prints the file name. The test added a rejection case that feeds the canonical SQL injection string to the script:

```
for bad in "x'; DROP TABLE alerts;--" "Kit_Regression" ""; do
```

`DROP TABLE alerts` matches `_HL_common`. The line is test data. The script exits 64 before any SQL runs, and the test stubs wrangler.

This spec covers that one canonical form only, in a test file only: a double-quoted code literal whose whole content is `<word>'; DROP TABLE <name>;--`. Every other spelling and every non-test file keeps hitting.

## Terms

- data-loss scan: the added-line pass at the end of `_floor_scan`. It writes `path<TAB>line` records for every added line in a non-doc file to `$tmp/added`, then greps them against the `_HL_*` signatures.
- sqli test path: a path with a `test`, `tests`, `spec` or `__tests__` directory segment, or a basename that starts with `test_` or `test-`, or contains `_test.` or `.test.`. Case-insensitive. It is local to this rewrite. It is NOT `_HP_testpath`, it does not change any hard-path kind, and no other floor reads it.
- canonical payload literal: a span that matches `_HL_sqli_payload` and passes every guard in the Contract.

## Contract

A canonical payload literal is replaced by `"sqli-payload"` before the grep chain runs, only when every guard holds. Any guard that fails leaves the line as it is, and the scan reads the raw line.

| Guard | Rule | Why it is fail-closed |
|---|---|---|
| G0 test path | the path is a sqli test path | production code never qualifies, so a real statement in shipped code always hits |
| G1 not SQL | the path does not end in `.sql`, `.psql`, `.pgsql`, `.ddl`, `.hql` or `.cql`, and does not contain `.sql.` in its basename (templates such as `seed.sql.j2`) | a SQL file is executed as SQL; nothing in it is test data |
| G2 one quote | the line holds exactly one `'` byte | SQL that reaches `DROP` after a string needs a second `'` on the line to open that string |
| G3 no escapes | the line holds no `\` and no backtick | escaped quotes and template literals break quote parity |
| G4 no joins | the lowercased line holds none of `+`, `%`, `\|\|`, `.format`, `f"`, `fr"`, `rf"`, `${`, `#{` | the literal is never concatenated or interpolated on its own line |
| G5 shape | the lowercased line matches `_HL_sqli_payload` | the span is one whole double-quoted literal and `;--` closes it with no gap |
| G6 opener | the count of `"` bytes before the span is even | the span's first `"` opens a code literal |
| G7 code token | the text before the span, trailing whitespace trimmed, ends in `=`, `(`, `,`, `[`, `:` or the word `in` | the literal is a value in code on this line. A span that starts the line after whitespace (an implicit-concatenation continuation) fails |
| G8 one span | G2 caps a line at one span; only that span is replaced | a second, real statement on the same line still hits |
| G9 file openers | the head image of the file holds no `_FLOOR_DATA_OPENER` match (heredoc `<<`, triple quote, YAML block scalar) and no backtick | a heredoc, triple-quoted string or template literal can carry an opener `'` from an earlier line into this one |

Shipped regex bytes, as an ERE matched against the lowercased line:

```
"[a-z0-9_]*';[[:space:]]*drop[[:space:]]+table[[:space:]]+[a-z0-9_]+;--"
```

Sqli test path ERE, matched against the lowercased path:

```
(^|/)(test|tests|spec|__tests__)/|(^|/)(test_|test-)[^/]*$|(^|/)[^/]*(_test|\.test)\.[^/]+$
```

Notices. Every replaced span adds one line to a buffer: `floor-exempt<TAB>data-loss<TAB>sqli-payload<TAB>-<TAB>built-in sqli-payload literal<TAB>-<TAB><path>`. The buffer goes to stderr only after the `mv` succeeds. A fallback to raw prints one line instead: `floor-note<TAB>data-loss<TAB>sqli-fallback<TAB><reason>`.

Relay. `_sr_relay` handles `$3 == "sqli-payload"` in its own branch with its own counter `ns`: up to 20 lines of `[advisory] data-loss skip: <path> (built-in sqli-payload literal, test path)` and `L` lines `EXEMPT | floor | <rid> (data-loss: <path>; sqli-payload literal)`, then one END line `[advisory] data-loss skip: <n> more sqli-payload literals`. A `floor-note ... sqli-fallback` line becomes one `L` line `SQLI-FALLBACK | floor | <rid> (<reason>)`. The test-path branch and its counter `nt` do not change.

## Picture

```
 git diff -U0 base..head
        |
        v
 producer awk (LC_ALL=C) --> $tmp/added  path<TAB>line  (format unchanged)
                         \-> $tmp/plen   byte length of each record's path
        |
        v
 self-test: run pass B on two built-in records ---fails---> floor-note sqli-fallback; keep raw
        | ok
        v
 pass A awk: prefilter (' and ;-- in line) + G0 + G1 on path --> candidate paths (unique)
        |
        v
 shell: per candidate (cap 20), _floor_git show <head>:<path> | G9 --> $tmp/sqli-allow
        |
        v
 pass B awk (regexes from ENVIRON): G2..G8 on allowed paths --> $tmp/added.n + $tmp/sqli-notes
        |
   exit 0 AND equal line counts? --no--> floor-note sqli-fallback; keep $tmp/added (raw)
        | yes
        v
 mv -f added.n added; cat sqli-notes >&2
        |
        v
 grep chain, unchanged --> "full data-loss: <path>" or nothing
        |
 stderr ---> ship-rules _sr_relay ---> sqli branch (ns, cap 20, END line) ---> push advisory + ship-gate.log
```

## Design

### Approaches considered + chosen

1. **Skip the data-loss scan on `_HP_testpath`.** Does not fix the sample (`scripts/test/test-hb-ack.sh` has a singular `test/` and a `test-` prefix). Widening `_HP_testpath` widens the auth exemption too. Rejected (SPEC-400 DEC-10).
2. **Neutralize any quote-semicolon-verb-dash span (round 1).** Rejected: it matched real SQL such as `UPDATE t SET a='x'; DROP TABLE b; -- reset`.
3. **Line guards only (round 2).** Rejected: an opener `'` on an earlier line (a variable, an implicit concatenation, a triple quote, a heredoc) makes a qualifying line part of real SQL.
4. **Tighten `_HL_common` itself.** Rejected: POSIX ERE has no lookaround, so the guards need awk and git anyway; one pre-scan keeps the five signatures byte-for-byte.
5. **Inline the rewrite into the producer awk.** Rejected: a separate pass reads a complete raw file and falls back to it on any error. G9 needs a git call between candidate detection and rewrite, which awk cannot make.
6. **Chosen: a guarded pre-scan rewrite** with G0 to G9, a self-test, and fail-closed fallback to the raw file. Tradeoff: it fixes the canonical form in test files only.

ADR: none. The change is reversible (two constants, two awk passes, one relay branch), and DEC-1 to DEC-8 hold the record.

### Diagram

See `## Picture`.

### Mechanics

- The producer awk runs under `LC_ALL=C` and also writes `$tmp/plen`, so a path that holds a TAB splits at the right byte.
- Prefilter: a line pays for `tolower` and `match` only when it holds both `'` and `;--`. G2 caps a line at one span, so there is no rescan loop.
- All regexes reach awk through `ENVIRON`, never `-v`. `tolower` under `LC_ALL=C` touches ASCII only, so offsets align after multibyte UTF-8.
- G9 runs one `_floor_git show` per candidate file, capped at 20 files. Past the cap, or when `git show` fails, the file is not allowed.
- Self-test: before pass B touches real data, it runs on two built-in records: `tests/x.py` with a canonical literal (must be replaced) and `app/x.py` with the same literal (must stay). The literal is assembled from parts in the source (`"dr""op table"`), so the source line itself is not a data-loss line. A failed self-test prints the fallback note and skips the rewrite.
- Fail-closed: pass B writes `$tmp/added.n` and `$tmp/sqli-notes`. The scan moves `added.n` over `added` only when awk exits 0 and the line counts match, then prints the notes. Otherwise it prints the fallback note and keeps the raw file.
- Verified flavours (scratch prototype of G0 to G8): macOS BWK awk 20200816, gawk and mawk from Homebrew.

### Boundaries & failure modes

See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- `lane-classify.sh floor <root> [<base> [<head>]]`: stdout contract unchanged. A diff whose only destructive-shaped added text is canonical payload literals in sqli test paths prints nothing for data-loss. Every other destructive added text prints `full data-loss: <path>` as today. Stderr gains the notices and fallback line above.
- `_HL_sqli_payload`, `_HL_sqli_testpath`: the two EREs above. No config key, no CLI flag. A PR cannot widen them.

### Data model changes

None.

## Task Breakdown

### Phase 1: Core

| Task | Depends on | Files | Acceptance |
|---|---|---|---|
| T1: neutralizer | none | `lib/classify/lane-classify.sh` | AC1 to AC5, AC7, AC8, AC9 hold; the comment above `_HL_common` names the carve-out in one line |
| T2: relay | T1 | `lib/gate/ship-rules.sh` | AC6 holds; `ship-test-path-skip-visible` stays green |
| T3: cases | T1, T2 | `tests/test-lanes-data.sh` | every AC row and case exists and goes red under NC1 or NC2 |
| T4: manual | T1 | `docs/MANUAL.md:138` | the sentence says an added data-loss line forces full, except a canonical injection literal in a test file (SPEC-412) |
| T5: record | T3 | `docs/verification/data-loss-hardpath-scope.md` | the Verification command output, the NC1 and NC2 `negctl.sh` results, and the ops-toolkit reproduction before and after |

## After state

A sandbox test that feeds `"x'; DROP TABLE alerts;--"` to an input validator owes the lane its own change earns, and the push output names the skip. Every other destructive added line still forces the full lane.

## Acceptance Criteria (global)

All rows are in-repo fixtures in `case_floor_data_loss` (`path|content|want`) unless a dedicated case is named.

| AC | Rule | Rows or case |
|---|---|---|
| AC1 | The live sample no longer hits | `tools/vps-mon/scripts/test/test-hb-ack.sh`, the exact #4630 line, `miss` |
| AC2 | Canonical literals in test paths never hit | `miss`: `tests/t.py` with `p = "1'; drop table users;--"`; `tests/t.py` with `db.execute("x'; DROP TABLE users;--")`; `app/test_q.py` with `cases = ["x'; DROP TABLE t;--", "ok"]`; `app/q_test.go` with `in := map[string]string{"k": "x'; DROP TABLE t;--"}`; `tests/é.py` with `s = ("é", "x'; DROP TABLE t;--")` (multibyte before the span) |
| AC3 | Real SQL, cross-line openers and near-misses still hit | `hit`. G0: `app/t.py` with `p = "x'; DROP TABLE users;--"`. Cross-line, as two-line fixtures in `floor-data-loss-sqli-crossline`: `tests/t.py` `opener = "UPDATE t SET a='"` then `db.execute(opener + "x'; DROP TABLE users;--")`; `tests/t.py` `sql = ("UPDATE t SET a='"` then `       "x'; DROP TABLE t;--")`; `tests/t.py` `q = """SELECT * FROM t WHERE n = '` then `""" + "x'; DROP TABLE t;--")`; `tests/t.sh` `psql <<EOF`, `UPDATE t SET a='`, `v = "x'; DROP TABLE t;--"`, `EOF` (G9). Single line in `tests/t.py` unless noted: `INSERT INTO t VALUES ('a'); DROP TABLE old; -- legacy`; `UPDATE t SET a='x'; DROP TABLE b; -- reset`; `SELECT 'done'; TRUNCATE TABLE tmp_load; -- nightly`; `db.exec("SELECT '1'; TRUNCATE users;--")`; `db.execute("a"); DROP TABLE users; -- x`; `q = "%s" % "x'; DROP TABLE t;--"`; `q = f"x'; DROP TABLE t;--"`; `q = "a" "x'; DROP TABLE t;--"` (G7); `"x'; DROP TABLE t;--"` alone in `tests/t.sh` (G7); `q = "SELECT '" + "x'; DROP TABLE t;--"`; `p = "say "x'; DROP TABLE t;--"` (G6); ``q = `x'; DROP TABLE t;--` `` (G3); `p = "a \"q\" x'; DROP TABLE t;--"` (G3); `tests/seed.sql`, `tests/seed.pgsql`, `tests/seed.sql.j2` with `x = "x'; DROP TABLE t;--"` (G1); `p = "x'; DROP TABLE alerts; --"`; `p = "x'; DROP TABLE alerts"`; `p = "x'; DROP TABLE IF EXISTS alerts;--"`; `name = "Robert'); DROP TABLE Students;--"`; `p = 'x"; DROP TABLE "users";--'`; `p = "x'; DELETE FROM users;--"`; `tests/t.sh` with `DROP TABLE users;` |
| AC4 | A real statement beside a literal still hits | `floor-data-loss-sqli-payload`: `tests/m.py` line `x = "a'; DROP TABLE t;--"; db.execute("DROP TABLE users")` prints `full data-loss: tests/m.py` |
| AC5 | TAB in a path splits right | `floor-data-loss-sqli-tab-path`: `tests/a<TAB>b.py` with a canonical literal prints no data-loss line; with `DROP TABLE users;` it prints a `full data-loss:` line (the existing `${rec%%$T*}` print is unchanged and out of scope) |
| AC6 | The skip is visible and labelled | `floor-data-loss-sqli-notice`: AC1's fixture writes one `floor-exempt<TAB>data-loss<TAB>sqli-payload` stderr line; `ship_rule_floor` relays `[advisory] data-loss skip: <path> (built-in sqli-payload literal, test path)` and logs `EXEMPT \| floor \| <rid> (data-loss: <path>; sqli-payload literal)`; 21 literals give 20 lines plus `1 more`; a mixed diff with one test-path skip and one sqli skip keeps both counters apart |
| AC7 | Awk failure or a failed self-test keeps the floor | `floor-data-loss-sqli-awk-fails`: a PATH shim `awk` exits 2 when `ENVIRON` holds the pass-B regex variable. With AC1's line, stdout is `full data-loss: <path>`, stderr holds one `sqli-fallback` line and no `sqli-payload` notice. A second leg breaks the self-test (shim rewrites `sqli-payload` output) with the same result |
| AC8 | Cost stays flat | `floor-data-loss-sqli-long-line`: one added line of 168,911 bytes (20,000 short literals then one canonical literal) in `tests/l.py`: stdout empty, floor under 3000 ms. `floor-data-loss-sqli-many-lines`: 30,000 added lines in `tests/` files, each holding a canonical literal (1.39 MB): floor under 15000 ms, the `floor-timing-30k` budget |
| AC9 | No regression | every existing row in `case_floor_data_loss` keeps its verdict; `floor-where-boundary`, `floor-plus-line`, `floor-non-ascii`, `floor-exempt-data-loss-still-hits`, `ship-data-loss`, `ship-test-path-skip-visible`, `floor-test-path-notice`, `floor-timing`, `floor-timing-30k` stay green; `floor-data-loss-still-hits-in-comments` in `tests/test-ceremony-fits-diff.sh` stays green |

## Verification

`bash tests/test-lanes-data.sh floor-data-loss floor-data-loss-sqli-payload floor-data-loss-sqli-crossline floor-data-loss-sqli-tab-path floor-data-loss-sqli-notice floor-data-loss-sqli-awk-fails floor-data-loss-sqli-long-line floor-data-loss-sqli-many-lines floor-where-boundary floor-plus-line floor-non-ascii floor-exempt-data-loss-still-hits ship-data-loss ship-test-path-skip-visible floor-test-path-notice floor-timing floor-timing-30k && bash tests/test-ceremony-fits-diff.sh floor-data-loss-still-hits-in-comments && bash tests/run-all.sh --changed`

Two negative controls through `lib/gate/negctl.sh`, test command `bash tests/test-lanes-data.sh floor-data-loss floor-data-loss-sqli-payload`, recorded by T5:

- NC1: restore `lib/classify/lane-classify.sh` from the merge base. The AC1 and AC2 rows go red (`floor-data-loss`).
- NC2: mutate pass B to replace the whole line content instead of the span. AC4 goes red (`floor-data-loss-sqli-payload`).

## Edge Cases

- The literal sits in a comment line in a test file (`# v = "x'; DROP TABLE t;--"`): replaced if every guard holds. A comment holding a bare `DROP TABLE users;` still hits (SPEC-410).
- Two literals on one line: G2 fails, the line hits.
- More than 20 candidate files in one diff: files past the cap keep the raw line and hit.
- A path with a TAB: split by the byte length from `plen` (AC5).

## Failure modes

| Class | Mitigation | Detection signal |
|---|---|---|
| Real SQL in shipped code is neutralized | G0: only sqli test paths qualify | AC3 G0 row |
| Real SQL in a test file is neutralized | G1 to G9: same-line openers (G2), joins (G4), continuation lines (G7), multi-line strings and heredocs (G9) all keep the raw line. Every round-1 and round-2 counterexample is an AC3 row | AC3 rows; the stderr notice names every replaced path |
| A deliberate test-file author hides one drop string (for example a list built over lines and joined later) | accepted, decided risk (DEC-7). The carve-out does not claim to stop it | AC6 notice on the push and the `ship-gate.log` EXEMPT line; review lenses read the diff |
| Pass B fails, truncates, or the regex misbehaves on a new awk | self-test first; temp file; `mv` only on exit 0 and equal line counts; notices only after `mv` | AC7; `sqli-fallback` line, `SQLI-FALLBACK` log line |
| A long line or many lines | prefilter, one `match` per line, no rescan; G9 capped at 20 files | AC8 |
| A TAB in a path misaligns the split | byte length from the producer | AC5 |
| Awk flavour or locale differences | `LC_ALL=C`; regex via `ENVIRON`; prototype verified on BWK awk, gawk, mawk | AC2 multibyte row, `floor-non-ascii` |
| Residual spellings that still hit | `IF EXISTS`, numeric context (`1; DROP TABLE t`), no trailing `--`, a gap before `--`, `)` variants, `DELETE` or `TRUNCATE` payloads, single-quoted or backtick literals, `OR 1=1` (not a data-loss signature), any literal in a non-test path | AC3 rows pin each as a hit |

## Out of Scope

- `_HP_testpath` and the auth test-path default. The sqli test path is a separate, local constant.
- Any per-repo exemption for data-loss. SPEC-400 DEC-10 stands for config.
- The pre-existing `${rec%%$T*}` path print for a path that holds a TAB.

## Touches

`lib/classify/lane-classify.sh`, `lib/gate/ship-rules.sh`, `tests/test-lanes-data.sh`, `docs/MANUAL.md`, `docs/verification/data-loss-hardpath-scope.md`.

## Grounding

Live sample (read-only, ops-toolkit; AC1 copies it into an in-repo fixture, so no test depends on this commit):

- Commit `ce61e16c3` ("fix(vps-mon): hb-ack --rule acks a job's stale rows of one non-heartbeat rule (#4630)") adds 28 lines to `tools/vps-mon/scripts/test/test-hb-ack.sh`. The only added line matching any `_HL_*` signature is file line 116: `for bad in "x'; DROP TABLE alerts;--" "Kit_Regression" ""; do`.
- The file header says no real Cloudflare call happens: `HB_ACK_WRANGLER` points at a stub. The case asserts a bad `rule_id` exits 64 before wrangler runs.
- G9 on the sample: `git show ce61e16c3:tools/vps-mon/scripts/test/test-hb-ack.sh | grep -nE '<<|"""|`'` prints nothing, and the block-scalar part of `_FLOOR_DATA_OPENER` counts 0 lines. The sample passes G9.
- Reproduction with this worktree's lib: `bash lib/classify/lane-classify.sh floor ~/workspace/tieubao/ops-toolkit ce61e16c3^ ce61e16c3` prints `full data-loss: tools/vps-mon/scripts/test/test-hb-ack.sh`.
- Matching rule: `_HL_common='drop[[:space:]]+(table|column|database|schema)|...'` at `lib/classify/lane-classify.sh:121`, applied by the first grep of the chain at `:735`, printed at `:740`.
- Not a path rule. `_HP_testpath` (`:118`) misses the sample path, and the floor reached the data-loss scan only because no path kind hit (`:716-719` returns first on a path hit).

Prototype runs (scratch awk implementing G0 to G8 with `plen`, regexes from `ENVIRON`, `LC_ALL=C`; G9 is a shell `git show` step and was checked on the sample above):

- 21 rows (AC1, AC2, the single-line AC3 rows for G0, G1, G4, G6, G7, round-1 SQL, and AC4) gave the wanted verdict after the existing grep chain on `/usr/bin/awk` (BWK 20200816), `gawk` and `mawk`, each exit 0 with 21 output lines.
- A first prototype with a malformed bracket expression made all three awks exit non-zero with empty output. That is the AC7 failure class: the scan must keep the raw file there.
- 30,000 canonical-literal lines (1,387,780 bytes): pass B took 162 ms on BWK awk, 347 ms on gawk, 67 ms on mawk. A 168,911-byte single line finished under one second on all three.

Dry trace of the negative controls (real data-loss lines from the rule's own tests that must still hit; every one fails G0 as an `app/`, `db/`, `ui/` or `docs/` path, and the second guard listed also fails):

| Existing case (file:line) | Content | Guards that fail | Grep that still fires | Verdict |
|---|---|---|---|---|
| `tests/test-lanes-data.sh:186` | `DROP TABLE users;` | G0, G2 | `_HL_common` | hit |
| `:187` | `db.execute("TRUNCATE users;")` | G0, G2 | `_HL_truncate_code` | hit |
| `:188` | `await db.users.deleteMany({})` | G0, G2 | `_HL_common` | hit |
| `:189` | `TRUNCATE users` in `db/reset.sql` | G0, G1 | `_HL_truncate_sql` | hit |
| `:190`, `:192` | `DELETE FROM users`, `... WHERE 1=1` | G0, G2 | delete-from greps | hit |
| `:193`, `:196`, `:197`, `:198`, `:199` | quoted drop and truncate strings | G0, G2 | `_HL_common`, `_HL_truncate_code` | hit |
| `:830` | `DELETE FROM users -- everywhere` | G0, G2 | delete-from-no-where | hit |
| `:477`, `:479`, `:482` | `db.execute("DROP TABLE users")` in non-ASCII, spaced and quoted file names | G0, G2 | `_HL_common` | hit, path field untouched |
| `:814` | `x("DROP TABLE users")` after a `++ a.md` string | G0, G2 | `_HL_common` | hit |
| `:1208` | `DROP TABLE users;` in an auth-exempt path | G0, G2 | `_HL_common` | hit (DEC-10 holds) |
| `tests/test-ceremony-fits-diff.sh:391` | `# DROP TABLE users;` in `app/q.sh` | G0, G2 | `_HL_common` | hit (SPEC-410 holds) |

NC1 trace: with the merge-base lib, `$tmp/added` keeps the raw AC1 line. `_HL_common` matches `DROP TABLE alerts` at `:735`. `floor_out` prints `full data-loss: tools/vps-mon/.../test-hb-ack.sh` for a `miss` row, so `case_floor_data_loss` fails `floor-data-loss`.

NC2 trace: the mutated pass B replaces the whole AC4 content with `"sqli-payload"`. The record holds no `drop table`. No grep fires, stdout is empty, and `floor-data-loss-sqli-payload` (want `full data-loss: tests/m.py`) fails.

## Decision Log

- DEC-1: replace the span, never the line (AC4, NC2).
- DEC-2: scope to the canonical form: `;--` with no gap, `DROP TABLE` only, inside a double-quoted literal. Each widening lacks a sample and is pinned as a hit in AC3.
- DEC-3: the sqli test path is a new local constant, not `_HP_testpath`. It never feeds another floor or another kind, so the auth exemption and SPEC-400's test-path default do not move.
- DEC-4: the name class is bare (`[a-z0-9_]+`). A quoted identifier stays a hit.
- DEC-5: fail closed on every doubt: any guard failing, a failed self-test, an awk error, a line-count mismatch, a `git show` failure, or the candidate cap leaves the raw line.
- DEC-6: every skip is visible in its own relay branch and log line (SPEC-400 DEC-15), and a fallback is logged.
- DEC-7: accepted, decided risk against SPEC-400 DEC-10. A test-file author who sets out to hide one drop string can still do it (for example a list built over several lines and joined later). DEC-10 bars config exemptions a PR can steer. This carve-out is fixed in code, limited to test paths and the canonical shape, and every use prints on the push. The operator directed the build with this residual named.
- DEC-8: the separate pass beats inlining into the producer because it can fall back to the complete raw file, and G9 needs git between detection and rewrite.
