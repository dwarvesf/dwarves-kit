# Spec: Advisory mutation smoke -- flag a suite that does not bite

Generated: 2026-07-04
Status: VALIDATED
Lane: normal (adds one advisory lib `lib/mutation-smoke.sh` + a `mutation` additive marker on
`lib/gate-ledger.sh` + a focused test suite + CI wiring. Advisory-only, off the push blocker;
no existing reader/contract changes, so not full lane, but design-bearing because the mutation
strategy + restoration safety + the runtime bound must be pinned before code.)

## Problem

Sub-goal 03 (coverage-delta) can see whether a changed line HAS a test near it (did the diff move
coverage the right way). It cannot see whether that test actually BITES: a suite can be green on
mutated code. A test that exercises a line but asserts nothing meaningful about it passes whether
the line is correct or broken. That is a FALSE PROOF -- a green suite that would stay green if the
code were wrong.

`task-verifier` (and the whole right-arm verifier stack) is structurally unable to catch this: it
runs the suite and trusts a green result. It has no way to ask "would this suite have stayed green
if the code were subtly wrong?" That question needs a mutation: change the code, re-run, observe.

The effectiveness-audit thread "task-verifier rubber-stamps / a green suite that does not bite" is
the motivation. This smoke is the check task-verifier structurally cannot be. It is the
HONESTLY-PROVEN pillar of the triad: a green suite that passes on mutated code is not a proof.

## Solution

### Approaches considered

1. **A cheap advisory smoke: a small fixed operator set on the CHANGED HUNKS ONLY, first surviving
   mutation flags, restore after each run, bounded mutation count.** Reuses the verifier's
   test-runner detection approach (portable detector + env override), warns + records + exits 0.
   CHOSEN (open-fork 4 default). Bounded runtime is a hard requirement; this satisfies it (a handful
   of textual mutations, stop at the first survivor, no whole-tree sweep).

2. **A full mutation-testing sweep (mutmut / go-mutesting / Stryker per language).** Rejected for
   this sub-goal: slow (minutes-to-hours), per-language tool sprawl, and out of scope (the roadmap
   scopes 04 to a cheap smoke, not a sweep). A real sweep is a future promotion, not the advisory
   default.

3. **Mutate a COPY of the repo and run there.** Rejected: the suite's runner resolves paths relative
   to the real working tree (relative `source`, `tests/` layout, `go test ./...`); a copy would need
   the whole runner re-pointed. Simpler and safer: mutate the real file, back up its exact bytes
   first, restore immediately after each run, and PROVE the tree is byte-identical at the end.

### Chosen shape

`lib/mutation-smoke.sh run` (a) computes the changed hunks vs a base ref, (b) collects mutation
CANDIDATES from added code lines that a small fixed operator set can mutate, (c) runs the suite
once pre-mutation and requires GREEN (else it SKIPs -- a red baseline cannot distinguish bite from
pre-existing red), then (d) for each candidate up to a cap: apply ONE mutation, re-run the suite,
restore the file; a SURVIVING mutation (suite still green) FLAGs and stops (first-survivor), a
CAUGHT mutation (suite red) is evidence of bite and the loop continues. All candidates caught (or
none available) => no flag. It always exits 0, warns to stderr, and records its verdict on the
gate-ledger as a new additive `| MUTATION |` marker.

## Design

### (a) Mutation strategy (operator set + changed-hunks-only + first-survivor-stops)

**Scope = added code lines in the changed hunks only.** `git diff <base>` unified output is parsed;
only `+` lines (added), mapped to their NEW-file line numbers via the `@@ -a,b +c,d @@` hunk headers.
Test / doc / non-code files are excluded (paths matching `tests?/`, `test-`, `_test`, `.test.`,
`spec`, `*.md`, `docs/`) so the smoke mutates the CODE under test, never the tests themselves.

**Operator set (small, fixed, portable, language-agnostic textual):**

| Operator | Mutation | Rationale |
|---|---|---|
| relational | `==`↔`!=`, `>=`↔`<`, `<=`↔`>`, `>`↔`<=`, `<`↔`>=` | flips a branch condition |
| logical | ` && `↔` \|\| ` | flips short-circuit logic |
| boolean literal | `true`↔`false` (word-bounded) | flips a constant |
| arithmetic | ` + `↔` - ` | perturbs a computation |
| shell return | `return 0`↔`return 1`, `exit 0`↔`exit 1` | flips a status |

