# SPEC-412: a canonical SQL injection literal in a test file is not a data-loss line

Generated: 2026-10-21
Status: DRAFT
Lane: full
Depth: blind-spot (failure: a carve-out in the data-loss scan that also hides a real destructive statement)
Type: spec-fix
References: `lib/classify/lane-classify.sh:118` (`_HP_testpath`), `:121-125` (the `_HL_*` added-line signatures), `:619` (`_FLOOR_DATA_OPENER`, reused as is), `:704-715` (the 8 s budget idiom), `:720-741` (the data-loss scan in `_floor_scan`); `lib/gate/ship-rules.sh:115-142` (`_sr_relay`) and `:163-166` (the floor call); `lib/gate/battery-gate.sh:36` and `lib/gate/proof-ledger.sh:391` (other floor callers); `docs/MANUAL.md:138`; `tests/test-lanes-data.sh:178-209` (`case_floor_data_loss`), `:465` and `:846` (timing cases), `:690` (PATH shim pattern); SPEC-368, SPEC-400 DEC-10 and DEC-15, SPEC-410.

## Problem

The ship-gate forced the full lane on an ops-toolkit PR (#4630) that added a `--rule` flag to a small script and a sandbox test for it. The floor printed `full data-loss: tools/vps-mon/scripts/test/test-hb-ack.sh`.

No path rule fired. The data-loss scan reads ADDED LINES, then prints the file name. The test added a rejection case that feeds the canonical SQL injection string to the script:

```
for bad in "x'; DROP TABLE alerts;--" "Kit_Regression" ""; do
```

`DROP TABLE alerts` matches `_HL_common`. The line is test data. The script exits 64 before any SQL runs, and the test stubs wrangler.

This spec covers that one shape only: a double-quoted literal `"<word>'; DROP TABLE <name>;--"` that follows the word `in`, in a test file of a known code language, at the ship-gate only. Every other spelling, file and caller keeps hitting.

## Terms

- data-loss scan: the added-line pass at the end of `_floor_scan`. It writes `path<TAB>line` records to `$tmp/added`, then greps them against the `_HL_*` signatures.
- carve-out flag: `KIT_FLOOR_SQLI_CARVEOUT=1` in the environment of `lane-classify.sh floor`. Only `ship_rule_floor` sets it. Without it the scan is the raw scan of today.
- sqli test path: a path with a `test`, `tests`, `spec` or `__tests__` directory segment, or a basename that starts with `test_` or `test-`, or contains `_test.` or `.test.`. Case-insensitive. Local to this rewrite: it is NOT `_HP_testpath`, it changes no hard-path kind, and no other floor reads it.
- candidate: a path that pass A selects (prefilter, G0, G1). Only candidates reach G9.
- head image: the file content at the floor's `<head>` rev, read with `_floor_git show <head>:<path>`.
- canonical payload literal: a span that matches `_HL_sqli_payload` and passes every guard below.

## Contract

With the carve-out flag set, a canonical payload literal is replaced by `"sqli-payload"` before the grep chain runs, only when every guard holds. Any guard that fails leaves the line as it is.

| Guard | Rule | Why it is fail-closed |
|---|---|---|
| G0 test path | the path is a sqli test path | ordinary production paths never qualify |
| G1 code language | the lowercased path ends in `.py`, `.sh`, `.bash`, `.js`, `.ts`, `.go`, `.rb`, `.rs`, `.java` or `.kt` (test variants such as `.test.ts` or `_test.go` end the same way) | SQL files, templates, and any language whose multi-line string syntax G9 does not know keep the raw line |
| G2 one quote | the line holds exactly one `'` byte | SQL that reaches `DROP` after a string needs a second `'` on the line to open it |
| G3 no escapes | the line holds no `\` and no backtick | escaped quotes and template literals break quote parity |
| G4 no joins | the lowercased line holds none of `+`, `%`, `\|\|`, `.format`, `f"`, `fr"`, `rf"`, `${`, `#{` | the literal is never concatenated or interpolated on its own line |
| G5 shape | the lowercased line matches `_HL_sqli_payload` | one whole double-quoted literal, `;--` with no gap |
| G6 opener | the count of `"` bytes before the span is even | the span's first `"` opens a code literal |
| G7 code token | the lowercased text before the span ends in the word `in` followed by at least one space or tab | the only sample-backed position: a loop or membership operand. Formatter arguments (`fmt.Sprintf(tmpl, "...")`, `util.format`, `String.Format`, `.replace`, `render(...)`), assignments (`p = "..."`, later reused) and continuation lines all fail |
| G8 one span | G2 caps a line at one span; only that span is replaced | a second, real statement on the same line still hits |
| G9 file openers | the head image holds no `_FLOOR_DATA_OPENER` match (heredoc `<<`, triple quote, YAML block scalar) and no backtick; a `.rs` file also no raw-string opener (`r"`, `r#"`, `br"`); a `.rb` file also no percent literal (`%(`, `%q(`, `%Q(` and the `[ { <` forms). An unreadable head image fails G9 | an opener `'` on an earlier line can reach this line only through a multi-line string |

Shipped EREs (fenced, so no markdown escaping applies). Payload, matched against the lowercased line:

```
"[a-z0-9_]*';[[:space:]]*drop[[:space:]]+table[[:space:]]+[a-z0-9_]+;--"
```

Sqli test path, matched against the lowercased path:

```
(^|/)(test|tests|spec|__tests__)/|(^|/)(test_|test-)[^/]*$|(^|/)[^/]*(_test|\.test)\.[^/]+$
```

Bounds. G9 reads at most 20 candidate files and stops after 5 seconds (the `SECONDS` idiom of the comment-only loop). Candidates past either bound are not allowed.

Notices. Every replaced span adds one line to a buffer: `floor-exempt<TAB>data-loss<TAB>sqli-payload<TAB>-<TAB>built-in sqli-payload literal<TAB>-<TAB><path>`. The buffer goes to stderr only after the `mv` succeeds. Each fallback class prints one line: `floor-note<TAB>data-loss<TAB>sqli-fallback<TAB><reason>`, reason one of `self-test failed`, `rewrite failed`, `head image unreadable`, `candidate cap`, `time budget`.

Relay. `_sr_relay` handles `$3 == "sqli-payload"` in its own branch, placed before the test-path `else`, with its own counter `ns`: up to 20 `A` lines `[advisory] data-loss skip: <path> (built-in sqli-payload literal, test path)` and `L` lines `EXEMPT | floor | <rid> (data-loss: <path>; sqli-payload literal)`, then one END line `[advisory] data-loss skip: <n> more sqli-payload literals`. A `floor-note ... sqli-fallback` line gives one `L` line `SQLI-FALLBACK | floor | <rid> (<reason>)` each, and one `A` line in total: `[advisory] data-loss sqli carve-out fell back to the raw scan (<first reason>)`. The test-path branch and its counter `nt` do not change.

## Picture

```
 ship_rule_floor --KIT_FLOOR_SQLI_CARVEOUT=1--> lane-classify.sh floor      battery-gate, proof-ledger --=0--> raw scan
        |
        v
 producer awk (LC_ALL=C) --> $tmp/added  path<TAB>line   (format unchanged)
                         \-> $tmp/plen   byte length of each record's path
        |
   flag set? --no--> grep chain on raw lines
        | yes
        v
 self-test: pass B on two built-in records ---fails---> note "self-test failed"; raw
        | ok
        v
 pass A awk: prefilter (' and ;--) + G0 + G1 --> candidates (unique, diff order)
        |
        v
 G9 loop: <= 20 files, <= 5 s; git show <head>:<path> must succeed; no openers --> $tmp/sqli-allow
        |                                                     \-> notes: cap, time budget, unreadable
        v
 pass B awk (EREs from ENVIRON): G0..G8 on allowed paths --> $tmp/added.n + $tmp/sqli-notes
        |
   exit 0 AND equal line counts? --no--> note "rewrite failed"; raw
        | yes
        v
 mv -f added.n added; cat sqli-notes >&2
        |
        v
 grep chain, unchanged --> "full data-loss: <path>" or nothing
        |
 stderr --> _sr_relay: sqli branch (ns, cap 20, END) | fallback (A once, L each) | test-path else --> push advisory + ship-gate.log
```

## Design

### Approaches considered + chosen

1. **Skip the data-loss scan on `_HP_testpath`.** Does not fix the sample (singular `test/`, `test-` prefix). Widening `_HP_testpath` widens the auth exemption. Rejected (SPEC-400 DEC-10).
2. **Any quote-semicolon-verb-dash span (round 1).** Matched real SQL (`UPDATE t SET a='x'; DROP TABLE b; -- reset`). Rejected.
3. **Line guards only (round 2).** An opener `'` on an earlier line makes a qualifying line part of real SQL. Rejected.
4. **Broad code tokens (`=`, `(`, `,`, `[`, `:`).** Admits formatter arguments and assign-then-reuse. Rejected for `in ` only (DEC-2).
5. **Tighten `_HL_common` itself.** POSIX ERE has no lookaround, so the guards need awk and git anyway. Rejected.
6. **Inline the rewrite into the producer awk.** A separate pass can fall back to the complete raw file, and G9 needs git between detection and rewrite. Rejected (DEC-8).
7. **Chosen: an opt-in, guarded pre-scan rewrite** at the ship-gate only, with G0 to G9, a self-test, bounds, and fail-closed fallback to the raw file.

ADR: none. The change is reversible (constants, two awk passes, one relay branch, one env flag), and DEC-1 to DEC-10 hold the record.

### Diagram

See `## Picture`.

### Mechanics

- The producer awk runs under `LC_ALL=C` and writes `$tmp/plen` beside `$tmp/added`, so a path that holds a TAB splits at the right byte.
- Prefilter: a line pays for `tolower` and `match` only when it holds both `'` and `;--`. G2 caps a line at one span: no rescan loop.
- EREs reach awk through `ENVIRON`, never `-v`. `tolower` under `LC_ALL=C` touches ASCII only, so offsets align after multibyte UTF-8.
- G9 captures `git show` to a file and tests its exit status. A failed read is not allowed. This is the opposite of the fail-open pipe at `lane-classify.sh:639`.
- Self-test: pass B runs on two built-in records, a canonical literal after `in ` in `tests/x.sh` (must be replaced) and the same literal after `= ` (must stay). The literal is built from parts in the source (`dr` + `op table`), so the source line is not a data-loss line.
- Fail-closed: pass B writes `$tmp/added.n` and `$tmp/sqli-notes`; `mv` happens only on exit 0 and equal line counts, then the notes print.
- Verified flavours (scratch prototype of G0 to G8): macOS BWK awk 20200816, gawk and mawk from Homebrew.
- Comments beside `_HP_testpath` and `_HL_sqli_testpath` name each other and state that neither feeds the other.

### Boundaries & failure modes

See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- `lane-classify.sh floor <root> [<base> [<head>]]`: stdout contract unchanged. With the carve-out flag, a diff whose only destructive-shaped added text is canonical payload literals prints nothing for data-loss. Stderr gains the notices and fallback notes above.
- New constants: `_HL_sqli_payload`, `_HL_sqli_testpath`, `_HL_sqli_ext`, `_HL_sqli_join`. No config key, no CLI flag. A PR cannot set the env flag or widen a constant.

### Data model changes

None.

## Task Breakdown

### Phase 1: Core

| Task | Depends on | Files | Acceptance |
|---|---|---|---|
| T1a: constants, producer `plen`, flag check, pass A, G9 allow-list | none | `lib/classify/lane-classify.sh`, `lib/gate/battery-gate.sh`, `lib/gate/proof-ledger.sh` | AC1 to AC5 |
| T1b: pass B, self-test, fail-closed `mv`, notices | T1a | `lib/classify/lane-classify.sh` | AC6 to AC10 |
| T2: relay and flag at the ship-gate | T1b | `lib/gate/ship-rules.sh` | AC11 |
| T3: cases | T1a, T1b, T2 | `tests/test-lanes-data.sh` | AC12, AC13; every AC has a case that goes red under NC1 or NC2 |
| T4: manual | T1b | `docs/MANUAL.md:138` | the sentence names the exception and that it applies at the ship-gate only |
| T5: record | T1a, T1b, T2, T3, T4 | `docs/verification/data-loss-hardpath-scope.md` | the Verification output, NC1 and NC2 `negctl.sh` results, the ops-toolkit reproduction before and after |

## After state

At the ship-gate, a sandbox test that loops over `"x'; DROP TABLE alerts;--"` as rejection input owes the lane its own change earns, and the push output names the skip. Every other destructive added line still forces the full lane, and every other floor caller sees the raw scan.

## Acceptance Criteria (global)

All rows are in-repo fixtures run with `KIT_FLOOR_SQLI_CARVEOUT=1` unless noted. Row tables use `path|content|want`.

| AC | Task | Rule | Rows or case |
|---|---|---|---|
| AC1 | T1a | Path guards keep the hit | `floor-data-loss-sqli-paths`, `hit`: `app/t.sh` with `for b in "x'; DROP TABLE alerts;--"; do` (G0); the same line in `tests/seed.sql`, `tests/seed.pgsql`, `tests/seed.sql.j2`, `tests/t.pl`, `tests/t.cpp`, `tests/t` (G1) |
| AC2 | T1a | Cross-line openers keep the hit | `floor-data-loss-sqli-crossline`, two-or-more-line files, `hit`: `tests/t.sh` with `psql <<EOF`, `UPDATE t SET a='`, `for b in "x'; DROP TABLE t;--"; do`, `EOF`; `tests/t.py` with `q = """SELECT * FROM t WHERE n = '` then `for b in "x'; DROP TABLE t;--": pass`; `tests/t.js` with a backtick line then the literal line; `tests/t.rs` with `let o = r#"a='"#;` then the literal line; `tests/t.rb` with `o = %q(a=')` then the literal line |
| AC3 | T1a | An unreadable head image keeps the hit | `floor-data-loss-sqli-show-fails`: a PATH shim `git` exits 128 on `show <rev>:tests/...` and execs the real git otherwise. The sample row prints `full data-loss: <path>` and stderr holds `sqli-fallback<TAB>head image unreadable` |
| AC4 | T1a | The candidate cap keeps the hit | `floor-data-loss-sqli-cap`: 21 files `tests/t01.sh` to `tests/t21.sh`, each with the sample-shaped line. Stdout is `full data-loss: tests/t21.sh`; stderr holds 20 `sqli-payload` notices and one `candidate cap` note |
| AC5 | T1a | Only the ship-gate opts in | `floor-data-loss-sqli-optin`: the sample row with no flag, and with `KIT_FLOOR_SQLI_CARVEOUT=0`, prints `full data-loss: <path>`; `battery-gate.sh` and `proof-ledger.sh` pass `KIT_FLOOR_SQLI_CARVEOUT=0` on their floor calls |
| AC6 | T1b | Canonical literals miss | `case_floor_data_loss` rows, `miss`: `tools/vps-mon/scripts/test/test-hb-ack.sh` with the exact #4630 line; `tests/t.py` with `for p in "1'; drop table users;--": pass`; `tests/é.sh` with `é=1; for b in "x'; DROP TABLE t;--"; do` (multibyte before the span) |
| AC7 | T1b | Line guards keep the hit | rows, `hit`, in `tests/t.sh` unless noted. G7: `p = "x'; DROP TABLE users;--"`; `tests/t_test.go` with `s := fmt.Sprintf(tmpl, "x'; DROP TABLE t;--")`; `db.execute("x'; DROP TABLE users;--")`; `       "x'; DROP TABLE t;--")`. G4: `db.execute(opener + "x'; DROP TABLE users;--")`; `""" + "x'; DROP TABLE t;--")`; `for b in f"x'; DROP TABLE t;--"`. G2: `for b in "x'; DROP TABLE t;--" 'y'`. G3: ``for b in `x'; DROP TABLE t;--` ``; `for b in "a \"q\" x'; DROP TABLE t;--"`. G6: `echo "a in "x'; DROP TABLE t;--"`. G5: `for b in "x'; DROP TABLE alerts; --"`; `for b in "x'; DROP TABLE alerts"`; `for b in "x'; DROP TABLE IF EXISTS alerts;--"`; `for b in "Robert'); DROP TABLE Students;--"`; `for b in "x'; DELETE FROM users;--"`. Real SQL: `INSERT INTO t VALUES ('a'); DROP TABLE old; -- legacy`; `UPDATE t SET a='x'; DROP TABLE b; -- reset`; `SELECT 'done'; TRUNCATE TABLE tmp_load; -- nightly`; `db.exec("SELECT '1'; TRUNCATE users;--")`; `db.execute("a"); DROP TABLE users; -- x`; `DROP TABLE users;` |
| AC8 | T1b | A real statement beside a literal still hits | `floor-data-loss-sqli-payload`: `tests/m.sh` line `for b in "a'; DROP TABLE t;--"; do psql -c "DROP TABLE users"; done` prints `full data-loss: tests/m.sh` |
| AC9 | T1b | TAB in a path splits right | `floor-data-loss-sqli-tab-path`: `tests/a<TAB>b.sh` with the sample-shaped line prints nothing; with `DROP TABLE users;` it prints a `full data-loss:` line (the `${rec%%$T*}` print is unchanged) |
| AC10 | T1b | Awk failure or a failed self-test keeps the hit | `floor-data-loss-sqli-awk-fails`: a PATH shim `awk` exits 2 when `ENVIRON` holds the pass-B payload variable: the sample row hits, stderr holds `rewrite failed` or `self-test failed` and no `sqli-payload` notice. Second leg: the shim prints nothing for the self-test input file only: the row hits and stderr holds `self-test failed` |
| AC11 | T2 | The skip and the fallback are visible and labelled | `ship-sqli-skip-visible`: the sample fixture on a normal-lane push passes (rc 0); `systemMessage` holds `[advisory] data-loss skip: <path> (built-in sqli-payload literal, test path)`; the log holds `EXEMPT \| floor \| <rid> (data-loss: <path>; sqli-payload literal)` and never `test-path default` for it; a push with one test-path auth skip and one sqli skip prints each with its own label (the branch sits before `else`); 21 sqli skips across 20 files give 20 lines plus `1 more sqli-payload literals`; the AC3 shim gives exactly one `A` fallback line and an `SQLI-FALLBACK` log line, and blocks (rc 2) |
| AC12 | T3 | Cost stays flat | `floor-data-loss-sqli-long-line`: one added line of about 170,000 bytes (`:` then 20,000 short literals, then `; for b in` and the literal) in `tests/l.sh`: stdout empty, under 3000 ms. `floor-data-loss-sqli-many-lines`: 30,000 added lines in `tests/m.sh`, each sample-shaped (about 1.4 MB): under 15000 ms. `floor-data-loss-sqli-big-head`: a 5 MB `tests/big.sh` head image with one sample-shaped added line: under 5000 ms |
| AC13 | T3 | No regression | every existing row in `case_floor_data_loss` keeps its verdict without the flag; `floor-where-boundary`, `floor-plus-line`, `floor-non-ascii`, `floor-exempt-data-loss-still-hits`, `ship-data-loss`, `ship-test-path-skip-visible`, `floor-test-path-notice`, `floor-timing`, `floor-timing-30k` stay green; `floor-data-loss-still-hits-in-comments` in `tests/test-ceremony-fits-diff.sh` stays green |

## Verification

`bash tests/test-lanes-data.sh floor-data-loss floor-data-loss-sqli-paths floor-data-loss-sqli-crossline floor-data-loss-sqli-show-fails floor-data-loss-sqli-cap floor-data-loss-sqli-optin floor-data-loss-sqli-canonical floor-data-loss-sqli-guards floor-data-loss-sqli-payload floor-data-loss-sqli-tab-path floor-data-loss-sqli-awk-fails ship-sqli-skip-visible floor-data-loss-sqli-long-line floor-data-loss-sqli-many-lines floor-data-loss-sqli-big-head floor-where-boundary floor-plus-line floor-non-ascii floor-exempt-data-loss-still-hits ship-data-loss ship-test-path-skip-visible floor-test-path-notice floor-timing floor-timing-30k && bash tests/test-ceremony-fits-diff.sh floor-data-loss-still-hits-in-comments && bash tests/run-all.sh --changed`

Two negative controls through `lib/gate/negctl.sh`, test command `bash tests/test-lanes-data.sh floor-data-loss-sqli-canonical floor-data-loss-sqli-payload`, recorded by T5:

- NC1: restore `lib/classify/lane-classify.sh` from the merge base. The AC6 rows go red (`floor-data-loss-sqli-canonical`).
- NC2: mutate pass B to replace the whole line content instead of the span. AC8 goes red (`floor-data-loss-sqli-payload`).

## Edge Cases

- A comment line in a test file (`# for b in "x'; DROP TABLE t;--"`): replaced when every guard holds. A comment holding a bare `DROP TABLE users;` still hits (SPEC-410).
- Two literals on one line: G2 fails, the line hits.
- A path with a TAB: split by the byte length from `plen` (AC9).

## Failure modes

| Class | Mitigation | Detection signal |
|---|---|---|
| Real SQL in production code is neutralized | G0; and the flag is off for every caller but the ship-gate | AC1, AC5 |
| Real SQL in a test file is neutralized | G1 to G9; every round-1 to round-3 counterexample is a row | AC2, AC7; the notice names every replaced path |
| Formatter argument or assign-then-reuse | G7 accepts `in ` only | AC7 G7 rows |
| A deliberate test-file author hides one drop string | accepted, decided risk (DEC-7) | AC11 advisory and EXEMPT log line; review lenses |
| Pass B fails, truncates, or misbehaves on a new awk | self-test; temp file; `mv` only on exit 0 and equal counts; notices only after `mv` | AC10; `sqli-fallback` note, `A` advisory, `SQLI-FALLBACK` log |
| `git show` fails or is slow | capture and test exit status; 20-file cap; 5 s budget | AC3, AC4, AC12 |
| A long line or many lines | prefilter; one `match` per line | AC12 |
| A TAB in a path | byte length from the producer | AC9 |
| Awk flavour or locale | `LC_ALL=C`; EREs via `ENVIRON`; prototype on BWK awk, gawk, mawk | AC6 multibyte row, `floor-non-ascii` |
| Residual spellings that still hit | any token but `in `, `IF EXISTS`, numeric context, no or gapped `--`, `)` variants, `DELETE` or `TRUNCATE` payloads, single-quoted or backtick literals, `OR 1=1` (not a signature), any non-test or unknown-language path | AC1, AC7 |

## Out of Scope

- `_HP_testpath` and the auth test-path default.
- Any per-repo exemption for data-loss. SPEC-400 DEC-10 stands for config.
- The pre-existing `${rec%%$T*}` path print for a path that holds a TAB.

## Touches

`lib/classify/lane-classify.sh`, `lib/gate/ship-rules.sh`, `lib/gate/battery-gate.sh`, `lib/gate/proof-ledger.sh`, `tests/test-lanes-data.sh`, `docs/MANUAL.md`, `docs/verification/data-loss-hardpath-scope.md`.

## Grounding

Live sample (read-only, ops-toolkit; AC6 copies it into an in-repo fixture, so no test depends on this commit):

- Commit `ce61e16c3` ("fix(vps-mon): hb-ack --rule acks a job's stale rows of one non-heartbeat rule (#4630)") adds 28 lines to `tools/vps-mon/scripts/test/test-hb-ack.sh`. The only added line matching any `_HL_*` signature is file line 116: `for bad in "x'; DROP TABLE alerts;--" "Kit_Regression" ""; do`. The text before the span ends in `in `.
- The file header says no real Cloudflare call happens: `HB_ACK_WRANGLER` points at a stub. The case asserts a bad `rule_id` exits 64 before wrangler runs.
- G9 on the sample: `git show ce61e16c3:tools/vps-mon/scripts/test/test-hb-ack.sh | grep -nE '<<|"""|`'` prints nothing, and the block-scalar part of `_FLOOR_DATA_OPENER` counts 0 lines. The sample passes G9.
- Reproduction with this worktree's lib: `bash lib/classify/lane-classify.sh floor <ops-toolkit checkout> ce61e16c3^ ce61e16c3` prints `full data-loss: tools/vps-mon/scripts/test/test-hb-ack.sh`.
- Matching rule: `_HL_common` at `lib/classify/lane-classify.sh:121`, applied at `:735`, printed at `:740`. `_HP_testpath` (`:118`) misses the sample path, and the floor reached the data-loss scan only because no path kind hit (`:716-719`).

Prototype runs (scratch awk of G0 to G8 with `plen`, EREs from `ENVIRON`, `LC_ALL=C`; G9 checked on the sample above): 21 rows gave the wanted verdict after the grep chain on `/usr/bin/awk` (BWK 20200816), `gawk` and `mawk`. A malformed bracket expression made all three exit non-zero with empty output: the AC10 class. 30,000 literal lines (1,387,780 bytes) took 162 ms on BWK awk, 347 ms on gawk, 67 ms on mawk.

Dry trace of the negative controls (real data-loss lines from the rule's own tests; with or without the flag each fails G0 as an `app/`, `db/`, `ui/` or `docs/` path, and also G2 or G1):

| Existing case (file:line) | Content | Guards that fail | Grep that still fires |
|---|---|---|---|
| `tests/test-lanes-data.sh:186`, `:188`, `:190`, `:192` | `DROP TABLE users;`, `deleteMany({})`, `DELETE FROM` forms | G0, G2 | `_HL_common`, delete-from greps |
| `:187`, `:193`, `:196`, `:197`, `:198`, `:199` | quoted drop and truncate strings | G0, G2 | `_HL_common`, `_HL_truncate_code` |
| `:189` | `TRUNCATE users` in `db/reset.sql` | G0, G1 | `_HL_truncate_sql` |
| `:830` | `DELETE FROM users -- everywhere` | G0, G2 | delete-from-no-where |
| `:477`, `:479`, `:482`, `:814` | `db.execute("DROP TABLE users")` and `x("DROP TABLE users")` | G0, G2 | `_HL_common` |
| `:1208` | `DROP TABLE users;` in an auth-exempt path | G0, G2 | `_HL_common` (DEC-10 holds) |
| `tests/test-ceremony-fits-diff.sh:391` | `# DROP TABLE users;` in `app/q.sh` | G0, G2 | `_HL_common` (SPEC-410 holds) |

NC1 trace: with the merge-base lib, `$tmp/added` keeps the raw AC6 lines. `_HL_common` matches at `:735`, so each `miss` row prints `full data-loss: <path>` and `floor-data-loss-sqli-canonical` fails.

NC2 trace: the mutated pass B replaces the whole AC8 content. No grep fires, stdout is empty, and `floor-data-loss-sqli-payload` (want `full data-loss: tests/m.sh`) fails.

## Decision Log

- DEC-1: replace the span, never the line (AC8, NC2).
- DEC-2: scope to the sample-backed shape: `;--` with no gap, `DROP TABLE` only, a double-quoted literal, after `in `. Each widening lacks a sample and is pinned as a hit.
- DEC-3: the sqli test path is a local constant, not `_HP_testpath`; neither feeds the other.
- DEC-4: the name class is bare (`[a-z0-9_]+`).
- DEC-5: fail closed on every doubt: a failed guard, self-test, awk run, line count, `git show`, cap or budget leaves the raw line.
- DEC-6: every skip and fallback is visible in its own relay branch and log line (SPEC-400 DEC-15).
- DEC-7: accepted, decided risk against SPEC-400 DEC-10. A test-file author who sets out to hide one drop string can still do it, for example an ordinary quoted string spanning lines in shell or Ruby that G9 does not see, or a value reused through a variable defined in an `in` loop. DEC-10 bars config exemptions a PR can steer; this carve-out is fixed in code, opt-in at the ship-gate only, and every use prints on the push. Cost on the other side: G9 rejects any Python test file with a docstring, so most Python test files never qualify. The operator directed the build with both named.
- DEC-8: a separate pass beats inlining into the producer: it falls back to the complete raw file, and G9 needs git between detection and rewrite.
- DEC-9: G9 reads the head image only. Added lines live in head, so only head can carry an opener into them; the base image adds a `git show` per file for no coverage.
- DEC-10: the carve-out is opt-in through an env flag that only `ship_rule_floor` sets. `battery-gate.sh` and `proof-ledger.sh` pass `=0`, so an exported value in an operator shell cannot reach them.
