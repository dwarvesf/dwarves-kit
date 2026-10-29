# SPEC-414: one ledger entry cites a design record in another repo

Generated: 2026-10-30
Status: APPROVED
Lane: full
Depth: standard (every fact is in gate-ledger.sh, ship-gate.sh, ship-rules.sh and two sampled GitHub API calls)
Type: spec-feature
References: `lib/gate/gate-ledger.sh` `inherit()` (a verb that writes coverage for the spec-level gates from a record outside the run, refuses and writes nothing on a bad source; imitate its refusal shape and its fixed phase set); `override()` (the per-gate path that must keep working unchanged); `check()` (the reader every gate consumer shares); `progress()` and `descent()` (the advisory readers); `lib/gate/ship-rules.sh` `ship_rule_floor` (the hard-path message); `hooks/ship-gate.sh` (the lane-check message); `lib/queue/orchestrate.sh:284` (the `GH_CMD` seam for a stubbed `gh`).

## Problem

In consolelabs/console-workers, every `workers/playdate-relay/` branch touches `src/auth.ts`, a hard path. The floor in `ship_rule_floor` then demands every full-lane gate for the branch slug. The design for that worker lives in another repo: consolelabs/playdate-agent (`docs/specs/SPEC-005-relay-link-and-seal.md`, `docs/decisions/0018-link-through-relay-agent-host-plays-bridge.md`, the plan review in `docs/implementation-notes/plan-v1-connect-existing-hermes.md`).

The kit has no way to say "the design gates ran over there". So each relay branch wrote six per-gate overrides by hand, one each for think, design, design-critique, spec, validate and design-record. `override()` refuses a reason already used for another gate, so each line had to carry its own text. The real ledgers (`~/.local/state/dwarves-kit/logs/runs/playdate-relay-*.log`, `relay-*.log`) show the result: `seal contract pinned in playdate-agent SPEC-005 and ADR 0008 with vectors; relay only forwards; gate think`, then the same text ending `gate design`, and so on. The suffix exists only to dodge the duplicate-reason guard. Nothing checks that SPEC-005 exists.

## Terms

- external design citation: one string naming a design record in another GitHub repo. Two forms: `<owner>/<repo>@<40-hex commit>:<path>`, or `https://github.com/<owner>/<repo>/pull/<number>`.
- cite line: the ledger line `<ts> | GATE | external-design | cite | <citation> | <reason>` that the new verb writes.
- covered gates: the fixed set a verified cite line satisfies: think, design, design-critique, spec, validate, design-record.

These terms are local to the gate ledger. The repo has no `CONTEXT.md` glossary, so none is written.

## Solution

### Approaches considered

1. Verb writes six `override` lines with generated reasons (the `inherit` shape). Cheap, every reader works. But a plain override passes `check()` with any text, so the citation would never be checked again at push. It also looks like six human overrides in stats.
2. Verb writes one cite line; `check()` verifies the citation through `gh api` when a covered gate has no ran or override line. One record per citation. Every consumer of `check()` (ship-gate lane check, the hard-path floor, mega-merge, lane telemetry) gets the same rule.
3. Ship-gate alone reads cite lines and verifies them. Keeps `check()` offline, but mega-merge and telemetry would disagree with the push gate about the same ledger.
4. The verb verifies once and stamps the blob or merge sha on the line; `check()` stays offline. No network in the hook, but the push never checks the citation, which the ask requires ("ship-gate verifies the cited path exists at a named commit or the PR is merged").

### Chosen approach + why

Approach 2. The citation is checked at the boundary where it matters, the push, and the rule lives in one reader. Approach 1 and approach 4 traded away the push-time check; approach 3 traded away reader agreement, which `mega-merge.sh` documents as load-bearing.

Threat model, stated once: ledger lines are agent-writable and a plain `override` passes on its text alone. A cite line is therefore no weaker than the six overrides it replaces. What it adds is a pinned pointer that a machine checks and a reviewer can open.

### Extensibility & boundaries

- The growing dimension is citation forms. A new form (a GitLab URL, a local clone) adds one parse branch and one verify branch in `_ext_verify`; the line format and the readers stay fixed.
- `_ext_parse <citation>`: syntax only, no network. `_ext_verify <citation>`: one `gh api` call, exit 0 or 1 with a reason on stderr. `external_design()`: the verb. `check()`: one extra branch for covered gates.

