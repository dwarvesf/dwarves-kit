# Proof of done: the ceremony a diff owes follows what the diff changes

## What changed

Two gates charged ceremony for diffs that change no behavior.

- `proof-ledger.sh classify` called a docs-only PR `behavioral` because a generated HTML drawing set under `docs/design/` holds JS. A diff made only of docs now classes `inert`. A doc is `*.md`/`*.txt`/`*.markdown`, a `.kit.toml`, or a documentation or asset file in a `docs/` tree. Source, build files and secret-shaped paths keep their class.
- `lane-classify.sh floor` demanded the full lane for a comment-only edit under `lib/gate/`. A hard-path hit now counts only for a non-doc file whose changed lines are more than blank or `#` comments. Every case the check cannot decide keeps the floor. `SPEC-410` holds the rules.
- Three slow suites (`test-config-registry`, `test-lanes-data`, `test-hooks`) run fewer subprocesses with the same assertions.

## Gate table

| Claim | Evidence |
|---|---|
| a docs-tree diff (any generated html, svg, png) classes inert and owes no proof | `class-*` and `check-docs-tree-owes-no-proof` in the run table |
| source, build files and secret-shaped paths under `docs/` keep their class | `class-code-under-docs-keeps-its-class` |
| a docs or comment-only edit does not hit the floor | `floor-docs-never-hit`, `floor-comment-only-edit-is-not-a-hit`, `ship-rule-floor-follows-the-diff` |
| every undecidable or risky case still hits | `floor-cannot-decide-keeps-the-floor`, `floor-hash-that-is-not-a-comment-keeps-the-floor`, `floor-code-under-docs-or-doc-named-still-hits`, `floor-secret-pattern-beats-first-kind`, `floor-nul-byte-keeps-the-floor`, `floor-cap-keeps-the-floor-on-a-flood` |
| line numbers stay aligned across every blanking; the stderr notice is unchanged | `floor-blanking-keeps-line-numbers-aligned`, `floor-exempt-notice-survives-drops` |
| the existing floor and classify pins hold | `test-lanes-data`, `test-classify-md-inert`, `run-all --changed` below |
| the suite is load-bearing | negative control below |
| the three slow suites got cheaper with the same assertions | slow-suite table below |

## Run table

```
Command: bash tests/test-ceremony-fits-diff.sh
Exit: 0
Output: 25 cases, PASS 25, FAIL 0 (last lines: PASS floor-data-loss-still-hits-in-comments / PASS ship-rule-floor-follows-the-diff)
Verdict: PASS
```

```
Command: bash tests/test-classify-md-inert.sh
Exit: 0
Output: --- ALL PASS (13/13) ---
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time   (52 suites, load average 20 to 60)
Exit: 1 (one suite), fixed, then that suite and the later-edited suites re-run alone
Output: 51 suites ok; test-meta-docs-registry failed "docs/FEATURES.md is fresh". After
        `bash lib/registry/feature-registry.sh generate docs/FEATURES.md` that suite prints "Passed: 120 / 120 All meta tests passed."
Re-runs after the fix: test-meta-docs-registry 120/120, test-boundary-lint 5/5, test-no-scattered-ids 9/9, test-ceremony-fits-diff 25/25,
        test-hooks 826 pass 0 fail (after the backlog fixture change), test-lanes-data 83 pass 0 fail, test-config-registry 59 pass 0 fail.
        A second full `--changed` run queued behind other sessions' runs on the per-host lock for 20 minutes and was stopped.
Verdict: PASS
```

The first run listed `test-lanes-data` 382 s, `test-hooks` 315 s, `test-wrap-land` 268 s as the slowest.

## Negative control

```
Command: bash lib/gate/negctl.sh <root> "bash tests/test-ceremony-fits-diff.sh" "<restore proof-ledger.sh and lane-classify.sh from ab38a33d>"
Exit: 0 (green before mutation)
Changed: lib/classify/lane-classify.sh, lib/gate/proof-ledger.sh
Exit: 1 (under mutation, RED expected)
Output: FAIL ship-rule-floor-follows-the-diff: [comment-only blocked rc=2 ...] [docs blocked rc=2 ...]
Restore: git checkout HEAD -- lib/classify/lane-classify.sh lib/gate/proof-ledger.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Review rounds

Four rounds of adversarial probing (each round reproduced holes in repos under a scratch dir), one correctness review, and two fresh-context spec validations (the second returned SOLID) shaped the final rules. The holes they found, and the cases that now pin them, are listed in `docs/implementation-notes/ceremony-fits-diff.md`. One residual stays by design and is named in SPEC-410: a `#` line added inside a multi-line quoted string that already holds a comment-shaped line at that spot.

## Slow suites

The host was shared with other sessions all evening. Wall seconds swing 2 to 5 times between identical runs, so CPU seconds (user plus sys) are the fair measure. Each pair ran side by side under the same load: the original file from `ab38a33d` against the edited file.

| Suite | Before: CPU s / wall s | After: CPU s / wall s | What changed |
|---|---|---|---|
| `test-config-registry` (59 assertions) | 46.8 / 97 (50.2 / 613 under load above 100) | 29.3 / 29 (28.7 / 112 under load above 100) | the two `bin/config list` renders (about 13 CPU s each) start in the background and are collected where asserted; AC8 reads the first render instead of a third; AC6 to AC8 read each table in one awk pass instead of a subshell per cell |
| `test-lanes-data` (83 cases) | 190.9 / 363 (208.8 / 920 under load above 100) | 156.4 / 304 (189.3 / 857 under load above 100) | `record_gates` writes each distinct gate list once through the real writer and appends the template; one floor run per config in `floor-exempt-malformed-rejected`; `reader_run` reuses one repo; `floor-timing-30k` writes its 30000 paths straight into the index |
| `test-hooks` (826 assertions) | 120.3 / 258 (127.6 / 646 under load above 100) | 95.5 / 165 (120.3 / 507 under load above 100) | the cosmetic-hook garbage battery (6 hooks x 10 inputs) runs once and answers both the exit-0 and the never-exit-2 assertions |

Not changed: `bin/config list` itself (321 rows, a fork per cell) is the real cost and belongs to the config module; `test-config-seams` costs about 12 CPU s and was left alone; `bin/test-affected.timeouts` waits for a re-measure on a quiet host.

Two side findings, both fixed in the test files: `test-hooks.sh` made its backlog fixture with `mktemp dk-backlog.XXXXXX.md`, which BSD `mktemp` treats as one literal file, so two concurrent `test-hooks` runs on a host collided (it happened twice during this work, with other sessions' runs). It is a directory now. The original `test-lanes-data` also failed once on its own `floor-timing-30k` limit (17.9 s against 15 s) when five suites shared the host; the edited version builds its 30000 paths in the index and ran in under 4 s.
