# Verification: proof path matching is location-agnostic

Scope: `_fresh_proof_files()` and the set-wise group regex in
`lib/gate/proof-ledger.sh`. The claim under test is that a proof at
`docs/verification/` nested under ANY owner directory now satisfies the gate,
that the pre-fix code did not accept it, and that nothing previously accepted
or rejected changes.

## Problem

The matcher enumerated owner directories: repo-root `docs/verification/`,
`tools/<name>/docs/verification/`, and any `/proof-of-done.md`. ops-toolkit's
co-location rule also puts an experiment's proof at
`experiments/<slug>/docs/verification/<feature>.md`, which matched none of
them. The gate then read a branch that HAD a proof as unproven, fell through
to the override branch, and refused the source change with "no proof of done".

This is the second occurrence. ID-478 fixed the same class for `tools/` by
adding one more alternative. Enumeration is the defect: each new co-location
home needs another alternative, and the failure is silent.

## Change

Two regexes collapse into location-agnostic forms.

```
-'^docs/verification/.+\.md$|^tools/[^/]+/docs/verification/.+\.md$|(^|/)proof-of-done\.md$'
+'(^|/)docs/verification/.+\.md$|(^|/)proof-of-done\.md$'

-'s#^(docs/verification/[^/]+/).*#\1#p;s#^(tools/[^/]+/docs/verification/[^/]+/).*#\1#p'
+'s#^(.*docs/verification/[^/]+/).*#\1#p'
```

This grants nothing the already-anywhere `/proof-of-done.md` rule did not.
The `grep -v '/README\.md$'` exclusion is untouched.

## Green run

```
bash tests/test-proof-experiment-verification-path.sh
```

| Case | Result |
|---|---|
| `experiments/<slug>/docs/verification/<feature>.md` accepted | PASS |
| `experiments/<slug>/docs/verification/<feature>/run.md` accepted (set-wise grouping) | PASS |
| An unenumerated owner dir (`learning/<topic>/docs/verification/...`) accepted | PASS |
| `docs/verification/README.md` still excluded | PASS |

- Command: `bash tests/test-proof-experiment-verification-path.sh`
- Exit: 0
- Verdict: PASS

## NEGATIVE CONTROL

The same fixture was run against `origin/master`'s copy of the lib, obtained
with `git show origin/master:lib/gate/proof-ledger.sh`, and then against the
patched copy.

```
--- PRE-FIX lib (expect BLOCK) ---
pre-fix lib BLOCKED as expected
--- POST-FIX lib (expect ACCEPT) ---
post-fix lib ACCEPTED as expected
```

- Command: pre-fix `check` on an `experiments/.../docs/verification/*.md` proof
- Exit: non-zero (BLOCKED)
- Verdict: RED-as-expected

The fixture is identical across both runs, so the accept is attributable to the
regex change and nothing else. The README case above is the second control: it
proves the loosened pattern did not become accept-everything.

## Regression

Every sibling proof test re-run against the patched lib.

| Test | Result |
|---|---|
| test-proof-dir-layout.sh | ALL PASS (3/3) |
| test-proof-tool-verification-path.sh | ALL PASS (1/1) |
| test-proof-visual-evidence.sh | ALL PASS (4/4) |
| test-proof-table-gen.sh | green |
| proof-loop-09-scenario-b.sh | every transcript claim reproduced |
| test-proof-override-order.sh | FAILS 1, pre-existing, see below |

`test-proof-override-order.sh` fails on pristine `master` as well, with no
change of mine present. Its negative control reverts "the fix" by stashing an
UNCOMMITTED working-tree diff to `lib/gate/proof-ledger.sh`. That fix has been
committed for some time, so on master the file has no diff to stash and the
test takes its own `[NO EXECUTABLE CHECK]` branch and counts a failure. On this
branch it stashes MY unrelated edit instead, reverts to committed master, which
still contains the override-order fix, and so the case stays PASS and again
counts a failure. The test can no longer pass either way. Reverting to
`git show <fix-sha>^:lib/gate/proof-ledger.sh` would repair it. Out of scope
here, filed separately.

## Rollback

`git revert`. The gate returns to enumerating owner directories, and an
experiment's co-located proof goes invisible again.
