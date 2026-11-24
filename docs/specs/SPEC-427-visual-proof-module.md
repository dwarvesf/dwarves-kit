# Spec: visual proof capture as a standalone kit module

Generated: 2026-11-25
Status: DRAFT
Lane: full (the diff floor: `lib/gate/proof-gate.sh` and `lib/config/modules.tsv` are enforcement-surface paths; `lane-classify.sh classify` on the task text alone says `normal`, and with `--files` it says `full`)
Depth: standard (every kit surface this touches was read in this tree, and the two capture paths were run on this host; the grounding below holds the output)
Type: spec-feature
Board: ID-395
File: `docs/specs/SPEC-427-visual-proof-module.md`
References: `docs/briefs/DECISION-BRIEF-visual-proof-module.md` (the why, the rejected options, the after-the-move table); `lib/proof/asset.sh` and `bin/proof-asset` (the consumer of the artifact, not edited); `lib/gate/proof-gate.sh` (`_proof_visual_row`, `proof_contract`); `lib/worktree-provision/` (the module dir shape: `bin/`, README, SPEC, `docs/proof-of-done.md`, `tests/`); `tests/test-proof-visual-gate.sh` (the temp-repo gate fixture to copy); `docs/reference/kit-contract.md` (C1 to C10, closed verbs); ADR-NNNN (standalone doctrine, the lead fills in the number).

## Problem

The kit can ask for visual proof and can store it, but cannot make it. With `[proof] visual` on, `proof-gate.sh contract` names the artifact a task owes ("before + after screenshots, desktop and 400px") and `/kit:verify` Step 7b says "capture", then hands the image to `bin/proof-asset put`. Nothing in the kit produces the image. `docs/verification/README.md` line 96 says so: until a producer lands, a hand-recorded capture satisfies the contract. The only capture engine is outside the kit: a prose skill and a 69-line Node walker in the operator's dotfiles, bound to a personal browser.

