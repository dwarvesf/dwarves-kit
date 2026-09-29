# Implementation notes: test-affected

Deltas from the task brief only.

| Item | Decision |
|---|---|
| Existing home | `tests/run-all.sh --changed` already selects by diff (basename match on code lines, `# always:` markers, no cache). `precedent find` did not surface it. `bin/test-affected` is still a new file because the brief fixes different semantics: path-or-basename match anywhere in a suite, `tests/test-meta.sh` as the sole always-run, UNCOVERED reporting, `--list` reasons, a content-keyed pass cache. Folding the two later is open. |
| Default base | `origin/HEAD` if live, else `origin/main`, else `origin/master`: the `wrap` `_default_branch` rule, inlined (that function is not sourceable without running `wrap`). |
| Reference scan | Non-source changed files (docs, fixtures) match by repo-relative path only. Sources (`lib/*.sh`, `hooks/*`, `bin/*`, `commands/*.md`) also match by basename. Basename matching over-selects (`board`, `lint`); accepted per brief. |
| Cache key sources | Tokens of the test that equal a source path or basename, expanded to every source with that path or basename, so the key covers whatever the selector would treat as a reference. |
| Census | `tests/test-bin-forwarders.sh` pins the `bin/` set; `test-affected` added to it. `docs/FEATURES.md` regenerated (suite count). |
| Cache failure | Unresolvable or unreadable/unwritable cache dir: no reads, everything runs, one stderr line. |
| `--no-cache` | Skips reads only; a PASS is still recorded (content-keyed, so harmless). |
