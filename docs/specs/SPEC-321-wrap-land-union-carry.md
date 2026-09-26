# SPEC-321: wrap land carries a dirty union file across its fast-forward

**Status:** VALIDATED (the change lands in the same PR)
Lane: full
Type: spec-feature
**Proof:** `tests/test-wrap.sh`, the land block; `docs/verification/wrap-land-union-carry.md`.

## Problem

`bin/wrap land <worktree>` squash-merges a PR, then fast-forwards the repo's
main checkout with a bare `git -C "$repo" pull --ff-only` (the block commented
"The fast-forward is advisory", `lib/wrap/wrap.sh`). When the main checkout
holds another session's dirty `merge=union` file (`_meta/LAB_LOG.md` with a
few local, uncommitted lines is the recurring shape), the pull refuses and
`land` prints `PULL BLOCKED: pull --ff-only refused in <repo>, nothing was
stashed or reset`. The merge already landed and the worktree/branch tidy
already ran by this point, so the only casualty is a main checkout stuck
behind origin until the operator runs `bin/wrap apply --apply <repo>` by
hand. Observed three times in one session.

`_pull_default` (the pull `apply` already uses) carries a dirty union file's
local lines across a pull via `_union_carry_back`, saving the union file
aside, letting the pull land, then merging the local lines back in. `land`'s
fast-forward does not reuse that path.

## Contract

- `land`'s fast-forward step gains a union-only carry, scoped to exactly what
  `_union_marked` + `_union_carry_back` already do for `apply`: a dirty
  tracked file the repo's `.gitattributes` declares `merge=union` is saved
  aside (`git checkout --` back to HEAD's content), the pull runs, and the
  saved local lines are merged back into the pulled file.
- Scope is the whole worktree top level (`git diff --name-only` against the
  index), same as `_pull_default`; a union file need not live at any
  particular path.
- **A staged change skips the carry entirely** (same guard as
  `_pull_default`): restoring an index the carry did not stash is out of
  scope, so any staged file makes `land` fall back to today's bare pull.
- A file that is dirty and NOT union-marked is untouched: `land` never
  stashes it and never resets it. If such a file blocks the fast-forward, the
  pull still refuses and `land` still prints the existing `PULL BLOCKED:
  pull --ff-only refused in <repo>, nothing was stashed or reset` line,
  unchanged. `wrap.pull_past_dirty` is NOT read here (see Design).
- On a successful carry, `land` prints one additional line before the pull,
  `saved N union-marked file(s) aside so the pull can fast-forward`, and one
  additional line per carried file after it lands,
  `carried <n> local line(s) back into <path>` -- the same wording
  `_pull_default` already prints, so an operator who has seen `apply`'s
  output recognizes it here. Both are ADDITIONS before/after the existing
  `pulled <repo>: <log line>` line; that line's own text does not change.
- A union file that will not union-merge against the pulled content (a
  merge-driver refusal) restores that file's pre-pull content and reports
  `FAILED carry: <path> would not union-merge, so its pre-pull content is
  back`; `land`'s overall pull is then reported as `PULL BLOCKED` same as any
  other refused pull, and the tidy still runs.
- The existing refusal paths (checkout not on the default branch, `pull
  --ff-only` refuses outright with no union file involved) are unchanged.

## Picture

```
land's fast-forward step (post-merge, main checkout)

  HEAD on <def>? --no--> PULL BLOCKED: "<repo> is on '<cur>', not <def>"
       |
      yes
       |
  git diff --name-only (unstaged) ---- any staged change? --yes--\
       |                                                          |
   any dirty file?                                                v
       |                                                   skip the carry
      yes                                                  (index restore
       |                                                   is out of scope)
  split dirty files: union-marked  vs  not-union-marked                |
       |                                                               |
  union files: save (copy) + `checkout --` back to HEAD's content      |
       |                                                               |
       +---------------------------<-----------------------------------+
       |
  git pull --ff-only
       |
    refused? --yes--> restore each saved union file's ORIGINAL dirty
       |               content byte-for-byte --> PULL BLOCKED (unchanged
       |               message; a lone non-union dirty file also lands here,
       |               untouched, exactly as before this spec)
      no
       |
  for each saved union file: _union_carry_back(saved, pre-pull-base, pulled)
       |
    union-merged? --no--> restore pre-pull content, print
       |                  "FAILED carry: <f> would not union-merge, so its
       |                  pre-pull content is back" --> overall PULL BLOCKED
      yes
       |
  print "carried <n> local line(s) back into <f>" per file,
  then the existing "pulled <repo>: <log line>" (byte-identical to today)
```

## Design

Chosen approach: a small land-scoped helper (`_land_ff_pull`) that reuses the
two existing building blocks `_union_marked` and `_union_carry_back`, called
in place of the bare `git -C "$repo" pull --ff-only`. It does not touch
`_pull_default` itself and does not read `wrap.pull_past_dirty`.

**Question 1 (design-bearing): union carry only, or also honor
`wrap.pull_past_dirty` for non-union files?** Union-carry only. `land`'s own
comment already states the guarantee this spec is not touching: "It is never
stashed past and never reset; the refusal is reported and the tidy
continues." `wrap.pull_past_dirty` is `apply`'s knob, read by `_pull_default`
only inside `apply`'s own dry-run/`--apply` distinction (it reports what
stashing WOULD do before ever doing it). `land` runs mid-flow, after a merge
already landed, with no dry-run half of its own; wiring the knob in here
means a `land` call can start stashing arbitrary dirty tracked files in a
checkout it does not own, on the strength of a knob the operator set for a
different verb's different UX. A dirty `merge=union` file is a narrower,
self-evidently safe case: the repo itself declares that file's local lines
and the incoming lines both survive, so there is nothing for `land` to guess
at or lose. Widening `land` to the knob is a real contract change (the
"never stashed past" line stops being true) for a case (a second uncommitted
dirty file, not the union log) this session never observed; narrowing to the
safe case is not. If a future session hits the wider case, that is a new
problem statement with its own spec, not a default assumed here.

