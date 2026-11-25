# Verification: visual-proof-module

Spec: `docs/specs/SPEC-427-visual-proof-module.md`. The `proof_capture` module (`lib/proof-capture/`, kit shim `bin/proof-capture`) makes one PNG from a page or one GIF from a terminal tape, so the `capture:` line that `proof-gate.sh contract` now prints names a command that works.

## The capture this change made

![The fixture page, captured headless by the tool](visual-proof-module/page.png)

Verified content (the image was opened and read, not only counted): a blue header band reading "Hello, proof", and below it one white card with the text "This page is the fixture for the capture tool." and a green line "Status: rendered". The PNG is 800 by 500 (read from the file header), 13613 bytes. Nothing on screen shows a path, a hostname, a token or a name. It was made by Microsoft Edge 157.0.4341.60 on macOS, through the kit shim. Not through `PROOF_CAPTURE_BROWSER`: `PROOF_CAPTURE_BROWSER_CANDIDATES` held one pid-recording wrapper that `exec`s the Edge app that built-in discovery lists, so the recorded group could be checked afterwards. The built-in discovery path itself was not run for this capture.

```
Command: bin/proof-capture run page lib/proof-capture/examples/hello.html docs/verification/visual-proof-module/page.png --width 800 --height 500
Exit: 0
Output:
proof-capture: wrote docs/verification/visual-proof-module/page.png (13613 bytes)
Verdict: PASS
```

Cleanup, read from the pid the wrapper recorded (the tool exposes no pid): the browser's process group and its pid were both gone after the run, and the private temp directory held nothing. No `pkill`, `pgrep -f` or process-table listing was used.

## Results

CI is down for this org, so these local runs are the only proof. `tests/run-all.sh` was not run in any form: the host is shared and overloaded, so the suites the spec lists for these tasks, plus the ones this change can reach, ran one after another, each in the foreground. The result line is the last line each printed.

| Suite | Result line |
|---|---|
| `bash lib/proof-capture/tests/test-proof-capture.sh` | `17 passed, 0 failed, 1 skipped` (case 11 is the opt-in real browser) |
| `PROOF_CAPTURE_REAL=1 bash lib/proof-capture/tests/test-proof-capture.sh` | `18 passed, 0 failed, 0 skipped` (Microsoft Edge 157.0.4341.60) |
| `bash tests/test-proof-capture-route.sh` (R1 runs the module suite again under `env -i`) | `ALL PASS (29/29)` |
| `bash tests/test-proof-contract-visual.sh` | `ALL PASS (15/15)` |
| `bash tests/test-proof-visual-gate.sh` (unedited) | `test-proof-visual-gate: all 33 passed` |
| `bash tests/test-modules-table.sh` | `== 66 passed, 0 failed ==` |
| `bash tests/test-bin-forwarders.sh` | `test-bin-forwarders: all 50 passed, 0 skipped` |
| `bash tests/test-install-clis.sh` | `test-install-clis: all 25 passed` |
| `bash tests/test-config-registry.sh` | `=== 60/60 passed ===` |
| `bash tests/test-install-modules.sh` | `== 67 passed, 0 failed ==` |
| `bash tests/test-anchor-module-gate.sh` | `Results: 39 passed, 0 failed` |
| `bash tests/test-operator-pin.sh` | `operator-pin: 4 passed, 0 failed` |
| `bash tests/test-kit-contract.sh` | `=== kit-contract: 25 passed, 0 failed ===` |
| `bash lib/gate/boundary-lint.sh` | `boundary-lint: PASS` |
| `bash tests/test-meta-docs-registry.sh` | `Passed: 121 / 121` |
| `bash tests/test-meta.sh` (all areas) | exit 0, the last area `Passed: 935 / 935` |

