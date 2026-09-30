# Proof of done: adopt pointer and two-idea tour (SPEC-371)

Scope: build only. The J2 and Claude Code measurement runs (AC-7, `RESULT.md`) are post-build and PARTIAL.

## Green run

| Command | Exit | Result |
|---|---|---|
| `bash tests/test-adopt.sh` | 0 | `PASS=51 FAIL=0` |
| `bash tests/test-meta.sh` | see note | `Passed: 885 / 886`, `Failed: 1` (failing check named in the test-meta row below) |
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

## Acceptance

| AC | Verified by |
|---|---|
| AC-1, AC-2 | test-adopt cases for size cap and pointer text (T1) |
| AC-3, AC-4 | "edited AGENTS.md survives refresh and swap", "drift vs pointer", "drift vs old contract", "not a kit file" |
| AC-5, AC-9, AC-10, AC-11 | "old copy swap needs flag", "known list complete against git log", "known-hashes refuses shallow", "no source contract", "swap-agents alone refused", "dry-run swap plans only" |
| AC-6 | grep chain above |
| AC-7 | PARTIAL, post-build measurement (`lib/adopt/onboarding-cost.sh` is built and tested) |