Exactly ONE operator is applied to ONE occurrence on ONE line per mutation attempt (the first
matching occurrence). The set is deliberately small: this is a smoke, not a sweep.

**First-survivor-stops:** candidates are tried in diff order; the FIRST mutation that SURVIVES (the
suite stays green) flags the suite as non-biting and the loop stops. This bounds cost to "until the
first hole is found" in the flag case, and to the cap in the clean case.

### (b) Bite detection (pre-mutation GREEN -> mutate -> re-run -> survival = still-green)

1. Run the suite once, unmutated. If it is NOT green, SKIP (exit 0, note): a red baseline makes
   "did the mutation break it" unanswerable. Honesty over a false signal.
2. For each candidate mutation: apply it, run the suite, capture the exit code, restore the file.
   - suite exit != 0 (RED) => the mutation was CAUGHT (the suite bit) -> good; continue.
   - suite exit == 0 (GREEN) => the mutation SURVIVED (the suite did not notice broken code) ->
     FLAG this suite as non-biting; stop.
3. If every attempted mutation was caught (or there were no candidates), the suite BITES -> no flag.

### (c) Advisory contract (warn + exit 0, cannot block)

Every terminal path returns 0. A flag is a `stderr` WARN line (`[MUTATION-SMOKE] WARN: ...`) plus a
`| MUTATION | verdict=flag ...` ledger marker; it never returns non-zero, sets no gate, and is wired
OFF the push blocker (an opt-in advisory phase, like `/kit:review` and coverage-delta). The
FALSE-POSITIVE negative control (a genuinely biting suite is NOT flagged) is load-bearing: a smoke
that flags a good suite is noise. Proven by test.

### (d) Code restoration (mutate in place, restore after; clean tree after)

The suite must run against the real working tree, so the target file is mutated IN PLACE. Safety:

- Before the FIRST mutation of a file, its exact bytes are copied to a private `mktemp` backup.
- The mutation rewrites the single target line via a `sed -n` head/tail split + `printf` (portable,
  NO `sed -i` -- which needs `sed -i ''` on BSD and `sed -i` on GNU -- and no `awk -v` escaping).
- After each suite run the file is restored from its byte backup (`cp` back).
- An `EXIT`/`INT`/`TERM` trap restores every backed-up file and removes the backups, so an interrupt
  mid-run cannot leave mutated code behind.
- The run ends by asserting `git status --porcelain` over the touched files is empty (byte-identical
  tree). The clean-tree-after property is PROVEN by test (a mutated-then-restored file hashes
  identically to the original).

### (e) The runtime bound (hard requirement)

- `MUTATION_SMOKE_MAX` (default 5) caps the number of mutations attempted. The loop stops at the cap
  even if none survived.
- First-survivor-stops caps the flag case earlier.
- Candidate collection itself is bounded (only added lines in changed hunks, only lines an operator
  matches).
- No whole-repo scan, no per-file combinatorial mutation. Worst case = `MAX` full suite runs plus
  one baseline run. A full mutation sweep is explicitly OUT of scope.

### (f) Test-runner detection (reuse the verifier's approach, do not invent a runner)

Mirrors `agents/system-verifier.md` / `task-verifier`'s detection (README/package scripts/native):
`MUTATION_SMOKE_TEST_CMD` env override wins; else `package.json` test script -> `npm test`;
`go.mod` -> `go test ./...`; `pyproject.toml`/`setup.py`/`pytest.ini` -> `pytest`;
`Cargo.toml` -> `cargo test`; a `Makefile` `test:` target -> `make test`; a `tests/` dir with
`test-*.sh` -> run those. No detected runner => SKIP (exit 0, note). It does not build a new runner.

### (g) Recording the decision (additive `| MUTATION |` marker, reuse the idiom)