Target (the pack's one line): proof-capture exists as a kit module; it is standalone-capable; the proof contract routes visual work to it; a fixture PR shows a screenshot or GIF in its proof.

Already shipped, not rebuilt: the knob, the gate's image rules, `bin/proof-asset`, the `wrap land` flush, the runs dashboard. The gap is the producer and its route. See the brief for the table.

## Terms

- proof-capture: the module this spec adds, `lib/proof-capture/`. A producer of one image or GIF file. It stores nothing and reads no kit config.
- artifact: the file `run page` or `run tape` writes. Its schema is its magic bytes, and it is the module's whole API.
- shim: `bin/proof-capture`, one `exec` line, no logic.

## Solution

### Approaches considered

| Approach | Verdict |
|---|---|
| A. A bash tool in its own directory: Chrome's own `--headless=new --screenshot` for pages, `vhs` for terminal GIFs; a shim, one registry row, one added contract line | chosen |
| B. Port the Node walker and Playwright | rejected: a Node and Playwright dependency for 69 lines, and its default browser is personal |
| C. A Node CDP driver like `lib/system-design/shots.mjs` | rejected: a second headless driver and Node in `lib/` for no gain over the browser's own flag |
| D. Add a `capture` verb to `bin/proof-asset` | rejected: `proof-asset` sources `kit-config.sh` and needs a git repo; the capture must run with neither |

### Chosen approach + why

A. One dependency per verb, readable in 30 seconds, copyable out of the kit. The cost is real: Chrome's `--screenshot` cannot click, so a scripted multi-step flow is not in v1.

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
                |-- capture: bin/proof-capture run page|tape  |
                |     only when: knob on AND bin/proof-capture exists AND the row has a verb
                v                                             |
 /kit:verify Step 7b --> bin/proof-capture (1 exec line) -----+--> lib/proof-capture/bin/proof-capture
                                                              |      run page: browser --headless=new --screenshot
                                                              |                (own profile, deadline, kill, rename on success)
                                                              |      run tape: vhs -o <out.gif> <file.tape>
                                                              |
        out.png | out.gif  <-----------------------------------+------ the artifact (the only interface)
                |
                v
 bin/proof-asset put <slug> <file> --> assets.json --> proof-ledger.sh check (unchanged)
```

The module has no arrow into the kit. Delete the left half and the tool still runs. Delete the right half and the left half loses one line of output.

## Design

Design-bearing: a new module, a process lifecycle that must not leak, and an interface other code reads. Approaches and the chosen one are in `## Solution`. ADR: the standalone doctrine, ADR-NNNN (the lead fills in the number); this module is its pilot and records no ADR of its own.

The `run page` lifecycle (the part a builder gets wrong):

```
 run page <src> <out.png> [flags]
    |
    +-- bad verb, bad flag, missing file, bad scheme -----------------> exit 64
    +-- no browser (or PROOF_CAPTURE_BROWSER not executable) ---------> exit 69
    |
    mktemp -d profile (own throwaway profile); partial = <outdir>/.proof-capture.<pid>.png
    start browser in the BACKGROUND:
        --headless=new --disable-gpu --no-first-run --disable-sync --disable-extensions --hide-scrollbars
        --user-data-dir=<profile> --window-size=<w>,<h> [--virtual-time-budget=<ms>] --screenshot=<partial> <url>
    poll every 0.2 s until the deadline (default 45 s):
        partial is a valid PNG and its size is equal on two reads 0.3 s apart ----> done
        browser pid gone and no valid partial ----------------------------------> fail
    reap, always: kill <pid>; pkill -f -- "--user-data-dir=<profile>"; wait; remove <profile>
    done: mv partial -> <out> ; print "proof-capture: wrote <out> (<n> bytes)" ; exit 0
    fail: remove partial ; one stderr line ; exit 1      (an existing <out> is left untouched)
```

Success is the file on disk, never the browser's exit: two browsers probed on this host write the PNG in about 2 s and then never exit.

`run tape` has the same shape with `vhs` in place of the browser: vhs writes `-o <outdir>/.proof-capture.<pid>.gif`; success is a valid GIF (`GIF8` magic, size > 0, size equal on two reads); at the deadline the tool sends TERM to the vhs pid, then KILL after 2 s; the partial is renamed to `<out>` on success and removed on failure. vhs starts `ttyd` and a browser of its own: the tool does not claim to reap them, and `GUIDE.md` tells a user to check `pgrep ttyd` after a killed run.

### Boundaries & failure modes

Out of bounds: kit config, git, the live desktop, any network call the tool makes itself (the browser may load the URL the caller gave). See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

This is the contract block `lib/proof-capture/README.md` carries, verbatim in shape. It is the module's API; a consumer reads the artifact, never the script.

```
proof-capture run page <src> <out.png> [--width N] [--height N] [--wait MS] [--deadline S]
proof-capture run tape <file.tape> <out.gif> [--deadline S]

IN
  argv only. No stdin. No config file.
  <src>        a file path, or an http://, https:// or file:// URL. Any other scheme exits 64.
  --width N    viewport width in px, default 1280.   --height N   default 800.
  --wait MS    let the page run MS ms of virtual time before the shot (maps to --virtual-time-budget); default none.
  --deadline S seconds to wait for a valid artifact; default 45 for page, 120 for tape.
  env PROOF_CAPTURE_BROWSER  path to a Chromium-family browser; set means use it or fail, never fall back.
  env PROOF_CAPTURE_VHS      path to vhs; same rule.
  env PROOF_CAPTURE_DEADLINE seconds; the flag wins.
  Browser discovery when unset, first hit wins: google-chrome, chromium, chromium-browser, microsoft-edge on PATH;
  the Google Chrome, Chromium and Microsoft Edge app paths on macOS. Brave is not listed (see Grounding).

OUT
  <out> is written only when valid: PNG magic 89504E470D0A1A0A for page, GIF magic "GIF8" for tape, size > 0.
  A parent directory that does not exist is created. A failed run leaves any existing <out> untouched.
  stdout, one line:  proof-capture: wrote <out> (<n> bytes)
  stderr: diagnostics, one line per fault. No sidecar file, no state, nothing under ~/.

EXIT
  0   artifact written and valid
  1   capture failed: no valid artifact before the deadline, the browser or vhs exited without one
  64  usage or bad input: unknown verb, missing argument, unknown flag, input file missing, bad scheme
  69  a required dependency is missing: no browser for page, no vhs for tape
```

Exact one-line messages (the suite greps them):

- no browser: `proof-capture: no Chromium-family browser found; install Chrome, Chromium or Edge, or set PROOF_CAPTURE_BROWSER=<path>`
- bad `PROOF_CAPTURE_BROWSER`: `proof-capture: PROOF_CAPTURE_BROWSER is not an executable file: <value>`
- no vhs: `proof-capture: vhs not found; install it (brew install vhs) or set PROOF_CAPTURE_VHS=<path>`
- deadline: `proof-capture: no valid artifact within <S>s`

`run tape` runs the commands in the tape as the invoking user. README says so: never run a tape you did not read.

Routing, in `lib/gate/proof-gate.sh` (the only kit logic this spec adds):

```bash
_proof_visual_capture() {                      # <row> -> the capture command, or nothing
  [ -x "$LIB_ROOT/../bin/proof-capture" ] || return 0
  case "$1" in
    "ui page") echo "bin/proof-capture run page <page.html|url> <out.png> --width 1280 (then --width 400 for the narrow shot)" ;;
    "tui")     echo "bin/proof-capture run tape <demo.tape> <out.gif>" ;;
  esac
}
```

`proof_contract` prints `capture: <that>` on the line after `visual:` only when the function prints something. The `visual:` text is untouched. Rows "ui flow", "bot message", "report", "generated file" and "none" print no `capture:` line.

Invariants: with `[proof] visual` off, `contract` output is byte-identical to master; `proof-ledger.sh` is not edited; the module never reads a kit file; `bin/proof-capture` holds one `exec` and nothing else.

### Data model changes

None. The artifact is a file; the manifest `proof-asset` writes is unchanged.

### API changes

`proof-gate.sh contract` gains one optional line. Nothing else changes for a caller.

### UI changes

None.

### Infrastructure changes

None. No hook, no daemon, no launchd, no CI workflow, no network call from the tool. A new opt-in module row only: `proof_capture`, off by default, no hooks, one CLI.

## Task Breakdown

Order matters: T1 before T2 to T6 (everything wraps the entry); T4 before T5 (the routing check reads the shim); T9 needs T1 and T4 (it runs the real capture through the shim); T10 last.

### Phase 1: The module

- [ ] T1: The entry and its suite. Files: `lib/proof-capture/bin/proof-capture`, `lib/proof-capture/examples/hello.html`, `lib/proof-capture/examples/hello.tape`, `lib/proof-capture/tests/test-proof-capture.sh`. Write the entry per `## Design` and the contract; the suite defines its own stub browser and stub `vhs` (a bash script that records its argv to a file, then acts per `STUB_MODE`: `ok`, `write-then-hang`, `never-write`, `exit-no-file`) and its own `ok`/`bad` helpers, and sources nothing from the kit. Check: `bash lib/proof-capture/tests/test-proof-capture.sh` ends `ALL PASS`; AC1 to AC7 and their negative controls.
- [ ] T2: Module docs. Files: `lib/proof-capture/README.md` (the contract block from Interfaces, the dependency table, the never-run-an-unread-tape note, a three-line "run it alone" example), `lib/proof-capture/GUIDE.md` (the neutral craft only: storyboard first with one story under 30 s; the frame check, which is open the image and look for the right content and a leak of paths, hostnames, tokens or names before committing; one story per capture; a note that user theme fidelity means the page or terminal is in the real theme, no tool default; the three gotchas below), `lib/proof-capture/SPEC.md` (a one-page interface spec, a pointer to this spec for the build story). Gotchas allowed in GUIDE: a browser can write the file and never exit (the tool kills it); `/tmp` and `/private/tmp` differ on macOS, so pass real paths; a locale without UTF-8 turns box-drawing glyphs into bytes in a tape, so set `LANG` on the tape's first line. No tenant words (herdr, one-dark, localterm, hermes, a personal browser name). Check: `grep -c '^IN$' lib/proof-capture/README.md` prints 1 and the same for `^OUT$` and `^EXIT$`; a grep for the tenant words over the dir prints nothing.

### Phase 2: Kit integration (thin)

- [ ] T3: Registry rows. Files: `lib/config/modules.tsv` (one row: `proof_capture`, `opt-in`, `-`, `proof-capture`), `kit.toml` (`proof_capture = false` under `[modules]`, comment: hookless, exposes the proof-capture CLI), `lib/config/module-registry.md` (stage Build (Execute); bump the module count text to match the table). Check: `bash tests/test-modules-table.sh` and `bash tests/test-config-registry.sh` pass; a fresh adopt does not turn it on (`tests/test-adopt.sh` stays green, since it reads the table).
- [ ] T4: The shim and its census. Files: `bin/proof-capture` (three lines: shebang, `SELF_DIR`, `exec "$SELF_DIR/../lib/proof-capture/bin/proof-capture" "$@"`, exec bit set), `tests/test-bin-forwarders.sh` (add `proof-capture` to the `EXPECTED` census), `tests/test-install-clis.sh` (add it to the module CLI loop if that loop names module CLIs). Check: `bash tests/test-bin-forwarders.sh`, `bash tests/test-install-clis.sh`, `bash tests/test-kit-contract.sh` (C2 wiring, C3 needs T2 and T9 done, so read C3 last).
- [ ] T5: Routing. Files: `lib/gate/proof-gate.sh` (the function above and a four-line addition to `proof_contract`), `tests/test-proof-contract-visual.sh` (new cases: knob on and "redesign the settings page UI" gives a `capture:` line with `run page` and the `visual:` line unchanged; a TUI task gives `run tape`; a bot-message task gives no `capture:`). Check: `bash tests/test-proof-contract-visual.sh` ends all pass, including the existing case 21 and case 22 unchanged.
- [ ] T6: Kit-side suite. Files: `tests/test-proof-capture-route.sh`, `bin/test-affected.timeouts` (only if the suite needs more than the default). Cases: the delete-the-tool tree (AC10), the end-to-end fixture repo (AC11), the module-dir-has-no-kit-reference lint with a planted violation (AC7), the install census line. Model the temp tree on case 22 of `tests/test-proof-contract-visual.sh` (copy `proof-gate.sh`, `proof-classes.sh`, `proof-classes.tsv` into a temp `lib/gate/`, symlink the other lib subdirs and `docs` except `proof-capture`, leave the temp `bin/` without the shim) and the temp repo on `tests/test-proof-visual-gate.sh`. Check: `bash tests/test-proof-capture-route.sh`.

### Phase 3: Say it exists, then prove it

- [ ] T7: Docs that say the producer exists. Files: `commands/verify.md` (Step 7b: name `bin/proof-capture run page|tape` as the capture, then `bin/proof-asset put`; a page flow or a generated file with no verb is captured by hand as today), `docs/verification/README.md` (replace the "producer is the visual-proof module ... until it lands" paragraph with the real command and what is still by hand), `docs/reference/tiers.md` (the row that says queued, line 53). Check: `bash tests/test-proof-contract-visual.sh` (its R10 case greps `verify.md`) and `bash tests/test-meta-docs-registry.sh`.
- [ ] T8: Surface lists. Files: `docs/reference/install.md` (module table row), `docs/reference/project-structure.md` and `docs/reference/consumer-contract.md` (the module-CLI lists), `lib/README.md` (a `proof-capture/` row next to `proof/`). Check: `bash tests/test-meta-docs-registry.sh`.
- [ ] T9: The fixture and the module's proof. Files: `docs/verification/visual-proof-module.md`, `docs/verification/visual-proof-module/page.png`, `lib/proof-capture/docs/proof-of-done.md`, `CHANGELOG.md`. Capture with the real browser: `bin/proof-capture run page lib/proof-capture/examples/hello.html docs/verification/visual-proof-module/page.png --width 800 --height 500`; open the PNG and read it (do not trust the byte count); write the verified-content line; embed it with a relative link, `![page fixture](visual-proof-module/page.png)`; also run `run tape` on `examples/hello.tape` and quote its output line (the GIF is not committed); put the real captured output, a run-table and one negative control in `proof-of-done.md`. Check: `bash lib/gate/proof-ledger.sh images docs/verification/visual-proof-module.md .` prints one line whose path exists; `wc -c docs/verification/visual-proof-module/page.png` is under 102400.
- [ ] T10: Whole-change check. Files: none. Run `bash tests/test-kit-contract.sh` (C3 now sees the proof-of-done), then `bash tests/run-all.sh --changed --time` once.

## After state

- [ ] `bash lib/proof-capture/bin/proof-capture run page lib/proof-capture/examples/hello.html /tmp/x.png --width 800 --height 500` exits 0 and `/tmp/x.png` is an 800 by 500 PNG. (Today: no such command.)
- [ ] The module dir runs with no kit: copied to a temp path outside any repo, its suite passes under `env -i`. (Today: no module.)
- [ ] With `[proof] visual` on, `proof-gate.sh contract "redesign the settings page UI"` prints a `capture:` line naming `run page`, and the `visual:` line is byte-identical to today's. With the knob off, the output is byte-identical to today's. (Today: the artifact is named, the way to make it is not.)
- [ ] The tree without `bin/proof-capture` still passes `contract` and prints no `capture:` line. (Today: not applicable.)
- [ ] This spec's own PR proof, `docs/verification/visual-proof-module.md`, embeds a committed PNG that exists in the tree, is under 100 KB, and shows the fixture page. (Today: a proof of this kind carries only a table.)
- [ ] `proof_capture` is a row in `modules.tsv` with default `opt-in`, `false` in `kit.toml`, a stage in the registry, and `bin/proof-capture` in the census. (Today: none.)

## Quality requirements

none

## Acceptance Criteria (global)

| AC | Check | Negative control |
|---|---|---|
| AC1 `run page` writes a valid PNG for a file and for an `http://` URL (stub browser), and the real-browser case checks the IHDR width and height equal the flags | suite cases 1 to 2 | the stub exits 0 with no file: the run exits 1 and `<out>` is absent |
| AC2 headless and throwaway: the browser argv holds `--headless=new` and a `--user-data-dir` under `TMPDIR` that no longer exists after the run; nothing but the named `<out>` is left behind (no `.proof-capture.*` partial) | suite case 3 (stub records argv) | mutate the entry to drop `--headless=new`: case 3 fails |
| AC3 a browser that writes the file and never exits: the run returns 0 within deadline plus 3 s and the stub process is gone (`pgrep -f` the profile finds nothing) | suite case 4 | delete the `pkill` line: case 4 fails on the leftover process |
| AC4 deadline: a browser that never writes: exit 1 at the deadline, the exact message, no `<out>`, an existing `<out>` unchanged | suite case 5 | none needed beyond the case itself |
| AC5 missing dependency, never a pass: `PROOF_CAPTURE_BROWSER=/nonexistent` exits 69 with the exact message and no artifact; `PROOF_CAPTURE_VHS=/nonexistent` exits 69 | suite case 6 | the same call with a valid stub exits 0, so the 69 is caused by the dependency |
| AC6 `run tape`: stub vhs gets `-o <out> <tape>`, writes a GIF, exit 0; stub exits 0 without a file: exit 1; GIF magic is checked | suite cases 7 to 8 | a stub that writes a non-GIF file: exit 1 |
| AC7 usage: no args, unknown verb, unknown flag, missing input file, a `javascript:` or `chrome:` scheme: exit 64 each, nothing written | suite case 9 | none needed |
| AC8 standalone: the module dir copied to a temp path outside any git repo passes its own suite under `env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin`; a lint finds no `DWARVES_KIT`, `kit-config` or `../../` in the module's executable | route suite | plant `source ../../config/kit-config.sh` in the copy: the lint fails |
| AC9 routing: knob on, module present: a UI task prints `capture:` with `run page`, a TUI task prints `run tape`, a bot-message task prints none, and the `visual:` line is byte-identical to master's | `tests/test-proof-contract-visual.sh` | change the frozen `visual:` text: the existing case 21 fails |
| AC10 both delete tests: knob off, output byte-identical to master (existing case 22); tree without `bin/proof-capture`, knob on: `contract` exits 0, same `visual:` line, no `capture:` line | contract suite and route suite | remove the `[ -x ... ]` guard: the no-module case prints a `capture:` line and fails |
| AC11 end to end in a hermetic repo with the knob on: a stub capture, `bin/proof-asset put`, the embed in a proof file: `proof-ledger.sh check` passes; remove the image: it BLOCKS with the visual message | route suite | the removal is the control |
| AC12 registry: `proof_capture` is `opt-in` in `modules.tsv`, `false` in `kit.toml`, present in the registry and the `bin/` census; kit contract C1 to C10 pass | `test-modules-table.sh`, `test-bin-forwarders.sh`, `test-kit-contract.sh` | a row with a bad default fails the table suite |
| AC13 fixture: the proof embeds a committed PNG that exists and is under 100 KB; the reader opened it and the verified-content line says what it shows | `proof-ledger.sh images` and `wc -c` | point the link at a missing file: `images` prints nothing |
| AC14 no regression | `bash tests/run-all.sh --changed --time` | not applicable |

Every behavior change owes a negative control run: break the code, watch the named test fail, restore, and quote the failing line in `docs/verification/visual-proof-module.md`.

## Verification

```bash
bash lib/proof-capture/tests/test-proof-capture.sh
bash tests/test-proof-capture-route.sh
bash tests/test-proof-contract-visual.sh
bash tests/test-modules-table.sh
bash tests/test-bin-forwarders.sh
bash tests/test-kit-contract.sh
T="$(mktemp -d)" && cp -R lib/proof-capture "$T/pc" && (cd "$T" && env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin bash "$T/pc/tests/test-proof-capture.sh")
bin/proof-capture run page lib/proof-capture/examples/hello.html /tmp/proof-capture-check.png --width 800 --height 500
bash lib/gate/proof-ledger.sh images docs/verification/visual-proof-module.md .
bash tests/run-all.sh --changed --time
```

The real-browser case inside the first suite reports `SKIP` (counted, never a pass) where no browser is found. On the build host it must run and pass; the proof file quotes it.

## Edge Cases

1. `<src>` is a relative path: resolve it to an absolute `file://` URL from the caller's cwd before launch. A path with spaces or `#` is percent-encoded.
2. `<out>` exists already: replaced only on success.
3. `<out>` parent missing: created. `<out>` is a directory: exit 64.
4. `--width` or `--height` not a positive integer: exit 64.
5. Two captures at once: each has its own profile and partial name, so they do not collide.
6. The page needs JavaScript time: `--wait 3000` gives it virtual time; without it the shot is of the first paint.
7. `TMPDIR` unset: `/tmp`. The profile is removed on every exit path, including a deadline.
8. A browser that prints errors to stderr (the CVDisplayLink lines seen in the probe) is silenced; the tool prints only its own one-line faults.
9. `run tape` with a tape that declares its own `Output`: the `-o` flag adds the partial path; only the partial is checked and renamed to `<out>`. Any other output the tape declares is vhs's and is not touched.
10. A `PROOF_CAPTURE_BROWSER` that is a stub script: used as is; this is the seam the suite uses.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Browser writes the file and never exits (seen on two browsers) | the poll sees a valid PNG while the pid is alive | success is the file; kill the pid and the helpers matched by `--user-data-dir`; AC3 |
| Browser never writes (seen with Brave) | deadline reached | exit 1, one line, no artifact; the discovery list leaves Brave out |
| Helpers outlive the main process | `pgrep -f` the profile path | `pkill -f -- "--user-data-dir=<profile>"` on every exit path |
| Partial or torn PNG | magic bytes ok, size still changing | require equal size on two reads 0.3 s apart; the file lands under `<out>` only by rename |
| A dependency is missing | `command -v` or an explicit env path fails | exit 69 with the exact line; never exit 0; never fall back from an explicit path |
| The tape hangs | deadline reached | TERM the vhs pid, then KILL after 2 s; exit 1 |
| A killed vhs leaves `ttyd` or its browser running | `pgrep ttyd` after a deadline exit | not reaped by the tool (not sampled here); GUIDE.md names the check; the suite uses a stub vhs, so it cannot leak |
| The capture shows a secret or a personal path | a human reading the frame | GUIDE.md frame check; the proof's verified-content line must say what was checked |
| A drift between the routing case and the module's verbs | AC9 | the route test greps `run page` and `run tape` from the contract output and runs those exact argv shapes against the stub |

## Out of Scope

- `run flow`, a scripted multi-step page walk ending in a GIF. Named as the next verb; Chrome's `--screenshot` cannot click. The "ui flow", "report" and "generated file" rows keep their artifact text and get no `capture:` line.
- Any lane that drives the live desktop or one platform: macOS window recording, keycastr, a real Terminal window, the simulator route. They stay in the operator's personal skill.
- Linux and containers: not claimed. The discovery list names Linux binaries; nothing here ran there.
- Upload to a bucket. `proof-asset` owns that and is not edited.
- Turning `[proof] visual` on for any repo, and any change to `proof-ledger.sh check`.
- Any edit to `hooks/ship-gate.sh`, `lib/classify/`, or `lib/adopt*`.
- The ops-toolkit and dotfiles changes (listed in the brief, D7). A later, separate PR in each repo.
- Pointing `lib/system-design/shots.mjs` at this module. It needs CDP to pull SVG out of a built sheet; it stays as is.

## Touches

- lib/proof-capture/**
- bin/proof-capture
- lib/gate/proof-gate.sh
- lib/config/modules.tsv
- lib/config/module-registry.md
- kit.toml
- commands/verify.md
- docs/verification/README.md
- docs/verification/visual-proof-module.md
- docs/verification/visual-proof-module/**
- docs/reference/tiers.md
- docs/reference/install.md
- docs/reference/project-structure.md
- docs/reference/consumer-contract.md
- lib/README.md
- tests/test-proof-capture-route.sh
- tests/test-proof-contract-visual.sh
- tests/test-bin-forwarders.sh
- tests/test-install-clis.sh
- bin/test-affected.timeouts
- CHANGELOG.md

## Grounding

Read live on 2026-11-25 on the build host (macOS, bash 3.2, node 22). Each line is a command and what it printed. Output trimmed; no credential-shaped value appears.

1. Browser, Helium (not in the discovery list; set by `PROOF_CAPTURE_BROWSER`): `Helium --headless=new --disable-gpu --no-first-run --disable-sync --disable-extensions --hide-scrollbars --user-data-dir=<tmp> --window-size=800,500 --screenshot=out.png file://.../hello.html`. Result: `out.png: PNG image data, 800 x 500, 8-bit/color RGB` (12890 bytes) written within seconds, and the command did not return within 120 s; a renderer helper carrying the same `--user-data-dir` was still running. `pkill -f <profile>` ended it. The `timeout` in the shell was an alias for `gtimeout`.
2. Browser, Microsoft Edge: the same flags. `out.png` valid, 800 x 500, 12890 bytes after about 2 s; the browser pid was still alive afterwards.
3. Browser, Brave: the same flags, run twice, 20 s then 40 s. No PNG written; the browser stayed alive; stderr held `CVDisplayLinkCreateWithCGDisplay failed` lines. This is why Brave is not in the discovery list.
4. Chrome and Chromium are not installed on this host, so the discovery entries for them are the reference behavior of the flag, not a run here; the build's real-browser case runs on whatever the discovery list or `PROOF_CAPTURE_BROWSER` finds and the proof says which browser it was.
5. `vhs --version` printed `vhs version 0.12.1`; `ttyd` and `ffmpeg` on PATH. `vhs -o <abs>/o2.gif demo.tape` exited 0 and wrote a 9486-byte file whose first bytes are `GIF89a`. A bare `vhs demo.tape` also exited 0 (9761 bytes). Neither opened a window.
6. `command -v setsid` printed nothing (absent on macOS). `pkill` is present. This is why the lifecycle uses `pkill -f` on the profile path and not a process group.
7. Kit sources read: `lib/gate/proof-gate.sh` lines 107 to 165 (`_proof_visual_row`, `_proof_visual_artifact`, `proof_contract`), `tests/test-proof-contract-visual.sh` (case 21 greps `^visual:`, case 22 compares a knob-off contract with master's), `lib/wrap/wrap-land.sh` lines 190 to 216 (a relative committed image becomes an absolute URL pinned to the head), `tests/test-kit-contract.sh` (C3 needs `README.md`, a spec and `docs/proof-of-done.md` per module; C4 needs a test), `tests/test-bin-forwarders.sh` line 41 (the `bin/` census).

Dry trace for the negative control of AC3: mutation = delete the `pkill -f -- "--user-data-dir=..."` line in the reap step; the suite's `write-then-hang` stub is a `sleep 300` child started with the same `--user-data-dir` argument; with the line gone the child survives the run; case 4 asserts `pgrep -f -- "--user-data-dir=$PROFILE"` finds nothing, so it goes red.

## Decision Log

- DEC-A: the module is a directory under `lib/` with its own `bin/`, README, SPEC, proof-of-done and tests, plus a kit shim in `bin/`. Why: that is the shape the kit contract (C2 to C4) already checks, and the directory is the copyable unit. Rejected: extending `lib/proof/`, which needs the kit.
- DEC-B: bash and Chrome's own `--screenshot`, no Node. Why: one dependency, and PHILOSOPHY holds the kit to bash. Rejected: Playwright, a CDP driver.
- DEC-C: verbs `run page` and `run tape`. Why: kit contract I4 closes the verb list to `run`, `show`, `propose`, `promote`, `trace`. Rejected: `shot` and `gif`, which are synonyms of `run`.
- DEC-D: routing is a separate added line gated on a file test, not an edit to the `visual:` text and not a read of `[modules]`. Why: the frozen text keeps its pinning tests, and the manifest is never read at run time. Rejected: a `route` verb.
- DEC-E: the fixture image is committed (one PNG, about 13 KB), not uploaded. Why: an upload reaches a real service, and the repo already commits small rendered figures. Open PR 1086 does the same with four PNGs; it is precedent in flight, not a settled rule.
- DEC-F: Brave is left out of the discovery list. Why: no output in 40 s on this host. An operator can still name it in `PROOF_CAPTURE_BROWSER`.
- DEC-G: lane `full`. Why: the diff floor, not the task text.

## Open questions

(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
