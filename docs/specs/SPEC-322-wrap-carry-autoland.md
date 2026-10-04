# SPEC-322: wrap apply lands its own carry PRs

**Status:** VALIDATED
Lane: full
Type: spec-feature
**Proof:** `tests/test-wrap.sh`, the carry-autoland block; `docs/verification/wrap-carry-autoland.md`.

## Problem

`bin/wrap apply --apply` carries stray lines (`_carry_stray_file`) and stray
commits (`_carry_stray_commits`) to a `wrap/stray-*` branch on origin, then
prints `open its PR with: gh pr create --head <branch>`. Nothing runs that
command. The branch orphans with no PR, and every later run skips the same
file with `SKIP <file>: ... an origin wrap/stray-<slug>-* branch already
carries this file; merge it first`. The stray lines then stay in the shared
checkout until someone opens and merges the PR by hand. Observed in
ops-toolkit: an orphan `wrap/stray-meta-lab-log-md-*` branch was hand-opened
and merged as #3467, then again as #3468 for the next carry.

## Contract

- New root-only knob `wrap.autoland_carry`, default `false`, resolved with
  `kit_config_get_root`. `false` keeps every output line and every write
  byte-identical to today. `wrap.merge_own_prs = false` wins: autoland is off.
- `true` with `--apply`, at each point that prints `open its PR with` today
  (a new stray-lines carry, a new stray-commits carry, a reused
  `wrap/stray-commits-*` branch), `apply` lands the branch instead:
  1. A PR already merged at the branch tip (`_squash_verdict` OK), or a
     merged `<branch>-squash` replacement, is reported as landed.
  2. Exactly one open same-repo PR on the branch is adopted when the operator
     authored it and it is not a draft. Marking a draft ready stays a lead
     decision (`merge --pr`). Two or more, or a failed lookup, refuse.
  3. No open PR: `gh pr create --head <branch>` with the tip commit subject
     as the title.
  4. A bounded wait while the PR has pending checks
     (`KIT_WRAP_CARRY_CHECKS_SECS`, default 300, one read every 10s). An
     empty rollup on a merge state other than CLEAN counts as pending: a PR
     opened seconds ago has not registered its checks yet.
     DIRTY or BEHIND ends the wait: GitHub runs no checks there.
  4b. Every landing carries the oid the caller checked (the pushed carry
     commit, the validated orphan tip, or HEAD for stray commits). An origin
     tip or a PR head anywhere else before the merge refuses and leaves the
     PR open, so a push during the wait never rides the merge unchecked.
  5. `cmd_merge --apply --pr <n> <repo>` merges it. That is the one merge
     path: `_open_own_prs` membership, `_pr_gate`, the union re-merge and
     squash fallback, `--match-head-commit`, and `_tree_verify`. Its output
     prints indented under the carry. Landed means exit 0 plus the anchored
     line `^merged #<n> (<sha>): tree verified`. When the squash fallback
     merged a replacement, the superseded PR is closed, so the next pass does
     not adopt it again.
- A gate refusal (checks failing, still pending, blocked state) leaves the
  PR open and prints `PR #<n> left open; wrap merge --apply --pr <n> merges
  it once green`. That is not a failure: exit stays 0.
- A merge `cmd_merge` reports as failed (exit 1 or 2) or a TREE MISMATCH or
  unverifiable tree (exit 3) sets `FAILURES`, so `apply` exits 2.
- Adoption of an orphan carry branch: with the knob on, the existing-branch
  SKIP in `_carry_stray_file` lands each matching origin
  `wrap/stray-<slug>-*` branch through steps 1 to 5, but only a branch that
  reads as this file's carry (`_carry_branch_ours`): the exact
  `wrap/stray-<slug>-<YYYYMMDD-HHMM>` name, a diff from origin/<default>
  touching that file alone, every added line present in the working copy,
  and no removed line except a board row whose id it adds back. Opening a PR makes any branch "own", so this check is the only thing
  between a look-alike branch and the default branch. Once every one lands,
  origin/<default> is fetched and the stray lines are recomputed. None
  left prints `<file>: the landed carry held every stray line`. Any left
  carry to a new branch, which then lands too. A branch that does not land
  keeps today's SKIP line.
- The dry run with the knob on prints `WOULD open and merge its PR
  (wrap.autoland_carry=true)` beneath each `WOULD carry` line and beneath
  the existing-branch SKIP line.
- gh unavailable or unauthenticated with the knob on: one SKIP line naming
  the gh state, then today's `open its PR with` line.
- Stray commits: the landing runs before the `reset --keep` move, and only
  when nothing blocks the move and the origin branch tip equals HEAD.
  Otherwise today's command prints with `not landed: <reason>`: a squash
  with <default> still ahead would be re-carried by a later pass once patch
  ids stop matching. The move still needs the carry branch on origin holding
  HEAD, which a merge does not delete, so the move and the pull behave as
  today.

## Picture

```
_carry_stray_file / _carry_stray_commits
        |
   carry branch on origin (new push, reused, or orphan found)
        |
   wrap.autoland_carry? --false--> "open its PR with: gh pr create --head B"  (today)
        |true
   _autoland_carry B
        |
   merged at tip? --yes--> "already merged" -> landed
        |no
   open PR on B? --1, draft--> SKIP (lead decision)
        |          --2+/failed--> SKIP
        |0 -> gh pr create --head B
        |1 -> adopt #n
        |
   wait pending checks (bounded)
        |
   (cmd_merge --apply --pr n repo)   <- _pr_gate, re-merge, match-head, _tree_verify
        |
   rc 0 + "tree verified" --> landed
   rc 0, nothing eligible  --> "PR #n left open", exit unaffected
   rc 1/2/3                --> FAILURES=1 (apply exits 2)
```

