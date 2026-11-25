# proof-capture: interface and invariants

One page. The build story, the options that were rejected and the validation record are in `docs/specs/SPEC-427-visual-proof-module.md` (and its brief, `docs/briefs/DECISION-BRIEF-visual-proof-module.md`). The full contract with the exact messages is in `README.md`.

## Interface

```
proof-capture run page <src> <out.png> [--width N] [--height N] [--wait MS] [--deadline S]
proof-capture run tape <file.tape> <out.gif> [--deadline S]
```

Arguments only. One file out (PNG or GIF, checked by magic bytes and trailer), one stdout line, diagnostics on stderr. Exit 0 written, 1 capture failed, 64 bad input, 69 a dependency is missing.

## Invariants

- The module reads argv and writes one file. It never reads a kit config, never sources a kit script, never writes under a repo except the `<out>` the caller names.
- Success is the file on disk (valid, size stable), never the child's exit. For `tape`, vhs must also exit 0.
- Every child starts in its own process group, headless, with a private profile and work directory, and is bounded by a deadline.
- The only signals the tool sends go to the group of a pid it recorded. No kill by name or pattern, no process-table listing.
- TERM, then KILL after 2 s. INT, TERM, HUP, QUIT, USR1, USR2, ALRM and PIPE reap at once and exit 1, also between the launch and the pid record. A second signal during a reap only sets a flag. A signal after the rename does not undo the write.
- A watchdog in its own group ends the child's group at the deadline plus 5 s, even if the tool is killed. It starts right after the child, so only the two process starts between them are unprotected.
- The browser writes only into the private work directory. The artifact reaches `<outdir>` by an exclusive temp file and a rename. A symlink `<out>` or `<outdir>` is refused at the start and again before the temp file and before the rename.
- The work directory is removed on every exit path a catchable signal can reach. A KILL to the tool leaves it.
- Nothing is stored, scheduled or credentialed.

## Checks

`tests/test-proof-capture.sh` (stub browser and stub vhs; the real-browser case is opt-in) and the lint in its case 10 for the forbidden tokens.

## Retire the module

Delete `lib/proof-capture/` and `bin/proof-capture`. Delete the `proof_capture` row in `lib/config/modules.tsv`, the key in `kit.toml` and the rows in `lib/config/module-registry.md`. Delete `_proof_visual_capture` and its `capture:` echo in `lib/gate/proof-gate.sh`. Drop the census entry, the install-clis lines and `tests/test-proof-capture-route.sh`. Revert the Step 7b lines in `commands/verify.md`. Regenerate `docs/reference/FEATURES.md`. Nothing is scheduled, stored or credentialed, so nothing else is left behind.