**Alternatives considered:**
- Reuse `_pull_default` wholesale in place of the bare pull. Rejected: it
  prints multiple extra `NOTE:`/`HEAD:` lines gated on a global `$APPLY`
  variable `land` does not set, and folds in the `wrap.pull_past_dirty`
  stash branch this spec deliberately excludes (Question 1). Reusing it
  would either change `land`'s output shape or require threading a new
  "no-stash" mode through an already dense, well-tested function --
  more surface than the fix needs.
- Duplicate the carry logic inline in the land block. Rejected: `_union_marked`
  and `_union_carry_back` already exist and are already exercised by
  `apply`'s tests; a second inline copy is the exact duplication `_pull_default`
  itself was written to avoid.

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: add `_land_ff_pull`, a union-only carry helper | `lib/wrap/wrap.sh` | new function defined near `_pull_default`, reusing `_union_marked` + `_union_carry_back`; not called from `_pull_default` or `apply` |
| T2: wire it into `land`'s fast-forward step | `lib/wrap/wrap.sh` | the bare `git -C "$repo" pull --ff-only` in `cmd_land` (fast-forward block, "The fast-forward is advisory" comment) calls `_land_ff_pull "$repo"` instead; both existing output lines (`pulled ...`, `PULL BLOCKED: pull --ff-only refused in ...`) stay byte-identical |
| T3: test the new case, keep the old one green | `tests/test-wrap.sh` | new case: dirty `merge=union` file in the main checkout, land carries it across a successful fast-forward; existing "PULL BLOCKED: a dirty tracked file ... never stops the tidy" case (non-union) still passes unchanged |
| T4: proof + notes | `docs/verification/wrap-land-union-carry.md`, `docs/implementation-notes/wrap-land-union-carry.md`, `docs/CHANGELOG.md` | green run + negative control recorded; delta-only implementation note; one CHANGELOG line |

## Test plan

| Case | Setup | Expected |
|---|---|---|
| dirty `merge=union` file in the main checkout, pull would otherwise fast-forward | land fixture with `_meta/LAB_LOG.md` declared `merge=union` in `.gitattributes`, a local uncommitted line, origin advanced by the squash-merge | exit 0, `pulled <repo>: ...` line present, `saved 1 union-marked file(s) aside` then `carried N local line(s) back into <path>`, HEAD moved to the merged tip, the local line still present and still uncommitted |
| dirty NON-union file blocking the pull (existing case) | existing `build_land blocked --modify-base` fixture, `base.txt` not union-marked | unchanged: exit 2, `PULL BLOCKED: pull --ff-only refused in <repo>, nothing was stashed or reset`, file untouched |
| no dirty file, pull fast-forwards cleanly (existing happy path) | existing land happy-path fixture | unchanged: exit 0, `pulled <repo>: ...` |
| checkout not on the default branch (existing case) | existing `build_land ondef` fixture | unchanged: `PULL BLOCKED: <repo> is on '<branch>', not <def>` |
| negative control | `bash lib/gate/negctl.sh <worktree root> "bash tests/test-wrap.sh" "<mutate reverting _land_ff_pull to the bare pull>"` | green before, RED under the mutation (the new union-carry case fails), green + clean tree after restore |

## Verification

`bash tests/test-wrap.sh` exits 0. The negative control above is recorded in
`docs/verification/wrap-land-union-carry.md`.

## After state

`bin/wrap land`'s fast-forward carries a dirty `merge=union` file's local
lines across the pull the same way `apply` already does, so a sibling
session's uncommitted log/board line no longer strands the main checkout
behind origin after a successful land. A dirty non-union file still blocks
the fast-forward exactly as before; `land` still tidies the worktree and
branch either way.

Not covered: `wrap.pull_past_dirty`-style stashing of non-union dirty files
inside `land` (Question 1, deliberately out of scope); a merge-driver-level
union conflict beyond what `_union_carry_back` already handles (unchanged,
inherited from `apply`).

## Decision Log

- Lane: full, because the change touches `lib/wrap/wrap.sh`, per this task's
  own instruction and the AGENTS.md rule that a run touching `lib/` escalates
  review.
- Grill skipped (`reason=operator-wave`): the task prompt itself posed and
  answered the one open design branch (union-carry only vs. also honoring
  `wrap.pull_past_dirty`), so there was no unresolved bank left to interview.
