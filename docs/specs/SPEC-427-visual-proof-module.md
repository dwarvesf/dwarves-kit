# Spec: visual proof capture as a standalone kit module

Generated: 2026-11-25
Status: VALIDATED
Lane: full (the diff floor: `lib/gate/proof-gate.sh` and `lib/config/modules.tsv` are enforcement-surface paths; `lane-classify.sh classify` on the task text alone says `normal`, and with `--files` it says `full`)
Depth: blind-spot (failure: the browser flag set was run on Edge and one other Chromium browser only, so Chrome, Chromium and any Linux browser, which the discovery list names, may hang or write nothing in a way this host could not show)
Type: spec-feature
Board: ID-395
File: `docs/specs/SPEC-427-visual-proof-module.md`
References: `docs/briefs/DECISION-BRIEF-visual-proof-module.md` (the why, the rejected options, the after-the-move table); `lib/proof/asset.sh` and `bin/proof-asset` (the consumer of the artifact, not edited); `lib/gate/proof-gate.sh` (`_proof_visual_row`, `proof_contract`); `lib/skill-curator/` (the one module dir with the full shape: `bin/`, `README.md`, `SPEC.md`, `docs/proof-of-done.md`, `tests/`); `tests/test-proof-visual-gate.sh` (the temp-repo gate fixture to copy); `docs/reference/kit-contract.md` (C1 to C10, and the closed verb list from SPEC-200 I4); `docs/decisions/0041-standalone-doctrine.md` (ADR-0041, the standalone doctrine; this module is its first extraction).

## Problem

The kit can ask for visual proof and can store it, but cannot make it. With `[proof] visual` on, `proof-gate.sh contract` names the artifact a task owes ("before + after screenshots, desktop and 400px") and `/kit:verify` Step 7b says "capture", then hands the image to `bin/proof-asset put`. Nothing in the kit produces the image. `docs/verification/README.md` line 96 says so: until a producer lands, a hand-recorded capture satisfies the contract. The only capture engine is outside the kit: a prose skill and a 69-line Node walker in the operator's private setup, bound to a personal browser.

