# Proof of done: adopt pointer and two-idea tour (SPEC-371)

Scope: build only. The J2 and Claude Code measurement runs (AC-7, `RESULT.md`) are post-build and PARTIAL.

## Green run

| Command | Exit | Result |
|---|---|---|
| `bash tests/test-adopt.sh` | 0 | `PASS=55 FAIL=0` |
| `bash tests/test-meta.sh` | 0 | `Passed: 887 / 887` after the review fixes (earlier 885 / 886 was FEATURES.md drift) |
| AC-6 grep chain (Lane, Proof of done, kit:dispatch present; `**Check** --` absent) | 0 | `AC6ok` |

## Negative controls

Each mutation was applied to the committed file, `bash tests/test-adopt.sh` run, then the file restored with `git checkout -- <file>` and the suite re-run.

| Case | Mutation | Red run | Restored run |
|---|---|---|---|
| T2 | hash check removed, a file that exists is always rewritten | `PASS=47 FAIL=4` | `PASS=51 FAIL=0` |
| T4 | plain `--refresh` swaps a known old copy | `PASS=50 FAIL=1` | `PASS=51 FAIL=0` |
| T6b | `--swap-agents` implies `--refresh` | `PASS=49 FAIL=2` | `PASS=51 FAIL=0` |
| T8 | hard exit restored when no source contract exists | `PASS=50 FAIL=1` | `PASS=51 FAIL=0` |
| T1 | adopt copies the full 18KB contract again | `PASS=47 FAIL=4` | `PASS=51 FAIL=0` |
| T5b | shallow-clone check inverted in `known-hashes.sh` | `PASS=50 FAIL=1` | `PASS=51 FAIL=0` |

Review-fix controls (same method; `git status --short` was empty after each restore; suite after all restores `PASS=55 FAIL=0`):

| Case | Mutation | Red run |
|---|---|---|
| Template guard | pointer-template-missing check removed | `PASS=54 FAIL=1` (missing pointer template) |
| Kit self-target | own-tree refusal removed; the test runs on a temp copy of the tree | `PASS=54 FAIL=1` (adopt refuses the kit's own tree) |
| Single-source pointer | neither-file path reverted to the old refusal | `PASS=53 FAIL=2` (single-source neither file; operator single_source=true fresh adopt) |

## Acceptance

| AC | Verified by |
|---|---|
| AC-1, AC-2 | test-adopt cases for size cap and pointer text (T1) |
| AC-3, AC-4 | "edited AGENTS.md survives refresh and swap", "drift vs pointer", "drift vs old contract", "not a kit file" |
| AC-5, AC-9, AC-10, AC-11 | "old copy swap needs flag", "known list complete against git log", "known-hashes refuses shallow", "no source contract", "swap-agents alone refused", "dry-run swap plans only" |
| AC-6 | grep chain above |
| AC-7 | PARTIAL, post-build measurement (`lib/adopt/onboarding-cost.sh` is built and tested) |
