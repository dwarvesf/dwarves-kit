# Spec: Advisory coverage-delta gate

Generated: 2026-07-04
Status: VALIDATED
Lane: normal (adds one advisory `lib/` script + its Review-phase wiring + an over-test
suite; it is ADVISORY by contract , it warns and always exits 0, so it can never block a
push and does not earn the full lane despite touching `lib/`).

## Problem

The 2026-07-02/03 process benchmark's headline finding (§2) is that the kit's real gap is
COVERAGE, not process: today a behavioral diff can change source with no matching test change
and nothing surfaces it. The gate/proof machinery records that a gate RAN, but coverage is
opt-in, so an under-tested change ships unremarked. There is no cheap, portable, always-on
signal that asks, for a given diff, "did the test surface move the right way?"

The kit is polyglot (bash here, but adopted downstream repos are Go / Python / TS / ...), so
a language-specific coverage runner (pytest-cov, `go test -cover`, c8) cannot be the DEFAULT
signal , it would only fire where that toolchain is configured. What is needed is a
language-agnostic heuristic that works on the diff itself, with a hook to a real coverage
runner where one is configured.

## Solution

### Approaches considered

1. **A language-agnostic diff-line heuristic, with an optional real-runner hook. CHOSEN.**
   For a diff, classify each changed file as source / test / docs / generated, count the
   added-or-changed lines in the SOURCE files vs the TEST files, and FLAG (warn) when source
   lines moved but test lines did not. Portable across every target the kit adopts (it reads
   `git diff`, nothing language-specific). Where a real coverage runner is configured
   (`COVERAGE_DELTA_RUNNER`), defer to it for the signal instead. This is exactly open-fork 3's
   default. ADVISORY: it warns and always exits 0.

2. **A real per-language coverage runner as the default.** Rejected as the default: it only
   fires where that toolchain is present and configured, so it is silent on most adopted
   repos and on the kit's own bash. Kept as the OPTIONAL hook (approach 1's runner escape),
   not the floor.

3. **A push-blocking coverage gate.** Rejected per gate-zero (the mega-goal's BINDING
   assumption): new gates 03/04 are ADVISORY by default; a block needs Han's bless and an ADR.
   The benchmark's own §2 lesson is that coverage is the problem AND that the process must not
   grow another hard wall that trains the operator to route around it. The false-positive risk
   (a genuinely well-tested diff flagged) makes a block actively harmful here.

### Chosen shape

