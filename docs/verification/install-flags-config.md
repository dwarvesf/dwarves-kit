# Verification -- install-flags-config

`install.sh` now answers `--help`/`-h` (exit 0) and rejects an unknown argument (exit 64), both before any write; the shipped `kit.toml` no longer carries a private 1Password ref, and a remote gauntlet run fails fast when `probe_key_ref` is empty.

## Green run
```
Command: bash tests/test-install-modules.sh; bash tests/test-gauntlet-remote-key.sh; bash tests/run-all.sh --changed origin/master
Exit: 0
Output:
test-install-modules.sh      == 67 passed, 0 failed ==   (includes 18 new --help / unknown-flag assertions, HOME isolated to a temp dir, nothing written)
test-gauntlet-remote-key.sh  == 7 passed, 0 failed ==    (empty ref exits 65 with no ssh call; placeholder exits 65; real ref reaches ssh)
run-all: all 32 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control
```
Command: git show <base>:install.sh > install.sh; bash tests/test-install-modules.sh   (then the same for run-remote.sh with test-gauntlet-remote-key.sh)
Exit: 1
Output:
  FAIL  --help prints usage
  FAIL  '--bogus' exits 64
  FAIL  'stray' writes nothing under HOME
  == 51 passed, 16 failed ==
  (run-remote.sh at base) FAIL  exits 65 / FAIL  ssh never called / FAIL  placeholder exits 65
  == 3 passed, 4 failed ==
Verdict: PASS
```
Both files were reverted to the committed fix after the control; `git status` was clean.

## Not proven
- `install.sh --help` placement relative to a literal `--with --help` value is not tested (any `--help` argument prints usage).
- The remote path past the key guard (docker, `op read` on the runner) was not run; ssh is a stub.
- Maintainer's own ref is not restored here: it belongs in the operator `~/.config/dwarves-kit/kit.toml` (outside this repo).
