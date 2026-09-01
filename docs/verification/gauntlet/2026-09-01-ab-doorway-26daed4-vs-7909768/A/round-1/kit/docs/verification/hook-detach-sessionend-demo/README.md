# Behavioral-capture proof: hook-detach-sessionend (real terminal recording)

Per SPEC-126 / the `proof-capture` skill. This folder is the visual companion to the
text proof at `docs/verification/hook-detach-sessionend.md` -- same finding, watchable
instead of read.

## The four SPEC-126 components

| Component | Where |
|---|---|
| Viewable artifact | `hook-cancelled-fix.gif` (this dir; 141 KB, 38s, 1200x640) |
| Committed reproduce script | `hook-cancelled-fix.tape` (this dir, `vhs` format) + `run-prefix.sh` / `run-fixed.sh` / `extractor.sh` / `settings-prefix.json` / `settings-fixed.json` |
| Verified-content note | below |
| Negative control | built into the single take: the first half (pre-fix) IS the bug-present state, side by side with the fixed second half |

## What it shows

Two real `claude -p` sessions, back to back, same terminal:

1. **Pre-fix** (`origin/master`'s `hooks/harvest.py`): `SessionEnd` hook wired with a
   5s declared timeout, extractor takes 6s. The hook blocks synchronously, exceeds its
   own timeout, and the real CLI prints `SessionEnd hook [...harvest.sh --lab-log]
   failed: Hook cancelled`. `real 0m9.062s`.
2. **Fixed** (this PR's `hooks/harvest.py`): identical 5s timeout, identical 6s-slow
   extractor. The hook detaches and returns immediately; no cancellation.
   `real 0m3.168s`.

## Verified-content note

- **Theme**: `vhs`'s built-in "Dracula" theme -- chosen for legibility, not to match a
  personal dotfiles config (this is a generic reproduction script, not a themed personal
  app, so the herdr-quicklook "record the user's real theme" rule doesn't apply the same
  way; the important thing here is that the text is readable, which it is).
- **Content**: frame-sampled at 1fps (`ffmpeg -vf fps=1`) and visually inspected. Frame
  16/38 shows the pre-fix "Hook cancelled" line + `real 0m9.062s` clearly legible. Frame
  33/38 shows the fixed side's clean `real 0m3.168s` with no cancellation. Both commands
  and both outputs are genuine -- nothing staged or typed as fake terminal text; every
  line on screen is the real stdout/stderr of an actual `claude -p` process.
- **Scaled-down, honestly**: the declared hook timeout is shortened to 5s (production is
  30s) and the fake extractor sleeps 6s (production reproduction used 33s, see the
  sibling `hook-detach-sessionend-transcript.txt`), purely so the recording stays
  watchable. Same mechanism (extractor duration vs. hook timeout), smaller numbers. The
  full, unscaled 30s/33s reproduction with the exact original bug wording is the text
  transcript, not this GIF.
- **Privacy**: re-recorded from a NEUTRAL scratch path (`/private/tmp/demo/...`) after
  the first take was caught (in this same session) leaking the operator's real home
  directory path and an internal session UUID -- this repo is public, so that take was
  discarded and redone from a clean clone before being accepted. No username, hostname,
  client/Dwarves data, or credentials appear in the final GIF.

## How it was recorded

`vhs hook-cancelled-fix.tape`, driving two real `claude -p --model haiku` sessions via
`run-prefix.sh` / `run-fixed.sh`, each of which `git init`s a scratch project dir, wires
`SessionEnd` to a scratch clone of `kit-prefix` (`origin/master`) or `kit-fixed` (this
branch) via `--settings`, and times the whole invocation with `time`.

## Frame-verification method

`ffmpeg -i hook-cancelled-fix.gif -vf "fps=1" frames/f%02d.png`, then visually inspected
frame 16 (pre-fix result) and frame 33 (fixed result) before accepting the capture.

## Reproduce

```sh
mkdir -p /private/tmp/demo
git clone --branch master                     git@github.com:dwarvesf/dwarves-kit.git /private/tmp/demo/kit-prefix
git clone --branch fix/hook-detach-sessionend  git@github.com:dwarvesf/dwarves-kit.git /private/tmp/demo/kit-fixed
cp extractor.sh settings-prefix.json settings-fixed.json run-prefix.sh run-fixed.sh hook-cancelled-fix.tape /private/tmp/demo/
cd /private/tmp/demo
vhs hook-cancelled-fix.tape    # writes hook-cancelled-fix.gif
```

Full text-form reproduction (unscaled, real 30s/33s numbers, exact original bug
wording): `docs/verification/hook-detach-sessionend.md`, "Round 3" section, and
`docs/verification/hook-detach-sessionend-transcript.txt`.
