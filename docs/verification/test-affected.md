# Verification -- test-affected

`bin/test-affected` selects the tests a diff touches, runs them, and caches PASS by content key.

## Green run
```
Command: bash tests/test-test-affected.sh
Exit: 0
Verdict: PASS
```
22 assertions in a temp git repo: mapping, always-meta, UNCOVERED not a failure, cache hit, miss after a referenced-source edit, FAIL never cached, `--no-cache`, unreadable cache runs everything, `--list` runs nothing.

```
Command: bash tests/test-meta.sh
Exit: 0
Verdict: PASS
```
879 / 879. `tests/test-bin-forwarders.sh`: 48 passed (census now names `test-affected`).

## Negative control
```
Command: bash tests/test-test-affected.sh
Exit: 1 (under mutation: the cache key stops scanning the test for source references)
Verdict: PASS
```
Run by `lib/gate/negctl.sh`: green before, RED under the mutation, green after `git checkout HEAD -- bin/test-affected`. The two red cases were "edited referenced source misses the cache" and "no stale CACHED after the edit": a stale PASS was served after a source edit.

## Negative control: narrowed selection
```
Command: bash tests/test-test-affected.sh
Exit: 1 (under mutation)
Verdict: PASS
```
Two mutations through `lib/gate/negctl.sh`, each green before, RED under the mutation, green after restore. Dropping the longer-path guard made "a suite naming only docs/README.md is not selected by README.md" fail. Lowering the basename cutoff from 5 to 0 turned the short-basename cases red.

`bash tests/test-run-all-changed.sh`: all 8 passed with `run-all.sh --changed` taking its picks from `bin/test-affected --list`. On this branch `--list` selects 20 distinct suites, down from about 38 before the narrowing (README.md alone: 33 suites to 12).

## Not proven
- A full real-repo run: `--list` was checked against this branch, but the selected suites (including the 5.7k-line wrap suite) were not executed through the tool.
- Comment-line skipping has no dedicated negative control beyond the fixture case.