Target (the pack's one line): proof-capture exists as a kit module; it is standalone-capable; the proof contract routes visual work to it; a fixture PR shows a screenshot or GIF in its proof.

Already shipped, not rebuilt: the knob, the gate's image rules, `bin/proof-asset`, the `wrap land` flush, the runs dashboard. The gap is the producer and its route. See the brief for the table.

## Terms

- proof-capture: the module this spec adds, `lib/proof-capture/`. A producer of one image or GIF file. It stores nothing and reads no kit config.
- artifact: the file `run page` or `run tape` writes. Its schema is its magic bytes, and it is the module's whole API.
- shim: `bin/proof-capture`, one `exec` and one missing-file guard, no other logic.
- own group: the process group the tool creates for the child it starts (bash job control makes the group id equal to the child's pid). The tool signals that group by the pid it recorded and nothing else.
- watchdog: a second recorded process the tool starts, in its own group, that ends the child's group at the deadline plus 5 s even if the tool itself was killed.

## Solution

### Approaches considered

| Approach | Verdict |
|---|---|
| A. A bash tool in its own directory: Chrome's own `--headless=new --screenshot` for pages, `vhs` for terminal GIFs; a shim, one registry row, one added contract line | chosen |
| B. Port the Node walker and Playwright | rejected: a Node and Playwright dependency for 69 lines, and its default browser is personal |
| C. A Node CDP driver like `lib/system-design/shots.mjs` | rejected: a second headless driver and Node in `lib/` for no gain over the browser's own flag |
| D. Add a `capture` verb to `bin/proof-asset` | rejected: `proof-asset` sources `kit-config.sh` and needs a git repo; the capture must run with neither |

### Chosen approach + why

A. One dependency per verb, readable in 30 seconds, copyable out of the kit. No new language, so no PHILOSOPHY justification is owed (no Node, Python or Playwright). The cost is real: Chrome's `--screenshot` cannot click, so a scripted multi-step flow is not in v1.

### Extensibility & boundaries

- Load-bearing dimension: the number of capture kinds. A new kind is a new `run <kind>` branch plus one row in the routing case in `proof-gate.sh`. A kind that needs interaction (a page flow ending in a GIF) is `run flow`, named and not built.
- Boundary: the module reads argv and writes one file. It never reads `kit.toml`, never sources a kit script, never writes under the repo except the `<out>` the caller names. Consumers (`proof-asset`, the gate, `/kit:verify`) read the file, never the script.

## Picture

Before: the contract names an artifact, and a person makes it by hand.

```
 task text --> proof-gate.sh contract --> "visual: before + after screenshots ..."   (an artifact name, no way to make it)

 the agent records an image by hand, any tool --> bin/proof-asset put <slug> <file> --> assets.json --> gate image rule
```

After: the contract also names the producer, and the producer is a directory that works alone.

```
   kit side                                                   | module (a copyable directory)
                                                              |
 task text --> proof-gate.sh contract                         |
                |-- visual:  <artifact>   (text unchanged)    |
                |-- capture: $DWARVES_KIT/bin/proof-capture run page|tape
                |     only when: knob on AND bin/proof-capture AND lib/proof-capture/bin/proof-capture
                |     are executable AND the row has a verb   |
                v                                             |
 /kit:verify Step 7b --> bin/proof-capture (shim) ------------+--> lib/proof-capture/bin/proof-capture
                                                              |      run page: browser --headless=new --screenshot
                                                              |                (own profile, own group, deadline, watchdog, reap, rename on success)
                                                              |      run tape: vhs -o <out.gif> <file.tape>
                                                              |                (own group, deadline, watchdog, reap, rename on success)
        out.png | out.gif  <-----------------------------------+------ the artifact (the only interface)
                |
                v
 bin/proof-asset put <slug> <file> --> assets.json --> proof-ledger.sh check (unchanged)
```

One-time wiring, not drawn: a `proof_capture` row in `lib/config/modules.tsv`, its key in `kit.toml`, rows in `lib/config/module-registry.md`, and the `bin/` census entry.

The module has no arrow into the kit. Delete the left half and the tool still runs. Delete the right half (and leave the shim and the table row) and the left half loses one line of output, and the shim says the module is missing.

## Design

Design-bearing: a new module, a process lifecycle that must not leak, and an interface other code reads. Approaches and the chosen one are in `## Solution`. ADR: the standalone doctrine, ADR-0041 (`docs/decisions/0041-standalone-doctrine.md`); this module is its pilot and records no ADR of its own.

The `run page` lifecycle (the part a builder gets wrong). `$$` is the tool, CPID the child it starts, WDPID its watchdog:

```
 run <page|tape> ... [flags]     one shared launch, poll and reap function serves both lanes (the child is the browser or vhs)
    |                            $$ = the tool, CPID = the child it starts, WDPID = its watchdog
    +-- bad verb, flag or number, missing input, a <file.tape> or <src> path starting with "-", bad scheme,
    |   <out> a directory or a symlink, <outdir> a symlink ---------------------------------> exit 64
    +-- no browser / no vhs (or the env path not executable) ---------------------------------> exit 69
    |
    work=$(mktemp -d "${TMPDIR:-/tmp}/proof-capture.XXXXXX")   mode 0700; profile=<work>/profile; partial=<work>/partial.png (or .gif)
    trap: INT, TERM, HUP, QUIT, USR1, USR2, ALRM, PIPE -> if no reap is running: reap at once in interrupt mode, "proof-capture: interrupted", exit 1
                            if a reap is running: only set INTR=1 (the running reap sees it and goes straight to KILL)
          EXIT -> reap if none ran
    set -m ; LAUNCHED=1 ; start the child in the BACKGROUND, stdin /dev/null, stdout and stderr to /dev/null ; CPID=$!
           ; start the watchdog at once, same redirections ; WDPID=$! ; set +m      (a reap that finds CPID empty and LAUNCHED set uses $!)
        watchdog: ( n=0 ; while kill -0 -- -CPID and n < deadline + 5 : sleep 1, n++ ; then, if the group still exists, kill -KILL -- -CPID )
        page flags: --headless=new --disable-gpu --no-first-run --disable-sync --disable-extensions --hide-scrollbars
        --use-mock-keychain --password-store=basic --user-data-dir=<profile> --window-size=<w>,<h> [--virtual-time-budget=<ms>] --screenshot=<partial> <url>
        tape: vhs -o <partial> <absolute tape path>
    check: ps -o pgid= -p CPID prints CPID -> ok ; prints a different id -> reap the one pid, exit 1 ("cannot isolate the browser process group") ;
           prints nothing (the child already exited, a fast stub) -> not a fault, go to the file check
    poll every 0.2 s until the deadline (default 45 s page, 120 s tape):
        partial is valid (page: PNG magic, IEND trailer, size > 0; tape: vhs exited 0 and GIF magic, trailer, size > 0)
            and its size is equal on two reads 0.3 s apart ----------------------------------------------> done
        CPID gone: look at the partial once more ; still not valid ---------------------------------------> fail
    done: recheck <out> and <outdir> (symlink, directory) ; copy partial to <outdir>/.proof-capture.XXXXXX (mktemp, exclusive create,
          name kept in FINAL_TMP) ; recheck again ; mv it onto <out> (mv -fh on macOS and the BSDs, mv -fT elsewhere) ; WROTE=1 ;
          THEN reap (the copy comes first: the reap removes the work dir) ; print ; exit 0
    fail: reap first, then one stderr line (a closed stderr cannot stop the cleanup) ; exit 1      (an existing <out> is left untouched)
    reap(): reaping=1, CPID and WDPID kept in saved variables until KILL has been sent
        deadline, fail, done:  kill -TERM -- -CPID ; wait up to 2 s for the group to empty (kill -0 -- -CPID), looping every 0.1 s ;
                               leave the wait early to KILL when INTR=1 or the 2 s are used
        interrupt:             skip the TERM wait
        kill -KILL -- -CPID (if the group still exists) ; kill -KILL -- -WDPID ; wait CPID and WDPID (stderr silenced) ;
        remove FINAL_TMP if set ; remove <work> ; clear the saved pids ; reaping=0
```

Rules for the reap, each one a blocking review point:

- The only signals the tool sends are to the group of a pid it recorded (CPID, WDPID). It never signals by name or pattern: the executable holds no `pkill`, `killall` or `pgrep`, and no process-table listing (`ps -A` took over 20 s on a loaded host, Grounding 10, so a reap built on it is not bounded).
- A group kill on CPID needs a numeric pid greater than 1 and the group check above. Without both, nothing is group-signalled.
- KILL is not optional: TERM alone left browser helpers running (Grounding 11), and a TERM-ignoring child would otherwise outlive the deadline. A suite stub that ignores TERM proves it (cases 5, 6 and 13).
- One reap runs at a time. `reaping` and the saved pids stay set until KILL has been sent, so a second signal can neither abandon the reap nor start a second one: while a reap runs the trap only sets `INTR=1`, and the reap's wait loop reads it and goes straight to KILL, then kills the watchdog and removes the work dir.
- The watchdog is the answer to a KILL sent to the tool, which cannot be caught: it is its own group, so it survives and ends the browser group at deadline plus 5 s. It polls `kill -0 -- -CPID` once a second and exits as soon as the group is gone, so it never signals a group id that was freed and recycled: a pid is not reused while a process group with that id exists, and the watchdog acts only while it has just seen the group exist. The tool starts it right after the child, before the group check, so the window with no watchdog is the two process starts between the child and the watchdog (a KILL there leaves a browser that never exits; stated in the README, not closed). A numeric check (`is_pid`) guards the start; the group check of the previous rule is made after it, and a failed group check reaps the child and the watchdog together. The watchdog itself acts only on a group it has just seen exist. Its stdout and stderr go to `/dev/null`, so a caller capturing the tool's output never waits on it. A normal exit kills it by WDPID.
- The browser never writes beside `<out>`: the partial lives in the private work dir. Only after a valid artifact does the tool make one exclusive `mktemp` file in `<outdir>`, copy into it and rename it onto `<out>`; the signal trap and the reap remove that file if it is still there. A planted symlink at a guessable name therefore has nothing to hit, and `<out>` or `<outdir>` being a symlink is refused (exit 64 at the start; exit 1 with the same message when it changes during the run). The check repeats before the temp file is made and before the rename, and the rename does not follow a symlink (`mv -fh`, or `-fT`). It checks `<out>` and the one directory it names, not the parts above; a second writer inside the last instants can still win, because a check and the write after it are two steps. On macOS `/tmp` is itself a symlink, so a caller names a directory under `$TMPDIR` or a real directory.
- The tool never attaches to a running browser and never passes a profile it did not create: `--user-data-dir` is always the fresh `<work>/profile`.
- `<work>` is removed with `rm -rf` only when it was created by this run's `mktemp -d` and its name matches `*/proof-capture.*`.

Success is the file on disk, never the browser's exit: two browsers probed on this host write the PNG in about 2 s and then never exit. A valid PNG has the 8-byte magic, ends with the 12-byte IEND chunk (`0000000049454E44AE426082`) and is not empty; a valid GIF starts `GIF8`, ends with the byte `3B` and is not empty. The size-twice rule and the trailer together reject a torn write.

`run tape` is the same function with `vhs` in place of the browser, so the deadline, interrupt and KILL cases cover it too: vhs writes `-o <work>/partial.gif` (the tape path is made absolute first; a path starting with `-` exits 64). Success is vhs exiting 0 (read with `wait` once CPID is gone) and a valid, size-stable GIF; vhs exiting non-zero or without a valid file is a failure. At the deadline, on a signal and after success the same own-group reap runs. vhs starts `ttyd` and a browser of its own; sampled on this host (Grounding 8), TERM ended `ttyd` but not vhs itself within 6 s, and KILL ended vhs with no `ttyd` and no headless browser left. The group reap covers vhs and what it started that stayed in the group; what vhs does on its own (it may look for or fetch a browser, `ttyd` runs a local terminal server while it runs (by design; its port was not sampled here), and a tape runs arbitrary commands as the user) is vhs's behavior, and the README and the verify step say so.

Prior art for the group pattern in this repo: `bounded_out` in `lib/decide/flick.sh` (lines 390 to 436) starts its child under `set -m`, signals `-<pid>` with TERM then KILL, and carries the same note that a descendant that leaves the group survives. This module adds the file-based success test and the watchdog.

### Module rules (ADR-0041, rule 3), each with where it is met and what checks it

| ADR item | Met by | Check |
|---|---|---|
| 1. Contract block: IN, OUT, EXIT in the module README | README has the headings `## IN`, `## OUT`, `## EXIT`, each holding its part of the block in `### Interfaces` | T5: `grep -c '^## IN$'`, `'^## OUT$'`, `'^## EXIT$'` each print 1 |
| 2. The artifact schema is the API; no file outside the module sources or imports a path inside it | magic bytes and trailer stated under OUT; consumers read the file. Deviation: the artifact is an image, not a `cat`-able text file (DEC-K) | AC8 (b): the no-inbound-source grep |
| 3. Thin adapter: one shim and one table row, no argument logic | `bin/proof-capture` (one `exec`, one missing-file guard) and the `proof_capture` row | AC12: the shim lint |
| 4. The delete test, both ways | kit deleted: the module dir runs alone. Tool deleted, shim and row left: the kit runs and reports the capability missing. Deviation: the kit contract suite goes red by design (DEC-K) | AC8 (a) and AC10 |
| 5. Own docs: install path and one standalone invocation with no kit file | README, per `### Module docs` | T5 check on the README headings and the run-it-alone block |

### Boundaries & failure modes

Out of bounds: kit config, git, the live desktop, any network call the tool makes itself (the browser may load the URL the caller gave). See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

This is the contract block `lib/proof-capture/README.md` carries, one part under each of its `## IN`, `## OUT`, `## EXIT` headings. It is the module's API; a consumer reads the artifact, never the script.

```
proof-capture run page <src> <out.png> [--width N] [--height N] [--wait MS] [--deadline S]
proof-capture run tape <file.tape> <out.gif> [--deadline S]

IN
  argv only. No stdin. No config file.
  <src>        a file path, or an http://, https:// or file:// URL. Any other scheme exits 64, and so does a path starting with "-".
  <file.tape>  a file path, made absolute before use; a path starting with "-" exits 64.
  --width N    viewport width in px, 1 to 10000, default 1280.   --height N   1 to 10000, default 800.
  --wait MS    1 to 120000: let the page run MS ms of virtual time before the shot (maps to
               --virtual-time-budget); default none. 0 exits 64, because the browser writes no file at budget 0.
  --deadline S 1 to 600, seconds to wait for a valid artifact; default 45 for page, 120 for tape.
  env PROOF_CAPTURE_BROWSER  path to a Chromium-family browser; set means use it or fail, never fall back.
  env PROOF_CAPTURE_VHS      path to vhs; same rule.
  env PROOF_CAPTURE_DEADLINE seconds, same range as --deadline; the flag wins; out of range exits 64.
  env PROOF_CAPTURE_BROWSER_CANDIDATES  colon-separated absolute paths or command names that REPLACE the built-in
               discovery list (the seam a test uses to make "no browser" reproducible on a host that has one).
  Built-in discovery when no env names a browser, first hit wins: google-chrome, chromium, chromium-browser,
  microsoft-edge on PATH; then the Google Chrome, Chromium and Microsoft Edge app paths on macOS. Brave is not
  listed (see Grounding). Every dependency check runs before any external command, so a test can run the entry
  with an empty PATH (the test calls it as `"$BASH" <entry>`).

OUT
  <out> is written only when valid: PNG (magic, IEND trailer, size > 0) for page, GIF ("GIF8", trailer 3B, size > 0) for tape.
  A parent directory that does not exist is created. A failed run leaves any existing <out> untouched.
  stdout, one line:  proof-capture: wrote <out> (<n> bytes)
  stderr: diagnostics, one line per fault. No sidecar file, no state, nothing under ~/.
  While running: one private 0700 directory under $TMPDIR (removed on every exit path a catchable signal can reach; a KILL leaves it). Next to <out>,
  a hidden .proof-capture.XXXXXX file exists only for the final copy and rename.

EXIT
  0   artifact written and valid
  1   capture failed: no valid artifact before the deadline, the browser or vhs exited without one (vhs: or
      exited non-zero), or the tool was interrupted (INT, TERM, HUP, QUIT, USR1, USR2, ALRM or PIPE)
  64  usage or bad input: unknown verb, missing argument, unknown flag, input file missing, bad scheme, a path starting with "-",
      a number outside its range, <out> is a directory or a symlink, <outdir> is a symlink
  69  a required dependency is missing: no browser for page, no vhs for tape
```

Exact one-line messages (the suite greps them):

- no browser: `proof-capture: no Chromium-family browser found; install Chrome, Chromium or Edge, or set PROOF_CAPTURE_BROWSER=<path>`
- bad `PROOF_CAPTURE_BROWSER`: `proof-capture: PROOF_CAPTURE_BROWSER is not an executable file: <value>`
- bad `PROOF_CAPTURE_VHS`: `proof-capture: PROOF_CAPTURE_VHS is not an executable file: <value>`
- no vhs: `proof-capture: vhs not found; install it (brew install vhs) or set PROOF_CAPTURE_VHS=<path>`
- deadline: `proof-capture: no valid artifact within <S>s`
- signal: `proof-capture: interrupted`
- symlink: `proof-capture: refusing a symlink: <path>`
- the shim, module dir gone: `proof-capture: module files missing: <path>` (exit 69)

`run tape` runs the commands in the tape as the invoking user. README and the verify step say so: never run a tape you did not read.

The shim, in full shape (`bin/proof-capture`):

```bash
#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SELF_DIR/../lib/proof-capture/bin/proof-capture"
[ -x "$TARGET" ] || { echo "proof-capture: module files missing: $TARGET" >&2; exit 69; }
exec "$TARGET" "$@"
```

The shim lint (AC12): the shim's non-comment, non-blank lines are the shebang, `set`, `SELF_DIR`, `TARGET`, the guard and the `exec`, at most 6; exactly one line starts `exec`; and the file holds none of `case`, `if `, `while`, `for `, `shift`, `getopts`, `$1`, `$#`. `"$@"` may appear only on the `exec` line.

Routing, in `lib/gate/proof-gate.sh` (the only kit logic this spec adds):

```bash
_proof_visual_capture() {                      # <row> -> the capture command, or nothing
  [ -x "$LIB_ROOT/../bin/proof-capture" ] && [ -x "$LIB_ROOT/proof-capture/bin/proof-capture" ] || return 0
  case "$1" in
    "ui page") echo '$DWARVES_KIT/bin/proof-capture run page <page.html|url> <out.png> --width 1280 (then --width 400 for the narrow shot)' ;;
    "tui")     echo '$DWARVES_KIT/bin/proof-capture run tape <demo.tape> <out.gif>' ;;
  esac
}
```

`proof_contract` computes the row once, prints `visual:` exactly as today, then prints `capture: <that>` on the next line only when the function prints something. The `visual:` text is untouched. Rows "ui flow", "bot message", "report", "generated file" and "none" print no `capture:` line. Both guards are file tests (an existence check, never a read of module code): the shim alone is not enough, because a shim whose module dir was deleted would advertise a dead command. The command is written with the literal `$DWARVES_KIT/bin/` prefix, the form `docs/reference/consumer-contract.md` tells consumers to use, so it resolves from any consumer repo without a CLI on `PATH`. The line does not depend on `[modules] proof_capture`: the kit ships both files whatever the toggle says, and the toggle only decides whether `install.sh` puts a `proof-capture` shim on `PATH`. The README says that.

Invariants: with `[proof] visual` off, `contract` output is byte-identical to master; `proof-ledger.sh`, `hooks/ship-gate.sh`, `lib/classify/` and `lib/adopt*` are not edited; the module never reads a kit file; `bin/proof-capture` holds one `exec` and one guard.

### Module docs (T5, with one line filled by T13)

- `README.md`: install path (copy the directory anywhere, or `install.sh --with proof_capture` for the kit CLI; the kit command path is `$DWARVES_KIT/bin/proof-capture` whether or not the module is toggled on); the contract block above under `## IN`, `## OUT`, `## EXIT`; the dependency table (page needs a Chromium-family browser; tape needs `vhs`, which brings `ttyd` and `ffmpeg`, may look for or fetch a browser of its own, and runs a local terminal server through `ttyd` while it runs); the exact messages; a three-line "run it alone" example that names no kit file; the warning that a tape runs commands as the invoking user, so never run one you did not read; the warning that `<src>` is the caller's choice, so a task text can point the browser at an internal endpoint, and the capture will show it; sizes: the capture does not resize, `proof-asset put` caps stills at 300 KB (it converts them) and GIFs at 2 MB, so an over-size GIF fails at `put` with exit 2, not at capture (shorten the tape or lower its size); the tool does not compare the image width with `--width` (a browser may clamp its window), the opt-in real-browser case does; who reruns the real-browser case (`PROOF_CAPTURE_REAL=1`) and when (before changing a browser flag, and after a major version bump of the browser the proof names); the minimum tested versions and "untested elsewhere" (T13 fills the versions); the residual: a KILL sent to the tool leaves its work dir under `TMPDIR` (the watchdog still ends the browser group), delete it by hand.
- `GUIDE.md`: the neutral craft only. Storyboard first, one story under 30 s. The frame check: open the image and look for the right content, and for a leak of paths, hostnames, tokens or names, before it is committed. User theme fidelity: the page or terminal is in the real theme, never a tool default. Gotchas: a browser can write the file and never exit (the tool ends its group); on macOS the short temp path under `/tmp` is a symlink and the tool refuses a symlinked output directory, so pass a real directory such as one under `$TMPDIR`; a locale without UTF-8 turns box-drawing glyphs into raw bytes in a tape, so set `LANG` on the tape's first line. Debugging a page that does not render: run the browser flags from `## Design` by hand, with `--user-data-dir` set to a fresh temp dir and the stderr redirect removed.
- `SPEC.md`: one page of interface and invariants, with a pointer to this spec for the build story, and a "retire the module" list: delete `lib/proof-capture/` and `bin/proof-capture`; delete the `proof_capture` row in `lib/config/modules.tsv`, the key in `kit.toml` and the rows in `lib/config/module-registry.md`; delete `_proof_visual_capture` and its `capture:` echo in `lib/gate/proof-gate.sh`; drop the census entry, the install-clis lines and `tests/test-proof-capture-route.sh`; revert the Step 7b lines in `commands/verify.md`; regenerate `docs/reference/FEATURES.md`. Nothing is scheduled, stored or credentialed, so nothing else is left behind.
- No tenant words and no host paths anywhere in the dir or in the proof files. The scan is exact and runs in T13 and T14 (see `## Verification`): the pattern `herdr|one-?dark|localterm|hermes|helium|tieubao|/Users/|/var/folders/|/private/` over `lib/proof-capture`, `docs/verification/visual-proof-module.md` and `docs/verification/visual-proof-module/` prints nothing. Captured output pasted into the proofs is edited to repo-relative paths first. The fixture capture uses discovery (Edge), never a personal browser through `PROOF_CAPTURE_BROWSER`.

### The suites (T1 to T4 and T9)

`lib/proof-capture/tests/test-proof-capture.sh` defines its own helpers, sources nothing from the kit, and prints one line per case: `PASS <n> <name>`, `FAIL <n> <name>` or `SKIP <n> <name>`, then the recap `N passed, M failed, K skipped` (exit 0 when M is 0). It exports a private `TMPDIR` per run so every "nothing left behind" assertion is exact, and it sets `PROOF_CAPTURE_BROWSER_CANDIDATES` in every case (to a stub, or to nonexistent names), because the built-in list includes absolute macOS app paths that would start a real browser even on an empty `PATH`. Each case runs under the suite's own 30 s guard (a recorded pid, killed by pid), so a broken entry fails the case instead of hanging the suite. Both stubs are written into a temp dir. The stub browser parses `--screenshot=<path>` and `--user-data-dir=<dir>`, appends its argv to `$STUB_ARGV`, appends its own pid to `$STUB_PIDS`, then acts by `STUB_MODE`: `ok` writes a valid PNG (a 1 by 1 PNG from `printf` octal escapes, IEND included) and exits; `slow-write` writes the first 20 bytes, waits 1.5 s, writes the rest and exits; `write-then-hang` writes the PNG, starts `sleep 20 &` as a helper (its pid also goes to `$STUB_PIDS`), then `sleep 20`; `never-write` does `sleep 20`; `term-ignore` runs `trap '' TERM`, starts a helper that also ignores TERM (`( trap '' TERM; sleep 20 ) &`, pid recorded), writes nothing, then `sleep 20`; `exit-no-file` exits 0. The stub `vhs` records its args, takes `-o <path>`, and acts by mode: `ok` writes a valid GIF (`GIF89a`, trailer `3B`) and exits 0, `exit-no-file`, `bad-file` writes text, `hang` does `sleep 20` after recording its pid, `term-ignore` as for the browser. The suite's EXIT trap signals only the pids listed in `$STUB_PIDS` (never by name), so a failing case cannot leave a stub running for more than 20 s. The suite keeps `ps`, `mktemp` and file-size calls portable (`ps -o pgid= -p`, template `mktemp`, `wc -c < file`), because stub suites also run on Linux runners.

Cases, numbered to the ACs: 1 page file (the output is a valid PNG; a missing parent directory is created; an existing `<out>` is replaced on success; `slow-write`: the output equals the full stub PNG byte for byte; the `exit-no-file` control); 2 page URL (an `http://` URL passes through; a file path holding a space, `#`, `?` and `%` reaches the stub's argv file percent-encoded); 3 argv, profile and leftovers; 4 write-then-hang; 5 never-write at a 2 s deadline (the deadline also set through `PROOF_CAPTURE_DEADLINE`, with a flag that wins over it) and the `term-ignore` row: TERM is ignored, so the KILL escalation must end every recorded pid; 6 TERM, INT and HUP to the tool mid-run (a never-write stub, then a `term-ignore` stub): each exits 1 with `proof-capture: interrupted`, every pid in `$STUB_PIDS` is gone, the private `TMPDIR` holds no work dir and `<outdir>` holds no `.proof-capture.*` file; 7 browser dependencies (bad `PROOF_CAPTURE_BROWSER`; the candidates seam with only nonexistent entries, exact message; empty `PATH` with nonexistent candidates exits 69 before any external command; the same seam with the stub as a control that exits 0; with the seam unset and `PATH` holding only a stub named `google-chrome`, built-in discovery picks that stub first, shown by its argv file, and no real browser starts because the `PATH` names come before the macOS app paths); 8 usage table (every row of AC7, including numbers outside their range, `PROOF_CAPTURE_DEADLINE` out of range, `<out>` a directory, `<out>` a symlink, `<outdir>` a symlink, with a planted target file that must stay byte-identical); 9 tape (modes; bad `PROOF_CAPTURE_VHS`; empty `PATH` with no vhs; `hang` with a 2 s deadline; a `term-ignore` stub at the deadline; a TERM mid-run; a tape path starting with `-`); 10 the standalone lint with its planted violations; 11 the real-browser case, opt-in: it runs only when `PROOF_CAPTURE_REAL=1`; it passes a wrapper as `PROOF_CAPTURE_BROWSER` that records its pid and `exec`s the real browser (so the recorded pid is the group id), captures `hello.html` at 800 by 500, reads the IHDR, then asserts nothing remains under the private `TMPDIR` and `pgrep -g <recorded pid>` finds no process; otherwise it prints `SKIP 11 real browser (set PROOF_CAPTURE_REAL=1)` and counts it; 12 a KILL to the tool mid-run (never-write stub, `--deadline 2`): every pid in `$STUB_PIDS` is gone within 12 s; 13 a second signal during the reap: `term-ignore` stub, `--deadline 2`, a second TERM to the tool about 1 s into the 2 s wait: the tool exits 1, every recorded pid is gone within 6 s of the start, no work dir remains. No default run starts a real browser.

The lint (case 10) scans the non-comment lines of the module's executable for `DWARVES_KIT`, `kit-config`, `../../`, `pkill`, `killall`, `pgrep`, `osascript`, `screencapture` and `ps -A`, and fails on any hit; the planted violations are one in the kit-dependency shape and one name-based kill (`pkill -f chrome`) in a copy.

`tests/test-proof-capture-route.sh` (kit side) pins `KIT_CONFIG_OPERATOR` (and `KIT_CONFIG_ROOT`) to scratch paths before it calls `contract`, exactly as `tests/test-proof-contract-visual.sh` does, because the contract reaches the config resolver and `tests/test-operator-pin.sh` fails a suite that does not. Its numbered cases: R1 the module dir copied out and its suite run under `env -i` (AC8a); R2 the no-inbound-source grep over a tree that holds an untracked planted file built from a variable, so the suite's own text never matches (AC8b); R3 the delete-the-tool trees (AC10b and AC10c); R4 the shim lint (AC12); R5 the end-to-end repo (AC11), a temp repo modeled on `tests/test-proof-visual-gate.sh` whose tracked, clean `.kit.toml` sets `[proof] visual = true` and `assets = "local"` (without `assets = "local"`, `proof-asset put` refuses with no bucket route), using `PROOF_CAPTURE_BROWSER` for the stub and `PROOF_ASSET_CONVERT` for the encoder seam so no real encoder or network is needed; R6 the argv-shape check, which takes the `run page` and `run tape` lines from `contract` output, replaces `$DWARVES_KIT` with the tree under test, fills the placeholders, and runs them against the stubs, once with `[modules] proof_capture = false` in the project `.kit.toml` (AC9); R7 `commands/verify.md` Step 7b carries the line "open the image and check it for paths, hostnames and tokens before `put`". The (c) tree of AC10 is a near-full copy of the kit made with `cp -R` minus `.git` and minus `lib/proof-capture`, not the minimal case-22 tree, because two real suites run in it.

### The fixture (T12 and T13)

Hand steps, numbered, each with the file it writes. T12 does steps 1 to 4; T13 does steps 5 to 10. No step uses a personal browser: discovery picks Edge or Chrome.

1. Capture with the real browser through the shim and discovery (no `PROOF_CAPTURE_BROWSER`): `bin/proof-capture run page lib/proof-capture/examples/hello.html docs/verification/visual-proof-module/page.png --width 800 --height 500`. Writes `page.png`.
2. Open the PNG and read it; the byte count proves nothing. Write one verified-content line in `docs/verification/visual-proof-module.md` (what is on screen, which browser and version made it, that no path or name leaks). Embed it there with a relative link next to the run table.
3. Run `run page lib/proof-capture/examples/timer.html <out> --wait 3000 --width 400` (a page that rewrites itself after 1500 ms; new file `lib/proof-capture/examples/timer.html`), read the IHDR (width 400) and the screen, and quote both in `docs/verification/visual-proof-module.md`, so the `--wait` and 400 px claims are shown, not asserted.
4. Add the `CHANGELOG.md` entry.
5. Run `run tape` on `examples/hello.tape` and quote its output line in `lib/proof-capture/docs/proof-of-done.md`; the GIF is not committed.
6. Check the tape deadline path by hand: a tape with `Sleep 90s` and `--deadline 5`. The run exits 1 with the deadline line. Record the ttyd pids before the run (`pgrep -x ttyd`, read only, other sessions run ttyd too), and after the run assert that none of the pids that appeared during it is still alive (`kill -0` on each new pid). Never compare global counts.
7. Run the opt-in suite: `PROOF_CAPTURE_REAL=1 bash lib/proof-capture/tests/test-proof-capture.sh` and quote its recap in `proof-of-done.md`.
8. Run one negative control from `## Acceptance Criteria` (the AC3 one) and quote the failing line in `proof-of-done.md`.
9. Fill the tested browser and vhs versions into `lib/proof-capture/README.md`.
10. Run the exact scan in `### Module docs` over all three paths; edit host paths out of every pasted output first.

The media guard, named: the repo has no size or type cap on a tracked image (checked in `hooks/`, `lib/gate/`, `.gitattributes` and `.gitignore`; `.gitignore` has no image rule). The only rule that reads a committed image is R3b in `lib/gate/proof-ledger.sh` (`_visual_proof`, via `_committed_images`), and it applies only where `[proof] visual` is on: the link must sit in a changed proof file, resolve to a file that exists, be tracked (`git ls-files`) and be among the branch's changed files. The kit repo has the knob off, so the check that bites here is `proof-ledger.sh images` (existence) and `wrap land`, which rewrites the relative link to an absolute URL pinned to the head. The 100 KB bound is this spec's own: two files under `docs/figures/` already exceed it (`push-gate.png` at 111883 bytes, `lanes.png` at 103434), and the fixture, a plain page, is expected at about 13 KB.

### Data model changes

None. The artifact is a file; the manifest `proof-asset` writes is unchanged.

### API changes

`proof-gate.sh contract` gains one optional line. Nothing else changes for a caller; the verbs `class`, `requirement`, `skeleton` and `coverage` print what they printed.

### UI changes

None.

### Infrastructure changes

None. No hook, no daemon, no launchd, no CI workflow, no network call from the tool. A new opt-in module row only: `proof_capture`, off by default, no hooks, one CLI.

## Task Breakdown

Order: T1, then T2, T3, T4 (each extends the entry and the suite); T5 after T4; T6 after T1 (the shim execs the entry); T7 after T6 (`test-modules-table.sh` checks that every table CLI has a `bin/` file); T8 after T4 and T6; T9 after T4, T6 and T8; T10 after T8 (it adds a case to the file T8 edits); T11 after T7 and T10 (FEATURES.md is generated from the files those tasks change); T12 after T4 and T6 (it runs the real capture through the shim); T13 after T5 and T12 (it edits the README T5 writes); T14 last. `tests/test-kit-contract.sh` is red from T7 until T13 writes the module's `docs/proof-of-done.md` (rule C3); run it only in T14. Each task is its files plus its check; the content lives in `## Technical Design`.

### Phase 1: The module

- [ ] T1: The entry skeleton: argument parsing, validation, dependency discovery, usage. Files: `lib/proof-capture/bin/proof-capture`, `lib/proof-capture/examples/hello.html`, `lib/proof-capture/tests/test-proof-capture.sh`. Check: `bash lib/proof-capture/tests/test-proof-capture.sh` prints `PASS` for case 8 and for the dependency rows of case 7 (bad env, nonexistent candidates, empty `PATH`) and a recap ending `0 failed`. Build to `### Interfaces` and `### The suites`; the launch step and `run tape` exit 64 as "not built yet".
- [ ] T2: The page capture, the deadline and the opt-in real case. Files: the same three. Check: the suite prints `PASS` for cases 1, 2, 3 and 5 (without its `term-ignore` row), the control and discovery rows of case 7, and `SKIP 11 real browser (set PROOF_CAPTURE_REAL=1)`; recap `0 failed, 1 skipped`. Build to `## Design` (the shared launch, poll and final copy), with a plain TERM to the recorded pid as the stop for now.
- [ ] T3: The own-group reap, the traps and the watchdog. Files: the same three. Check: `PASS` for cases 4, 6, 12 and 13 and the `term-ignore` row of case 5, recap `0 failed, 1 skipped`; run each case's negative control from `## Acceptance Criteria` once and quote the failing lines in the notes. Build to the rules for the reap in `## Design`.
- [ ] T4: The tape lane. Files: `lib/proof-capture/bin/proof-capture`, `lib/proof-capture/examples/hello.tape`, `lib/proof-capture/tests/test-proof-capture.sh`. Check: `PASS` for cases 9 and 10, recap `0 failed, 1 skipped`.
- [ ] T5: Module docs. Files: `lib/proof-capture/README.md`, `lib/proof-capture/GUIDE.md`, `lib/proof-capture/SPEC.md`. Check: `grep -c '^## IN$' lib/proof-capture/README.md` prints 1, the same for `^## OUT$` and `^## EXIT$`, and the exact scan in `### Module docs` prints nothing for `lib/proof-capture`.

### Phase 2: Kit integration (thin)

- [ ] T6: The shim and its census. Files: `bin/proof-capture` (the shim above, exec bit), `tests/test-bin-forwarders.sh` (add to `EXPECTED`, and one dispatch assertion: with `lib/proof-capture/` present the shim with no arguments exits 64; the assertion is skipped when that dir is absent, where the shim exits 69 and AC10c expects it). Check: `bash tests/test-bin-forwarders.sh` ends with no failure.
- [ ] T7: Registry rows and the install shim. Files: `lib/config/modules.tsv` (one row: `proof_capture`, `opt-in`, `-`, `proof-capture`), `kit.toml` (`proof_capture = false` under `[modules]`, hookless, exposes the proof-capture CLI), `lib/config/module-registry.md` (a stage row, Build (Execute); a `modules.proof_capture` key row beside `modules.worktree`; the module count text, which says 12 while the table already holds 13 toggleable rows: make it 14), `tests/test-install-clis.sh` (add `proof_capture` to its `--with` list and CLI loop, and a "no shim without the module" line). Check: `bash tests/test-modules-table.sh`, `bash tests/test-config-registry.sh`, `bash tests/test-install-clis.sh` and `bash tests/test-adopt.sh` pass (adopt seeds `[modules]` from the table with the new key `false`; a fresh adopt must not turn the module on).
- [ ] T8: Routing. Files: `lib/gate/proof-gate.sh` (the function above, and the row-once change in `proof_contract`), `tests/test-proof-contract-visual.sh` (cases: knob on and a settings-page task gives a `capture:` line with `run page` and an unchanged `visual:` line; a TUI task gives `run tape`; a bot-message task gives none; the verbs `class`, `requirement` and `skeleton` print the same bytes as master's gate on four task strings with the knob on and off), `lib/gate/README.md` (the `gate proof` row mentions the `capture:` line). Check: `bash tests/test-proof-contract-visual.sh` all pass, case 21 and case 22 unchanged and green; `bash tests/test-proof-visual-gate.sh` passes unedited.
- [ ] T9: Kit-side suite. Files: `tests/test-proof-capture-route.sh`, `bin/test-affected.timeouts` (only if the suite needs more than the default). Check: `bash tests/test-proof-capture-route.sh` ends `0 failed`; R1 to R6 print `PASS` (R7 is added in T10). Model the contract tree on case 22 of the contract suite and the temp repo on `tests/test-proof-visual-gate.sh`.

### Phase 3: Say it exists, then prove it

- [ ] T10: Docs that say the producer exists. Files: `commands/verify.md` (Step 7b names `$DWARVES_KIT/bin/proof-capture run page|tape`, then `bin/proof-asset put`; says "open the image and check it for paths, hostnames and tokens before `put`"; carries the tape warning: a tape runs its commands as you, so read it first, and `ttyd` runs a local terminal server while it runs; a flow or generated file with no verb stays by hand), `docs/verification/README.md` (replace the "producer is the visual-proof module ... until it lands" paragraph at line 96), `docs/reference/tiers.md` (the queued row at line 53), `tests/test-proof-contract-visual.sh` (a case R10b: `verify.md` Step 7b names `proof-capture run page`), `tests/test-proof-capture-route.sh` (case R7). Check: `bash tests/test-proof-contract-visual.sh` and `bash tests/test-proof-capture-route.sh`.
- [ ] T11: Surface lists. Files: `docs/reference/install.md` (module table row), `docs/reference/project-structure.md` and `docs/reference/consumer-contract.md` (the module CLI lists), `lib/README.md` (a `proof-capture/` row beside `proof/`), `docs/reference/FEATURES.md` (regenerated, never hand edited: `bash lib/registry/feature-registry.sh generate`). Check: `bash tests/test-meta-docs-registry.sh` (its FEATURES freshness pin is green only after this task) and `git diff --stat docs/reference/FEATURES.md` shows only generated rows.
- [ ] T12: The fixture. Files: `docs/verification/visual-proof-module.md`, `docs/verification/visual-proof-module/page.png`, `lib/proof-capture/examples/timer.html`, `CHANGELOG.md`. Check: `bash lib/gate/proof-ledger.sh images docs/verification/visual-proof-module.md .` prints one line whose path exists, and `wc -c docs/verification/visual-proof-module/page.png` is under 102400. Steps 1 to 4 of `### The fixture`.
- [ ] T13: The module's proof. Files: `lib/proof-capture/docs/proof-of-done.md`, `lib/proof-capture/README.md` (the tested versions). Check: the exact scan in `### Module docs` prints nothing for all three paths it names. Steps 5 to 10 of `### The fixture`.
- [ ] T14: Whole-change check. Files: none. Check: `bash tests/test-kit-contract.sh` (C3 now sees the proof-of-done), `bash lib/gate/boundary-lint.sh` prints `boundary-lint: PASS`, the exact scan again over all three paths, `git diff --stat origin/master -- hooks/ship-gate.sh lib/classify lib/gate/proof-ledger.sh lib/proof` prints nothing and `git diff --name-only origin/master | grep -E '^lib/adopt'` prints nothing (AC15), then `bash tests/run-all.sh --changed --time` once.

## After state

- [ ] `bash lib/proof-capture/bin/proof-capture run page lib/proof-capture/examples/hello.html "$(mktemp -d)/x.png" --width 800 --height 500` exits 0 and the file is an 800 by 500 PNG (run by hand once, T12). (Today: no such command.)
- [ ] The module dir runs with no kit: copied to a temp path outside any repo, its suite passes under `env -i`. (Today: no module.)
- [ ] With `[proof] visual` on, `proof-gate.sh contract "redesign the settings page UI"` prints a `capture:` line naming `$DWARVES_KIT/bin/proof-capture run page`, with `[modules] proof_capture` on or off, and the `visual:` line is byte-identical to today's. With the knob off, the output is byte-identical to today's. (Today: the artifact is named, the way to make it is not.)
- [ ] The tree without `bin/proof-capture`, and the tree with the shim but without `lib/proof-capture/`, still pass `contract` and print no `capture:` line. (Today: not applicable.)
- [ ] A tool run never leaves a browser, a profile directory or a partial file behind, on success, failure, deadline, a TERM, INT or HUP to the tool, a TERM-ignoring child, or a KILL to the tool (the watchdog ends the browser group within deadline plus 5 s). (Today: no tool.)
- [ ] This spec's own PR proof, `docs/verification/visual-proof-module.md`, embeds a committed PNG that exists in the tree, is under 100 KB, and shows the fixture page. (Today: a proof of this kind carries only a table.)
- [ ] `proof_capture` is a row in `modules.tsv` with default `opt-in`, `false` in `kit.toml`, a stage in the registry, and `bin/proof-capture` in the census. (Today: none.)
- [ ] `hooks/ship-gate.sh`, `lib/classify/`, `lib/adopt*`, `lib/gate/proof-ledger.sh` and `lib/proof/` are untouched by the diff.

## Quality requirements

none

## Acceptance Criteria (global)

Every check below is a command; "the suite" is `bash lib/proof-capture/tests/test-proof-capture.sh`, "the route suite" is `bash tests/test-proof-capture-route.sh`, "the contract suite" is `bash tests/test-proof-contract-visual.sh`. The expected result is the named case printing `PASS <n> ...` and the recap saying `0 failed`. A negative control means: apply the named break to a copy or in place, watch the named case print `FAIL`, restore.

| AC | Check | Negative control |
|---|---|---|
| AC1 `run page` writes a valid PNG for a file and for an `http://` URL (stub browser); a missing parent directory is created; an existing `<out>` is replaced on success; a slow writer is not accepted half-written; a path with a space, `#`, `?` and `%` reaches the browser percent-encoded | suite cases 1 and 2 print `PASS`; case 1's slow-write row compares byte for byte; case 2 asserts on the stub's argv file. The real-browser case 11 (`PROOF_CAPTURE_REAL=1`, by hand) checks the IHDR width and height equal the flags | the stub exits 0 with no file: the run exits 1 and `<out>` is absent. Drop the trailer check: the slow-write row fails. Drop the `%` encoding: case 2 fails |
| AC2 headless and throwaway: the browser argv holds `--headless=new` and a `--user-data-dir` under the private `TMPDIR` that no longer exists after the run; nothing but the named `<out>` is left (no work dir, no `.proof-capture.*` file beside `<out>`) | suite case 3 (stub records argv) | mutate the entry to drop `--headless=new`: case 3 fails |
| AC3 a browser that writes the file and never exits, with a helper process: the run returns 0 within 10 s and every pid in `$STUB_PIDS` is gone (`kill -0` fails for each) | suite case 4 | change the group kill to signal the recorded pid only: the helper's pid survives and case 4 fails (Grounding dry trace) |
| AC3b a TERM, an INT and a HUP to the tool mid-run (a never-write stub, then a `term-ignore` stub): the tool exits 1 with `proof-capture: interrupted`, every pid in `$STUB_PIDS` is gone, the private `TMPDIR` holds no work dir and `<outdir>` holds no `.proof-capture.*` file | suite case 6 | delete the `trap` line: the stub pids survive and case 6 fails |
| AC3c a KILL to the tool mid-run (a never-write stub, `--deadline 2`): every pid in `$STUB_PIDS` is gone within 12 s, because the watchdog ends the group at deadline plus 5 s | suite case 12 | delete the watchdog start: the stub outlives the 12 s window (it sleeps 20 s) and case 12 fails |
| AC3d the KILL escalation and the single reap: a child and helper that ignore TERM are ended at the deadline (case 5) and on an interrupt (case 6); a second TERM to the tool 1 s into the 2 s wait finishes the reap at once, with every pid gone within 6 s and no work dir (case 13) | suite cases 5, 6 and 13 | remove the KILL step: the `term-ignore` rows of cases 5 and 6 and case 13 fail. Let the trap start a second reap instead of setting the flag: case 13 fails |
| AC4 deadline: a browser that never writes: exit 1 at the deadline, the exact message, no `<out>`, an existing `<out>` unchanged; `PROOF_CAPTURE_DEADLINE` applies and the flag wins over it | suite case 5 | remove the deadline test from the poll loop: case 5 fails on the suite's 30 s guard |
| AC5 missing dependency, never a pass: a bad `PROOF_CAPTURE_BROWSER` exits 69 with its exact message; `PROOF_CAPTURE_BROWSER_CANDIDATES` holding only nonexistent entries exits 69 with the no-browser message, also on an empty `PATH`; a bad `PROOF_CAPTURE_VHS` exits 69 with its message; no vhs on an empty `PATH` exits 69 before any external command; none writes an artifact and none starts a real browser | suite cases 7 and 9 | the same candidates seam holding the stub exits 0, so the 69 is caused by the missing dependency |
| AC6 `run tape` through the same launch, poll and reap: stub vhs gets `-o <partial> <absolute tape>`, writes a GIF, vhs exits 0, `<out>` is that GIF, exit 0; a stub that exits 0 without a file: exit 1; a stub that exits non-zero: exit 1; a hanging stub and a TERM-ignoring stub are ended at the deadline; a TERM mid-run leaves no stub pid | suite case 9 | a stub that writes a non-GIF file: exit 1 |
| AC7 usage: no args, unknown verb, unknown flag, missing input file, a `javascript:` or `chrome:` scheme, a path starting with `-`, `--wait 0`, `--deadline 0`, `--deadline 601`, `PROOF_CAPTURE_DEADLINE` out of range, `--width abc`, `--width 10001`, `<out>` a directory, `<out>` a symlink, `<outdir>` a symlink: exit 64 each, nothing written, a planted symlink target byte-identical | suite case 8 | allow the `javascript:` scheme: case 8 fails. Remove the symlink refusal: the planted target is overwritten and case 8 fails |
| AC8 standalone, both ways. (a) the module dir copied to a temp path outside any repo passes its own suite under `env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin`; the suite's lint (case 10) finds none of its forbidden tokens in the module executable. (b) the no-inbound-source grep in `## Verification` prints nothing over tracked and untracked files: no file outside the module sources a path inside it | suite case 10; route suite R1 and R2 | plant `source ../../config/kit-config.sh` and, separately, `pkill -f chrome` in the copy: case 10 fails for each. Plant an untracked kit script that sources `lib/proof-capture/bin/proof-capture` (the text built from a variable): the grep prints it |
| AC9 routing: knob on, module present: a UI task prints `capture:` with `$DWARVES_KIT/bin/proof-capture run page`, a TUI task prints `run tape`, a bot-message task prints none, and the `visual:` line equals the frozen text pinned by case 21; the same with `[modules] proof_capture = false` in the project `.kit.toml`; the `capture:` lines, with `$DWARVES_KIT` set to the tree and the placeholders filled, run against the stubs | the contract suite and route suite R6 | change the frozen `visual:` text: case 21 fails. Make `_proof_visual_capture` print nothing: the contract suite's `capture:` cases and R6 fail |
| AC10 the delete test, tool side. (a) knob off: contract output byte-identical to master's (existing case 22) and holds no `capture:` line. (b) tree without `bin/proof-capture`, knob on: `contract` exits 0, same `visual:` line, no `capture:` line. (c) near-full copy of the tree with the shim and the table row but no `lib/proof-capture/`, knob on: the same; `bin/proof-capture run page x y` prints the missing-files line and exits 69; `tests/test-modules-table.sh` and `tests/test-bin-forwarders.sh` pass in that tree; `tests/test-kit-contract.sh` is expected red there (DEC-K) | the contract suite (a) and route suite R3 (b, c) | (a) move the `capture:` echo outside the `visual` condition: case 22 fails. (b, c) remove the matching `[ -x ... ]` guard: the tree prints a `capture:` line and the case fails |
| AC11 end to end in a hermetic repo with the knob on and `assets = "local"`: a stub capture, `bin/proof-asset put`, the embed in a proof file: `proof-ledger.sh check` passes; remove the image: it BLOCKS with the visual message | route suite R5 | the removal is the control |
| AC12 thin shim and registry: the shim passes the lint in `### Interfaces`; `proof_capture` is `opt-in` in `modules.tsv`, `false` in `kit.toml`, present in the registry and the `bin/` census; kit contract C1 to C10 pass | route suite R4 (the shim lint); `test-modules-table.sh`, `test-bin-forwarders.sh`, `test-kit-contract.sh` | add an `if` to a copy of the shim: the lint fails; a row with a bad default fails the table suite |
| AC13 fixture: the proof embeds a committed PNG that exists and is under 100 KB; the reader opened it and the verified-content line says what it shows; the scan finds no tenant word or host path | `proof-ledger.sh images`, `wc -c` and the scan | point the link at a missing file: `images` prints nothing. Put a `/Users/` path in the proof: the scan prints it |
| AC14 no regression | `bash tests/run-all.sh --changed --time` | not applicable |
| AC15 blast radius: a repo with `[proof] visual` off sees byte-identical `contract` output (AC10a); a repo with it on cannot fail a push that passes today, because the push path (`hooks/ship-gate.sh` and `lib/gate/proof-ledger.sh check`) is not edited and `contract` is not on it (the hook calls only `proof-gate.sh coverage`) | `git diff --stat origin/master -- hooks/ship-gate.sh lib/classify lib/gate/proof-ledger.sh lib/proof` prints nothing; the contract suite's verbs-unchanged case; `bash tests/test-proof-visual-gate.sh` passes unedited | add a byte to the `skeleton` output in a copy: the verbs-unchanged case fails |
| AC16 the verify step tells the reader to look before `put`: `commands/verify.md` Step 7b carries "open the image and check it for paths, hostnames and tokens before `put`" | route suite R7 | delete the line: R7 fails |

Every behavior change owes a negative control run: break the code, watch the named test fail, restore, and quote the failing line in `docs/verification/visual-proof-module.md`.

## Verification

```bash
bash lib/proof-capture/tests/test-proof-capture.sh
bash tests/test-proof-capture-route.sh
bash tests/test-proof-contract-visual.sh
bash tests/test-proof-visual-gate.sh
bash tests/test-modules-table.sh
bash tests/test-bin-forwarders.sh
bash tests/test-install-clis.sh
bash tests/test-kit-contract.sh
bash lib/gate/boundary-lint.sh
git diff --stat origin/master -- hooks/ship-gate.sh lib/classify lib/gate/proof-ledger.sh lib/proof
git grep --no-index --exclude-standard -nE '(^|[;&|[:space:]])(source|[.])[[:space:]]+[^#]*proof-capture/' -- . ':!lib/proof-capture' ':!docs' ':!*.md' ':!tests/test-proof-capture-route.sh'
grep -rniE 'herdr|one-?dark|localterm|hermes|helium|tieubao|/Users/|/var/folders/|/private/' lib/proof-capture docs/verification/visual-proof-module.md docs/verification/visual-proof-module
T="$(mktemp -d)" && cp -R lib/proof-capture "$T/pc" && (cd "$T" && env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin bash "$T/pc/tests/test-proof-capture.sh")
bash lib/gate/proof-ledger.sh images docs/verification/visual-proof-module.md .
bash tests/run-all.sh --changed --time
```

The `git grep --no-index`, `grep -rniE` and `git diff --stat` lines print nothing when they pass. By hand, once, for the fixture (T12 and T13, steps in `### The fixture`; never part of a default run): the capture through the shim, the `--wait` page, the tape run and its deadline check, and `PROOF_CAPTURE_REAL=1 bash lib/proof-capture/tests/test-proof-capture.sh`. The real-browser case reports `SKIP` (counted, never a pass) in every default run. On the build host the hand run must pass; the proof file quotes it and names the browser and its version.

## Edge Cases

1. `<src>` is a relative path: resolve it to an absolute `file://` URL from the caller's cwd before launch. A path with spaces, `#`, `?` or `%` is percent-encoded.
2. `<out>` exists already: replaced only on success, by rename.
3. `<out>` parent missing: created (tested in case 1). `<out>` is a directory or a symlink, or `<outdir>` is a symlink: exit 64.
4. `--width`, `--height`, `--wait` or `--deadline` not an integer in its range: exit 64. `--wait 0` is refused on purpose: Edge wrote no file at `--virtual-time-budget=0` (Grounding 7). `PROOF_CAPTURE_DEADLINE` follows the same rule.
5. Two captures at once: each has its own work dir, profile, group and watchdog, so they do not collide. Two captures to one `<out>`: the last rename wins.
6. The page needs JavaScript time: `--wait 3000` gives it virtual time; without it the shot is of the first paint.
7. `TMPDIR` unset: `/tmp`. The work dir is removed on every exit path a catchable signal can reach, including a deadline.
8. A browser that prints errors to stderr (the CVDisplayLink lines seen in the probe) is silenced; the tool prints only its own one-line faults. The shell's own "Terminated" job notice is silenced too (the `wait` runs with stderr discarded).
9. `run tape` with a tape that declares its own `Output`: the `-o` flag adds the partial path; only the partial is checked and copied to `<out>`. Any other output the tape declares is vhs's and is not touched.
10. A `PROOF_CAPTURE_BROWSER` that is a stub script: used as is; this is the seam the suite uses.
11. The browser exits 0 having written the file: the poll sees the valid file first, the reap finds an empty group and signals nothing harmful.
12. A signal during the reap: the trap only sets `INTR`; the running reap goes straight to KILL. A signal before the reap starts reaps in interrupt mode.
13. A path argument starting with `-`: exit 64 (it could be read as a flag by the browser or vhs).
14. `<outdir>` is `/tmp` on macOS (a symlink): exit 64; pass a real directory.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Browser writes the file and never exits (seen on two browsers) | the poll sees a valid PNG while the pid is alive | success is the file; reap the own group; AC3 |
| Browser never writes (seen with Brave) | deadline reached | exit 1, one line, no artifact; the discovery list leaves Brave out |
| Helpers outlive the main process | `kill -0 -- -<CPID>` after TERM | KILL the same group after 2 s; sampled: Edge left helpers after TERM and none after KILL (Grounding 11); AC3 |
| A helper leaves the group (a browser that calls setsid for a child) | the opt-in real-browser case, which asserts the recorded group is empty (`pgrep -g`, read only) | none in the tool: no name-based kill is allowed. The hand run reports it and the README names it; a browser that does this is left out of discovery. Same limit as `lib/decide/flick.sh` |
| The tool is interrupted (INT, TERM, HUP), also twice | the trap | KILL the group at once (no TERM wait), remove the final temp file and the work dir, `proof-capture: interrupted`, exit 1; a second signal during a reap only sets a flag; AC3b, AC3d |
| A child that ignores TERM | the group still exists after the 2 s wait | KILL the group; AC3d |
| The tool itself is sent KILL, or the host crashes | none at the time (a KILL cannot be caught) | the watchdog, its own group, ends the browser group at deadline plus 5 s; AC3c. The work dir under `TMPDIR` remains (the OS clears it). The watchdog polls the group once a second and exits when it is gone, so it only acts on a group it has just seen; a pid is not reused while a group with that id exists. Residual: a recycle between its last check and its KILL, a window of well under a second |
| A planted symlink at the output path or its directory | the refusal | exit 64, nothing written through; the browser never writes beside `<out>`; AC7 |
| Job control does not give an own group (`ps -o pgid=` differs from the pid) | the check after launch | reap the one pid, exit 1 with the isolate message; never signal a group the tool did not create. A defensive branch with no test (a stub cannot defeat job control) |
| Partial or torn PNG or GIF | magic and trailer ok, size still changing | require the trailer and equal size on two reads 0.3 s apart; the file lands under `<out>` only by copy then rename; AC1 slow-write |
| A dependency is missing | `command -v` or an explicit env path fails | exit 69 with the exact line; never exit 0; never fall back from an explicit path |
| The module dir is gone but the shim and row remain | the shim's file test | exit 69 with `module files missing`; the gate prints no `capture:` line; AC10c |
| The tape hangs | deadline reached | TERM the own group, KILL after 2 s; exit 1; hand check in T13 |
| A killed vhs leaves `ttyd` or its browser running | the group still exists after TERM | KILL the group after 2 s; sampled: after KILL no `ttyd` and no headless browser remained (Grounding 8). The suite uses a stub vhs, so it cannot leak |
| vhs fetches a browser, `ttyd` serves a local shell, a tape runs arbitrary commands | none in the tool | vhs's own behavior, not controlled here; the README and the verify step say so |
| The capture shows a secret or a personal path | a human reading the frame | GUIDE.md frame check; the proof's verified-content line must say what was checked; the T12 and T13 scan covers the proof text |
| A drift between the routing case and the module's verbs | AC9 | the route test takes `run page` and `run tape` from the contract output and runs those exact argv shapes against the stub |
| Browser flags change in a new release (headless modes have moved before) | the opt-in real-browser case fails, or a run exits 1 at the deadline | one line, no artifact, no hang; README records the tested browser and vhs versions and who reruns the case, so a drift is visible |

## Out of Scope

- `run flow`, a scripted multi-step page walk ending in a GIF. Named as the next verb; Chrome's `--screenshot` cannot click. The "ui flow", "report" and "generated file" rows keep their artifact text and get no `capture:` line.
- Any lane that drives the live desktop or one platform: macOS window recording, keycastr, a real Terminal window, the simulator route. They stay in the operator's personal skill.
- Linux and containers: not claimed. The discovery list names Linux binaries; nothing here ran there. This is the failure the Depth line names, and the real-browser case is opt-in and reports SKIP, never a pass, by default.
- Upload to a bucket. `proof-asset` owns that and is not edited.
- Turning `[proof] visual` on for any repo, and any change to `proof-ledger.sh check`.
- Any edit to `hooks/ship-gate.sh`, `lib/classify/`, or `lib/adopt*`.
- The follow-up changes in the operator's two private repos (listed in the brief, D7). A later, separate PR in each repo.
- Pointing `lib/system-design/shots.mjs` at this module. It needs CDP to pull SVG out of a built sheet; it stays as is.
- Controlling what vhs does with its own browser, and a browser child that leaves the process group.
- Amending ADR-0041 to admit the three deviations this module found (DEC-K): done in `docs/decisions/0041-standalone-doctrine.md`.
- Resizing or capping a capture: `proof-asset put` owns the 300 KB (stills, after conversion) and 2 MB (GIF) limits.

## Touches

- lib/proof-capture/**
- bin/proof-capture
- lib/gate/proof-gate.sh
- lib/gate/README.md
- lib/config/modules.tsv
- lib/config/module-registry.md
- kit.toml
- commands/verify.md
- docs/briefs/DECISION-BRIEF-visual-proof-module.md
- docs/implementation-notes/visual-proof-module.md
- docs/verification/README.md
- docs/verification/visual-proof-module.md
- docs/verification/visual-proof-module/**
- docs/reference/tiers.md
- docs/reference/install.md
- docs/reference/project-structure.md
- docs/reference/consumer-contract.md
- lib/README.md
- docs/reference/FEATURES.md
- tests/test-proof-capture-route.sh
- tests/test-proof-contract-visual.sh
- tests/test-bin-forwarders.sh
- tests/test-install-clis.sh
- bin/test-affected.timeouts
- CHANGELOG.md

## Grounding

Read live on 2026-11-25 on the build host (macOS, bash 3.2.57, node 22). Each line is a command and what it printed. Output trimmed; no credential-shaped value appears.

1. A third Chromium-family browser (the operator's own; not in the discovery list; set by `PROOF_CAPTURE_BROWSER`): `<browser> --headless=new --disable-gpu --no-first-run --disable-sync --disable-extensions --hide-scrollbars --user-data-dir=<tmp> --window-size=800,500 --screenshot=out.png file://.../hello.html`. Result: `out.png: PNG image data, 800 x 500, 8-bit/color RGB` (12890 bytes) written within seconds, and the command did not return within 120 s; a helper carrying the same `--user-data-dir` was still running. Ending the processes of that profile stopped it. The `timeout` in the shell was an alias for `gtimeout`.
2. Browser, Microsoft Edge: the same flags. `out.png` valid, 800 x 500, 12890 bytes after about 2 s; the browser pid was still alive afterwards.
3. Browser, Brave: the same flags, run twice, 20 s then 40 s. No PNG written; the browser stayed alive; stderr held `CVDisplayLinkCreateWithCGDisplay failed` lines. This is why Brave is not in the discovery list.
4. Chrome and Chromium are not installed on this host and no Linux host was available, so the flag set was never run on them. That is the failure the Depth line names. The build's opt-in real-browser case runs on whatever discovery or `PROOF_CAPTURE_BROWSER` finds and the proof says which browser and version it was; the SKIP rule keeps an absent or unrun browser from reading as a pass.
5. `vhs --version` printed `vhs version 0.12.1`; `ttyd` and `ffmpeg` on PATH. `vhs -o <abs>/o2.gif demo.tape` exited 0 and wrote a 9486-byte file whose first bytes are `GIF89a`. A bare `vhs demo.tape` also exited 0 (9761 bytes). Neither opened a window.
6. `command -v setsid` printed nothing (absent on macOS). So the tool uses bash job control for its own group. `/bin/bash` 3.2.57 in a script: `set -m` then a background job gave `pgid=74020` equal to the job's pid while the script's own pgid was 73934; `kill -TERM -- -74020` ended the job and its grandchild; `pgrep -g 74020` then printed nothing. The shell printed a `Terminated: 15` job notice on the wait, which the tool silences (edge case 8).
7. Edge, `--window-size=400,800`: `file` reports `PNG image data, 400 x 800`. The same with `--virtual-time-budget=3000` against a page that rewrites itself after 1500 ms: the PNG (7769 bytes, opened and read) shows `READY after 1500ms` on a green page, while the run without the budget (4679 bytes) is of the first paint. `--virtual-time-budget=0`: no file was written. So the 400 px and `--wait` claims in the contract were run, and `--wait` must be positive.
8. vhs killed mid-run: a tape with `Sleep 90s`, started in the background; `ttyd` count 1 while it ran. After `kill -TERM` and 3 s, `ttyd` count 0 but the vhs process was alive; it was still alive 6 s later and `kill -KILL` ended it. Afterwards `pgrep` for `ttyd`, a headless browser, and `rod` helpers each found nothing. So the tool sends TERM, waits 2 s, then KILL. (Sampled with the pid, not the group; the group reap covers at least that. The group form is re-checked by hand in T12.)
9. Kit sources read: `lib/gate/proof-gate.sh` lines 124 to 183 (`_proof_visual_enabled`, `_proof_visual_row`, `_proof_visual_artifact`, `proof_contract`), `tests/test-proof-contract-visual.sh` (case 21 greps `^visual:`, case 22 compares a knob-off contract with master's), `lib/wrap/wrap-land.sh` lines 186 to 227 (`_land_proof_body`: a relative committed image becomes an absolute URL pinned to the head), `tests/test-kit-contract.sh` (C3 needs `README.md`, a spec and `docs/proof-of-done.md` per module; C4 needs a test; the module list is the table row with `_` turned into `-`, so `proof_capture` maps to `lib/proof-capture/`), `tests/test-bin-forwarders.sh` line 41 (the `bin/` census), `tests/test-modules-table.sh` T3 (every table CLI needs a `bin/` file), `hooks/ship-gate.sh` line 761 (the only `proof-gate.sh` verb on the push path is `coverage`), `lib/gate/proof-ledger.sh` lines 433 to 510 (R3a, R3b, R3c), `lib/adopt.sh` (seeds `[modules]` from `modules.tsv` through `lib/config/modules.sh`), `docs/reference/consumer-contract.md` line 77 (reference `$DWARVES_KIT/bin/<name>`), `lib/registry/feature-registry.sh` (the verb is `generate [outfile]`).
10. `ps -A -o pid= -o ppid=` did not return within 20 s while `uptime` reported a load average of about 340 and 21 users; `ps -p <pid>` returned at once. So the tool never lists the process table.
11. Edge under job control, run during this validation: `set -m`, the same flags, `--screenshot` to a temp file. `out.png` 12890 bytes after about 2 s; `pgrep -g <pid>` listed 11 processes (the browser and 10 helpers, all in the own group); `kill -TERM -- -<pid>` plus 2 s left the group non-empty; `kill -KILL -- -<pid>` emptied it; afterwards `pgrep -g` was empty and a read-only `pgrep -f` on the profile path found nothing. So the group holds the helpers, and TERM alone is not enough.
12. `lib/decide/flick.sh` `bounded_out` (lines 390 to 436): `set -m`, the child in the background, `kill -s TERM -- "-$cpid"`, a 1 s grace, `kill -s KILL -- "-$cpid"`, with the comment that a descendant that calls setsid or setpgid leaves the group and survives. The same pattern, and the same stated limit.
13. `ls -l docs/figures/*.png`: `push-gate.png` 111883 bytes, `lanes.png` 103434, `adopt.png` 95083. The kit repo has no tracked image size cap.

Dry trace for the negative control of AC3: mutation = change the group kill in the reap to signal the recorded pid only. The suite's `write-then-hang` stub starts `sleep 20 &` as a helper in its own group and records both pids in `$STUB_PIDS`; killing the leader alone leaves the helper running (it is reparented, not signalled). With the mutation the helper survives the run, case 4 asserts `kill -0` fails for every recorded pid within 10 s, and it goes red. Negative control for AC3b: delete the `trap` line; a TERM to the tool then kills the tool and leaves the stub, and case 6 goes red on the surviving pid. Negative control for AC3c: delete the watchdog start; a KILL to the tool leaves the stub, which sleeps 20 s, past case 12's 12 s window, and case 12 goes red.

## Decision Log

- DEC-A: the module is a directory under `lib/` with its own `bin/`, README, SPEC, proof-of-done and tests, plus a kit shim in `bin/`. Why: that is the shape the kit contract (C2 to C4) already checks, and the directory is the copyable unit. Rejected: extending `lib/proof/`, which needs the kit.
- DEC-B: bash and Chrome's own `--screenshot`, no Node. Why: one dependency, and PHILOSOPHY holds the kit to bash. Rejected: Playwright, a CDP driver.
- DEC-C: verbs `run page` and `run tape`. Why: SPEC-200 I4 (stated in `docs/reference/kit-contract.md`) closes the verb list to `run`, `show`, `propose`, `promote`, `trace`. Rejected: `shot` and `gif`, which are synonyms of `run`.
- DEC-D: routing is a separate added line gated on file tests, not an edit to the `visual:` text and not a read of `[modules]`. Why: the frozen text keeps its pinning tests, and the manifest is never read at run time. Rejected: a `route` verb.
- DEC-E: the fixture image is committed (one PNG, about 13 KB), not uploaded. Why: an upload reaches a real service, and the repo already commits small rendered figures. Open PR 1086 does the same with four PNGs; it is precedent in flight, not a settled rule.
- DEC-F: Brave is left out of the discovery list. Why: no output in 40 s on this host. An operator can still name it in `PROOF_CAPTURE_BROWSER`.
- DEC-G: lane `full`. Why: the diff floor, not the task text.
- DEC-H: Edge is in the discovery list, behind Chrome and Chromium within each group, but the `microsoft-edge` name on `PATH` is tried before the macOS Chrome app path, so a host with Edge on `PATH` and Chrome only as an app gets Edge. `lib/system-design/shots.mjs` warns that Edge can sign a fresh profile into the OS account on its own. The probe runs here (a throwaway profile, `--disable-sync`, headless) showed no sign-in prompt, the profile is deleted on every exit path, and Edge is reached only when Chrome and Chromium are absent. An operator who objects sets `PROOF_CAPTURE_BROWSER`.
- DEC-I: the module's env vars (`PROOF_CAPTURE_*`) get no rows in `module-registry.md`. They are the tool's own contract in its README; a standalone tool does not register its knobs with the kit. The registry gets the stage row and the `modules.proof_capture` key row only.
- DEC-J: the operator's personal walker (multi-step Playwright) stays where it is. It overlaps the page lane for single shots and is the only part of the old engine that clicks; folding or retiring it is the operator's call once a flow verb exists.
- DEC-K: three deviations from ADR-0041 rule 3, all reported to the lead, none fixed in this spec; the ADR amendment is done in `docs/decisions/0041-standalone-doctrine.md`. Item 2: the artifact is an image, so "plain file a person can `cat`" is met only in the weaker form (a plain file with a stated schema: magic bytes and trailer under OUT), because a screenshot cannot be text. Item 4: the ADR says that with the tool deleted the kit's own suites pass except that module's; here `tests/test-kit-contract.sh` goes red by design, because C3 and C4 require every declared module to have a home. Item 3: the kit side is the shim and the row plus a third integration point, `_proof_visual_capture` in `lib/gate/proof-gate.sh`, which tests an inner module path (`lib/proof-capture/bin/proof-capture`) so the gate can tell a deleted module from a present one. The ADR wording now admits all three.
- DEC-L: the reap never kills by name or pattern. It signals the process group the tool created, by the pid it recorded (bash job control gives the group id), TERM then KILL after 2 s, and KILL at once on an interrupt. Why: this host runs other sessions' browsers and test apps, and `pkill -f` on a profile path, though unique, is a name-based kill and a bad habit to ship; a process-table walk hung under load (Grounding 10). Rejected: `pkill -f`, a `ps -A` descendant walk. Residual: a child that leaves the group is not reached (Failure modes).
- DEC-M: the real-browser case is opt-in (`PROOF_CAPTURE_REAL=1`), not "runs when a browser is found". Why: a default suite run must not start a real browser on a loaded host; the builder runs it by hand once for the fixture.
- DEC-N: the gate guards on the shim and on the module entry, and the shim carries one missing-files guard. Why: ADR-0041 item 4 deletes the tool and leaves the adapter; a shim-only guard would advertise a dead command. The `capture:` line carries the literal `$DWARVES_KIT/bin/proof-capture` path, the form the consumer contract prescribes, so it resolves from a consumer repo and puts no home path in output that gets pasted into proofs. The bare `bin/` name was rejected: it does not resolve from a consumer repo.
- DEC-O: a TERM, INT or HUP to the tool reaps and exits 1 (`proof-capture: interrupted`). Why: a caller that times the tool out must not leak a browser.
- DEC-P: the browser writes only into the tool's private 0700 work dir; the artifact reaches `<outdir>` by an exclusive `mktemp` file and a rename. Why: a partial named by pid beside `<out>` is guessable, and a planted symlink there would be written through. `<out>` and `<outdir>` being symlinks are refused.
- DEC-Q: a watchdog (its own recorded group) ends the browser group at deadline plus 5 s, so a KILL sent to the tool no longer leaks a browser that never exits. Cost: one more recorded process and the narrow pid-recycle residual in Failure modes.
- DEC-S: no third validation round. Lead decision after round 2: the round 1 criticals were cleared, round 2 found two criticals with exact fixes (the TERM-ignoring stub and the single-reap rule), both folded here, and the build's own suites and its multi-lens review cover the rest. Consequence: the last validate verdict in the ledger is NEEDS-REVISION, overridden on the lead's decision (not the operator's), and no fresh round has read the round 2 fold.
- DEC-T: changes after the independent security review of the built tool, each with a suite case and a run negative control (see `docs/implementation-notes/visual-proof-module.md`): a reap that finds CPID empty after a launch uses `$!`; the watchdog starts right after the child; the output checks repeat before the temp file and before the rename, and the rename does not follow a symlink; `fail` reaps before it prints and QUIT, USR1, USR2, ALRM and PIPE are trapped; a signal after the rename lets the run finish with exit 0; an `<out>` ending in a slash exits 64; a bare `PROOF_CAPTURE_BROWSER` or `PROOF_CAPTURE_VHS` name is looked up on `PATH`; the no-own-group branch signals the pid only while it is still the tool's child; the browser gets `--use-mock-keychain --password-store=basic`; the suite records each pid with its start time and signals only a pid whose start time still matches. Considered and not added: `--disable-background-networking` and `--disable-component-update`.
- DEC-R: the validity rule is magic plus trailer plus size-stable twice, and for a tape also vhs exit 0. Why: size-equal on two reads alone accepts a writer that paused mid-file.

## Open questions

(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)

## Validation

Pass 0, before any round (the validator's own adversarial read of the first draft against the tree). Fixed in the spec: a name-based kill (`pkill -f`) replaced by an own-process-group reap by recorded pid, with a bash job-control probe and an Edge probe behind it (Grounding 6, 10, 11); the real-browser case made opt-in; a TERM, INT and HUP trap added; a forward dependency between the registry rows and the shim removed; AC to case numbering corrected; the delete test made to cover the ADR-0041 case (tool deleted, shim and row left); wrong line cites fixed (Grounding 9); the exemplar module corrected; the media guard named; the blast-radius checks added as AC15; ADR-0041 replaced the ADR number placeholder here and in the brief, with a five-row module-rules table.

Round 1 (seven fresh reviewers, Sonnet for 1 to 5 and 7, Opus for 6): NEEDS-REVISION, 4 criticals, 21 warnings. Reviewer 5 (design and extensibility; serves N4, modularity), Reviewer 6 (`design-bearing=yes pass`) and Reviewer 7 found no critical.

| Critical | Fix in the spec |
|---|---|
| R1: the partial `.proof-capture.<pid>.png` beside `<out>` is guessable, so a planted symlink is written through | the browser writes only in a private 0700 work dir; the artifact reaches `<outdir>` by an exclusive `mktemp` file and a rename; a symlink `<out>` or `<outdir>` exits 64; AC7 plants one (DEC-P) |
| R2: a KILL to the tool leaves a browser that never exits; the 2 s TERM wait has a race | a watchdog in its own recorded group ends the browser group at deadline plus 5 s; the interrupt path KILLs at once; the reap is idempotent; AC3c and case 12 (DEC-Q, DEC-O) |
| R4: T1 carried 7 acceptance criteria | split into T1 to T4 (skeleton, page, reap, tape), none over 5 |
| R3 and R4: the tenant-word scan ran only in the docs task, but T12 writes proofs with real output | the scan, plus `/Users/`, `/var/folders/`, `/private/`, runs in T12, T13 and `## Verification` over the module and both proof paths; the private repo and browser names were scrubbed from the spec and the brief |

Warnings folded because they were cheap and several reviewers agreed: the `docs/figures` size claim corrected; the post-launch group check made safe for a child that already exited; `$$` and CPID kept apart and the `mktemp -d` template spelled out; the PNG IEND and GIF trailer checks, vhs exit 0 for a tape, and a slow-write stub; the no-inbound-source grep rebuilt on `git grep --no-index` with a planted text built from a variable; the shim lint defined; the candidates seam set in every case so no default run can start a real browser; the operator pin in the route suite; the `capture:` line printed as `$DWARVES_KIT/bin/proof-capture`, with an AC for the module-off case; the kit contract suite named as red by design in the delete-the-tool tree (DEC-K); the `generate` verb; README lines moved to T12 and added (who reruns the real case, tested versions, leftovers); the vhs warning added to the verify step; a hand-run tape deadline check; upper bounds on numbers; negative controls for AC4 and AC7; brief D4 aligned; `lib/decide/flick.sh` cited (Grounding 12); `lib/gate/README.md` in Touches; IN, OUT and EXIT as real README headings; the opt-in case uses `pgrep -g` on a recorded pid.

Rejected: none. One finding was met by a different mechanism than the reviewer proposed: instead of a random `mktemp` partial beside `<out>`, the partial lives in the private work dir (DEC-P), which removes the guessable name entirely.

Round 2 (seven fresh reviewers, re-validating against the round 1 digest and the fold diff): NEEDS-REVISION, 2 criticals, 26 warnings, all from Reviewer 2. Round 1's four criticals were confirmed cleared. Reviewers 5 and 7 and the Reviewer 6 line (`design-bearing=yes pass`) raised no critical.

| Critical | Fix in the spec |
|---|---|
| The TERM-then-KILL escalation had no test: every stub died on TERM, so deleting the KILL step kept all cases green | a `term-ignore` stub mode (child and helper both ignore TERM) in the deadline case (5), the interrupt case (6) and the tape case (9); negative control: remove the KILL step (AC3d) |
| The reap rules contradicted each other, and a second signal during the 2 s wait abandoned the reap | one reap at a time: `reaping` and the saved pids stay set until KILL is sent; while a reap runs the trap only sets `INTR`, and the reap's wait loop goes straight to KILL, then kills the watchdog and removes the work dir; new case 13 (a second TERM 1 s into the wait) |

Warnings folded: case 7's control and discovery rows moved from T1 to T2, the opt-in case 11 given to T2, the FEATURES freshness check moved to T11, T12 split into T12 and T13 with numbered hand steps, T13 ordered after T5; the GUIDE wording reworded so the path scan passes; the T6 dispatch assertion made conditional on the module dir; the after-state example uses a real directory (macOS `/tmp` is a symlink); the final temp file removed by the trap and asserted in the interrupt case, and the copy ordered before the reap removes the work dir; the poll rechecks the partial once after the child is gone, and an empty `ps -o pgid=` means "gone"; the watchdog polls the group each second and exits when it is gone; one shared launch, poll and reap function for page and tape; the tape path made absolute and a leading `-` refused; percent-encoding case; INT and HUP rows; the deadline env range and precedence; parent-directory creation and replace-on-success rows; a negative control for the routing itself; the verify step line "open the image and check it" with a route suite grep (AC16); the README lines on the caller-chosen source URL, size caps and width; a GUIDE debugging line instead of a debug env var; a retire list in the module SPEC.md; DEC-K names the third deviation and the ADR amendment is listed as follow-up; corrected `flick.sh` lines, DEC-H, the brief's line count, numbered route suite cases R1 to R7, the Picture's wiring line, a softer `ttyd` claim, Linux-portable suite calls, and a recorded-pid tape check in place of global `ttyd` counts.

Rejected: none.

Lead decision (DEC-S): no third round. The round 2 fold has not been read by a fresh reviewer. The ledger's last validate verdict is NEEDS-REVISION, overridden on the lead's decision, not the operator's. The build's suites and the build-time multi-lens review are the remaining check, and the builder should treat the reap and the suite cases for it (4, 5, 6, 12, 13) as the part of this spec with the least outside review.
