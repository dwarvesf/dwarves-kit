# ci-green-master: implementation notes

Goal: the `test` workflow green on master. Baseline run 40213719424 (head 2892b84c, before the layout refactor) failed 13 suites on ubuntu-latest and 5 on macos-latest. Each row below is one suite: cause, fix, evidence. Proof: `docs/verification/ci-green-master.md`.

## Method

- macOS: `bash tests/<suite>.sh` in this worktree.
- Ubuntu: a container that mirrors the runner: `ubuntu:24.04`, a non-root `runner` user (uid 1001), git from the git-core PPA (the runner ships a current git; the distro 2.43 breaks `git worktree repair`), `jq`, `ripgrep`, `shellcheck`, `lsof`, `procps`, `locales` with `en_US.UTF-8`, `uv`, `CI=true`, `docker run --init` (so suites do not run as pgid 1). The repo is a `git clone` of this worktree with `master` and `origin/master` set to the base commit, copied into the container per run. The mount must sit under `$HOME`: colima shares only that.
- Stock macOS has no `timeout`: a PATH built from symlinks to every tool on the real PATH except `timeout` and `gtimeout` reproduces the runner.

## Per suite

| Suite | Cause | Fix | Verified |
|---|---|---|---|
| test-board-health, test-board-hermes, test-board-sweep-post, test-staging-one-writer | File mode read as `stat -f %Lp \|\| stat -c %a`. On GNU `stat -f` is a filesystem query: it exits 0 and prints several lines, so the fallback never ran. | GNU form first: `stat -c %a \|\| stat -f %Lp` (the order the product code already uses). | container + mac |
| test-board-brief | Expected day built with `date -r <epoch>`. On GNU `date -r` takes a file. | `epoch_day` helper: `date -r`, else `date -d @`. Local day, as the product computes it. | container + mac |
| test-hook-util | The GNU-style `stat` double ran `exec a \|\| exec b`; `exec` replaces the shell, so `b` never ran. | Try the GNU form, exit 0 on success, else exec the BSD form. | container + mac |
| test-hook-util, test-intake-sweep-parity (product) | `hu_run_capture` with a zero or negative timeout started the command and raced a kill against it. A fast command won 36 runs in 40 on Linux (1 in 40 on this Mac). Two parity cases expect "timed out, no items". | Zero timeout answers without the race: empty output, the `.timedout` mark, status 137. New test: 20 runs, all must time out. | container (160/160) + mac |
| test-flick | The denial-reason cases set `word_gate=on` with no `dict_file`, so they read `/usr/share/dict/words`, absent on the runner. | Point those cases at the fixture dictionary, like the rest of the word-gate section. | container + mac |
| test-harvest-sweep (test) | `plutil` and `PlistBuddy` exist only on macOS. | `plist_lint` and `plist_get`: native tool when present, else python3 `plistlib`. | container + mac |
| test-harvest-sweep (product) | The launcher read the report mtime with `stat -f %m`. On Linux that is garbage, so every bridge call got `-` instead of the report path. | `stat -c %Y \|\| stat -f %m`, digits checked. | container + mac |
| test-harvest-sweep (product) | The plist template held `--apply` inside an XML comment. A double hyphen is illegal there; `plutil` tolerates it, `plistlib` does not. | Reword the comment. | container + mac |
| test-wrap-apply | The no-lsof case removed lsof's directory from PATH. On a merged-usr host lsof sits in `/usr/bin` beside git, so the run died on a missing git. | Build a directory of symlinks to every tool except lsof and use only that. | container + mac |
| test-no-personal-paths | A quoted git warning carried the home path in `front-door-rewrite.md:91` and three lines of `repo-layout.md`. | `/Users/<name>/.git_template` became `~/.git_template`. Nothing else in those records changed. | container + mac |
| test-test-affected, -cache, -parallel | macos-latest has no `timeout`. `bin/test-affected` and `tests/run-all.sh` then ran every suite with no ceiling and never printed TIMEOUT. | `tests/lib/timeout.sh`: `kit_timeout` uses `timeout`, `gtimeout`, else a perl fork with its own process group, TERM at the limit, KILL 5 s later, GNU exit codes. Both runners source it. The three suites and five `test-run-all-*` suites copy it into their fixtures. | mac with no `timeout` on PATH |
| test-proof-negctl | Cases 31 and 32 slept a fixed 1.0 s, then sent SIGINT, assuming negctl was inside the restore's `git checkout`. | The git shim writes a marker on entering `checkout`; the test waits for it (20 s ceiling) before the interrupt. | mac, also under 30 busy loops. Root cause unconfirmed, see below. |

## Full container run

`CI=true bash tests/run-all.sh --all` in the container at the fix commits: 260 suites ok or skipped for missing agent CLIs, one red (test-board-work, the image gap below). The baseline run listed 13 red ubuntu suites.

## Not reproduced

- test-lanes-data and test-tool-policy-guard failed on ubuntu in the baseline run. They pass alone at that commit and at current master in the container, and pass in a full CI-like `run-all.sh --all`. Both read a throwaway repo or the module table, which another suite does not touch. I could not tie them to a cause. They are the likeliest suites to be flaky or order-dependent. Dispatch once and look.
- test-proof-negctl on macOS: I never reproduced the failure on a Mac (the old file passes under 30 busy loops). The timing guess is the only fixed-delay assumption in the two failing cases and the symptom (empty output, clean tree) matches an early interrupt. The fix removes that assumption; it is not proven to be the CI cause.
- test-proof-negctl case 42 failed once in four macOS runs, only while 33 other suites ran beside it (`run-all.sh --changed`). Bash printed `child setpgid (...): Operation not permitted` into the output the case compares byte for byte. That is bash's own job-control race in `lib/gate/negctl.sh --parallel` (`set -m` workers that exit fast). Thirty busy loops did not reproduce it, so I did not touch negctl.sh. If it recurs, redirect stderr of the worker launch loop. The suite passed alone on the same tree.
- test-board-work fails in my container and passes in the baseline run, so the gap is in my image, not the kit. Not investigated further.

## Rollback

Revert the commits on `fix/ci-green-master`. Nothing is deployed and no state is written outside the tree.
