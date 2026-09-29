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

## Not proven
- A full real-repo run: `--list` was checked against this branch, but the selected suites (including the 5.7k-line wrap suite) were not executed through the tool.
- Non-source files such as `README.md` match every suite that names them by path, so a README edit over-selects (about 40 suites here). Accepted.
- Basename matching over-selects for short names (`board`, `lint`).
