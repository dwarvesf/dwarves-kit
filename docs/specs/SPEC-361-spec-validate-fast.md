# Spec: faster full-lane spec validation (grounding, delta re-validation)

Generated: 2026-09-29
Status: APPROVED
Lane: full (lane-classify: the change edits the spec validation gate and adds a lib helper)
Type: refactor
File: `docs/specs/SPEC-361-spec-validate-fast.md`
References: `commands/spec.md` (step 5), `commands/spec-validate.md`, `commands/wrap.md` (step 10 full-lane worker), `lib/telemetry/kit-log-dir.sh`, `lib/gate/gate-ledger.sh`

## Problem

A real full-lane task took 4 validation rounds at 5 to 7 minutes each. Two causes:

1. Rounds 2 and 3 found defects the spec writer could have caught alone. Fixtures did not match the real `gh` output shape (a pending CheckRun carries `completedAt:"0001-01-01T00:00:00Z"`, not null). A negative control could not go red against its own fixtures.
2. Every re-validation re-ran all 7 reviewers over a spec that had changed in one or two sections.

The fix must be faster without being weaker: the first validation stays a full pass, and any doubt falls back to a full pass.

## Change

1. **Grounding before handoff.** `commands/spec.md` step 5 and the wrap step-10 worker paragraph: before `Spec ran` or `VALIDATE PENDING`, the writer adds a `## Grounding` section. For each external data shape the spec asserts, one read-only live sample (command plus excerpt, masked). For each negative control, a dry trace: mutation, fixture reads, code path, named test that goes red. A claim that cannot be sampled is stated as such. `commands/spec-validate.md` Reviewer 4: a missing or unsampled `## Grounding` is a warning, never a critical.
2. **Delta re-validation.** `commands/spec-validate.md` gains a "Re-validation" section. The re-run gets the prior report, the folded criticals, and `git diff <last-validated-sha>..HEAD -- <spec>`. It re-checks each folded critical and re-runs only reviewers whose section hash changed; the rest are carried as `carried from <sha>`. `lib/spec/validate-cache.sh` holds the hashes and verdicts. A missing or unreadable cache means a full pass.
3. **Round budget.** `commands/spec.md` step 5 and wrap step 10: the one re-validation after NEEDS REVISION stays. When the operator directed the build, one more delta round is allowed. Each round is recorded in the ledger as today.

## Picture

```
first validation (full, 7 reviewers)
        |  lead: validate-cache.sh store <rid> <spec> <sha> < verdicts
        v
   cache file  <log dir>/validate-cache/<rid>.<spec-basename>.tsv
        ^                                   |
        |                                   v
NEEDS REVISION -> writer folds -> lead: validate-cache.sh plan <rid> <spec>
                                        |
                        rN rerun  /  rN carry <sha>   (cache bad -> all rerun)
                                        |
                  validator: folded criticals + rerun reviewers + git diff
                                        |
                          lead: validate-cache.sh store (merge)
```

## Design

### Approaches considered

1. Section-hash cache in a small shell helper (chosen). The map from reviewer to sections lives in one awk table. A section outside the table goes to every reviewer, so an unknown heading fails closed.
2. Let the validator judge which reviewers to re-run from the diff. Rejected: that is an LLM deciding to skip a check, with no mechanical floor.
3. Always re-run all 7 but on a smaller model. Rejected: it cuts cost, not the round-trip, and weakens the reviewers.

### Reviewer to section map

| Reviewer | Sections read (case-insensitive heading prefix) |
|---|---|
| r1 Security | Solution, Technical Design, Edge Cases, Task Breakdown |
| r2 Failure modes | Solution, Technical Design, Edge Cases, Failure modes, Task Breakdown |
| r3 Assumptions | Problem, Solution, Technical Design, Edge Cases, Task Breakdown, Grounding |
| r4 Scope | Picture, Task Breakdown, After state, Acceptance Criteria, Verification, Out of Scope, Grounding |
| r5 Design critic | Solution, Design, Technical Design, Picture |
| r6 Design record | Design, Picture, Solution, Task Breakdown |
| r7 Sustainability | Solution, Design, Technical Design, After state, Failure modes |

The preamble (lines before the first `##`, which carries `Lane:`) is read by r4 and r6. Any `##` heading matching no row goes to all seven. r6 is the blocking reviewer; its inputs include Solution and Task Breakdown so a design-bearing verdict cannot go stale.

### Interfaces (I/O contract)

`bash lib/spec/validate-cache.sh <verb>`:

- `hashes <spec>` prints `r1 <sha256>` to `r7 <sha256>`.
- `plan <rid> <spec>` prints `HEAD <sha>` (the cached last-validated sha, or `none`), then per reviewer `rN rerun` or `rN carry <sha> <verdict>`. Exit 0 always. Cache missing, unreadable, malformed, or keyed to a different spec path prints all `rerun`.
- `store <rid> <spec> <sha>` reads `rN<TAB><verdict>` lines on stdin for reviewers that just ran. It writes their fresh hashes, keeps an existing line only when its stored hash still equals the current hash, and drops the rest.

Invariants: a reviewer is carried only when the hash of its sections is byte-equal to the hash stored with its verdict. The cache never holds a verdict for a section set that changed. The helper never edits the spec and never calls `gate-ledger.sh`.

