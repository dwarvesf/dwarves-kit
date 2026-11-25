# proof-capture

Makes one image or GIF file for visual proof, from a web page or a terminal tape. It reads its arguments, writes one file, and keeps no state. It works alone: copy this directory anywhere and run it. It needs no repo, no config file and no other kit file.

```
proof-capture run page <src> <out.png> [--width N] [--height N] [--wait MS] [--deadline S]
proof-capture run tape <file.tape> <out.gif> [--deadline S]
```

## Install

Copy the directory anywhere and call `bin/proof-capture`. Inside the dwarves-kit, the same tool is reachable as `$DWARVES_KIT/bin/proof-capture` (a one-line shim). That path works whether or not `proof_capture` is toggled on in `[modules]`; the toggle only decides whether `install.sh --with proof_capture` puts a `proof-capture` shim on your `PATH`. The kit also prints that path in the `capture:` line of `proof-gate.sh contract` when `[proof] visual` is on.

Bash 3.2 or newer and POSIX coreutils. No Node, no Python, no Playwright.

## Run it alone

```bash
cp -R proof-capture "$HOME/proof-capture-tool"
"$HOME/proof-capture-tool/bin/proof-capture" run page ./page.html ./shots/page.png --width 800 --height 500
"$HOME/proof-capture-tool/bin/proof-capture" run tape ./demo.tape ./shots/demo.gif
```

## IN

Arguments only. No stdin. No config file.

- `<src>`: a file path, or an `http://`, `https://` or `file://` URL. Any other scheme exits 64, and so does a path starting with `-`. A relative path becomes an absolute `file://` URL from the current directory, with `%`, space, `#` and `?` percent-encoded.
- `<file.tape>`: a file path, made absolute before use. A path starting with `-` exits 64.
- `--width N`: viewport width in px, 1 to 10000, default 1280. `--height N`: 1 to 10000, default 800.
- `--wait MS`: 1 to 120000. Lets the page run MS ms of virtual time before the shot (maps to `--virtual-time-budget`). Default none: the shot is of the first paint. `0` exits 64, because the browser writes no file at budget 0.
- `--deadline S`: 1 to 600 seconds to wait for a valid artifact. Default 45 for `page`, 120 for `tape`.
- `PROOF_CAPTURE_BROWSER`: path to a Chromium-family browser. A bare name (no slash) is looked up on `PATH`, and the file found is the file that runs. When set, it is used or the run fails; there is no fallback.
- `PROOF_CAPTURE_VHS`: path to `vhs`. Same rules.
- `PROOF_CAPTURE_DEADLINE`: seconds, same range as `--deadline`. The flag wins. A value out of range exits 64.
- `PROOF_CAPTURE_BROWSER_CANDIDATES`: colon-separated absolute paths or command names that replace the built-in discovery list. A test uses it to make "no browser" reproducible on a host that has one.
- Built-in discovery, when no env names a browser, first hit wins: `google-chrome`, `chromium`, `chromium-browser`, `microsoft-edge` on `PATH`; then the Google Chrome, Chromium and Microsoft Edge apps under `/Applications` on macOS. Brave is not listed: it wrote no file in 40 s on the build host. Name it in `PROOF_CAPTURE_BROWSER` if you want it.

Every dependency check runs before any external command, so the entry runs with an empty `PATH` when called as `bash bin/proof-capture`.

## OUT

- `<out>` is written only when valid. PNG for `page`: the 8-byte magic, the 12-byte IEND trailer (`0000000049454e44ae426082`), not empty. GIF for `tape`: starts `GIF8`, ends with the byte `3b`, not empty. A file only counts when its size is equal on two reads 0.3 s apart.
- A parent directory that does not exist is created. A failed run leaves any existing `<out>` untouched. The file lands by a copy into a hidden `.proof-capture.XXXXXX` file next to `<out>` and a rename. A signal that arrives after the rename cannot undo the write, so that run still ends with exit 0 and the new file.
- stdout, one line: `proof-capture: wrote <out> (<n> bytes)`.
- stderr: diagnostics, one line per fault. No sidecar file, no state, nothing under your home.
- While running: one private directory (mode 0700) under `$TMPDIR`, with the browser profile and the partial file. It is removed after a success, a failure, the deadline, and any signal the tool can catch (INT, TERM, HUP, QUIT, USR1, USR2, ALRM, PIPE). A KILL cannot be caught and leaves it (see Residuals).

The artifact is the whole API. A consumer reads the file; it never reads the script.

## EXIT

| Code | Meaning |
|---|---|
| 0 | artifact written and valid |
| 1 | capture failed: no valid artifact before the deadline, the browser or vhs exited without one (vhs: or exited non-zero), or the tool was interrupted by a signal it can catch |
| 64 | usage or bad input: unknown verb, missing argument, unknown flag, input file missing, bad scheme, a path starting with `-`, a number out of range, `<out>` is a directory, a symlink or ends with a slash, `<outdir>` is a symlink |
| 69 | a required dependency is missing: no browser for `page`, no vhs for `tape` |