## Design

Reuse `cmd_merge --pr` in a subshell rather than calling `_pr_gate` and
`_tree_verify` directly. `cmd_merge --pr` already composes the gate, the
conflict recovery (a union carry PR goes CONFLICTING right after creation),
the pinned squash, the MERGED check and the tree verify. A second composition
would be the new merge path the handoff rules out. The subshell keeps
`cmd_merge`'s globals (`REMERGE_OID`, `SQ_PR`, `SQ_OID`) out of `apply`.

Alternatives considered:
- Open the PR only and let the next `/kit:wrap` step 3 merge it. Rejected:
  the handoff asks for opens AND merges, and step 3 runs in a later session.
  The gate-refusal path degrades to exactly this.
- Sweep every orphan `wrap/stray-*` branch in the repo. Rejected: a branch
  whose stray lines no longer sit in the working copy may carry content that
  already landed another way; landing it blind can duplicate lines. The
  adoption stays tied to a file that still has stray lines.

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: knob | `kit.toml`, `lib/config/module-registry.md` | `autoland_carry = false` under `[wrap]`; registry row and key list entry |
| T2: `_autoland_on`, `_autoland_carry` | `lib/wrap/wrap.sh` | steps 1 to 5 above; header write-set comment names the new writes |
| T3: wire the call sites | `lib/wrap/wrap.sh` | new stray-lines carry, orphan adoption, stray-commits carry and reuse; dry-run WOULD lines |
| T4: tests | `tests/test-wrap.sh` | cases below; every existing case unchanged |
| T5: command text | `commands/wrap.md` | step 5 stray bullets and the knob list name the knob and the landed path |
| T6: proof + notes | `docs/verification/wrap-carry-autoland.md`, `docs/implementation-notes/wrap-carry-autoland.md`, `docs/CHANGELOG.md` | green run, negative control, scratch-repo fixture transcript |

## Test plan

| Case | Setup | Expected |
|---|---|---|
| knob fence | shipped, operator, project tomls | ships `false`; operator `true` honoured; project `.kit.toml` ignored |
| knob off (regression) | every existing stray case | unchanged, `gh pr create --head` still printed |
| dry run, knob on | stray lines + stray commits fixtures | `WOULD open and merge its PR (wrap.autoland_carry=true)`; no PR call |
| adopt orphan + land remainder | orphan branch holding 1 of 2 stray lines, no PR | `gh pr create --head <orphan>`, merge pinned to the orphan tip, tree verified; the 1 remaining line carried to a new branch and landed; origin main holds both lines; exit 0 |
| stray commits land | clone ahead by 1 commit, knob on | PR created, merged, tree verified; main moved and pulled; exit 0 |
| gate refusal | PR JSON with a FAILURE check | `SKIP #42 ... checks are pending or failing`, `PR #42 left open`, no `pr merge` call, exit 0 |
| draft refusal | an open draft PR on the orphan | SKIP names the draft; no `pr ready`, no merge; SKIP line of today follows |
| merge failure | `gh pr merge` exits 1 | `FAILED merge #42`, apply exits 2 |
| foreign PR author | open PR on the orphan by another login | SKIP names it; no merge |
| foreign content / look-alike name | orphan adding a line the checkout lacks; a `...-bak-x` branch | both refused by `_carry_branch_ours`; today's SKIP follows; no PR |
| orphan removes a line | orphan branch dropping the base line | refused; no PR |
| moved PR head | PR head differs from the checked oid | `PR #42 head is ..., not the checked`; no merge |
| fresh PR settle | first read BLOCKED with no checks, second CLEAN | two wait reads, then merged |
| merge_own_prs false wins | both knobs on and off | today's command prints; no PR |
| stray commits blocked | dirty non-union file | `not landed: dirty tracked files block the move`; no PR |
| negative control | `negctl.sh` mutating `_autoland_on` to false | the adopt case goes RED, restores green |

## Verification

`bash tests/test-wrap.sh` exits 0; the negative control and a scratch-repo
fixture transcript are recorded in `docs/verification/wrap-carry-autoland.md`.

## After state

With `wrap.autoland_carry = true` in the operator `kit.toml`, a wrap pass on a
shared checkout carries stray lines and stray commits and lands them through
the same gate as any own PR. An orphan carry branch from an earlier run lands
on the next pass instead of blocking it. The default stays `false` until the
operator flips it.

Not covered: orphan `wrap/stray-*` branches whose file has no stray lines left
(see Design); a carry PR whose CI stays pending past the wait (left open for
step 3).

## Decision Log

- Lane: full (kit core, `lib/wrap/wrap.sh`), per the classifier and the handoff.
- Default `false`: the change reverses the documented sentence "it opens no
  PR" and merges into the default branch; the operator flips it after review.
- The PR ships as a draft for the operator's design review.
- Validation round 1 (NEEDS REVISION, 4 critical) changed: exact-name and
  content check before landing an existing branch (`_carry_branch_ours`),
  own-author check on an adopted PR, stray commits land only unblocked with
  tip == HEAD, merged `-squash` replacement counts as landed and the
  superseded PR is closed, empty-rollup settle wait, explicit fetch before the
  recompute, `merge_own_prs=false` wins. Round 2: removed lines checked,
  diff headers parsed by hunk position, checked-oid pinning (4b), DIRTY and
  BEHIND end the wait, a failed fetch before the recompute skips. Warnings accepted, not fixed:
  concurrent `apply` runs on one checkout (no lock exists today either), the
  serial wait across many carries, row duplication on an anchorless board
  when a sibling writes between carry and pull.