Cache path: `$(kit_resolve_log_dir)/validate-cache/<rid>.<spec-basename>.tsv`. Line 1 is `# spec=<path>`; then `rN<TAB><hash><TAB><sha><TAB><verdict>`. Verdict has tabs and newlines flattened to spaces.

## Failure modes

| Failure class | Detection signal | Mitigation |
|---|---|---|
| Cache file missing, empty, or corrupt | `plan` prints all `rerun` | Full pass; fail closed |
| Spec heading renamed so a section leaves the map | Heading matches no row, so it goes to all reviewers | All reviewers rerun; over-run, never under-run |
| Stale verdict carried after a hash collision | SHA-256, not credible | none needed |
| Lead skips `store` after a round | Next `plan` sees the older sha and hashes | Reviewers whose sections changed since then rerun; still safe |
| Two runs share a rid | Cache is keyed by rid and spec path; `store` last-writer-wins | Hash equality is re-checked on every `plan`, so a stale line cannot carry |
| No `shasum` or `sha256sum` | helper exits 1 with a message | Lead treats a nonzero `plan` as a full pass |

## Grounding

External shapes this spec relies on, sampled read-only on 2026-09-29:

| Claim | Command | Excerpt |
|---|---|---|
| The kit log dir resolver prints a path with no trailing newline | `bash -c 'source lib/telemetry/kit-log-dir.sh; kit_resolve_log_dir'` | `/Users/tieubao/.local/state/dwarves-kit/logs` (the next `ls` output began on the same line, so no newline). The helper reads it through `$(...)`, which strips it either way. |
| `shasum -a 256` and `sha256sum` give identical output | `printf 'a\n' \| shasum -a 256` and `\| sha256sum` | both print the same digest, `87428fc5…c4cf25c7` (masked), then `  -` |
| `gate-ledger.sh rid` derives the rid from the branch | `bash lib/gate/gate-ledger.sh rid` on `feat/spec-validate-fast` | `spec-validate-fast` |
| Real specs use varied h2 names | `grep -n '^## ' docs/specs/SPEC-353-observe-hooks-all-events.md` | `## Problem`, `## Solution`, `## Design`, `## Task breakdown`, `## Test plan`, `## Acceptance criteria`, `## Verification`, `## Out of scope`, `## Decision log` |
| macOS awk is BWK awk 20200816 | `awk --version` | `awk version 20200816` |

Consequences: heading match is case-insensitive prefix, and the awk uses no POSIX classes, no `gensub`, no `-v` arrays. `## Test plan` and `## Decision log` are outside the map, so they go to all reviewers.

Negative-control dry trace (AC4, run with `lib/gate/negctl.sh`):

| Step | Detail |
|---|---|
| Mutation | In `validate-cache.sh` `plan`, make the hash comparison always true |
| Fixture reads | `tests/test-validate-cache.sh` builds a spec, stores 7 verdicts, edits only `## Failure modes`, then runs `plan` |
| Code path | `plan` compares the stored hash to the `hashes` output per reviewer |
| Red test | `changed Failure modes reruns r2 and r7 only` sees r2 and r7 as `carry`, so it fails |

Not sampled: the run-time saving. It depends on the model and spec size and is not asserted here.

## Acceptance Criteria (global)

- AC1: `hashes` is stable across two runs on one spec, and editing one section changes exactly the hashes of the reviewers that read it, per the map.
- AC2: `plan` prints all `rerun` on a missing, empty, malformed, or wrong-spec cache.
- AC3: `store` then `plan` on an unchanged spec carries all seven; after a `## Failure modes` edit, only r2 and r7 rerun; after a `## Test plan` edit, all seven rerun.
- AC4: the AC3 assertion goes red under the negative control in Grounding.
- AC5: `commands/spec.md`, `commands/spec-validate.md`, and `commands/wrap.md` carry the three changes; `bash tests/test-meta.sh` passes.

## Verification

`bash tests/test-validate-cache.sh && bash tests/test-meta.sh`

## Edge Cases

1. Spec has CRLF line endings: hash covers the bytes as read, so a CRLF conversion reruns everything. Safe.
2. A folded critical edits only the preamble (`Lane:`): r4 and r6 rerun.
3. First validation has no cache: `plan` prints all `rerun`, which is the full pass.
4. Cache written under one rid, `plan` run under another: no file, full pass.

## Out of Scope

- Caching devs-team, advisor, or test-plan critique results.
- Caching across specs or across branches.
- Any change to the first validation, or to Reviewer 6's blocking rule.

## Touches
- commands/**
- lib/spec/**
- tests/**
- docs/implementation-notes/**

## Tasks

- [ ] T1: `lib/spec/validate-cache.sh` plus `tests/test-validate-cache.sh`, and a row in `lib/README.md`.
- [ ] T2: `commands/spec-validate.md` Re-validation section and the Reviewer 4 Grounding warning.
- [ ] T3: `commands/spec.md` step 5 and `commands/wrap.md` step 10: grounding before handoff, delta re-validation, round budget.

## Decision Log
- DEC-A: unknown headings go to all reviewers, so the cache can only over-run. Rejected: dropping unknown headings, which could carry a stale verdict.
- DEC-B: the lead runs `plan` and `store`, never the read-only validator. The validator stays free of writes.
- DEC-C: the extra delta round needs the operator to have directed the build. Rejected: always allowing it, which lets an unattended loop iterate on its own.
