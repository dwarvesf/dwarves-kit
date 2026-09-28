# Verification: safety-gate splits segments the way bash does

Verdict: PASS

Spec: `docs/specs/SPEC-332-safety-gate-quoted-split.md` (revision 7). Change: `hooks/safety-gate.sh`, `tests/test-hooks.sh` (rows Q1 to Q90).

## Checks

| Check | Command | Result |
|---|---|---|
| Suite, fix, BSD awk 20200816 | `bash tests/test-hooks.sh` | `Passed: 604 / 604` |
| Suite, fix, gawk 5.4.1 | same, with a PATH shim so `awk` is gawk | `Passed: 604 / 604` |
| Suite, fix, mawk 1.3.4 | same, with a PATH shim so `awk` is mawk | `Passed: 604 / 604` |
| Suite, master's hook | `git show origin/master:hooks/safety-gate.sh` swapped in on a scratch clone | `Passed: 541 / 604`; all 63 failures are Q rows, every pre-existing row passes |
| Negative controls | `bash lib/gate/negctl.sh <clone> "bash tests/test-hooks.sh" "bash <mutation>"`, seven mutations, below | see below |
| Feature registry | `bash lib/registry/feature-registry.sh check --fix` | `docs/FEATURES.md regenerated`, committed |
| Cost | a 28 KB `python3 -c "x = 1; ..."` command through the hook | 0.4 s (master: 17 s); 30 nested false `$((` frames: 0.04 s |

## Red on master

The 63 Q rows that fail against master's hook: Q1 to Q7, Q9 to Q18, Q27, Q29 to Q50, Q54 to Q57, Q59, Q60, Q62 to Q65, Q67, Q71 to Q76, Q81, Q83 to Q86, Q88. Q54 is a false positive master had (a continued `rm -rf` of artifacts); the rest are bypasses master allowed.

The Q rows that pass on master pin shapes master already handled or allowed (Q8, Q19 to Q26, Q28, Q51 to Q53, Q58, Q61, Q66, Q68 to Q70, Q77 to Q80, Q82, Q87, Q89, Q90). They guard the new walk against regressions: Q28, Q58, Q66, Q69, Q70, Q78 to Q80, and Q87 are the orderings where an earlier revision allowed what master blocked.

## Validation

Six fresh-context Opus validation rounds plus one Opus break-it pass. Rounds 1 to 6 each returned NEEDS REVISION; every critical was folded in and pinned by a Q row. Rounds 5 and 6 rated their findings contrived except one plausible shape (`git -C "$(git rev-parse --show-toplevel)" push origin main`, open on master too), fixed in revision 7. The gate ledger records the rounds and a `validate` override. History: `docs/implementation-notes/safety-gate-quoted-split.md`.

## Negative controls

Each ran in a scratch clone of the committed branch, in parallel, with the full suite as the test command.

| # | Behavior | Mutation | Under mutation | Verdict |
|---|---|---|---|---|
| NC1 | quote-aware split | pass 1 splits on `;` and `\|` inside quotes | Exit 1 | PASS |
| NC2 | naive pass | the naive split no longer prints | Exit 1 | PASS |
| NC3 | heredoc replay | the END replay is dropped | Exit 1 | PASS |
| NC4 | comment rule | `#` is never a comment | Exit 1 | PASS |
| NC5 | grammar skip | the grammar arm of the segment-start loop is deleted | Exit 1 | PASS |
| NC6 | lone-`)` re-walk | the frame only turns | Exit 1 | PASS |
| NC7 | word-start flag | every `#` is a comment | Exit 1 | PASS |

Each run printed `Exit: 0 (green before mutation)`, `Changed: hooks/safety-gate.sh`, `Exit: 1 (under mutation, RED expected)`, `Exit: 0 (green after restore)`, `Verdict: PASS`.

## Not covered

Recorded in the hook header and the spec's Failure modes: a ref in a variable or an escape, a script file or a pipe into `bash`, a quoted separator inside a wrapped script, a `)` in a `case` pattern inside `"$(...)"`, a misread `<<` whose false delimiter appears later, a false arithmetic frame spanning lines, wrappers outside the segment-start list, wrapper flags with operands outside the table, and zsh-only syntax beyond the listed words.
