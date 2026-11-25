# Implementation notes: visual proof capture module

For the builder of `docs/specs/SPEC-427-visual-proof-module.md`. These are warnings from the validation rounds that the build's own tests would catch, so they are not folded into the spec. Log the delta from the spec here as you build.

## Shell traps (bash 3.2, macOS)

- Percent-encoding a path for `file://` has no helper: encode `%` first, then space, `#`, `?`, in a plain parameter-expansion loop. Test a path with all four.
- An empty array under `set -u` errors in 3.2. Build the browser argv as a plain list or guard each expansion.
- `mktemp -d` on macOS needs the template form `"${TMPDIR:-/tmp}/proof-capture.XXXXXX"`; `mktemp` for the final copy needs a template inside `<outdir>`.
- `$TMPDIR` on macOS ends with a slash; build paths with one slash, or the `*/proof-capture.*` guard on the `rm -rf` fails to match.
- A background job under `set -m` prints a `Terminated` notice on `wait`. Put `wait` inside `{ wait "$pid"; } 2>/dev/null`.
- `wait` on a pid already reaped by a second reap returns 127; ignore it, never branch on it.
- The watchdog is `( sleep N; kill -KILL -- -"$cpid" ) </dev/null >/dev/null 2>&1 &` under `set -m`; without the redirections a caller that captures the tool's output waits for the watchdog to end.
- Always pass the browser an absolute `--screenshot` path and an absolute `--user-data-dir`.
- Sleeps in the suite stay under 30 s per command line (a repo hook refuses long sleeps typed into a shell tool). The stubs use `sleep 20`.

## Tests

