# Implementation notes: wrap split

Delta from `docs/specs/SPEC-374-wrap-split.md` only: decisions the spec did not
make, deviations, and tradeoffs. The spec is the contract; this log is what the
build itself learned.

## Step 0: spec fold

Folded the round-2 lead decisions and flipped `Status:` to VALIDATED:

- `bin/test-affected` maps `lib/wrap/wrap.sh` and `lib/wrap/wrap-common.sh` to
  every `tests/test-wrap-*.sh` suite, never the runner. `tests/run-all.sh` skips
  a `# runner:` file, so a runner mapping would make `run-all --changed` run no
  wrap suite at all, and the runner takes about 7m40s, over test-affected's 300s
  timeout. Folded into the Picture, the Design paragraph, T3's Done-when, and
  the Verification comment.
- Picture now says the suites cover 11 of 12 modules plus report-lint and cli:
  there is no `test-wrap-common.sh`.
- The `chk_no` red proof in T2 now breaks the code under test so it prints the
  forbidden string; a `chk_no` fails only when the string appears, so breaking
  seed state alone cannot turn it red.
- Verification order: the T1 commit lands before any `git checkout --` restore
  in the cache sequence or the negative control, because a restore fails on an
  untracked module file. The negative control asserts the named rebase assert
  goes red; the runner's exit code does not discriminate since the baseline
  already carries 2 FAILs.
- The Sourcing paragraph now states the reason plainly: the fixed order is a
  determinism pick, safe because module top-levels carry no inter-assignment
  dependency.

## T1: code split

Decisions the spec did not make:

- Boundary blanks. Spec ranges leave four orphan blank lines (today's 254, 384,
  438, 1648). Each was folded into the following module, so every original line
  lands in exactly one file and a byte-level reconstruction is possible.
- Module headers. Each `lib/wrap/wrap-<m>.sh` opens with one comment line
  (`# wrap-<m>.sh -- <what>; sourced by lib/wrap/wrap.sh.`) plus a blank line:
  the spec's allowed "module header comments". No shebang, no `set`, no `exit`.
- `wrap.sh` carries the source loop as the spec's exact line with no extra
  comment, keeping the added-lines diff to the loop alone.
- Vacuous-pass caveat, temporary: `tests/test-wrap.sh:5736` greps `_absorbed`
  out of `lib/wrap/wrap.sh`. After T1 that sed extracts nothing, so the two
  descriptor-exhaustion asserts pass vacuously until T2 repaths the sed to
  `wrap-apply.sh`. Totals stay 1,581 either way; the asserts go live again in
  T2.

Checks (run on this worktree, baseline = detached worktree at a9f0c9dc):

- Rebuild proof: concatenating the pieces back in original order reproduces
  wrap.sh byte-identically (3,616 lines, `diff` empty). Stronger than the
  spec's sorted top-level diff: every line, not only top-level statements.
- `bash -n` on all 13 files: ok.
- Function defs across `lib/wrap/wrap*.sh`: 98, `uniq -d` empty.
- `grep -nE '^(set |exit|#!)' lib/wrap/wrap-*.sh`: no output (exit 1).
- Guard grep: prints `guard ci`, `guard carry`, `guard merge`.
- Top-level awk: baseline prints 52; sorted diff vs `lib/wrap/wrap*.sh` adds
  only the `for _m in ... unset _m` source loop.
- `git diff` new-lines audit: the only added lines absent from the original
  file are the 12 module headers and the loop; no removed original line fails
  to reappear.
- `bin/wrap --help` vs baseline: identical.
- `bash lib/codex/repin.sh check`: the two master-baseline stale pins
  (safety-gate.sh, ship-gate.sh), no new ones.
- `bash tests/test-wrap.sh` vs baseline monolith run: both print
  `test-wrap: 1579 passed, 2 FAILED of 1581`; the sorted PASS/FAIL line diff
  is empty (1,581 lines each side). The 2 FAILs are the baseline wording ones
  ("step 10 re-sizes the real diff before landing", "commands/wrap.md
  classifies each candidate's lane").

Deviations:

- The split commit briefly wrote `wrap.sh` at mode 644 (original 755); a
  follow-up commit restored the bit. Module files stay 644: sourced, never
  executed, and the spec's "no shebang" matches that mode.


