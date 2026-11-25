# Proof of done: proof-capture

The module makes one PNG from a page and one GIF from a terminal tape. This file holds the runs that show it works on a real browser and a real vhs, and one negative control. The stub-based suite is the repeatable check; the runs below were made by hand, once each, on one host, and say so. The kit-side proof is `docs/verification/visual-proof-module.md`.

## Host and tools

| Item | Value |
|---|---|
| OS | macOS, arm64 |
| Shell | bash 3.2 |
| Browser | Microsoft Edge 157.0.4341.60 |
| vhs | 0.12.1, with ttyd and ffmpeg from Homebrew |
| Not run | Chrome, Chromium, any Linux browser, `--wait` against a real page in this session |

## Real capture, page

```
Command: bin/proof-capture run page lib/proof-capture/examples/hello.html docs/verification/visual-proof-module/page.png --width 800 --height 500
Exit: 0
Output:
proof-capture: wrote docs/verification/visual-proof-module/page.png (13613 bytes)
Verdict: PASS
```

The PNG header reads 800 by 500. The browser started through a wrapper that recorded its pid and `exec`ed the browser, so the recorded pid was the process group id. After the run, `kill -0` on that group and on that pid both failed (gone), and the private temp directory was empty.

## Real capture, tape

```
Command: bin/proof-capture run tape lib/proof-capture/examples/hello.tape <scratch>/hello.gif
Exit: 0
Output:
proof-capture: wrote <scratch>/hello.gif (21150 bytes)
Verdict: PASS
```

The GIF is a 1200 by 600 GIF89a and is not committed. vhs started through the same kind of wrapper; after the run its recorded group and pid were gone (`ttyd` runs in that group). vhs's own shell left a 51 byte `.ses` file under the temp directory; the tool's `proof-capture.*` directory was removed.

Not run: the tape deadline path against real vhs (a tape with `Sleep 90s` and `--deadline 5`) and a `--wait` capture of a self-rewriting page. The stub suite covers the deadline for both lanes (cases 5 and 9); the `--wait` and 400 px claims rest on the sampling recorded in the spec's grounding (item 7), which was made before this build and not repeated here.

## The suite, with the real-browser case on

```
Command: PROOF_CAPTURE_REAL=1 bash lib/proof-capture/tests/test-proof-capture.sh
Exit: 0
Output (excerpt, cases 1 to 10 also PASS):
PASS 11 real browser
PASS 12 KILL to the tool, the watchdog ends the group
PASS 13 a second signal during the reap
PASS 14 QUIT, USR1, USR2, ALRM and PIPE to the tool
PASS 15 launch window, slow ps, no own group
PASS 16 output path rechecked before it is written
PASS 17 stderr is a closed pipe
PASS 18 the suite never signals a pid it cannot prove
18 passed, 0 failed, 0 skipped
Verdict: PASS
```

Case 11 captured `examples/hello.html` at 800 by 500 through the wrapper, read the PNG header, asserted an empty private temp directory and an empty recorded group (`pgrep -g`, read only). It reads only the recorded group: a child that left the group would not show.

## Negative control

The group signals changed to signal the recorded pid only, on a scratch copy of the module (the AC3 control):

```
Command: SUITE_CASES=4 bash <scratch copy>/tests/test-proof-capture.sh
Exit: 1 (RED expected)
Output:
FAIL 4 write-then-hang
  - write-then-hang (the helper too): a recorded stub pid is still alive
0 passed, 1 failed, 0 skipped
Verdict: RED as expected
```

Restoring the group signals returns case 4 to PASS. The controls for the review findings (launch window, watchdog start, output rechecks, closed stderr, the second signal, the suite's own pid proof) are in `docs/implementation-notes/visual-proof-module.md`.

## Reproduce

```
bash lib/proof-capture/tests/test-proof-capture.sh
PROOF_CAPTURE_REAL=1 bash lib/proof-capture/tests/test-proof-capture.sh
```