A new `lib/coverage-delta.sh` (the advisory gate) reuses the kit's existing diff plumbing
(the 4-source changed-files union `lib/proof-ledger.sh` already uses: `base..HEAD` + working
tree + `--cached` + untracked). It classifies each changed path, computes the source-vs-test
line delta via `git diff --numstat`, prints a one-line advisory verdict prefixed
`[coverage-delta]`, and ALWAYS exits 0. It is invoked at the **Review phase** (the cycle
table's advisory enforcer, the Build->Review boundary) from `commands/review-team.md`, the
same live-dispatch pattern `lib/role-classify.sh` already uses there. It is deliberately kept
OFF `hooks/ship-gate.sh` (the push blocker).

## Design

### (a) How the delta is computed + the exempt classes

**Changed files** come from the same 4-source union `proof-ledger.sh:_changed` uses, so the
gate sees the same diff the proof gate does (committed `base..HEAD`, working tree, staged,
and untracked), with `base` passed in (default: `git merge-base HEAD <default-branch>` via the
kit's three-way default-branch fallback: `origin/HEAD` symref -> `master` -> `main`).

**Per-file classification** (first match wins, so a test file is never also counted as source):

| Class | Match (path/name, language-agnostic) |
|---|---|
| docs | `\.(md|markdown|txt|rst|adoc)$` |
| generated | `(^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|go\.sum|Cargo\.lock|composer\.lock|poetry\.lock)$`, `\.min\.(js|css)$`, `\.(pb|pb2)\.(go|py)$`, `_pb2\.py$`, `\.generated\.`, `(^|/)vendor/`, `(^|/)node_modules/` |
| test | `(^|/)tests?/`, `(^|/)spec/`, `(^|/)__tests__/`, `(^|/)test-[^/]*$`, `_test\.(go|py|rb|js|ts)$`, `test_[^/]*\.py$`, `\.(test|spec)\.(js|jsx|ts|tsx)$`, `_spec\.rb$`, `Test\.java$`, `Tests?\.(cs|swift)$`, `\.t\.sol$` |
| source | anything else that is a changed file (the load-bearing behavioral surface) |

Precedence is docs -> generated -> test -> source (docs/generated are exempt classes that must
not be mistaken for uncovered source; test must be recognized before source or a test file
would count as an uncovered source change and defeat the whole gate).

**Line counts** come from `git diff --numstat` over the same base + working-tree sources,
summing `added + deleted` per class (a "changed" line is a delete+add pair; summing both
captures edits, not just growth). Binary files (`-` in numstat) contribute 0.

- `src_lines` = added+deleted across SOURCE files.
- `test_lines` = added+deleted across TEST files.

**Verdict** (the three-way boundary the over-test suite pins):

| Condition | Verdict | Meaning |
|---|---|---|
| `src_lines == 0` (only docs/test/generated moved) | **exempt** | no behavioral source change; nothing to cover |
| `src_lines > 0` AND `test_lines == 0` | **FLAG** (warn) | under-tested: source moved, test surface did not |
| `src_lines > 0` AND `test_lines > 0` | **ok** | well-tested: source + test moved together |

The FLAG line NAMES what is under-covered (the source files with no paired test change), so
the warning is actionable, not a bare "under-tested".

### (b) The advisory contract (warn + exit 0; exact stdout)

The gate NEVER blocks. Every path prints exactly one advisory line to stdout and returns 0.
Exit is unconditionally 0 (a `trap`-free, single `exit 0` at the end of `main`; there is no
code path that returns non-zero for a verdict , only a usage error, `return 64`, on a missing
argument, which is a caller bug, not a gate verdict).

Exact stdout shapes:

```
[coverage-delta] exempt: no source change (docs/test/generated only)
[coverage-delta] ok: source + test moved together (src=<N> test=<M> lines)
[coverage-delta] WARNING under-tested: <K> source line(s) changed with no matching test change
[coverage-delta]   uncovered: <file1> <file2> ...            # only on WARNING; names the files
```

`WARNING` (not `BLOCKED`/`FAIL`) is the deliberate severity word: it mirrors ship-gate.sh's
existing `[advisory]` lines, which print and flow through without affecting exit.

### (c) Where the gate hooks into the lifecycle (NOT the push blocker)

The **Review phase** (WORKFLOW.md cycle table: enforcer = `advisory`, the Build->Review
boundary). `commands/review-team.md` gains one advisory step that runs
`bash lib/coverage-delta.sh check "<root>" "<base>"` and folds the `[coverage-delta]` line
into the review report's test-coverage section. This is the SAME live-dispatch pattern the
file already uses for `lib/role-classify.sh classify`. The gate is deliberately NOT wired into
`hooks/ship-gate.sh`: it is off the push/block path entirely (studied ship-gate.sh only to
learn the advisory-vs-block boundary, per the sub-goal's Where-to-look).

The decision is recorded on the gate-ledger via the existing `record` verb (01's `caught=`
outcome marker is not merged yet):
`bash lib/coverage-delta.sh check <root> <base> --rid <rid>` appends
`... | GATE | coverage-delta | ran | <verdict> src=<N> test=<M>` (a `record` line readers
that key on known phases ignore , additive, cannot fake a phase gate). Without `--rid` the
gate is a pure read-only reporter (used by the tests).

### (d) The real-coverage-runner hook

If `COVERAGE_DELTA_RUNNER` is set to an executable, the gate invokes it with the changed
source files as arguments and uses its stdout verdict line (a `covered=<N> uncovered=<M>`
shape) in place of the diff-line heuristic , the escape hatch for a configured target
(pytest-cov / `go test -cover` / c8) that wants a real coverage signal. The runner's OWN exit
code is captured and reported but NEVER propagated: even a runner that exits non-zero leaves
the gate at exit 0 (advisory is preserved regardless of the hook). When the env var is unset
or the target is not executable (the default everywhere today), the diff-line heuristic is
used. This resolves open-fork 3: heuristic default, real-runner hook where configured.

## Acceptance criteria

1. **Under-tested -> FLAG:** a diff that changes a source file with NO matching test change is
   flagged (`WARNING under-tested`), and the warning NAMES the uncovered source file(s).
2. **Well-tested -> quiet (the false-positive negative control, load-bearing):** a diff that
   changes a source file AND a test file does NOT trip (`ok`, not `WARNING`).
3. **Docs-only / test-only -> exempt:** a diff touching only docs, or only tests, or only
   generated files, yields `exempt` (nothing to flag).
4. **ADVISORY , cannot block:** every verdict path (flag, ok, exempt) exits 0. Proven by
   asserting `$? -eq 0` on the FLAG path specifically (a flagged diff still exits 0).
5. **Names what is under-covered:** the FLAG output lists the specific source file(s) that
   moved without a paired test change.
6. **Diff-plumbing reuse:** the gate reads changed files via the same base..HEAD + working-tree
   union proof-ledger uses (no new differ); a staged-but-uncommitted change is seen.
7. **Real-runner hook:** with `COVERAGE_DELTA_RUNNER` pointing at a stub runner, the gate uses
   the runner's verdict; a runner that exits non-zero still leaves the gate at exit 0.
8. **Ledger record:** `check ... --rid <rid>` appends one `| GATE | coverage-delta | ran | ...`
   line carrying the verdict + `src=`/`test=` counts.

## Verification

```
# Acceptance 1-8 (the gate mechanism + advisory contract + runner hook + ledger):
bash tests/test-coverage-delta.sh

# COVERAGE-DELTA row + FALSE-POSITIVE negative control are asserted inside that suite
# (T2 = well-tested does NOT trip; T4 = a flagged diff still exits 0).

# No regression in the structural suite:
bash tests/test-meta.sh 2>&1 | tail -5
```

## Test plan

Coverage matrix (categories x cases), derived from the acceptance criteria:

| # | Category | Case | Asserts |
|---|---|---|---|
| T1 | Happy path / FLAG | source changed, no test change | `WARNING under-tested`; names the source file (AC1, AC5) |
| T2 | FALSE-POSITIVE NC (load-bearing) | source changed + test changed | verdict is `ok`, NOT `WARNING` (AC2) |
| T3 | Exempt / docs-only | only `*.md` changed | `exempt` (AC3) |
| T4 | Advisory-cannot-block | the FLAG fixture, capture `$?` | exit is 0 even when flagged (AC4) |
| T5 | Exempt / test-only | only a test file changed | `exempt` (AC3) |
| T6 | Exempt / generated-only | only a lock/generated file changed | `exempt` (AC3, generated class) |
| T7 | Classification | one path per class through `class` subcommand | docs/generated/test/source each classify correctly |
| T8 | Diff-plumbing reuse | a STAGED-only source change | seen and flagged (AC6, working-tree union) |
| T9 | Real-runner hook | `COVERAGE_DELTA_RUNNER` = stub | gate uses runner verdict; non-zero runner still exit 0 (AC7) |
| T10 | Ledger record | `check --rid <rid>` on a temp ledger | one `\| GATE \| coverage-delta \| ran \|` line w/ src=/test= (AC8) |

COVERAGE-DELTA (recorded post-build): covered = T1-T10 above (the under/well/exempt boundary,
the false-positive NC, the advisory-cannot-block proof, the runner hook, the ledger record).
Uncovered by design = a REAL per-language coverage percentage (the heuristic counts diff lines,
not executed lines , the runner hook is the escape for that where a target configures it); and
a semantic judgement of whether a test actually EXERCISES the changed source (line co-movement
is the portable proxy, deliberately , 04 mutation-smoke is the sibling that bites the suite).

## Out of scope

- The block promotion (advisory-only unless Han blesses; gate-zero).
- A full per-language coverage subsystem (a portable heuristic + an optional runner hook only).
- 04 mutation smoke (sibling sub-goal) and 06 docs-wiring (docs-last).
- Re-implementing the diff plumbing (reuse proof-ledger's changed-files union).
