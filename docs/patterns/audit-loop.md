# The audit-loop pattern

One repeatable shape for every "go through all X and make sure each one is still right" job: memory stores, doc sets, research notes, test-coverage checks, feature liveness, backlog reconciles. An audit loop enumerates a set of items, judges each against a contract with checkable evidence, fixes what fails, and ships the changes through a gate the operator approves.

This doc is the template. A concrete audit is a thin instance that fills four slots. The loop-engineering skill is the driver you attach when a run must survive interruption or recur on a cadence; it is not part of the pattern itself.

## The skeleton

```
enumerate ITEM SET (discrete list, written down first)
      |
      v
per item: VERDICT against the CONTRACT, with EVIDENCE
      |         OK / FIX <how> / REMOVE <why> / UNSURE / DANGER
      v
apply on an isolated branch (merges preserve history; indexes derived, not hand-edited)
      |
      v
verify (removed names grep to zero; counts reconcile)
      |
      v
GATE: a PR the operator approves; UNSURE items listed, never auto-resolved
      |
      v
repeat next cadence, or hand the item list to a loop runtime for big sets
```

## The four slots an instance fills

| Slot | Question | Examples |
|---|---|---|
| Item set | What gets enumerated? | memory notes; docs/ files; acceptance criteria; shipped features; backlog rows |
| Contract | What must be true per item? | "referenced paths exist"; "doc claims match source"; "criterion has a test that fails when the code reverts"; "feature has usage" |
| Evidence class | What proves a verdict? | a tested file referent; a named superseding artifact; a shipped commit; a test run; a usage query (analytics, logs, flag states) |
| Apply mechanics | How do fixes land? | edit + merge-preserving-history; delete with named successor; new test; deprecation PR |

## Verdict grammar

- **OK**: contract holds, evidence spot-checked.
- **FIX**: contract fails in a way the auditor can repair (path drift, missing test, outdated claim). Say how.
- **REMOVE**: superseded by a NAMED artifact, or the event concluded, or codified elsewhere (name the place). Never "obviously stale".
- **UNSURE**: only the operator can answer. Never auto-resolved; always listed in the gate PR.
- **DANGER**: the item actively recommends something that contradicts current policy. Worse than stale; someone may follow it. Quote the contradiction, fold the still-true parts into the policy-carrying artifact, then remove or mark superseded.

Hard rules: a verdict with no checkable evidence downgrades to UNSURE. Evidence you cannot test from where you run (another host, another tenant, missing usage data) is UNTESTABLE, never REMOVE. Pending retirement is not concluded.

## SDLC instances (what this looks like in product work)

| Instance | Item set | Contract | Evidence |
|---|---|---|---|
| Doc drift | docs/ + runbooks | every claim matches the live source | the codebase itself |
| Test coverage | spec acceptance criteria | each criterion has a test that goes red when its code reverts | test runs (revert -> RED -> restore) |
| Feature liveness | shipped features/flags | each feature has real usage | analytics, request logs, flag states; no data = UNSURE |
| Memory store | .claude/memory notes | fact still true, referents alive | tested paths, superseding notes |
| Backlog reconcile | board rows | row status matches reality | commits, PRs, deploy state |

## The loop bridge

Write the item enumeration as a discrete, reproducible list (a command or a script, not "look around"). That single discipline makes any instance adoptable by a loop runtime with zero rework: the runtime turns the list into a queue, tracks per-item state, and resumes mid-set. Drivers, smallest first: one interactive pass (default), `/loop` or a schedule for cadence, the loop-engineering runtime for large sets that need resume. See the loop-engineering skill for the driver side.

## Known instances

`memory-tidy` and `stale-sweep` (personal skills, ops-toolkit/dotfiles) are the first two instances; the 2026-07-31 memory-store run (140 notes -> 127, three DANGER items caught) is the worked example. Derivation record: ops-toolkit `research/2026-07-31-claude-md-stack-architecture.md` §4.

`skills/doc-drift/SKILL.md` (in-kit) is the built form of the Doc-drift row above: living docs only (dated records excluded), a two-tier evidence pass per the loop-engineering cheap-first split (mechanical grep/ls/diff on every file, model judgment only where flagged or high-traffic), PR-gated.
