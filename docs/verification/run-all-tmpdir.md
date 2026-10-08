# Proof of done: run-all.sh builds its scratch dir under TMPDIR and fails loudly

## What changed

`tests/run-all.sh` made its scratch dir with a bare `mktemp -d`. macOS `mktemp -d` ignores `$TMPDIR` and uses `/var/folders`, which a sandbox may deny. `OUTDIR` stayed empty, every write went to `/runlist`, `/parallel` and `/serial`, zero suites ran, and the report read "all  suites passed". The runner now uses `mktemp -d "${TMPDIR:-/tmp}/run-all.XXXXXX"` and exits 1 with one line when the dir cannot be made. The runner has no other `mktemp` call. Suites with their own bare `mktemp` are out of scope for this change.

## Gate table

| Claim | Evidence |
|---|---|
| scratch lands under `$TMPDIR` | `tests/test-run-all-tmpdir.sh` case 1, manual run below |
| an uncreatable `$TMPDIR` exits non-zero with one clear line | case 2, manual run below |
| the new test is load-bearing | negative control below |
| no regression in the suites the diff touches | `run-all.sh --changed --time` below |

## Run table

```
Command: bash tests/test-run-all-tmpdir.sh
Exit: 0
Output:
[1] the scratch dir lands under $TMPDIR
  ok: scratch under TMPDIR during the run, removed after
[2] an uncreatable $TMPDIR fails loudly, runs nothing
  ok: non-zero exit, one clear line, no false pass
test-run-all-tmpdir: all 2 passed
Verdict: PASS
```

```
Command: TMPDIR=$(mktemp -d "/private/tmp/rk.XXXXXX") bash tests/run-all.sh --only run-all-tmpdir
Exit: 0
Output:
run-all: 1 suites, 4 at a time, 0 serial
test-run-all-tmpdir                            ok
run-all: all 1 suites passed, 0 skipped for missing tooling
Verdict: PASS (nonzero suite count under a redirected TMPDIR)
```

```
Command: TMPDIR=/nonexistent bash tests/run-all.sh --only run-all-tmpdir
Exit: 1
Output:
run-all: cannot create a scratch dir under /nonexistent; set TMPDIR to a writable directory
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 0
Output:
test-run-all-timeout                           ok (5s)
test-run-all-times                             ok (3s)
test-run-all-tmpdir                            ok (1s)
run-all: all 12 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control

```
Command: git show origin/master:tests/run-all.sh (pre-fix runner) installed over tests/run-all.sh, then bash tests/test-run-all-tmpdir.sh
Exit: 1
Output:
/var/folders/.../T//rat.XXXXXX/kit/tests/run-all.sh: line 54: .../tests/lib/run-lock.sh: No such file or directory
run-all: all 1 suites passed, 0 skipped for missing tooling
test-run-all-tmpdir: 0 passed, 2 FAILED
Verdict: RED with the old runner (it ignored TMPDIR and passed with an unwritable one); GREEN again after restoring the fix.
```

## Not proven

- The sandbox that denies `/var/folders` was simulated with a nonexistent `TMPDIR`, not reproduced.
- `bash tests/run-all.sh --all` was not run: `AGENTS.md` reserves it for CI and the nightly job.
- Suites that call a bare `mktemp -d` themselves (for example `tests/lib/hook-parity.sh`) are untouched.
