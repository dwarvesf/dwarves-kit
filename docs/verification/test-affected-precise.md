# Proof of done: test-affected-precise

Branch `perf/test-affected-precise` on master 764e0d02. Spec: `docs/specs/SPEC-397-test-affected-precise.md`. Notes: `docs/implementation-notes/test-affected-precise.md`.

Verdict summary: `bin/test-affected` now picks a source file's suites by run or source (or full repo path), and a kit.toml change by the changed section or key. Over the last 30 merged PRs the picks fell from 820 to 743 suites with 0 MISS; the SG-05 diff (PR #913) fell from 94 to 64, and one added `load_warn` line now picks 3 kit.toml referencers instead of 39. A committed replay tool is the guard, and dropping full-path references in a saved copy makes it report MISS and exit 1.

## Replay over the last 30 merged PRs

Master's script is `git show master:bin/test-affected` (with its timeouts file) at a scratch path; mine is the branch copy. "touched" is the replay's independent rule (a run or source of a changed file, a full-path name of a changed non-source file, a kit.toml referencer naming a changed key or section, or an edit of the suite by the PR). MISS is touched minus picked.

| PR | files | picked before | picked after | touched | MISS before | MISS after |
|---|---|---|---|---|---|---|
| #926 | 2 | 2 | 2 | 2 | 0 | 0 |
| #925 | 6 | 44 | 44 | 34 | 0 | 0 |
| #924 | 11 | 34 | 34 | 22 | 0 | 0 |
| #923 | 5 | 3 | 3 | 0 | 0 | 0 |
| #922 | 1 | 0 | 0 | 0 | 0 | 0 |
| #921 | 5 | 17 | 17 | 13 | 0 | 0 |
| #920 | 6 | 30 | 29 | 27 | 0 | 0 |
| #919 | 1 | 26 | 26 | 26 | 0 | 0 |
| #918 | 1 | 53 | 48 | 45 | 0 | 0 |
| #917 | 10 | 58 | 34 | 26 | 0 | 0 |
| #916 | 14 | 20 | 19 | 16 | 0 | 0 |
| #915 | 9 | 28 | 26 | 23 | 0 | 0 |
| #914 | 10 | 71 | 68 | 65 | 0 | 0 |
| #913 | 23 | 94 | 64 | 55 | 0 | 0 |
| #912 | 10 | 63 | 59 | 53 | 0 | 0 |
| #911 | 10 | 15 | 15 | 13 | 0 | 0 |
| #910 | 1 | 26 | 26 | 26 | 0 | 0 |
| #909 | 17 | 19 | 19 | 19 | 0 | 0 |
| #908 | 6 | 10 | 10 | 10 | 0 | 0 |
| #907 | 26 | 25 | 25 | 24 | 0 | 0 |
| #906 | 10 | 29 | 28 | 27 | 0 | 0 |
| #905 | 1 | 24 | 24 | 24 | 0 | 0 |
| #904 | 4 | 7 | 7 | 7 | 0 | 0 |
| #903 | 2 | 8 | 8 | 8 | 0 | 0 |
| #902 | 1 | 2 | 2 | 1 | 0 | 0 |
| #901 | 1 | 5 | 5 | 3 | 0 | 0 |
| #900 | 1 | 17 | 13 | 13 | 0 | 0 |
| #899 | 1 | 10 | 10 | 10 | 0 | 0 |
| #898 | 18 | 79 | 77 | 75 | 0 | 0 |
| #897 | 1 | 1 | 1 | 0 | 0 | 0 |
| total | 214 | 820 | 743 | 667 | 0 | 0 |

```
Command: bash tests/lib/test-affected-replay.sh --n 30 --ta <branch bin/test-affected> --compare <master bin/test-affected>
Exit: 0
Output: test-affected-replay: 30 PRs, picked 820 before, 743 after, 0 MISS before, 0 MISS
Verdict: PASS (the selection dropped 77 picks and omitted no touched suite)
```

The saving over 30 PRs is modest because most diffs name their files by full repo path, which still picks (the spec keeps that rule). The cuts land where a mention was the only link: #913 (94 to 64), #917 (58 to 34), #900 (17 to 13), #918 (53 to 48). After the change the pick is within a few suites of the touched set on every PR.

## PR #913 (the SG-05 diff) and a one-line kit.toml edit

```
Command: bin/test-affected --list --base <913^1>   (master script, then branch script, scratch worktree at the merge commit)
Exit: 0, 0
Output: before 94 unique suites (24 from lib/queue/orchestrate.sh, 35+ from kit.toml); after 64
Verdict: PASS
```

```
Command: sed on kit.toml (load_warn 16 -> 17), then bin/test-affected --list --base HEAD | grep -c 'references kit.toml'   (master script, then branch script)
Exit: 0, 0
Output: master 39 suites reference kit.toml; branch 3 (the ones naming load_warn, KIT_LOAD_WARN or [test])
Verdict: PASS (kit.toml restored with command cp -f, git status clean)
```

The 24 orchestrate.sh picks remain: those suites name `lib/queue/orchestrate.sh` by full path, which the spec keeps. A finer cut needs per-function attribution, not a path rule.

## Suites

```
Command: bash tests/test-test-affected.sh ; test-test-affected-replay.sh ; test-test-affected-parallel.sh ; test-test-affected-cache.sh ; test-run-all-changed.sh ; test-bin-forwarders.sh   (one at a time)
Exit: 0 for each
Output: 74 passed, 0 failed ; 9 passed, 0 failed ; 41 passed, 0 failed ; 17 passed, 0 failed ; all 12 passed ; all 48 passed, 0 skipped
Verdict: PASS
```

New cases in `tests/test-test-affected.sh`: a suite that sources, dot-sources `$VAR/<name>`, calls directly or runs the full path of a basename-over-5 source is picked; a suite that only greps the basename or sources it in a comment is not; a suite that names the full path inside a grep is still picked; a [test] `load_warn` hunk picks the suite naming `load_warn` and neither the `[review]` suite nor a copy-only suite; a [review] key hunk picks the `[review]` suite and not the [test] one; a hunk above every section falls back to all three referencers. The old "long basename selects by echo" case now asserts the opposite and gains a run-form twin. `tests/test-test-affected-replay.sh` (new): a clean replay is 0 MISS, an omitting selection reports MISS and exits 1, `--compare` fills the before count, bad arguments exit 2.

## Negative control

Committed first (80be7026). Saved `bin/test-affected`, removed the full-path rule from `refs_run` in the working copy (the source rule now drops full-path references too), ran the replay, restored with `command cp -f` (never `git checkout --`).

```
Command: bash tests/lib/test-affected-replay.sh --n 30      (mutant: no full-path reference in refs_run)
Exit: 1
Output: MISS #924 tests/test-bin-forwarders.sh ; MISS #924 tests/test-gitattributes-union.sh ; MISS #907 tests/test-bin-forwarders.sh ; MISS #907 tests/test-gitattributes-union.sh
        test-affected-replay: 30 PRs, picked 716, 4 MISS
Verdict: PASS (the control fails as it must: the guard catches a selection that omits suites running a changed file)
```

```
Command: bash tests/lib/test-affected-replay.sh --n 30      (after restore; git status clean)
Exit: 0
Output: test-affected-replay: 30 PRs, picked 743, 0 MISS
Verdict: PASS
```
