# Spec: spec helpers resolve co-located specs

Generated: 2026-10-04
Status: VALIDATED
Lane: full
Depth: standard (every fact settles by reading the five callers and sampling two repos' spec trees)
Type: spec-feature
Source: operator brief, session 2026-10-04. A session in `tieubao/ops-toolkit` recorded three validation rounds by hand because the helpers below missed `tools/circle/docs/specs/`.
References: `lib/spec/spec-index.sh:68` already walks every `*/docs/specs/SPEC-*.md`; imitate its "find under the root, skip `.git`" shape, not its per-namespace grouping.

## Problem

Consumer repos keep a tool's spec next to the tool: `tools/<x>/docs/specs/SPEC-NNN-<slug>.md`. Five kit helpers look only in the repo-root `docs/specs/`:

| Caller | Today |
|---|---|
| `lib/spec/spec-next.sh` `_scan_numbers` | `next` answered 142 while `tools/circle/docs/specs/SPEC-147-*` existed |
| `lib/gate/gate-ledger.sh` `validate-round open` (line 1105) | exits 1 `no docs/specs/SPEC-*-<slug>.md under '<top>'` even when given the exact co-located path |
| `hooks/ship-gate.sh` (line 350) | finds no spec, falls to `_floor_check`, never reads the spec's `Lane:` header |
| `lib/gate/proof-ledger.sh` `_negctl_required` (line 361) | never sees a co-located `Lane: full`, so it falls back to the classifier |
| `lib/pitch.sh` `_find_spec` (line 55) | reports "no spec" for a co-located run |

The brief names the first three. The last two hold the identical glob, so one shared resolver fixes all five.

## Solution

### Approaches considered

1. **One sourced resolver, `lib/spec/spec-find.sh`.** Two functions; every caller swaps its glob for one call. Tradeoff: one more lib file every caller must reach.
2. **Patch each glob in place with its own `find`.** No new file. Tradeoff: five copies of the depth, prune list and tie-break, which drift apart. The tie-break must agree between `validate-round` and ship-gate, so drift here is a correctness bug.
3. **`git ls-files` instead of `find`.** Fast and ignores untracked noise. Tradeoff: misses an uncommitted spec, and `spec-next` deliberately counts a sibling worktree's uncommitted spec file.

### Chosen approach + why

Approach 1. `validate-round` refuses unless its pick equals ship-gate's pick, so both must call the same code. Five callers clears the kit's three-copies rule for a shared helper.

### Extensibility & boundaries

- Load-bearing dimension: the number of directories under the root. The walk stops at depth 7 (a `docs/specs` dir at most 4 directories below the root) and prunes every dot-directory and `node_modules`. Measured: 56 ms on ops-toolkit (256 co-located specs), 34 ms on this repo.
- `spec_files <root>`: lists spec files in pick order. `spec_for_slug <root> <slug>`: the first listed file whose name matches. A root file matches today's glob `SPEC-*-<slug>.md`. A co-located file matches only the exact basename `SPEC-<digits>-<slug>.md`. Each function is testable alone by sourcing the file.

## Picture

```
 callers (before: ls "$root"/docs/specs/...)          resolver (new)
 ┌──────────────────────────────┐
 │ spec-next.sh _scan_numbers   │──spec_files──────┐
 └──────────────────────────────┘                  │
 ┌──────────────────────────────┐                  ▼
 │ gate-ledger.sh validate-round│──┐      ┌──────────────────────────┐
 └──────────────────────────────┘  │      │ lib/spec/spec-find.sh    │
 ┌──────────────────────────────┐  │      │  spec_files <root>       │
 │ hooks/ship-gate.sh           │──┼─────▶│   1. <root>/docs/specs   │
 └──────────────────────────────┘  │      │   2. */docs/specs, ≤4 up │
 ┌──────────────────────────────┐  │      │      shallow first, C    │
 │ proof-ledger _negctl_required│──┤      │  spec_for_slug <root> <s>│
 └──────────────────────────────┘  │      │   first SPEC-*-<s>.md    │
 ┌──────────────────────────────┐  │      └──────────────────────────┘
 │ pitch.sh _find_spec          │──┘ spec_for_slug (co-located: exact SPEC-<digits>-<s>.md)
 └──────────────────────────────┘
 validate-round pick == ship-gate pick, because both call spec_for_slug
```

## Design

### Approaches considered + chosen

See `## Solution`.

### Diagram

Flowchart of `spec_for_slug <root> <slug>`:

```
 ls <root>/docs/specs/SPEC-*.md          (locale order, exactly today's ls)
        │ then
 cd <root>; find . -maxdepth 7
   prune: any .?* dir, node_modules
   keep:  */docs/specs/SPEC-*.md, not ./docs/specs/*
   sort:  path depth asc, then LC_ALL=C path
        │
 walk the list; first match wins:
   root file:       basename glob SPEC-*-<slug>.md   (today's rule)
   co-located file: basename exactly SPEC-<digits>-<slug>.md
        │
 none ──▶ empty output, exit 0 (callers keep their "no spec" path)
```

### Tie-break (the decision most expensive to change)

| Rank | Rule | Why |
|---|---|---|
| 1 | Root `docs/specs/` beats any co-located match | Every repo that works today keeps the exact same pick |
| 2 | Shallower co-located path beats deeper | The nearer namespace is the more general one; `tools/circle` beats `tools/circle/collectors/social` |
| 3 | Same depth: `LC_ALL=C` byte order of the path | Stable on every host and locale |

### Co-located name match

A co-located basename must equal `SPEC-<digits>-<slug>.md`. The glob `SPEC-*-<slug>.md` lets `*` span dashes. Branch `feat/cs` would then match an unrelated `tools/y/docs/specs/SPEC-147-foo-cs.md`, and ship-gate would read that spec's `Lane:`. Root files keep the glob, so every repo that works today keeps its pick. The test suite carries this decoy as a fixture.

### Depth

4 directories above `docs/specs`, so `find -maxdepth 7`. ops-toolkit's deepest real namespaces sit at 4: `tools/circle/collectors/social`, `_meta/megagoals/_archive/homelab-mesh-ops`. A fixed constant, no knob.

### Dot-directory prune

Every `.?*` directory is pruned. This drops `.git` and `.claude/worktrees/<x>/` (another branch's checkout, which must never answer this branch's slug), plus `.venv` and similar. `spec-next` still sees sibling worktrees through its existing `git worktree list` loop, which calls `spec_files` on each worktree root.

### ADR link(s)

None. The change is reversible: revert the five call sites.

### Boundaries & failure modes

Read-only file walk. No data, no network. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- `lib/spec/spec-find.sh`, sourced, defines no globals beyond `SPEC_FIND_MAXDEPTH=7` and two functions. Sets no shell options.
- `spec_files <root>`: prints one path per line, each `<root>/<rel>`, in pick order. Exit 0 always.
- `spec_for_slug <root> <slug>`: prints zero or one path. Exit 0 always, so a `set -e` caller's `$(...)` never aborts.
- Invariant: `spec_for_slug` output for a repo with only root specs equals today's `ls "$root"/docs/specs/SPEC-*-"$slug".md | head -1`.

### Caller changes

| Caller | Change |
|---|---|
| `spec-next.sh` `_scan_numbers` | keep the `ls "$wt/docs/specs"` line; add `spec_files "$wt"` basenames. Purely additive, so `next`, `check` and `reserve` all count co-located numbers |
| `gate-ledger.sh` `validate-round open` | `match="$(spec_for_slug "$top" "$slug")"`; message becomes `no SPEC-*-<slug>.md under '<top>' (docs/specs or a co-located */docs/specs)` |
| `ship-gate.sh` line 350 | `SPEC=$(spec_for_slug "$ROOT" "$SLUG")`. If `spec-find.sh` is unreadable, a one-line fallback keeps today's root glob |
| `proof-ledger.sh` `_negctl_required` | `spec="$(spec_for_slug "$root" "$slug")"` |
| `pitch.sh` `_find_spec` | `spec_for_slug . "$slug"`, leading `./` stripped so printed paths stay `docs/specs/...` |

The open-PR scan in `spec-next.sh` (`gh api .../contents/docs/specs`) stays root-only: see `## Out of Scope`.

### Data model, API, UI, infrastructure changes

None.

## Task Breakdown

### Phase 1: Foundation
- [ ] TASK-1: `lib/spec/spec-find.sh` with `spec_files` and `spec_for_slug` per `## Design`. AC: sourcing it in a fixture repo lists root first, then co-located by depth and C order; a depth-5 namespace, a dot-dir and `node_modules` are absent; the decoy of Edge Case 9 resolves to nothing.

### Phase 2: Core
- [ ] TASK-2: Wire the five callers per `### Caller changes`. AC: each caller finds a co-located spec in a fixture repo; a root-only repo behaves exactly as before.

### Phase 3: Polish
- [ ] TASK-3: `tests/test-spec-find.sh`: resolver cases, one case per caller, and an in-suite negative control (a mutant kit copy whose `spec_files` is root-only must turn the caller cases red). AC: suite exits 0; the mutant block reports every caller case red.
- [ ] TASK-4: Docs. `spec-index.sh` header (it says spec-next stays namespace-scoped), the `gate-ledger.sh` comment at line 1101, and every doc that describes spec-next, validate-round or ship-gate spec lookup now says co-located specs are found. AC: `rg -n 'docs/specs/SPEC-\*-' docs commands lib hooks` shows no prose claiming root-only lookup for these helpers.

## After state

- [ ] `spec-next.sh next` in a repo holding root `SPEC-005` and `tools/x/docs/specs/SPEC-147-*` prints `148`. (Today: `006`.)
- [ ] `spec-next.sh reserve` in that repo prints `148`, then `149`. (Today: `006`, `007`.)
- [ ] `gate-ledger.sh validate-round open <rid> tools/x/docs/specs/SPEC-001-<slug>.md` exits 0 and prints a token. (Today: exit 1.)
- [ ] `hooks/ship-gate.sh` on a branch whose only spec is co-located with `Lane: full` and an empty ledger exits 2 with `The 'full' lane requires gates`. (Today: exit 0.)
- [ ] `bash tests/test-spec-find.sh` exits 0, and its mutant block shows each caller case red under root-only search.

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria.
- [ ] Tests cover the happy path and the edge cases below.
- [ ] No regressions: `bash tests/run-all.sh --changed origin/master` green, plus `bash tests/test-meta.sh` and `bash tests/test-hooks.sh`.

## Verification

```bash
bash tests/test-spec-find.sh
bash tests/test-gate-validate-round.sh
bash tests/test-spec-reserve.sh && bash tests/test-spec-next-pr-scan.sh
bash tests/test-spec-index.sh && bash tests/test-ship-gate-profiles.sh
bash tests/test-meta.sh && bash tests/test-hooks.sh
```

## Edge Cases

1. Root and co-located specs share a slug: root wins in every caller. `validate-round open` given the co-located path refuses with `is not the ship-gate pick`.
2. Two co-located specs share a slug at different depths: the shallower wins.
3. Two co-located specs share a slug at the same depth: the `LC_ALL=C` smaller path wins.
4. A namespace 5 directories deep: not found, by design.
5. `.claude/worktrees/<x>/docs/specs/SPEC-*-<slug>.md` in the main checkout: never picked, never counted by the root walk. spec-next counts it through its worktree loop only when git lists it as a worktree.
6. The root itself sits inside `.claude/worktrees/<x>` (a kit worktree): the walk starts at `.`, so the prune does not drop the root.
7. Root path holds a space: callers already refuse or quote it. The resolver quotes every expansion.
8. Low per-namespace numbers (`SPEC-001` in ten tools): they never raise the max, so `next` is unaffected. Only a higher co-located number moves it.
9. Decoy: branch `feat/cs`, only `tools/y/docs/specs/SPEC-147-foo-cs.md` co-located. `spec_for_slug` prints nothing; ship-gate takes its no-spec path.
10. A test fixture spec under `tests/fixtures/**/docs/specs/` whose slug equals a branch slug with no root spec: it resolves. Accepted; root still wins whenever it exists.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Walk too slow on a huge repo | push latency; `time` on the find | depth cap 7 plus dot-dir and `node_modules` prune; 56 ms measured on the largest consumer |
| Resolver file missing in an older install | ship-gate `source` fails | ship-gate falls back to the old root glob; other callers ship in the same `lib/` tree |
| Wrong spec picked when two match | ship-gate reads the wrong `Lane:` | deterministic tie-break; `validate-round` and ship-gate share one function, so they cannot disagree |

## Out of Scope

- The open-PR scan in `spec-next.sh` stays on `contents/docs/specs`. A co-located spec that exists only in an unmerged PR is not counted. Fixing it needs the git trees API and a new stub contract in `tests/test-spec-next-pr-scan.sh`.
- Hooks that list "the active spec" from root `docs/specs` (`session-state-save.sh`, `pre-compact-backup.sh`, `context-readiness.sh`, `post-compact-reinject.sh`, `spec-drift-guard.sh`). They pick the newest spec, not a slug's spec; a different question.
- The feature-registry hard-path regex at `ship-gate.sh:298`.

## Touches

- lib/spec/**
- lib/gate/**
- lib/pitch.sh
- hooks/ship-gate.sh
- tests/test-spec-find.sh
- docs/**

## Decision Log

- DEC-1: one sourced resolver over five inline globs. validate-round's equality check needs one shared pick.
- DEC-2: depth 4 above `docs/specs`. Matches the deepest real namespace in ops-toolkit; deeper costs walk time for no known spec.
- DEC-3: root wins, then shallow, then C order. Keeps every working repo's pick unchanged; C order is locale-free.
- DEC-4: prune every dot-directory. Covers `.git` and `.claude/worktrees` in one rule.
- DEC-5: fix `proof-ledger` and `pitch` too. Same glob, same bug, one-line swap each.
- DEC-6: negative control as an in-suite mutant copy. A manual revert proves it once; the mutant proves it every run.
- DEC-7: co-located files match the exact basename `SPEC-<digits>-<slug>.md`; root files keep the glob. A wide co-located walk turns a dash-spanning glob into a cross-namespace mismatch. Root keeps its glob so no working pick changes.

## Grounding

- Co-located layout and depth, sampled read-only in ops-toolkit: `find . -path ./.git -prune -o -path '*/docs/specs/SPEC-*.md' -print | grep -v worktrees | awk -F/ '{print NF-1}' | sort | uniq -c` printed `32 2`, `252 4`, `2 5`, `2 6`. The depth-5 and depth-6 files: `tools/circle/collectors/social/docs/specs/SPEC-134-social-desk.md`, `_meta/megagoals/_archive/homelab-mesh-ops/docs/specs/SPEC-109-homelab-mesh-ops.md`, `_meta/megagoals/icy-mint-burn/docs/specs/SPEC-117-icy-mint-burn.md`, `experiments/herdr-quicklook/sdd/docs/specs/SPEC-001-token-kinds-and-agent-push.md`.
- Mixed numbering, same sample: root max `SPEC-141`; co-located max `SPEC-148` (`tools/circle`); `SPEC-001` through `SPEC-010` recur across namespaces. So max+1 over all namespaces is collision-free, and the recurring low numbers never move it.
- Walk cost: `time (find . -maxdepth 7 \( -name '.?*' -o -name node_modules \) -prune -o -type f -path '*/docs/specs/SPEC-*.md' ! -path './docs/specs/*' -print | wc -l)` printed 256 in 0.056 s (ops-toolkit) and 25 in 0.034 s (this repo).
- This repo's own co-located specs (same command): `lib/stats` SPEC-126..137, `lib/sync` SPEC-001..004, `lib/cosmetic` SPEC-201, `tests/fixtures/whole-spec-dispatch/ab-medium` SPEC-001, `examples/hello-spec` SPEC-001. All below the root max 386, so the kit's own `next` does not move.
- Root-only call sites, read directly: `spec-next.sh:97`, `gate-ledger.sh:1105`, `ship-gate.sh:350`, `proof-ledger.sh:361`, `pitch.sh:55`.
- ship-gate's block text `The '$LANE' lane requires gates`: `ship-gate.sh:421`, read directly.
- Negative-control dry trace. Mutation: the test copies `lib/`, `hooks/` and `kit.toml` to a temp kit and replaces `spec_files` with the root `ls` alone. Fixture reads: a repo on `feat/cs` with only `tools/x/docs/specs/SPEC-147-cs.md` (`Lane: full`) plus root `docs/specs/SPEC-005-old.md`. Code paths: mutant `spec-next next` takes `_scan_numbers` and prints `006`; mutant `validate-round open` hits the empty `match` at the new line and exits 1; mutant ship-gate gets an empty `SPEC`, takes `_floor_check` and exits 0. Named test: the `mutant:` block of `tests/test-spec-find.sh` asserts each of those three outcomes, so the real-kit cases (`148`, exit 0, exit 2) and the mutant cases cannot both pass unless the walk is what changed them.
- Cannot be sampled: the original ops-toolkit session that recorded three rounds by hand. Taken from the brief.

## Test plan
Date: 2026-10-04
Source: this spec's ## Acceptance Criteria, ## After state and ## Edge Cases

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|-------------|----------|-------|
| 1 | `spec_files` on a fixture with root + co-located specs | happy-path | TASK-1 | root first, then co-located by depth, then C order; every line `<root>/<rel>`, no `./` | `bash tests/test-spec-find.sh` |
| 2 | `spec_files` skips depth-5 namespace, dot-dir, `node_modules`, `vendor`, `build` | boundary/edge | TASK-1, EC 4, EC 5 | none of those paths listed | `bash tests/test-spec-find.sh` |
| 3 | Decoy `tools/y/docs/specs/SPEC-147-foo-cs.md`, slug `cs` | security/abuse | TASK-1, EC 9 | `spec_for_slug` prints nothing | `bash tests/test-spec-find.sh` |
| 4 | Root and co-located share a slug | regression | EC 1, invariant | root path wins | `bash tests/test-spec-find.sh` |
| 5 | Two co-located at different depths; two at the same depth | boundary/edge | EC 2, EC 3 | shallower wins; C-smaller wins | `bash tests/test-spec-find.sh` |
| 6 | Spec path with a space; root that is a `.claude/worktrees/x` dir | boundary/edge | EC 6, EC 7 | found; root not pruned | `bash tests/test-spec-find.sh` |
| 7 | Unreadable subdirectory in the walk | failure-injection | Interfaces (exit 0) | exit 0, other specs still listed | `bash tests/test-spec-find.sh` |
| 8 | `spec-next next` / `reserve` with root SPEC-005 + co-located SPEC-147 | happy-path | After state 1, 2 | `148`, then `148`, `149` | `bash tests/test-spec-find.sh` |
| 9 | `validate-round open` on a co-located spec | happy-path | After state 3 | exit 0, token printed | `bash tests/test-spec-find.sh` |
| 10 | ship-gate, co-located `Lane: full`, empty ledger | happy-path | After state 4 | exit 2, `The 'full' lane requires gates` | `bash tests/test-spec-find.sh` |
| 11 | ship-gate with `spec-find.sh` missing from the kit copy | failure-injection | Failure modes row 2 | root spec still found (exit 2 on a root full-lane spec) | `bash tests/test-spec-find.sh` |
| 12 | `_negctl_required` (via `proof-ledger.sh check`, `negative_control = "full"` overlay) and `pitch.sh _find_spec` (via `pitch.sh ask`) on a co-located spec; no-spec control | happy-path | TASK-2 | check exits 1 (yes); pitch prints `tools/x/docs/specs/SPEC-147-cs.md`; no spec: check exits 0 | `bash tests/test-spec-find.sh` |
| 13 | Mutant kit, root-only `spec_files`, all five callers; a root-spec positive control per caller in the same mutant kit | regression | After state 5, DEC-6 | flips: next `006`; validate-round exit 1 `no SPEC-*-cs.md under`; ship-gate exit 0; check exit 0; pitch `no spec or PR reference found`. Controls: `002`, exit 0, exit 2, exit 1, root path | `bash tests/test-spec-find.sh` (mutant block) |
| 14 | Root-only repos unchanged | regression | global AC | existing suites green; in-suite root controls for validate-round, ship-gate, pitch | `bash tests/run-all.sh --changed origin/master`, then every `## Verification` line (`test-gate-validate-round`, `test-spec-reserve`, `test-spec-next-pr-scan`, `test-spec-index`, `test-ship-gate-profiles`, `test-meta`, `test-hooks`) |
| 15 | Root and co-located twins share slug `cs` at the callers | regression | EC 1 | `validate-round open <co-located>` exits 1, `is not the ship-gate pick '<root>'`; ship-gate reads the root twin (exit 2, `has no 'Lane:' header`) | `bash tests/test-spec-find.sh` |
| 16 | Only the decoy `tools/y/docs/specs/SPEC-147-foo-cs.md` (`Lane: full`) on branch `feat/cs` | security/abuse | EC 9 | ship-gate exits 0 | `bash tests/test-spec-find.sh` |
| 17 | Real `git worktree add` sibling holds co-located SPEC-200 | boundary/edge | EC 5 | `next` prints 201; main walk never picks `.claude/worktrees` | `bash tests/test-spec-find.sh` |
| 18 | Co-located `SPEC-001` under root SPEC-005 | boundary/edge | EC 8 | `check 001` exits 1 (taken); `next` stays `006` | `bash tests/test-spec-find.sh` |
| 19 | Docs no longer claim root-only lookup for spec-next, validate-round, ship-gate | regression | TASK-4 | every hit of the `rg` reads as co-located-aware or as an active-spec lookup marked root-only (Out of Scope) | `rg -n 'docs/specs/SPEC-\*' docs commands lib hooks`, read by `kit:doc-verifier`. [NO EXECUTABLE CHECK: prose meaning; the oracle is the doc-verifier verdict] |

Negative controls, each a mutant of `lib/spec/spec-find.sh` run against `bash tests/test-spec-find.sh`:

- Root-only `spec_files`: 20 of 55 red (rows 1, 2, 3, 5 to 10, 12, 17, 18). In-suite as row 13.
- DEC-7 numeric-prefix check removed from `spec_for_slug`: rows 3 and 16 red.
- Root `ls` emitted after the walk: rows 1, 4 and 15 red.
- Depth key dropped from the sort: row 5 red.

Row 7 skips the unreadable-dir case when euid is 0. Each `reserve` case uses its own state file. Walk speed (Failure modes row 1) is measured, not tested.

### Coverage notes
- Categories skipped: none.
- This is a coverage TARGET across the enumerated categories, NOT an exhaustive test list. A missing acceptance criterion or an unenumerated category is a gap, surfaced here, not a guarantee.

## Open questions

(none)