### Architecture

See `## Design`.

## Picture

```
 operator / agent
      |
      | gate-ledger.sh external-design <rid> <citation> "<reason>"
      v
 +-------------------+   _ext_parse (syntax)   +------------------+
 | external_design() |------------------------>| refuse: exit 64  |
 |                   |   _ext_verify (gh api)  +------------------+
 |                   |------------------------>| refuse: exit 1   |
 +-------------------+                          +------------------+
      | one cite line
      v
 runs/<rid>.log  ----read---->  check()  ----per missing covered gate---->  _ext_verify (gh api)
      ^                          ^   ^
      |                          |   +--- ship_rule_floor (hard path, --kit-lanes)
      |                          +------- ship-gate lane check / mega-merge / lane-telemetry
      |
  progress() / descent(): a cite line disposes the covered gates (display only, no network)
```

## Design

### Approaches considered + chosen

See `## Solution`.

### Diagram

```
 push of feat/relay-seal (diff hits src/auth.ts)
   ship-gate -> ship_rule_floor -> check full relay-seal --kit-lanes
     for each required phase:
       ran|override line?  -------------------------- yes -> covered
       no: phase in covered gates AND a cite line exists?
              no  -> MISSING-GATE
              yes -> _ext_verify each distinct citation (memo per call)
                       any verifies -> covered
                       none         -> MISSING-GATE + EXTERNAL-DESIGN: <citation> did not verify: <why>
```

### ADR link(s)

No ADR. The decision is reversible: one verb and one reader branch. The covered-gate set is the lasting choice; DEC-2 records it and the PR asks for review of it.

### Boundaries & failure modes

The verifier talks to GitHub through `gh`. It never reads a local clone. Network, auth or `gh` absence makes a citation unverified, which fails closed. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- New verb: `gate-ledger.sh external-design <rid> <citation> <reason...>`.
  - Exit 64 and write nothing: missing args, empty reason, a citation that fails `_ext_parse`.
  - Exit 1 and write nothing: the citation parses but `_ext_verify` fails.
  - Exit 0: appends one cite line. A second call with the same citation for the same rid prints `already cited` and writes nothing.
- Citation grammar (`_ext_parse`):
  - path form: `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}:<path>$`. Owner and repo are not `.` or `..`. `<path>` is 1-300 chars of `/`-joined segments from `[A-Za-z0-9_.@+-]`, no empty, `.` or `..` segment.
  - PR form: `^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]{0,8}$`.
- Verification (`_ext_verify`), through `"${GH_CMD:-gh}" api`:
  - path form: `api "repos/<o>/<r>/contents/<path>?ref=<sha>" --jq 'if type=="object" then .type else "dir" end'` exits 0 and prints exactly `file`.
  - PR form: `api "repos/<o>/<r>/pulls/<n>" --jq .merged` exits 0 and prints exactly `true`.
  - Each `gh` call is bounded to 4 s by a background-and-kill wrapper (macOS has no `timeout`). A timeout counts as unverified. `KIT_EXT_TIMEOUT_SECS` may lower the bound for tests, never raise it.
  - One `check()` tries at most 2 distinct citations and stops at the first that verifies, so a hang costs at most 8 s against the hook's 30 s budget. A killed hook fails open, so this bound is what keeps fail-closed true.
- `check()`: a required phase in the covered set with no ran or override line passes when at least one cite line in the ledger verifies. A failed citation prints `EXTERNAL-DESIGN: <citation> did not verify: <why>` on stderr, once per citation. A failing result is not written to the check cache when a covered phase is in its fail set and the ledger holds a cite line; a pass is cached as today.
- `check <lane> <rid> --offline` (new flag, may follow `--kit-lanes`): a cite line that parses counts as verified, with no `gh` call, and the check cache is neither read nor written. Lane telemetry passes it. The ship-gate, the floor and mega-merge never do.
- `progress()` and `descent()`: a cite line disposes each covered phase. They never call `gh`.
- Ship-gate and floor block messages: when the gap list names a covered phase, print one extra hint line with the `external-design` command.