- No case may use `pkill`, `killall` or `pgrep -f`. Stubs record their pids in `$STUB_PIDS`; the assertions and the EXIT trap use `kill -0` and `kill` on those pids only. The opt-in case uses `pgrep -g <recorded pid>`.
- `bin/test-affected.timeouts`: the module suite waits on deadlines (2 s cases, a 12 s window); add a row if the default is too tight on a loaded host.
- The route suite copies the whole kit tree for AC10c; copy once and reuse it for both deleted-tool variants.
- The no-own-group branch cannot be reached with a stub (job control is on); it has no test. Keep it three lines.
- `tests/test-kit-contract.sh` is red from T7 to T12 by design (C3 wants the module's proof-of-done). Run it first in T13.

## Docs

- `lib/gate/README.md` (`gate proof` row) must mention the `capture:` line; `tests/test-meta-docs-registry.sh` checks the row text exists, not its wording.
- FEATURES.md is generated: `bash lib/registry/feature-registry.sh generate`, then commit the result.
- README names the tested browser and vhs versions only after T12 has run them; do not write them from memory.
- `docs/figures/*.png` already holds two files over 100 KB; the 100 KB bound for the fixture is the spec's own, not a repo rule.

## Build deltas from the spec (T1 to T5)

- Usage messages are free text, one distinct line per refusal, so a suite row can assert the message and not only exit 64 (an exit code alone proves nothing while the launch is unbuilt). A positional that starts with `-` reaches the flag branch and is refused with "unknown flag, or a path starting with '-'".
- `PROOF_CAPTURE_DEADLINE` is validated whenever it is set and non-empty, even when `--deadline` is given (the flag still wins for the value). An out-of-range env value is an error either way.
- `PROOF_CAPTURE_BROWSER_CANDIDATES` set to an empty string counts as unset (built-in discovery runs). Only a non-empty value replaces the list.
- A scheme-looking input (`word:` with only letters, digits, `+`, `.`, `-` before the colon) that is not http, https or file exits 64 even if a file of that name exists; use `./name:x` for such a file.
- An `<outdir>` that exists and is not a directory exits 64 (cheap, same class as a symlink).
- The launch lines are wrapped in `{ ...; } 2>/dev/null`: bash prints `child setpgid ... Operation not permitted` when a fast child has already exec'd, and that notice would reach the caller's stderr.
- The suite starts the tool in the background under job control (`set -m`) so INT reaches it; a non-interactive bash starts plain `cmd &` jobs with INT ignored. `tests/run-all.sh` was not read for how it starts a suite; the suite itself does not depend on its own INT disposition.
- The suite's INT and TERM rows need a ready marker from the stub before the signal is sent, so the signal cannot land before launch.
- T2 negative controls, each run on a copy of the module in scratch, with the failing line: removing the scheme refusal fails case 8 (`javascript scheme: stderr lacks: refusing the scheme 'javascript:'`); dropping `--headless=new` fails case 3 (`argv lacks --headless=new`); dropping the `%` encoding fails case 2 (`special path: not percent-encoded`); dropping the IEND trailer check fails case 1 (`slow-write is byte for byte: output differs from the expected bytes`); removing the symlink refusal fails case 8 (`output is a symlink: stderr lacks: refusing a symlink`); making the exit-without-file path accept fails case 1 (`exit-no-file: stderr lacks: exited without a valid artifact`); removing the deadline test fails case 5 (the stub's own 20 s exit surfaces as a different stderr line on the guard). Carry the lines the proof file needs to T12.
- The suite has a `SUITE_CASES="1 5"` selector (an aid, unset runs everything) so a control or a debug run does not pay for the whole suite on a loaded host.
- The PNG the stub writes has the real magic, IHDR and IEND trailer; its IDAT checksum is not real, because the tool checks only magic and trailer.
- A `${s//$q/...}` replace with an unquoted `?` is a glob in bash 3.2 and matched every character; the encoder quotes every pattern variable.
- Output files are made by `mktemp` and keep mode 0600 (the spec does not name a mode); not changed.
- T3 timing deltas, all so the suite does not flake on a loaded host: the watchdog, the TERM wait (an iteration cap of 20 plus a 3 s `SECONDS` cap) and the poll use `SECONDS` (wall clock) and not a loop count of `sleep 1`, because a spawn takes long under load. The suite's "pids gone" bounds are 17 s from the start (spec: 6 s for case 13, 10 s for case 4, 12 s for case 12), kept under the stub's own 20 s sleep so a late finish cannot pass for the wrong reason; a run that finishes after 19 s fails as "too late to prove anything".
- Case 13 sends its TERM 3 s after the start, with a 2 s deadline. The integer `SECONDS` clocks make the landing point inside the 2 s TERM wait approximate, so a run may take the first-signal path instead; both paths must pass. The named mutation (a second signal during a reap exits at once and abandons the reap) does fail the case.
- Stubs end in `exec sleep 20` and the helper in `( trap '' TERM; exec sleep 20 )`, so every process they leave is a recorded pid, and a TERM-ignoring stub passes its ignore down to its sleep.
- Case 12 (a KILL to the tool) leaves the tool's work dir under the private TMPDIR, as the spec's residual says; the case removes it so later cases start clean.
- The tool is started under job control in every case so INT reaches it. `tests/run-all.sh` was not run (barred in this step); the next builder should run the module suite once under it, because a runner that backgrounds suites without job control cannot affect the suite's own children, which it creates itself.
- T3 negative controls (each on a copy in scratch; failing line shown). Group signals reduced to the recorded pid: case 4 `write-then-hang (the helper too): a recorded stub pid is still alive`. The `trap on_signal INT TERM HUP` line deleted: case 6 `term-ignore stub, HUP: exit 129, wanted 1` and `a recorded stub pid is still alive`. The watchdog start disabled: case 12 `KILL to the tool: a recorded stub pid is still alive`. The KILL step removed: cases 5, 6 and 13 fail (`term-ignore (KILL escalation): finished too late to prove anything`, `second TERM during the reap: a recorded stub pid is still alive`). A signal during a reap made to exit at once: case 13 `second TERM: the private TMPDIR is not empty`. The proof file needs these lines (T12).
- T4: `examples/hello.tape` was parsed with `vhs validate` (parse only, nothing started) and passes; it was never run. T12/T13 must run it through the tool once. Its first line is `Env LANG "en_US.UTF-8"` per the GUIDE note. It declares no `Output`, so vhs writes only the partial the tool names.
- T4: the stub vhs has an extra `exit-nonzero` mode (a valid GIF and exit 3) to prove "vhs exits 0" is part of the success rule; the spec lists `exit-no-file` and `bad-file` only. Messages for a vhs failure are the tool's own: `vhs exited with status N` and `vhs exited without a valid artifact`.
- T4 controls: GIF magic and trailer checks replaced by `true`: case 9 `bad-file: exit 0, wanted 1`; vhs exit-status test removed: case 9 `non-zero exit with a valid file: exit 0, wanted 1`; `pkill -f chrome` planted in a copy of the tool: case 10 `the module executable holds a forbidden token`. Removing only the GIF magic check changes nothing, because the trailer check also rejects the text file.
- The suite wall time is about 45 to 55 s at a load average near 60.
- T5: the README carries a "Tested versions" section that says "Not recorded yet"; T13 must replace it with the real browser and vhs versions after the hand run (do not write them from memory). It also documents `PROOF_CAPTURE_REAL_BROWSER` (the real-browser case's own override, not read by the tool) and `SUITE_CASES`.
- T5: the standalone check from the spec ran green on a copy under `env -i HOME=... PATH=/usr/bin:/bin:/usr/sbin /bin/bash` (12 passed, 0 failed, 1 skipped); the suite then leaves nothing under `/tmp`. The in-kit `tests/test-kit-contract.sh` and the route suite are not run in this step.
