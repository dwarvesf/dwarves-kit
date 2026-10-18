# Proof of done: the ship-gate refuses a push while the spec review verdict is DO NOT SHIP

Acceptance: `hooks/ship-gate.sh` exits 2 on `git push` and `gh pr create` when the LAST canonical `Verdict:` line inside the branch spec's `## Review` section(s) is `DO NOT SHIP`. A section with no verdict, no section, an unreadable spec, or `[gate] review_verdict = false` on the default branch passes. Lane: full (the diff touches `hooks/` and `lib/`; the classifier suggested full). Files: `hooks/ship-gate.sh`, `lib/gate/ship-rules.sh`, `lib/gate/gate-policy.sh`, `kit.toml`, `tests/test-ship-gate-review-verdict.sh`, plus the docs that claimed the block.

## The gap this closes

| Claim | Where | What the code did |
|---|---|---|
| "ship gate (blocks on DO NOT SHIP)" | `docs/WORKFLOW.md`, `examples/hello-spec/WORKFLOW.md`, `docs/workflow-paths.md`, `docs/MANUAL.md`, `docs/architecture.md` | no hook or lib/gate file read the verdict; only the `/kit:ship` prose stopped |
| the review gate is satisfied | `gate-ledger.sh check` | any `review ran` record passed, whatever its verdict |

## Green run

```
Command: bash tests/test-ship-gate-review-verdict.sh
Exit: 0
Output:
  ok - DO NOT SHIP blocks and names the spec
  ok - SHIP passes
  ok - FIX THEN SHIP passes
  ok - no Review section passes
  ok - Review section without a verdict passes
  ok - gh pr create blocks too
  ok - last wins: DO NOT SHIP then SHIP passes
  ok - last wins: SHIP then DO NOT SHIP blocks
  ok - an uncommitted edit to SHIP does not clear a committed DO NOT SHIP
  ok - unreadable spec: the hook neither crashes nor blocks on this rule
  ok - key off (on the default branch): DO NOT SHIP passes
  ok - key off is logged as OFF-BY-CONFIG
  ok - key off but uncommitted: still blocks
  ok - key off committed only on the branch: still blocks
  ok - the block is written to ship-gate.log
  ok - review_verdict resolves ON by default
  pass=37 fail=0
Verdict: PASS
```

The real flow, a spec ending in DO NOT SHIP driven through the real hook in a temp repo, then the same spec after a re-review replaced the verdict:

```
Command: bash <scratch>/rv-demo.sh
Output:
  --- DO NOT SHIP, push:
  BLOCKED: ship-gate. The '## Review' section of spec 'demo' ends in the verdict DO NOT SHIP:
    <repo>/docs/specs/SPEC-001-demo.md
  Fix what the review found, then re-run /kit:review (or /kit:review-team), commit the spec, and push again. The re-run replaces the '## Review' section, so the new verdict clears this block.
  A project that does not want this check: set 'review_verdict = false' under [gate] in a committed .kit.toml.
  exit=2
  --- ship-gate.log:
  BLOCKED | ship-gate | demo (review verdict DO NOT SHIP)
  --- after the re-run replaced the verdict with FIX THEN SHIP, push:
  exit=0
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 0
Output:
  run-all: --changed against 60493c21: 20 changed files -> 76 suites (73 named, the rest always-on)
  run-all: all 76 suites passed, 0 skipped for missing tooling
Verdict: PASS, no regression
```

The changed set includes `test-hooks`, `test-lanes-data`, `test-gate-opt-in`, `test-gate-opt-out`, `test-adopt`, `test-config-registry`, `test-meta`, every `test-ship-gate-*` suite and `test-wrap-land`.

## Negative control

```
Command: bash tests/test-ship-gate-review-verdict.sh
Exit: 0 (green before mutation)
Mutation: perl -i -pe 's/^ship_rule_review_verdict .*/true/' hooks/ship-gate.sh
Changed: hooks/ship-gate.sh
Exit: 1 (under mutation, RED expected)
Output:
  ok - key off (on the default branch): DO NOT SHIP passes
  NOT ok - key off is logged as OFF-BY-CONFIG
  NOT ok - key off but uncommitted: still blocks (rc=0)
  ok - key off committed only on the branch: still blocks
  NOT ok - the block is written to ship-gate.log
  ok - review_verdict resolves ON by default
  ok - review_verdict is a known gate key
  pass=23 fail=14
Restore: git checkout HEAD -- hooks/ship-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Disabling the hook call turns 14 of 37 cases red (every DO NOT SHIP block case); the restore returns the suite to 37 of 37.

## Review

Two read-only lenses (security and bypass, architecture and tests) returned FIX THEN SHIP. Applied: the spec is read as committed at the pushed head; history bullets, quotes, indented code and tilde fences no longer read as verdicts; the spec path and slug are stripped of control characters in the message and log; `commands/review-team.md` writes the verdict as a level-3 heading so it stays inside `## Review`; this proof file. Accepted: the verdict lives in a file the branch controls, so the rule checks the spec's own record and is not a tamper check; `spec_for_slug` takes the first matching spec, a flaw the lane checks share.

## Not proven

- The rule does not read the ledger's `review ran` verdict text; only the spec line counts.
- `lib/goal/mega-merge.sh` does not call the rule (it calls neither the identities rule); a mega-loop merge is not gated on the verdict.
- A heading variant such as `## Review (round 2)` is not a `## Review` section and fails open.
