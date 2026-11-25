# Verification -- master-red-suites

Two master suites went red on the Mini after #1194 and #1195. Both are test-side defects; no kit behavior changes.

| Suite | Root cause | Fix |
|---|---|---|
| test-mktemp-template-guard | #1194 added three `mktemp -d` assignments in the proof-capture suites without the R3 guard form (`|| exit 1` / `|| return 1` on the same line); `new_dir` had no guard at all | the three lines carry the guard |
| test-operator-pin | (a) #1195's test-shared-lookups names `lib/wrap/...` paths as data, so the reach pattern flags it, and it pins nothing; (b) the helper scan piped `code_of` into `grep -q` under `pipefail`, so a SIGPIPE (141) on the 32 KB wrap-stub.sh dropped it from the helper lists at random and flagged every test-wrap-* suite | (a) test-shared-lookups carries `# operator-layer: unpinned-ok` with its reason (it reads files as text and runs no resolver); (b) the scan reads a here-string, no pipe |

## Green run

Commit `ebf0629b`, on the Mini (macOS, bash 5.3):

```
Command: bash tests/test-mktemp-template-guard.sh; bash tests/test-operator-pin.sh; bash tests/test-shared-lookups.sh
Exit: 0 / 0 / 0
Output:
  test-mktemp-template-guard rc=0
  test-operator-pin rc=0
  test-shared-lookups rc=0
  operator-pin x10 fixed: 0 0 0 0 0 0 0 0 0 0
Verdict: PASS
```

## Negative control

Run after the commit; each mutation planted back, the suite run, the file restored (`git status` clean after):

```
Command: bash negctl.sh <worktree>
Output:
  == NC1: drop the shared-lookups exemption
    FAIL  no suite reaches the resolver unpinned (355 suites scanned) (want '', got 'tests/test-shared-lookups.sh')
  == NC2: put the pipe back in the helper scan
  piped lines: 2
  operator-pin x10 piped: 0 0 0 0 0 1 0 0 0 1
  == NC3: unguard new_dir in the proof-capture suite
    FAIL violations:
  R3 lib/proof-capture/tests/test-proof-capture.sh:104: new_dir() { local d; d=$(mktemp -d "$SUITE_TMP/d.XXXXXX"); echo "$d"; }
Verdict: each planted bug turns its suite red; NC2 shows the flake the fix removes (2 of 10 red with the pipe, 0 of 10 without)
```

## Reproducible

`bash tests/test-operator-pin.sh` ten times in a row on the fixed tree; `bash tests/test-mktemp-template-guard.sh` once.

## Not covered

`bash tests/run-all.sh --changed` selects `lib-proof-capture-test-proof-capture` and `test-proof-capture-route` because this diff touches their files. Under a Mini load average of 60 to 77 the proof-capture signal cases (6, 14, 15) time out: the tool does not exit within the window after INT, and the leaked work dir then fails every later "private TMPDIR is empty" check. The same cases failed on the Linux runner at `f3c90238` before this change, the standalone suite passes (`17 passed, 0 failed, 1 skipped`), and this diff does not touch `lib/proof-capture/bin/proof-capture`. It is a load-sensitive timing issue in that suite, left to the nightly full run.