### Readers of GATE lines

| Reader | Decision |
|---|---|
| `check()` (ship-gate lane check, floor, mega-merge) | verifies the citation (this spec) |
| `lane-telemetry.sh` shipped-incomplete | calls `check --offline` |
| `progress()`, `descent()` | the cite line disposes the six at its own timestamp; a cite recorded after test-plan still shows the earlier DESCENT lines, which is the truth |
| `ship_rule_large_spec` (normal lane, validate) | unchanged: a cite line does not satisfy it |
| ship-gate impl-notes rule | unchanged: a cite line does not satisfy it |
| `history`, stats, bench, proof-table-gen, pitch, wrap | unchanged: they see phase `external-design`, state `cite` |

### Data model changes

One new ledger line shape (the cite line). `$2` is `GATE`, so readers that filter on `GATE` see a phase named `external-design` with state `cite`. No existing line changes.

### API changes

None beyond the verb.

### UI changes

None.

### Infrastructure changes

None. `gh` is already a kit dependency (`/kit:ship`, `/kit:wrap`, orchestrate).

## Task Breakdown

### Phase 1: Ledger

- [ ] TASK-001: `_ext_parse`, `_ext_verify` and the `external-design` verb in `lib/gate/gate-ledger.sh`, plus the header usage line. Accept: the verb writes exactly one cite line for a verifying citation; it writes nothing and exits 64 on a bare string, a short sha, a `..` segment and a non-PR URL; it writes nothing and exits 1 when `gh` reports 404, a dir, `merged=false`, or `gh` is missing.
- [ ] TASK-002 (needs TASK-001): the `check()` covered-gate branch and its cache rule. Accept: `check full` passes on a ledger with one cite line plus ran lines for test-plan, build, review, docs, ship and reflect; the same ledger fails with one `EXTERNAL-DESIGN:` line and six MISSING-GATE lines when the stub `gh` answers 404; test-plan is never covered; after a failing check on a ledger with a cite line, a second check calls `gh` again (no cached failure).
- [ ] TASK-003 (needs TASK-002): the `--offline` flag on `check`, accepted in either order with `--kit-lanes`, and `lane-telemetry.sh` passing it. Accept: `check full <rid> --offline` passes a parsing citation with zero `gh` calls; `check full <rid> --kit-lanes --offline` and `--offline --kit-lanes` behave the same; `rg -n 'check .*--offline' lib/telemetry/lane-telemetry.sh` has one hit.
- [ ] TASK-004 (needs TASK-001): `progress()` and `descent()` dispose the six covered gates at the cite line. Accept: `progress <rid> full` on a ledger with grill, a cite line and test-plan points at build; `descent <rid> full` on that ledger prints `descent clean`; neither calls `gh`.

### Phase 2: Ship boundary

- [ ] TASK-005 (needs TASK-002): hint line in `hooks/ship-gate.sh` (lane check) and `lib/gate/ship-rules.sh` (`ship_rule_floor`) when a gap names a covered phase. Accept: the floor block message for a hard-path diff with no design gates names `external-design <rid>`; the lane-check block message for a full-lane spec with no design gates names it too.
- [ ] TASK-006 (needs TASK-001 to TASK-005): `tests/test-gate-external-design.sh`. Accept: it holds a named case for edge cases 1 to 13 and 16 to 17, plus `hook: one cite line passes the auth diff`, `hook: a bogus citation blocks the auth diff`, `hook: six per-gate overrides still pass`, and `hook: a second push re-verifies` (the stub flips 200 to 404 between two hook runs on one ledger, the second blocks); every case runs with `GH_CMD` pointing at a stub and no network.
- [ ] TASK-007 (needs TASK-006): docs. `lib/gate/README.md` and `docs/MANUAL.md` gate-ledger rows, the `mega-merge.sh` "no gh calls" comment, CHANGELOG, and `bash lib/registry/feature-registry.sh generate docs/reference/FEATURES.md`. Accept: `bash lib/registry/feature-registry.sh check docs/reference/FEATURES.md` exits 0; `rg -n external-design docs/MANUAL.md lib/gate/README.md CHANGELOG.md` has a hit in each.

