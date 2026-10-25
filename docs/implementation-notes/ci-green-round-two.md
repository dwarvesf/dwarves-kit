# ci-green-round-two: implementation notes

Run 40224820774 on master c04aa302. Proof: `docs/verification/ci-green-round-two.md`.

## The runner changed under us

The job log says `Image: ubuntu-26.04`. `ubuntu-latest` is Ubuntu 26.04, not the 24.04 the first round modeled. 26.04 ships uutils (Rust) coreutils, so `tr`, `sort` and friends behave differently from GNU. Its `awk` on the runner is also multibyte-aware. An `ubuntu:26.04` container (git 2.53, uutils `tr` 0.10, `LANG=C.UTF-8`, gawk as `awk`) reproduces both ubuntu failures. The round-one container was 24.04 and passed them.

## Per suite

| Suite | Cause | Fix | Verified |
|---|---|---|---|
| test-tool-policy-guard row 21 | `bash -c kit_module_hooks \| tr ' ' '\n' \| grep -qxF X` under `set -o pipefail`. The module reader prints its list, then a trailing `echo` newline. `grep -q` exits on the first match; uutils `tr` writes eagerly, so the late newline hits a closed pipe and `tr` dies of SIGPIPE. GNU `tr` buffers to EOF and hid it. 151 of 200 runs fail on 26.04, 0 of 600 on 24.04. | The row captures the output and matches with `case`. A failure now prints the output it saw. | 26.04 container |
| test-lanes-data | The awk reader stripped a UTF-8 BOM with `substr(line, 1, 3) == "\357\273\277"`. A multibyte awk in a UTF-8 locale counts characters, so the 3-byte BOM is one character and was never stripped; the BOM-prefixed `.kit.toml` read as no record. mawk and the macOS awk count bytes, which hid it. | `index(line, BOM) == 1` and `substr(line, 1 + length(BOM))`, with the BOM passed in; both use the awk's own unit. | gawk on 24.04 and 26.04, gawk on macOS |
| macOS time ceilings (test-bin-forwarders, test-stats-no-persist) | Both are listed at the 60 s floor and take 2.4 s on the 14-core Mac the file was measured on. The runner's load average was 75 on 3 cores. `tests/lib/timeout.sh` made the ceilings real on macOS for the first time. | `RUN_ALL_TIMEOUT_FLOOR_SECS`: a minimum for every ceiling. The macOS job sets 300, ubuntu leaves it empty. | `test-run-all-timeout` case 7b |

## Why a floor, not the two other options

- `RUN_ALL_TIMEOUT_SECS=300` on the macOS job would cut every higher listed ceiling to 300: `test-lanes-data` from 692 s, `test-meta-docs-registry` from 682 s, `test-wrap-land` from 600 s. That hides nothing but can fail slow suites that are fine.
- Raising the two suites in the file needs a measured reason, and I can measure only the fast host. Most of the 260 suites sit at the 60 s floor, so any of them is one slow runner away from the same failure.
- The floor lifts only what is below 300, never lowers, and a real hang still ends at 300 s. Empty or junk falls back to the per-suite file; the explicit `RUN_ALL_TIMEOUT_SECS` still wins.

## Not fixed or not proven

- The macOS cause is inferred from the load line and the 2.4 s local time; I cannot reproduce a loaded GitHub Mac. If a suite still hits 300 s there, it is a hang, and the TIMED OUT line names it.
- test-tool-policy-guard row 7 failed once in about 220 runs on 26.04 (in a batch that ran right after `apt-get install gawk`); 200 direct runs of the hook and 16 suite runs afterwards were clean. Not explained.
- test-flick (`ps shows no token while curl is in flight`) failed in my container full runs on both images and passes alone and on the runner. A `ps` timing assertion on a 2-CPU container; not a runner failure, not touched.
- The 26.04 container does not have the runner's exact awk package; gawk reproduces the failure and the fix holds with mawk, gawk and the macOS awk.

## Rollback

Revert the commits on `fix/ci-green-round-two`. They touch two tests, `lib/gate/lane-data.sh`, `tests/run-all.sh` and `.github/workflows/test.yml`. Nothing is deployed.
