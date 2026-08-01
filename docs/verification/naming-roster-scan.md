# Proof of done: naming-enforcement rosters derived from live dirs

2026-08-01. Closes finding 6 of `docs/research/2026-08-01-naming-reconciliation.md`: the ADR-0029
retired-suffix ban walked `agents/` only, and the positive-axis check ran over a hardcoded 11-name
list frozen before api/frontend/infra/performance-reviewer, audit-scanner, and claim-verifier
existed. Both checks now roster-scan (same derivation style as the SPEC-219 registry-freshness
pin): the retired-suffix ban walks `agents/` + `commands/` + `skills/`, and the review-agent set is
derived live from `agents/` (read-only tools roster, minus the ADR-0029:89 out-of-scope names).
No renames applied; grandfathered names are pinned in explicit named allowlists
(`RETIRED_GRANDFATHERED="spec-validate"`, finding 3; `AXIS_GRANDFATHERED="audit-scanner"`,
finding 4) with comments pointing at the report's proposal rows. Lane: tiny (test-only diff).

## Green run

Command: `bash tests/test-meta.sh`
Exit: 0
Output: `Passed: 795 / 795` / `All meta tests passed.`
Verdict: PASS. The widened retired-suffix scan covers every agent, command, and skill name;
`commands/spec-validate` and `audit-scanner` pass as explicitly GRANDFATHERED rows (visible debt).
The derived review roster carries a non-vacuous floor (must contain `task-verifier` +
`api-reviewer`) so a broken derivation fails loudly instead of checking nothing. The SPEC-219
`docs/FEATURES.md` freshness pin went RED first (the tested-by column is derived from literal agent
names in test files, which this diff changed) and regenerating drove it GREEN.

Command: the 57-suite CI set (`grep 'run: bash tests/' .github/workflows/test.yml`), run locally
Exit: 0 for 52 of 57 suites
Output: `FAILED: tests/test-bin-forwarders.sh tests/test-outcome-emit-sweep.sh tests/test-command-emit-sweep.sh tests/test-config-registry.sh tests/test-kit-contract.sh`
Verdict: PASS for this diff. The five failures reproduce byte-identically on a clean `git archive
master` tree (verified side by side), so they are pre-existing local-environment divergences
(installed-kit `bin/` census drift, stale command-count pins, `lib/bench` gaps), not caused by this
change. No suite outside test-meta.sh depends on the old hardcoded list; PR CI is the arbiter.

## Negative controls

Planted `commands/dummy-checker.md` (retired `-checker` suffix) and `agents/dummy-scanner.md`
(read-only tools roster, off-axis `-scanner` name), never committed:

Command: `bash tests/test-meta.sh` (with plants)
Exit: 1
Output: `FAIL commands/dummy-checker uses a retired suffix` and
`FAIL review agent 'dummy-scanner' is OFF the ADR-0029 naming axis` (788/805, 17 failed; the other
failures are the plants tripping the pre-existing frontmatter/MANUAL/registry pins, as expected)
Verdict: RED as intended, on both widened axes: a retired suffix in `commands/` now fails, and a
new read-only agent enters the positive-axis roster automatically with no list edit. Plants
removed; suite back to `Passed: 795 / 795`.

Also in-file: the pure-function negative control block gained `is_on_review_axis "foo-scanner"`
(must reject), proving `-scanner` conformance comes only from the named grandfather allowlist.

## Reproduce

```
bash tests/test-meta.sh
# negative control
printf -- '---\ndescription: dummy\n---\n' > commands/dummy-checker.md
bash tests/test-meta.sh   # expect RED on "commands/dummy-checker uses a retired suffix"
rm commands/dummy-checker.md
```