## After state

- [ ] `bash lib/gate/gate-ledger.sh external-design <rid> consolelabs/playdate-agent@7e3e190e854c23ecc4571f203970cd993d08b041:docs/specs/SPEC-005-relay-link-and-seal.md "relay design"` writes one cite line. (Today: unknown verb.)
- [ ] A hard-path push with that one cite line plus ran lines for test-plan, build, review, docs, ship and reflect exits 0 at ship-gate. (Today: six per-gate overrides required.)
- [ ] The same push with a citation whose path is missing at the commit exits 2 and prints `EXTERNAL-DESIGN:`. Checkable by `bash tests/test-gate-external-design.sh`.
- [ ] `override <rid> think "<reason>"` behaves byte-for-byte as before, duplicate-reason guard included. Checkable by `bash tests/test-gate-ledger-inherit.sh` and the override cases in `tests/test-hooks.sh`.

## Quality requirements

none

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria.
- [ ] Tests cover the happy path and every edge case below.
- [ ] No regressions: `bash tests/run-all.sh --changed` is green.

## Verification

`bash tests/test-gate-external-design.sh && bash tests/test-gate-ledger-inherit.sh && bash tests/test-lanes-data.sh && bash tests/run-all.sh --changed origin/master`

## Edge Cases

1. A bare string (`playdate-agent SPEC-005`) as the citation: exit 64, nothing written.
2. A branch name or short sha in place of the 40-hex commit: exit 64 (a branch can move; the record must be pinned).
3. A path that exists in the repo but not at the cited commit: `gh` 404, exit 1.
4. A directory path: the API returns an array, the jq prints `dir`, exit 1.
5. A closed, unmerged PR: `merged=false`, exit 1.
6. A hand-appended cite line with a bogus citation (bypassing the verb): `check()` re-verifies and fails the covered gates.
7. A cite line plus an explicit per-gate override for one covered gate: both count; the override needs no network.
8. Two cite lines, one bogus and one real: the real one covers; the bogus one prints its `EXTERNAL-DESIGN:` line only when no citation verifies.
9. A private design repo the token cannot read: `gh` 404 or 403, the citation fails like a missing path.
10. `gh` missing or unauthenticated at push: every citation fails, the push blocks with the `gh` error in the reason; per-gate overrides still unblock it.
11. A citation with a newline or ` | ` inside: `_ext_parse` refuses it (the grammar has neither), so no ledger forgery.
12. test-plan, build, review, docs, ship, reflect missing with a valid cite line: still MISSING-GATE; a design record never covers the change's own tests or build.
13. A lane that does not require a covered gate (normal, bug): the cite line is inert.
14. Owner or repo spelled in another case (`ConsoleLabs/...`): GitHub resolves it, the verb's `already cited` check compares exact text, so a second cite line can land. Harmless: both verify.
15. The floor block message: the `EXTERNAL-DESIGN:` line sits inside the indented gap list, below the MISSING-GATE lines.
16. `gh` hangs: the call is killed at 4 s and the citation is unverified; the push blocks.
17. A cite line recorded after test-plan: progress shows the six done; descent prints the out-of-order lines.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| GitHub or `gh` unreachable at push | `EXTERNAL-DESIGN: ... did not verify: gh: ...` on the block | Retry the push, or record per-gate overrides; fail closed by design |
| `gh` hangs inside the hook | push latency | each call is killed at 4 s, at most 2 citations per `check()`, so at most 16 s across the lane check and the floor; a timeout is unverified |
| Every push re-verifies | up to 2 x 2 `gh` calls per push (lane check, then floor) | expected: ship-gate appends OUTCOME lines to the ledger before each check, so the check cache never holds a pass for a pushed rid; the cost is a few hundred ms per call |
| Lane telemetry scanning every ledger over the network | telemetry run time | telemetry calls `check --offline`, so it makes no `gh` call |
| Cited repo deleted, made private, or the token loses access | a later push of the branch blocks with `EXTERNAL-DESIGN: ... did not verify` | record per-gate overrides for that rid; a merged PR is unaffected because nothing re-pushes it |
| GitHub down or rate limited (403) at push | the block names the `gh api` error | wait and retry, or per-gate overrides; an unattended mega-merge holds the merge |
| Private repo the token cannot see | `gh` answers 404 or 403, so the block names the `gh api` failure | grant the token read on the design repo, or use per-gate overrides |