`gate-ledger.sh` gains a `mutation` subcommand emitting `ISO8601 | MUTATION | verdict=<flag|clean|skip>
[file=... op=... reason=...]` -- the SAME additive shape `tokens`/`debt` already ride. Every existing
reader keys on `$2=="GATE"|START|ACTION`, so a `MUTATION` line is ignored by `check`/`override`/
`descent`/`_rows` and can never fake or satisfy a gate. This is the additive property the kit relies
on; no reader changes. (Independent of sub-goal 01's `caught=` marker -- different surface.)

## Acceptance criteria

1. **Biting suite fails on mutation:** given a suite whose test asserts the mutated line's behavior,
   a mutation injected into the changed code makes that suite FAIL (exit != 0) -- the mechanism can
   observe a bite.
2. **Non-biting suite is FLAGGED:** given a suite that runs the changed code but asserts nothing
   that the mutation breaks, the smoke flags it (`verdict=flag`, a WARN line).
3. **FALSE-POSITIVE negative control (load-bearing):** given a genuinely biting suite, the smoke does
   NOT flag it (`verdict=clean`, no WARN). A good suite is quiet.
4. **Clean tree after (no residue):** after a run (flag OR clean), every mutated file is byte-identical
   to before (same hash); `git status --porcelain` shows nothing from the smoke.
5. **Advisory cannot block:** a FLAGGED run exits 0. The smoke sets no gate and no reader treats its
   marker as a gate; a `check` for a required gate is unaffected by a `MUTATION` line.
6. **Runtime bounded:** the smoke attempts at most `MUTATION_SMOKE_MAX` mutations (default 5) and
   stops at the first survivor; it never runs a whole-tree sweep.
7. **Baseline-red SKIP:** if the pre-mutation suite is already red, the smoke SKIPs (`verdict=skip`,
   exit 0) rather than emitting a false flag.
8. **Additive marker safety:** a `| MUTATION |` ledger line is ignored by `gate-ledger.sh check`
   (it never satisfies nor blocks a required gate).

## Verification

```
# All acceptance criteria (the smoke mechanism + the marker):
bash tests/test-mutation-smoke.sh

# Additive-marker regression (MUTATION line does not disturb existing readers):
bash tests/test-ledger-durability.sh 2>&1 | tail -3
bash tests/test-meta.sh 2>&1 | tail -3
```

## Test plan

Coverage matrix (categories x cases), derived from the acceptance criteria:

| # | Category | Case | Asserts |
|---|---|---|---|
| T1 | Bite (core) | biting suite + a mutation | suite run under mutation exits != 0 (bite observable) |
| T2 | Flag (core) | non-biting suite (runs code, weak assert) | `verdict=flag`, WARN emitted |
| T3 | FALSE-POSITIVE NC | biting suite | `verdict=clean`, NO flag, NO WARN (load-bearing) |
| T4 | Clean tree | after a flag run AND after a clean run | mutated file hash == original hash; porcelain clean |
| T5 | Advisory | a flagged run | exit code 0 |
| T6 | Bounded | a diff with many mutable lines, all caught | attempts <= MAX; stops; no full sweep |
| T7 | Baseline red | pre-mutation suite already failing | `verdict=skip`, exit 0, no flag |
| T8 | Marker safety | a `MUTATION` line in a ledger with a required gate | `check` still reports the gate missing (marker ignored) |
| T9 | No runner | a repo with no detectable test command | `verdict=skip`, exit 0 |
| T10 | Portability | mutate+restore via sed-split (no `sed -i`, no `stat -f`) | restore is byte-exact on the CI shell |
| T11 | Scope | a diff touching only tests/docs | no candidates -> `verdict=skip` (mutates code, not tests) |

COVERAGE-DELTA (recorded post-build): covered = T1-T11 (bite, flag, the false-positive NC, clean-tree,
advisory-exit-0, bounded, baseline-red skip, marker additive-safety, no-runner skip, portability,
test/doc scope-exclusion). Uncovered = a REAL polyglot suite run (the tests use a controllable bash
fixture suite as the runner, the strongest portable stand-in; a live `npm test`/`go test` mutation is
not re-run in CI), and semantic-equivalent mutations (a mutation that is behaviorally a no-op would
read as a false survivor -- accepted noise for an advisory smoke, called out, not solved here).

## Out of scope

- 03 coverage-delta (sibling sub-goal).
- A full/slow mutation-testing sweep (this is a bounded smoke on changed hunks only).
- Promotion to a push-blocking gate (advisory by gate-zero; a block needs Han's bless).
- A new test runner (reuse the verifier's detection).
- 06 docs-wiring (AGENTS/WORKFLOW/CLAUDE full wiring is the last sub-goal).
- Semantic-equivalence detection of mutations (accepted noise for a smoke).