## Exact messages

- no browser: `proof-capture: no Chromium-family browser found; install Chrome, Chromium or Edge, or set PROOF_CAPTURE_BROWSER=<path>`
- bad `PROOF_CAPTURE_BROWSER`: `proof-capture: PROOF_CAPTURE_BROWSER is not an executable file: <value>`
- bad `PROOF_CAPTURE_VHS`: `proof-capture: PROOF_CAPTURE_VHS is not an executable file: <value>`
- no vhs: `proof-capture: vhs not found; install it (brew install vhs) or set PROOF_CAPTURE_VHS=<path>`
- deadline: `proof-capture: no valid artifact within <S>s`
- signal: `proof-capture: interrupted`
- symlink: `proof-capture: refusing a symlink: <path>`
- the kit shim, module directory gone: `proof-capture: module files missing: <path>` (exit 69)

## Dependencies

| Verb | Needs | Notes |
|---|---|---|
| `run page` | a Chromium-family browser | runs headless on a throwaway profile that the tool creates and deletes, with a mock keychain and a basic password store so it never touches your real keychain. It never attaches to a running browser. |
| `run tape` | `vhs` | brings `ttyd` and `ffmpeg`. vhs may look for or fetch a browser of its own, and `ttyd` runs a local terminal server while it runs. That is vhs's own behavior, not controlled here. |

## Process safety

The tool starts the browser (or vhs) in its own process group, records the pid, and ends that group by pid: TERM, a 2 s wait, then KILL. It never kills by name or pattern and never lists the process table. A watchdog in its own group ends the browser group at the deadline plus 5 s, so a KILL sent to the tool does not leave a browser running for long. The watchdog starts right after the browser, so a KILL that lands in the two process starts between them (a fraction of a second) leaves a browser nothing will end. A catchable signal (INT, TERM, HUP, QUIT, USR1, USR2, ALRM, PIPE) reaps at once and exits 1, also when it lands between the launch and the moment the tool records the pid. A closed stderr cannot stop the cleanup: the tool ends the browser and removes its directory before it prints.

The checks that refuse a symlink or a directory as `<out>` or `<outdir>` run at the start, again before the temp file is made, and again before the rename. A second writer that swaps the path inside the last instants can still win, because a check and the write that follows it are two steps.

Residuals, stated so nobody is surprised:

- A KILL sent to the tool cannot be caught. The watchdog still ends the browser group, but the tool's work directory stays under `$TMPDIR`. Delete it by hand (it is named `proof-capture.XXXXXX`).
- A browser child that leaves the process group (calls `setsid`) is not reached. Nothing in the tool or its suite sees it: the opt-in real-browser case reads only the recorded group, so a child that left the group is invisible to it.

## Warnings

- A tape runs its commands as you. Never run a tape you did not read.
- `<src>` is the caller's choice. A task text can point the browser at an internal endpoint, and the capture will show it. Open every image and check it before it is committed.
- The capture does not resize. `proof-asset put` (in the kit) caps stills at 300 KB (it converts them) and GIFs at 2 MB, so an over-size GIF fails at `put` with exit 2, not at capture. Shorten the tape or lower its size.
- The tool does not compare the image width with `--width`; a browser may clamp its window. The opt-in real-browser case does.
- The tool checks `<out>` and the one directory it names, not the parts above them. On macOS `/tmp` is itself a symlink, so naming it as the output directory is refused, while a path below it is accepted. Pass a real directory, such as one under `$TMPDIR`.

## Tests

```bash
bash tests/test-proof-capture.sh
```

The suite uses a stub browser and a stub vhs, sources nothing from the kit, and starts no real browser. It ends with `N passed, M failed, K skipped`. `SUITE_CASES="1 5"` runs only those cases.

The real-browser case (11) is opt-in: `PROOF_CAPTURE_REAL=1 bash tests/test-proof-capture.sh`. It captures `examples/hello.html` at 800 by 500 with a real browser, reads the PNG header, and checks that nothing is left under the private temp dir and that the recorded process group is empty. By default it prints `SKIP` (counted, never a pass). Run it by hand before you change a browser flag, and after a major version bump of the browser that a proof names. Set `PROOF_CAPTURE_REAL_BROWSER=<path>` to pick the browser.

## Tested versions

Run by hand once on macOS (arm64) with bash 3.2: Microsoft Edge 157.0.4341.60 for `run page` (the real-browser case 11 and one capture of `examples/hello.html` at 800 by 500) and vhs 0.12.1 (with ttyd and ffmpeg from Homebrew) for `run tape` (one run of `examples/hello.tape`). The browser flags include `--use-mock-keychain --password-store=basic`, so the browser does not read or write the real keychain; the capture still wrote a valid image with them. Nothing is claimed for Chrome, Chromium or any Linux browser: none of them ran. Rerun the real-browser case (`PROOF_CAPTURE_REAL=1`) before you change a browser flag and after a major version bump of the browser a proof names.
