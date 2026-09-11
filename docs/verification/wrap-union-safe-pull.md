# Proof of done: `wrap apply` carries union-marked logs across the ff-only pull

2026-09-11. Acceptance: on the default branch, `bin/wrap apply --apply` completes the pull when the
only uncommitted tracked files are declared `merge=union`, keeps both the incoming lines and the
local ones, and lands each carried line below the header anchor. Any other modified file, or a dirty
index, keeps today's behavior and prints the blocking reason before the pull. HEAD prints in the same
output block. Lane: full. Files: `lib/wrap/wrap.sh`, `tests/test-wrap.sh`.

## Why this is safe to automate

`.gitattributes` in the adopting repos marks the append-only logs `merge=union`. That declaration
says keeping every line from both sides resolves the file. Carrying local lines across a pull is
therefore the file's stated semantics, not a judgment. For every other path it stays a judgment, so
one non-union modified file switches the whole run back to the old behavior.

## The failure this replaces

A shared checkout collects uncommitted lines from other sessions, most often in `_meta/LAB_LOG.md`.
Git printed `Updating <a>..<b>`, then aborted the merge, and a `tail -1` hid the abort. An operator
deployed a Cloudflare Worker from a checkout two commits behind and served the wrong version for
about eleven minutes. The manual workaround ran six times by hand in one session.

## Green run

Command: `bash tests/test-wrap.sh`
Exit: 0
Output: `test-wrap: all 308 passed`
Verdict: PASS. 278 assertions before the change, 308 after; the 30 new ones are the five contract
cases plus the dry-run case, each against real git repos built on disk.

Command: `bash tests/run-all.sh`
Exit: 0
Output: `run-all: FAILED -> test-orchestrate-gate-dispatch test-orchestrate-wavefront` /
`run-all: 133 suites run, 1 skipped for missing tooling`
Verdict: PASS, no regression. The same two suites fail identically on `master` at `cfb5448` before
the change, so the counts match on both sides.

| Suite run | Suites | Skipped | Failing suites |
|---|---|---|---|
| Before, `master` cfb5448 | 133 | 1 | test-orchestrate-gate-dispatch, test-orchestrate-wavefront |
| After, `feat/wrap-union-safe-pull` | 133 | 1 | test-orchestrate-gate-dispatch, test-orchestrate-wavefront |

## Cases the tests bind

Each case builds a bare origin plus a clone with a real `.gitattributes`, a real commit, and a real
incoming commit to fast-forward to. Nothing stubs `git`, because what git does to a dirty checkout
during a pull is the whole subject.

| Case | Setup | Asserted |
|---|---|---|
| Union log dirty | `_meta/LAB_LOG.md` modified locally and remotely | pull succeeds, HEAD moves to the incoming commit, both lines present, the local line still uncommitted |
| Anchor rule | same fixture | line 1 is still the header, the carried line sits below the `---` separator and above the older entries |
| Non-union dirty | `README.md` modified locally and remotely | the file is byte-identical after the run, the reason names `README.md` before the pull, `FAILED pull --ff-only`, exit 2 |
| Mixed | one union file and one non-union file dirty | treated as the non-union case, nothing saved aside, no carry-back, the union file byte-identical |
| Dirty index | a staged `_meta/LAB_LOG.md` | the index reason prints, nothing saved aside, the path is still staged, the file byte-identical |
| Dry run | union file dirty, no `--apply` | the carry is announced only, nothing saved or checked out, the file byte-identical |

## Negative control

Command: `bash lib/gate/negctl.sh <worktree> "bash tests/test-wrap.sh" "<mutation>"`
Mutation: force `_union_marked` to accept every path, which defeats the classification.

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: perl -i -pe 's/\*"merge: union"\) return 0/*) return 0/' lib/wrap/wrap.sh
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Ten assertions go RED under that mutation, `test-wrap: 298 passed, 10 FAILED of 308`:

```
  FAIL non-union: apply exits 2 because the pull still aborts
  FAIL non-union: the blocking file is named before the pull
  FAIL non-union: the pull failure is still reported
  FAIL non-union: nothing was saved aside
  FAIL non-union: the dirty file is byte-identical
  FAIL non-union: HEAD did not move
  FAIL mixed: the non-union file is named
  FAIL mixed: the union file was never saved aside
  FAIL mixed: no carry-back happened
  FAIL mixed: the union file is byte-identical
```

`the dirty file is byte-identical` is the load-bearing one. Without the classification the run checks
out a file the operator never declared safe to discard. The gate holds because that assertion fails.

## Reproduce

```
git -C <repo> switch feat/wrap-union-safe-pull
bash tests/test-wrap.sh          # the feature, 308 assertions
bash tests/run-all.sh            # no regression across 133 suites
bash lib/gate/negctl.sh . 'bash tests/test-wrap.sh' \
  'perl -i -pe '\''s/\*"merge: union"\) return 0/*) return 0/'\'' lib/wrap/wrap.sh'
```