Known failure, not caused by this change: `bash tests/test-adopt.sh` ends `PASS=77 FAIL=1`. The failing line is `NOT ok - known list complete against git log (1 missing; run lib/adopt/known-hashes.sh)`: a merge commit that arrived with master is not in the adopt known-hash list. `lib/adopt*` is not edited here. The adopt cases that read the new module row (a fresh adopt leaves `proof_capture` off) pass.

Not run: `tests/test-wrap-land.sh` (red on master in its proof-asset round-trip section, owned elsewhere; this diff does not touch `bin/proof-asset`, `lib/proof/` or the land path) and `tests/run-all.sh`. Also not run: the capture of a self-rewriting page with `--wait 3000 --width 400`, and a real-vhs tape deadline check. The spec's grounding item 7 holds the earlier sampling of `--wait` and 400 px; it is not a result of this build.

Whole-change checks, each printed nothing (as they must):

```
Command: git diff --stat origin/master -- hooks/ship-gate.sh lib/classify lib/gate/proof-ledger.sh lib/proof bin/proof-asset
Exit: 0
Output: (empty)
Verdict: PASS

Command: git diff --name-only origin/master | grep -E '^lib/adopt'
Exit: 1
Output: (empty)
Verdict: PASS

Command: the tenant-word and host-path scan from the Verification block of the spec, over lib/proof-capture, this file and its image directory
Exit: 1
Output: (empty)
Verdict: PASS
```

```
Command: bash lib/gate/proof-ledger.sh images docs/verification/visual-proof-module.md .
Exit: 0
Output:
visual-proof-module/page.png	docs/verification/visual-proof-module/page.png
Verdict: PASS (13613 bytes, under 102400)
```

## NEGATIVE CONTROL

Each control was run on a scratch copy (module) or in place and restored (kit files): break the code, watch the named case fail, restore. The failing line is quoted. Full list with the review findings: `docs/implementation-notes/visual-proof-module.md`.

```
Command: SUITE_CASES=4 bash <module copy with the group signals changed to the recorded pid only>/tests/test-proof-capture.sh
Exit: 1 (RED expected)
Output:
FAIL 4 write-then-hang
  - write-then-hang (the helper too): a recorded stub pid is still alive
Verdict: RED as expected
```

| Break | Case | Failing line |
|---|---|---|
| no fallback to `$!` when a signal lands before the pid is recorded | suite 15 | `a signal between the launch and CPID: a recorded stub pid is still alive` |
| watchdog starts only after the slow `ps` | suite 15 | `KILL during a slow ps check: a recorded stub pid is still alive` |
| no recheck before the temp file | suite 16 | `outdir swapped: the temp file was made through the symlink` |
| no recheck before the rename | suite 16 | `out swapped: exit 0, wanted 1` |
| `fail` prints before it reaps, PIPE untrapped | suite 17 | `exit 141, wanted 1` and `the private TMPDIR is not empty` |
| trap list cut to INT TERM HUP | suite 14 | `never-write stub, QUIT: the tool did not exit after the signal` |
| the second signal not read by the TERM wait | suite 13 | `the tool did not leave the TERM wait at once after the second TERM (twice)` |
| the suite signals a pid with no proof | suite 18 | `kill_owned signalled a pid it had no proof for` |
| `capture:` line never printed | contract suite | `FAIL ui page: want a capture: line with run page, got []` |
| `capture:` echo moved outside the knob test | contract suite | `FAIL project visual=false: output drifted from master` |
| module guard removed from `_proof_visual_capture` | route suite | `FAIL R3b: shim without a module, yet a capture: line printed` |
| `--use-mock-keychain` and `--password-store=basic` removed | suite 3 | `argv lacks --use-mock-keychain` |

## Reproduce

```
bash lib/proof-capture/tests/test-proof-capture.sh
bash tests/test-proof-capture-route.sh
bash tests/test-proof-contract-visual.sh
bin/proof-capture run page lib/proof-capture/examples/hello.html /tmp/x/page.png --width 800 --height 500
```

The first three need no browser. The fourth needs one installed.
