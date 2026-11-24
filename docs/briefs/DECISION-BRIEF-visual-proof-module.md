# Decision brief: visual proof as a standalone kit module

**Status:** DECIDED. Nothing is built. The build spec is `docs/specs/SPEC-427-visual-proof-module.md`.
**Question:** board row ID-395 says visual proof must be kit machinery, and the pilot for standalone packaging. The brief it cites (`DECISION-BRIEF-standalone-packaging.md`) was never written, and the packaging row ID-396 was dropped. This brief replaces both pointers. What is left to build, and how does it fit the standalone doctrine?
**Doctrine:** ADR-0041 (`docs/decisions/0041-standalone-doctrine.md`). Three rules: the kit ships neutral defaults; user data lives outside the code; a module runs standalone and composes when co-installed. This module is the pilot.

## Verified current state

The pack's one-line target, part by part, read against this tree (master at `3eb93852`):

| Part of the target | State | Evidence |
|---|---|---|
| `proof-capture` exists as a kit module | not shipped | no `lib/proof-capture/`, no `bin/proof-capture`, no `modules.tsv` row |
| it is standalone-capable | not shipped | nothing to be capable yet |
| the proof contract routes visual work to it | half shipped | `proof-gate.sh contract` prints a `visual:` line (the artifact owed) when `[proof] visual` is on, but names no command; `commands/verify.md` Step 7b says "capture" with no tool; `docs/verification/README.md` line 96 says "until it lands, a hand-recorded capture satisfies the contract" |
| a fixture PR shows a screenshot or GIF in its proof | not shipped as a producer proof | the gate accepts images (R3a uploaded, R3b committed, R3c local); open PR 1086 commits four PNGs by hand under `docs/verification/system-design-c4/` |

Already shipped and reused as is (zero edits): the opt-in knob and its three image rules in `proof-ledger.sh check`; `bin/proof-asset put|flush` (convert, 300 KB cap, manifest, optional bucket); `wrap land` flush and its rewrite of a relative image link to an absolute URL in the PR body; the runs dashboard that renders captures; ADR-0026 table-first proof. `lib/system-design/shots.mjs` is a doc renderer (Node plus CDP, needs a built HTML sheet), not a proof capturer.

The engine outside the kit:

| Where | What it really is |
|---|---|
| operator tooling repo `experiments/proof-capture/` | a README (status parked) and one sample, `samples/web-localterm/`: a 9 KB Playwright spec, notes, and about 6 MB of recorded media. No tool. |
| operator tooling repo SPEC-126, its brief, implementation notes | the convention: the artifact class, an environment matrix, four invariants, a gotcha table. Terminal and web lanes proven, macOS GUI designed only. |
| operator skills repo `home/dot_claude/skills/proof-capture/` | the live engine: `private_SKILL.md` (248 lines of recipes) and `walk.mjs` (69 lines of Node: `playwright-core`, a personal browser path as default). |

So the engine is prose plus one 69-line walker bound to a personal browser. There is no code to lift. The kit needs one small producer and one route, not a port.

**The gap is small:** a producer (one bash entry, two verbs, a few hundred lines), its module docs and tests, one registry row, one shim, one added contract line, and the doc edits that say the producer now exists. Every other part of the target is already in the tree.

## Decisions

**D1. Boundary and name.** Module `proof_capture` (the table key), directory `lib/proof-capture/`, stable entry `lib/proof-capture/bin/proof-capture`, kit shim `bin/proof-capture`. Named for the function (kit-fold rule), no host prefix. It is separate from `lib/proof/` on purpose: `lib/proof/asset.sh` sources `kit-config.sh` and needs a git repo, so it can never be copied out alone. The two compose through the artifact (a PNG or GIF file) in `commands/verify.md` Step 7b: capture, then `bin/proof-asset put`. Neither calls the other.

**D2. Verbs (kit contract I4, closed vocabulary).** `run page <src> <out.png>` and `run tape <file.tape> <out.gif>`. Nothing else in v1. Contract block (full text in the spec):

| | |
|---|---|
| IN | argv only; no stdin. `<src>` is a file path or an `http(s)://` or `file://` URL. Flags `--width`, `--height`, `--wait`, `--deadline`. Env `PROOF_CAPTURE_BROWSER`, `PROOF_CAPTURE_VHS`, `PROOF_CAPTURE_DEADLINE`, and `PROOF_CAPTURE_BROWSER_CANDIDATES` (replaces the discovery list; the seam that makes "no browser" testable on a host that has one). |
| OUT | the artifact file (PNG for `page`, GIF for `tape`, checked by magic bytes, never empty) and one stdout line `proof-capture: wrote <out> (<n> bytes)`. No sidecar, no state, no config. |
| EXIT | 0 artifact written; 1 capture failed (no valid artifact before the deadline); 64 usage or bad input; 69 a required dependency is missing. |

