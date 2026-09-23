# Verification: precedent partial match (SPEC-308)

`precedent find --surface inventory` ranks rows by terms matched instead of zeroing a row on one absent word, reads YAML block-scalar descriptions, and indexes the extensionless entry points under `lib/<x>/bin/`.

Headless CLI change: the capture is the text output below, no image capture.

## Green run

```
Command: bash tests/test-precedent.sh
Exit: 0
  PASS partial match: a three-term query with one absent word still finds tools/alpha/
  PASS floor: one matching term of three is below the floor, nothing_matched
  PASS none-query: an unrelated three-word query reports nothing_matched
  PASS partial match without a name hit is dropped; the all-terms match still surfaces
  PASS separators: alpha_run matches tools/alpha/bin/alpha-run
  PASS separators: alpha-run matches tools/alpha/bin/alpha-run
  PASS separators: alpha/run matches tools/alpha/bin/alpha-run
  PASS dedupe: a repeated query word counts once toward the floor
  PASS block scalar: a >- and a | skill description index the real text
  PASS block scalar: an empty block reads as no description
  PASS ranking: an all-terms row outranks a partial row with more name hits
  PASS lib bin entry point: session-observe is indexed and tops 'session entry fee breakdown'
== summary ==
  81/81 passed
```

```
Command: RUN_ALL_TIMEOUT_SECS=600 bash tests/run-all.sh --changed
Exit: 0
run-all: 10 suites, 4 at a time, 0 serial
test-boundary-lint ok, test-config-registry ok, test-kit-contract ok, test-lane-classify ok,
test-meta ok, test-no-personal-paths ok, test-no-scattered-ids ok, test-precedent ok,
test-registry-freshness-guard ok, test-release ok
run-all: all 10 suites passed, 0 skipped for missing tooling
```

Live CLI on the operator's full registry (`~/.config/dwarves-kit/inventory.txt`, 49 rows), cwd ops-toolkit, `--json`, top hit:

| query | origin/master | this branch |
|---|---|---|
| lane classify regex | nothing_matched, 0.50s | `kit lib/classify/lane-classify.sh`, 7 hits, 0.54s |
| session entry fee breakdown | nothing_matched, 0.49s | `kit lib/session/observe/bin/session-observe`, 1 hit, 0.50s |
| mini reachability job liveness probe | nothing_matched, 0.48s | nothing_matched, 0.50s |
| board flip | 26 hits, 0.50s | 26 hits, 0.50s |
| kubernetes pod autoscaler | nothing_matched, 0.50s | nothing_matched, 0.54s |

Block scalars on the operator's machine: 172 skills across `~/.claude/skills`, the kit's `skills/` and ops-toolkit `.claude/skills`. Descriptions read as a bare marker or empty: 29 on origin/master, 1 on this branch. The one left has no frontmatter at all.

## Labeled set (jev-eval kit-decisions, 59 queries)

A local loop over `seed-data/kit-decisions/precedent-queries.json`, using the harness's own `kit_data` helpers and the same flat ranking as `harness/kit_decisions.py lexical_rank`. It reproduces the published origin/master numbers exactly.

| engine | hit@1 | hit@3 | none precision | none recall | p50 / max per query |
|---|---|---|---|---|---|
| origin/master | 26/45 | 30/45 | 12/18 | 12/14 | 0.38s / 0.54s |
| this branch | 30/45 | 34/45 | 9/11 | 9/14 | 0.41s / 0.75s |
| this branch, gold + newly indexed rows (P02 session-recall, P04/P06 session-observe) | 32/45 | 36/45 | 9/11 | 9/14 | 0.40s / 0.64s |

Queries that moved into hit@1: P18 share local html, P35 lane classify regex, P36 gate ledger bulk record, P41 disk full cleanup. Into hit@3 only: P29 browser profile backup snapshot. New false hits on negatives: N09 wifi password rotate, N11 ssh host keys rotate, N13 run-all suite timing (N05 and N10 were already false hits). Still missed: P16 eternal terminal, P31 mini reachability job liveness probe (2 of 5 words match the gold row), P03, P05, P07, P20, P34.

## Test plan coverage

| Row | Run / skip reason |
|---|---|
| 1 | green run, "partial match: a three-term query..." |
| 2 | green run, "floor: a two-term query with one absent term..." |
| 3 | green run, "floor: one matching term of three..." |
| 4 | green run, "none-query: an unrelated three-word query..." |
| 5 | green run, "partial match without a name hit is dropped..." |
| 6 | green run, the three "separators:" cases |
| 7 | green run, "dedupe: a repeated query word..." |
| 8 | green run, "ranking: an all-terms row outranks..." |
| 9 | green run, "block scalar: a >- and a \| skill description..." |
| 10 | green run, "block scalar: an empty block..." |
| 11 | green run, "lib bin entry point: session-observe..." |
| 12 | green run, the full suite 81/81 plus run-all --changed |
| 13 | labeled set table above |

## Negative control

```
## Negative control (negctl)
Command: bash tests/test-precedent.sh >/dev/null 2>&1
Exit: 0 (green before mutation)
Mutation: git show origin/master:lib/precedent/inventory.py > lib/precedent/inventory.py
Changed: lib/precedent/inventory.py
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/precedent/inventory.py
Exit: 0 (green after restore)
Verdict: PASS
```

Under the origin/master engine the suite goes 74/81. Red: partial match, separators `alpha_run` and `alpha/run`, both block-scalar cases, the ranking case, the lib bin entry point. The `alpha-run` separator case, the floor cases and the none-query case stay green there: they pin the contract that did not change.

## Review

`/kit:review-team`: architecture + correctness PASS, security SECURE, test-coverage 5 gaps (4 added as cases, the `tests/`-`fixtures/` bin exclusion left untested because the scan reads the real kit root), advisor 4 findings (score scale widened to 1000, pattern-cache comment, wrap step 7b partial-hit caution, the error-cost asymmetry written into the spec).

## Not proven

- The lib `bin/` exclusion for paths under `tests/` or `fixtures/` has no test; the code path is one set intersection.
- The labeled set is 59 queries from one labeler against a restricted registry. The live registry holds more rows and more distractors.
- `records` still misses `record` from a plural query: the inflection set stays closed by measurement (spec, Design record).

## Rollback

Revert the two commits. No state, no config, no schema.

## Reproduce

```
bash tests/test-precedent.sh
bash lib/gate/negctl.sh "$PWD" "bash tests/test-precedent.sh >/dev/null 2>&1" "git show origin/master:lib/precedent/inventory.py > lib/precedent/inventory.py"
```
