# Implementation notes: test-affected

Deltas from the task brief only.

| Item | Decision |
|---|---|
| Existing home | `tests/run-all.sh --changed` already selected by diff. `precedent find` did not surface it. `bin/test-affected` owns the selection rule now and `run-all.sh --changed` calls `--list` and keeps its parallel runner and `# always:` suites. The old `lib/<mod>/` rule moved into `test-affected` as reason `module lib/<mod>`. |
| Default base | `origin/HEAD` if live, else `origin/main`, else `origin/master`: the `wrap` `_default_branch` rule, inlined (that function is not sourceable without running `wrap`). |
| Reference scan | Non-source changed files (docs, fixtures) match by repo-relative path only. Sources (`lib/*.sh`, `hooks/*`, `bin/*`, `commands/*.md`) also match by basename. Basename matching over-selects (`board`, `lint`); accepted per brief. |
| Cache key sources | Tokens of the test that equal a source path or basename, expanded to every source with that path or basename, so the key covers whatever the selector would treat as a reference. |
| Census | `tests/test-bin-forwarders.sh` pins the `bin/` set; `test-affected` added to it. `docs/FEATURES.md` regenerated (suite count). |
| Cache failure | Unresolvable or unreadable/unwritable cache dir: no reads, everything runs, one stderr line. |
| `--no-cache` | Skips reads only; a PASS is still recorded (content-keyed, so harmless). |
| Narrowing | A non-source file matches only a full-path reference: not inside a longer path (`docs/README.md` is not `README.md`), not on a comment line; `$KIT_DIR/README.md` counts. Sources match by path, or by basename over 5 chars, on non-comment lines. `skills/*.md` and `agents/*.md` count as sources. README.md went from 33 suites to 12. |
| Cache key | Still scans the whole test text, comments included: over-inclusion only costs a cache miss. |