**D3. Dependencies and what a missing one does.**

| Verb | Needs | If missing |
|---|---|---|
| `run page` | a Chromium-family browser | exit 69, one line: `proof-capture: no Chromium-family browser found; install Chrome, Chromium or Edge, or set PROOF_CAPTURE_BROWSER=<path>`. An explicit `PROOF_CAPTURE_BROWSER` that is not executable also exits 69 and never falls back. |
| `run tape` | `vhs` (brings `ttyd` and `ffmpeg`) | exit 69, one line naming `vhs` and `brew install vhs`. A failure inside vhs exits 1 with vhs's own last line. |

No Node, no Python, no Playwright, no jq. Bash 3.2 and POSIX coreutils; no `pkill`, `killall` or process-table scan. Why bash and not the Node walker: Chrome's own `--headless=new --screenshot` does the job with one dependency; a page flow with clicks is out of v1 (see D8). Why `PROOF_CAPTURE_BROWSER` is honest: browsers differ in what they do headless. Probed on this host (Grounding in the spec): Edge and a third Chromium-family browser write the PNG in about 2 s and then never exit; Brave wrote nothing in 40 s. So the discovery list is Chrome, Chromium, Edge only (Edge ran here; Chrome and Chromium did not, and the spec's Depth line names that), Brave is left out, and the tool judges success by the file on disk, not by browser exit: it polls for a valid PNG, then ends the browser's own process group (the tool starts it under bash job control, so the group id is the pid it recorded; TERM, then KILL after 2 s) and removes its throwaway profile. It never kills by name, never depends on `timeout` (a `gtimeout` alias on macOS) or `setsid` (absent on macOS).

**D4. Routing.** When `[proof] visual` is on and both the module's shim (`bin/proof-capture`) and its entry (`lib/proof-capture/bin/proof-capture`) are executable, `proof-gate.sh contract` adds one line after `visual:`: `capture: $DWARVES_KIT/bin/proof-capture run page ...` for the "ui page" row, `capture: $DWARVES_KIT/bin/proof-capture run tape ...` for the "tui" row, nothing for every other row (a bot message in a test channel is not headless-capturable; "ui flow", "report" and "generated file" have no verb yet). The `visual:` text is frozen and stays byte-identical, so the tests that pin it hold. The two guards are file tests (a shim whose module dir was deleted must not advertise a dead command), the command carries the literal `$DWARVES_KIT/bin/` prefix so it resolves from a consumer repo, and the line does not depend on the `[modules]` toggle; not a read of the `[modules]` manifest (the manifest is an install record, never read at run time).. Knob off: nothing changes, byte for byte (the existing case 22 pins it). Module deleted: the line is simply absent. No edit to `proof-ledger.sh check`, so no repo that passes the push gate today can fail it.

**D5. Standalone proof.** The module dir is the unit: `bin/`, `README.md`, `GUIDE.md`, `SPEC.md`, `docs/proof-of-done.md`, `tests/`, `examples/`. Its own suite uses stub browsers and stub `vhs` through the same seams a user has (`PROOF_CAPTURE_BROWSER`, `PATH`), so it runs where no browser exists. Standalone check, exact: copy the dir to a temp path outside any git repo and run its suite under `env -i` (no `DWARVES_KIT`, no kit on `PATH`). A grep lint inside the suite fails on any `DWARVES_KIT`, `kit-config` or `../../` in the module's executable, with a planted violation to prove the lint can fail. The other direction: a temp kit tree without `bin/proof-capture`, knob on, `contract` still exits 0 and prints the same `visual:` line.

**D6. Fixture and media.** Two parts. (a) A hermetic suite builds a temp repo with the knob on, captures with a stub browser, runs `bin/proof-asset put`, and asserts `proof-ledger.sh check` passes with the image and blocks with it removed. (b) The build PR's own proof, `docs/verification/visual-proof-module.md`, embeds one real PNG the build captured from `lib/proof-capture/examples/hello.html` (about 13 KB), committed at `docs/verification/visual-proof-module/page.png`. `.gitignore` has no image rule, no hook or test caps tracked images, and `wrap land` turns a relative committed image link into an absolute one pinned to the PR head, so the PR body shows it. The repo's own convention for rendered figures (`docs/figures/*.png`, and PR 1086, still open) is a small committed PNG. No bucket upload: it would reach a real service. The `tape` verb's GIF is captured and its output line quoted in the proof, but not committed (one image per PR). Captures run headless with a throwaway profile; the suite asserts `--headless=new` and a fresh `--user-data-dir` in the browser's argv. Nothing drives the live desktop.

