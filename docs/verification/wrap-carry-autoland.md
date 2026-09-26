# Proof of done: `wrap apply` lands its own carry PRs (`wrap.autoland_carry`)

With the root-only knob `wrap.autoland_carry` on (default `false`), `wrap apply --apply` opens and merges its own stray-line and stray-commit carry PRs through `wrap merge --apply --pr`, and lands an orphan carry branch an earlier run left without a PR when that branch reads as the file's carry. Knob off, every existing output line holds (SPEC-322).

## Acceptance criteria

| AC | Claim | Proof |
|---|---|---|
| AC1 | knob ships `false`, root-only; `merge_own_prs=false` wins | `wrap.autoland_carry ships as false`, `honours the operator kit.toml`, `ignores a project .kit.toml`, `autoland held: prints today's PR command` |
| AC2 | knob off is unchanged | every pre-existing stray-lines and stray-commits case green, incl. `the PR command is named, not run` |
| AC3 | an orphan carry branch is adopted: PR opened, merge pinned to its tip, tree verified, the remainder carried and landed | `autoland adopt:` block (9 checks); fixture transcript below |
| AC4 | stray commits land, then main moves and pulls; blocked moves are not landed | `autoland commits:` (6), `autoland commits blocked:` (3) |
| AC5 | gate refusal leaves the PR open, exit 0; failed merge exits 2 | `autoland gate refusal:` (4), `autoland merge failure:` (2) |
| AC6 | never lands foreign work: another author's PR, a draft, a look-alike name, a line the checkout lacks, a removed line, a moved head | `autoland foreign PR:`, `draft:`, `foreign content:`, `removal:`, `moved head:` blocks |
| AC7 | a fresh PR waits for its state to settle | `autoland settle:` (two wait reads, then merged) |
| AC8 | dry run names the landing, opens nothing | `autoland dry-run:`, `autoland commits dry-run:` |
| AC9 | no regression | full suite green |

## Green run

```
Command: bash tests/test-wrap.sh
Exit: 0
test-wrap: all 1264 passed
```

The autoland block contributes 56 of those checks. `tests/test-config-registry.sh` (56/56), `tests/test-lane-classify.sh` (38/38) and `tests/test-gitattributes-union.sh` (27/27) are green. `tests/test-meta.sh` fails one check, `docs/FEATURES.md is fresh`, identically on master before this change.

## Negative control

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh >/dev/null 2>&1
Exit: 0 (green before mutation)
Mutation: perl -pi -e 's/wrap\.autoland_carry false\)" = "true"/wrap.autoland_carry false)" = "never"/' lib/wrap/wrap.sh
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Scratch-repo fixture

A local bare origin, an orphan `wrap/stray-meta-lab-log-md-20260101-0000` holding one of two stray lines, a shared clone with both lines uncommitted, the kit's gh stub, operator `kit.toml` with `autoland_carry = true`:

```
$ bin/wrap apply --apply <shared checkout>   # wrap.autoland_carry = true
-- stray lines:
     opened PR #42 for wrap/stray-meta-lab-log-md-20260101-0000
       eligible #42 carry [wrap/stray]
       merged #42 (6c3416226f626036e2421f32a0332dda9bec20cd): tree verified
     carried 1 stray lines in _meta/LAB_LOG.md to origin/wrap/stray-meta-lab-log-md-20260926-2249
     opened PR #42 for wrap/stray-meta-lab-log-md-20260926-2249
       eligible #42 carry [wrap/stray]
       merged #42 (08b47c59cd73ac00329337880bd8a2fa7bb477cb): tree verified
-- stray commits:
     none
-- pull:
exit: 0
$ gh calls (create, merge)
pr create --repo <tmp>/origin.git --head wrap/stray-meta-lab-log-md-20260101-0000 --title chore(LAB_LOG): carr
pr merge 42 --repo <tmp>/origin.git --squash --match-head-commit 6c3416226f626036e2421f32a0332dda9bec20cd
pr create --repo <tmp>/origin.git --head wrap/stray-meta-lab-log-md-20260926-2249 --title chore(LAB_LOG): carr
pr merge 42 --repo <tmp>/origin.git --squash --match-head-commit 08b47c59cd73ac00329337880bd8a2fa7bb477cb
$ git show origin main:_meta/LAB_LOG.md
# Lab log

---

2026-09-05 · stray: the second line
2026-09-04 · stray: the first line
2026-09-01 · base: the first line
```

## Review

`/kit:spec-validate` ran three rounds through one fresh-context reviewer: NEEDS REVISION (4 critical), NEEDS REVISION (critical 1 partial plus a time-of-check gap), APPROVED. Every fix has a test in the autoland block.

## Not proven

- The squash-fallback path under autoland (close the superseded PR; a merged `<branch>-squash` counts as landed): no test drives the CONFLICTING-then-fallback chain through `apply`.
- A real GitHub run: the knob ships `false`; the first live run is the operator's flip.
