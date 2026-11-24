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