**D7. After the move (separate PRs, not in this build).**

| Repo | Files | Change |
|---|---|---|
| operator tooling repo | `experiments/proof-capture/README.md` | status line and a pointer to the kit module |
| operator tooling repo | `experiments/proof-capture/MOVED.md` (new) | where the engine lives now; the web-localterm sample and its media stay as history, nothing deleted |
| operator tooling repo | `docs/specs/SPEC-126-proof-capture.md`, `docs/specs/SPEC-126-brief-proof-capture.md` | a supersession note at the top; the text stays as the record |
| operator tooling repo | `docs/implementation-notes/proof-capture.md` | one appended delta note |
| operator tooling repo | `docs/verification/README.md` (the tool-specifics bullet), `experiments/INDEX.md` | point at the kit module |
| operator skills repo | `home/dot_claude/skills/proof-capture/private_SKILL.md` | becomes a thin front door: keeps the trigger phrases and the personal lanes below, sends page and tape work to `proof-capture` |
| operator skills repo | `home/dot_claude/skills/proof-capture/walk.mjs` | stays until a flow verb exists; it is the only part of the old engine not covered |

One engine in the kit for the lanes the kit takes (page, tape). The personal skill keeps what the kit refuses: macOS window recording, keycastr, a real Terminal window, the simulator route, the multi-step Playwright walker. Those drive a live desktop or a personal setup, so they do not belong in a neutral module. Tenant words (the herdr, one-dark, localterm, hermes-watch and personal-browser content of the old skill) are not carried into the kit: `GUIDE.md` keeps only the neutral craft (storyboard, frame check, privacy check, three gotchas).

**D8. Files the build touches, and the collisions.** New: the module dir, `bin/proof-capture`, `tests/test-proof-capture-route.sh`, one proof file and one PNG. Edited: `lib/gate/proof-gate.sh`, `lib/config/modules.tsv`, `kit.toml`, `lib/config/module-registry.md` (a stage row and a `modules.proof_capture` key row, no rows for the tool's own env vars), `docs/reference/FEATURES.md` (regenerated, never hand edited), `commands/verify.md`, `docs/verification/README.md`, `docs/reference/tiers.md`, `docs/reference/install.md`, `docs/reference/project-structure.md`, `docs/reference/consumer-contract.md`, `lib/README.md`, `tests/test-bin-forwarders.sh`, `tests/test-install-clis.sh`, `tests/test-proof-contract-visual.sh`, `CHANGELOG.md`. None is `hooks/ship-gate.sh`, anything under `lib/classify/`, or anything named `lib/adopt*`. One behavior coupling remains: `lib/adopt.sh` reads `modules.tsv`, so the new row reaches adopt through the table; the row is `opt-in`, so a fresh adopt leaves the module off, and `tests/test-adopt.sh` is in the build's check list. The lane is `full` by the diff floor: `proof-gate.sh` and `modules.tsv` are enforcement-surface paths.

## Rejected

| Option | Why not |
|---|---|
| Port `walk.mjs` and Playwright into the kit | a Node plus Playwright dependency for a 69-line walker, and its default browser is personal |
| A Node CDP driver like `shots.mjs` | a second headless driver, Node in `lib/` for no gain over Chrome's own flag |
| Add `capture` to `bin/proof-asset` | `proof-asset` needs git and `kit-config.sh`; the capture must run with neither |
| A `route` verb the gate asks for the command | one more verb and one more process per contract call, to avoid a four-line case in the gate |
| Turn the knob on by default, or add a hook | a push that passes today could fail; the brief says opt-in stays |
| macOS GUI, keycastr, simulator lanes | they drive the live desktop or one platform; they stay in the personal skill |
| Upload the fixture image to the bucket | reaches a real service from a build |

## Not built, and named

`run flow` (a scripted multi-step page walk that ends in a GIF) is the next verb if flows matter; Chrome's `--screenshot` cannot click. The "ui flow", "report" and "generated file" rows keep their artifact text and get no `capture:` line until then. Linux and containers are not claimed: the module lists Linux browser names, nothing here ran there, and the real-browser case of the suite is opt-in (`PROOF_CAPTURE_REAL=1`) and reports SKIP (counted, not a pass) by default.
