# Proof of done: doc figures (model, render, freshness check)

Acceptance: twelve figures render from one model; `check` fails when a sheet changes without a re-render, a PNG is missing, or a doc names an unknown figure id; a green suite does not hide a broken `check`.

## Green run

```
Command: bash tests/test-doc-figures.sh
Exit: 0
Output:
  == committed state ==
    PASS check passes on the committed repo
    PASS the manifest holds exactly the twelve agreed ids, sorted
  == an edited sheet without a re-render ==
    PASS check exits 1 after a block edit
    PASS the problem line names the sheet
  == a missing PNG ==
    PASS check exits 1 when a PNG is missing
  == doc references ==
    PASS an unknown id in README.md fails
  == render (browser needed) ==
    PASS render exits 0 on a one-sheet model
    PASS check passes straight after render
  doc-figures: 24 passed, 0 failed (24 checks)
Verdict: PASS
```

```
Command: bash lib/system-design/doc-figures check
Exit: 0
Output: doc-figures: ok (12 figures)
Verdict: PASS
```

The real failure path, on a temp copy with one edited sheet title, one deleted PNG and one README reference to an unknown id:

```
Command: DOC_FIGURES_ROOT=<temp copy> bash lib/system-design/doc-figures check
Exit: 1
Output:
  lanes: sheet changed since the last render (run render)
  wrap: <temp copy>/docs/figures/wrap.png is missing
  README.md:4: figures/nope.png names no manifest id
Verdict: PASS (exit 1 is the expected result for a broken copy)
```

Render, in this checkout (Microsoft Edge, node 22):

```
Command: CHROME="/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" bash lib/system-design/doc-figures render
Exit: 0
Output: rendered 12 figures into docs/figures
Verdict: PASS
```

Every PNG was opened and read after the last render. Layout fixes that came out of that pass are in `docs/implementation-notes/doc-figures.md`.

Affected suites: `bash tests/run-all.sh --changed origin/master` passed 18 of 18, including `test-system-design`, `test-doc-figures`, `test-no-personal-paths` and `test-no-scattered-ids`.

## NEGATIVE CONTROL (mutate, RED, restore)

Run after the change was committed: `bash lib/gate/negctl.sh "$PWD" "bash tests/test-doc-figures.sh" "<mutate>"`. The mutation replaces the hash comparison in `check` with `false`, so a changed sheet reads as fresh.

```
Command: bash tests/test-doc-figures.sh
Exit: 0 (green before mutation)
Mutation: perl -pi -e 's/\[ "\$mhash" != "\$hash" \]/false/' lib/system-design/doc-figures
Changed: lib/system-design/doc-figures
Exit: 1 (under mutation, RED expected)
Output: doc-figures: 22 passed, 2 failed (24 checks)
Restore: git checkout HEAD -- lib/system-design/doc-figures
Exit: 0 (green after restore)
Verdict: PASS
```

The two red checks are "check exits 1 after a block edit" and "the problem line names the sheet".

## Rollback

Revert the commit. It adds only `docs/figures/`, `lib/system-design/doc-figures`, `tests/test-doc-figures.sh`, notes, and one README paragraph. Nothing reads the figures yet, and no hook calls the script.
