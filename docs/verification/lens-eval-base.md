# Proof of done: lens-eval names the base a `fewer` signal assumes

Spec: `docs/specs/SPEC-325-lens-eval-base.md`. Lane: full. Files: `lib/bench/lens-eval.sh`,
`lib/bench/README.md`, `tests/test-lens-eval.sh`, `docs/CHANGELOG.md`, `docs/FEATURES.md`
(regenerated), this file. Profile: tool-build. Proof class: behavioral, fully offline (no model
call; the script's own stub-driven test suite is the real primary flow for this feature).

Acceptance: every `control: fewer` signal in a run shows no gap (treatment hit the majority and
control tied or beat it) and at least one such signal ran, and the script prints exactly one
`note:` line naming the count and the base ref; the note stays silent when a `fewer` signal
still shows a real gap, when no signal carries `fewer`, or when a `fewer` signal's treatment arm
itself missed the majority (a treatment regression, not a base problem); the note never changes
the exit code.

| Check | Command | Exit | Result |
|---|---|---|---|
| Green | `bash tests/test-lens-eval.sh` | 0 | `Passed: 105 / 105`, `All lens-eval tests passed.` |
| Structural | `bash tests/test-meta.sh` | 0 | `Passed: 879 / 879`, `All meta tests passed.` |
| Freshness | `bash lib/registry/feature-registry.sh check` | 0 | `docs/FEATURES.md is fresh` |
| Negative control | `bash lib/gate/negctl.sh "$PWD" "bash tests/test-lens-eval.sh" "<mutation>"` | 0 | `Verdict: PASS` (green -> mutated RED -> restored GREEN) |
| Full suite (changed) | `bash tests/run-all.sh --changed` | 0 | `all 35 suites passed, 0 skipped for missing tooling` |

## Green run

```
Command: bash tests/test-lens-eval.sh
Exit: 0
Output (excerpt):
  === base-mismatch note ===
  PASS all-fewer-no-gap: note prints, names the count
  PASS all-fewer-no-gap: exit code unchanged (still FAIL)
  PASS single-fewer-no-gap: note prints, names 1
  PASS one-still-shows-a-gap: no note line
  PASS no-fewer-signals: no note line
  PASS treatment-miss-not-base-problem: no note line
  PASS treatment-miss-not-base-problem: signal still recorded as a tie

  === Results ===
  Passed: 105 / 105
  All lens-eval tests passed.
```

```
Command: bash tests/test-meta.sh
Exit: 0
Output: Passed: 879 / 879 / All meta tests passed.
```

```
Command: bash lib/registry/feature-registry.sh check
Exit: 0
Output: feature-registry: docs/FEATURES.md is fresh
```

```
Command: bash tests/run-all.sh --changed
Exit: 0
Output (excerpt):
  test-lens-eval                                 ok
  test-meta                                      ok
  test-registry-freshness-guard                  ok
  run-all: all 35 suites passed, 0 skipped for missing tooling
```

## Test plan coverage

| Case | Run / skip reason |
|---|---|
| All fewer, no gap | `bash tests/test-lens-eval.sh`, `bm1` block ("all-fewer-no-gap") |
| One still shows a gap | same run, `bm3` block ("one-still-shows-a-gap") |
| No fewer signals | same run, `bm4` block ("no-fewer-signals", reruns the report-shapes `SHAPES` case file) |
| Single fewer, no gap | same run, `bm2` block ("single-fewer-no-gap") |
| Treatment regression, not a base problem | same run, `bm5` block ("treatment-miss-not-base-problem") |
| Exit status unchanged | same run, the "all-fewer-no-gap: exit code unchanged (still FAIL)" assertion |

## Negative control

Pinned mutation: neutralize the `fewer_nogap` credit so a no-gap `fewer` signal is counted but
never credited toward the note.

```
Command: bash tests/test-lens-eval.sh
Mutation: sed -i.bak "s/fewer_nogap=\$((fewer_nogap + 1))/:/" lib/bench/lens-eval.sh && rm -f lib/bench/lens-eval.sh.bak
Exit before: 0 (green before mutation)
Exit under mutation: 1 (RED as expected)
Restore: git checkout HEAD -- lib/bench/lens-eval.sh
Exit after restore: 0 (green after restore)
Verdict: PASS
```

Rows that went red under the mutation (`fewer_nogap` never reaches `fewer_total`, so the
`fewer_total > 0 && fewer_nogap == fewer_total` gate never fires):

- `all-fewer-no-gap: note prints, names the count` (expected the note text, got none)
- `single-fewer-no-gap: note prints, names 1` (expected the note text, got none)

Unaffected, confirming the mutation's blast radius is exactly the note-presence assertions:
`all-fewer-no-gap: exit code unchanged (still FAIL)`, `one-still-shows-a-gap: no note line`,
`no-fewer-signals: no note line`, `treatment-miss-not-base-problem: no note line`, and every
pre-existing row (`103 / 105` still pass under the mutation).

## Reproduce

```
bash tests/test-lens-eval.sh
bash tests/test-meta.sh
bash lib/registry/feature-registry.sh check
mutate='sed -i.bak "s/fewer_nogap=\$((fewer_nogap + 1))/:/" lib/bench/lens-eval.sh && rm -f lib/bench/lens-eval.sh.bak'
bash lib/gate/negctl.sh "$PWD" "bash tests/test-lens-eval.sh" "$mutate"
```

## Limits

No live `claude` call: the feature is the scoring loop's own arithmetic (a counter and a
conditional print), fully exercised by the offline stub harness; a live lens-eval run was out of
scope per the dispatch instruction (no model spend for this change). The note is a heuristic,
not a proof that a base ref is wrong: it fires whenever every `fewer` signal in a run ties or
loses, which a genuinely gapless base and a genuinely broken script both happen to produce
identically from the script's own point of view; only the operator can tell which by reading the
base ref choice.