## Out of Scope

- A `--covers` flag to narrow the covered set. A record that covers fewer gates uses per-gate overrides for the rest.
- Non-GitHub hosts and local-clone verification.
- Changing `override()`, `inherit()` or the duplicate-reason guard.
- Fork-network commits. GitHub can resolve a fork's commit through the parent repo's API; v1 does not prove the commit is on the cited repo's default branch.
- A `GH_CMD` or `PATH` stub in an agent shell makes citations verify there. The hook runs with the harness environment, and the ledger is agent-writable anyway (see the threat model).
- Relevance. Verification proves the record exists, never that it is about this change: any file at any commit of any readable repo passes. The reason text and the PR review carry relevance. No repo allowlist in v1.
- `record-batch` and `plan-record` do not accept a cite item; the verb is one call on its own.
- An offline switch for advisory readers. An environment flag that skips verification would also skip it at the push, so there is none.
- Stats and bench dashboards: they see an `external-design` row with state `cite` and treat it as their default.

## Grounding

Sampled 2026-10-30 against the real cited repo, read-only:

```
$ gh api "repos/consolelabs/playdate-agent/contents/docs/specs/SPEC-005-relay-link-and-seal.md?ref=7e3e190e854c23ecc4571f203970cd993d08b041" --jq '{type, path, size}'
{"path":"docs/specs/SPEC-005-relay-link-and-seal.md","size":7559,"type":"file"}   rc=0
$ gh api "repos/consolelabs/playdate-agent/contents/docs/specs/NOPE.md?ref=7e3e…b041" --jq .type
{"message":"Not Found",...,"status":"404"}gh: Not Found (HTTP 404)                 rc=1
$ gh api "repos/consolelabs/playdate-agent/contents/docs/specs?ref=7e3e…b041" --jq type
array                                                                              rc=0
$ gh api repos/consolelabs/playdate-agent/pulls/35 --jq '{merged, state, merge_commit_sha}'
{"merge_commit_sha":"d8a564ce…f84634","merged":true,"state":"closed"}             rc=0
```

The 404 prints its body on stdout with rc 1, so `_ext_verify` checks both the exit code and the exact printed value. The floor sample: `lane-classify.sh floor ~/workspace/consolelabs/console-workers 0f308e1~1 99009ec` prints `full auth: workers/playdate-relay/src/auth.ts`.

Negative controls (dry trace):

- Mutation: `check()` accepts any cite line without calling `_ext_verify`. Fixture: a ledger with a cite line and a stub `gh` that returns 404. Path: `check full` -> covered branch -> pass. Red test: `bogus citation fails check` in `tests/test-gate-external-design.sh`.
- Mutation: the covered set includes test-plan. Fixture: cite line, no test-plan line. Red test: `test-plan never covered`.
- Mutation: `_ext_parse` accepts a short sha. Red test: `short sha refused`.

## Decision Log

- DEC-1: one cite line, not six override lines. A plain override is never re-checked, and the ask is one ledger entry. Rejected: the `inherit` shape (approach 1).
- DEC-2: the covered set is think, design, design-critique, spec, validate, design-record, derived in code as `inherit`'s `INHERITABLE` minus test-plan so the two lists cannot drift. These are the six gates the relay ledgers overrode by hand, and `inherit`'s set minus test-plan. test-plan stays with the change: the relay's own tests live in this repo, not the design repo. Han reviews this choice on the PR.
- DEC-3: a 40-hex commit is required in the path form. A branch ref can move after the push; a commit cannot.
- DEC-4: verification goes through `gh api`, with `GH_CMD` as the test seam (the `orchestrate.sh` convention). Fail closed on any `gh` error.
- DEC-6: no owner allowlist and no check of the record's own Status line. Either would add config or assume the other repo follows kit conventions, and neither closes the override path (see the threat model). Han reviews this on the PR.
- DEC-5: `check()` verifies only when a covered phase has no ran or override line, so a ledger without cite lines makes zero network calls.

## Open questions

(none)
