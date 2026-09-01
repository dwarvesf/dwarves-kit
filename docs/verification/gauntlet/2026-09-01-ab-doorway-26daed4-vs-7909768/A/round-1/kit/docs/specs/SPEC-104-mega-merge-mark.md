# SPEC-104: auto-mark gate/gated-final PRs at creation (SPEC-100 mark half)

Status: VALIDATED
Lane: normal
Type: spec-feature

## Problem

The SPEC-100 merge guard (`lib/goal/mega-merge.sh` `_merge_exclusion`, shipped, ID-083) refuses to
auto-merge a held PR that CARRIES a mark (draft / hold-label / bracketed-title marker), but it
cannot synthesize a mark. So an UN-marked `gate`-tagged sub-goal PR or held `gated-final` PR
slips through (security review B1, ID-089). The guard is the defense; nothing guarantees the
mark it defends against is present.

## Solution

Add the complementary MARK half: a `mark <pr> [repo]` verb in `lib/goal/mega-merge.sh` that puts a
held PR into exactly the state `_merge_exclusion` refuses:

1. Ensures the `do-not-merge` label exists (idempotent `gh label create ... || true`), so a
   later `--add-label` never fails on a repo that lacks it.
2. Converts the PR to a **draft** (`gh pr ready <pr> --undo`) -- the primary, GitHub-intrinsic
   block (GitHub itself refuses to merge a draft).
3. Adds the **`do-not-merge`** label (`gh pr edit --add-label`) -- the belt-and-suspenders the
   code guard also reads.

`gh` is routed through `MEGA_MERGE_GH` (default `gh`) so tests assert the calls offline. The verb
is idempotent (all steps `|| true`), so re-running is safe. `commands/mega.md`'s held-PR step calls
`mega-merge.sh mark <pr>` right after opening a gate/gated-final PR; a normal `auto` PR is left
un-marked so the guard clears it.

The SPEC-100 guard itself is UNCHANGED (this is the mark half only). Now the state the guard keys
off is guaranteed present, so a prompt-rationalizing model cannot merge a held PR even by skipping
the routing, and GitHub itself refuses to merge a draft (a second, intrinsic layer).

## Verification

```bash
cd dwarves-kit
grep -n 'mark)' lib/goal/mega-merge.sh                    # the verb is wired
grep -n 'mega-merge.sh mark' commands/mega.md         # the held-PR step calls it
bash tests/test-mega-merge.sh                         # mark pins + mark<->guard end-to-end + negative control
```

Pins added to `tests/test-mega-merge.sh` (offline, `MEGA_MERGE_GH` mock):
- `mark` ensures the label, sets draft (`pr ready --undo`), adds the label.
- **mark <-> guard meet**: fed the state `mark` produces (draft / `do-not-merge`), `_merge_exclusion`
  refuses even with a passing gate.
- **negative control**: an un-marked `auto` PR clears the guard and merges.
- input guard (non-numeric PR refused) + idempotence.

## After state

- `lib/goal/mega-merge.sh` has a `mark` verb; `commands/mega.md` calls it at the held-PR open step.
- `README.md` mega-merge entry + `MANUAL.md` held-PR note document the mark.
- `docs/verification/merge-mark.md` carries the run-table + the mark<->guard end-to-end proof.
- Closes the ID-083 / ID-089 guard pair FOR THE `commands/mega.md`-driven PR-open path: the guard
  defends a marked PR; `mark` guarantees (and now verifies) the mark on that path.

## Open questions

- **Second PR-open site (TIER-4 advisor P5-2).** ID-089 also named the bounded `/goal` loop's own
  gated-final PR-open step; only `commands/mega.md` calls `mark` here. The loop currently relies on
  the human/loop invoking `mark` (as this wave's own final held PR does). A `mega-merge sweep` that
  scans open gate/gated-final PRs for a missing mark (surfaced at `/kit:retro` like boardless runs)
  is the durable close for every site; tracked in the mega-goal NOTES `## Proposed additions`.
- `mark` was hardened at TIER-4 to VERIFY the mark landed (reuse `_merge_exclusion`; WARN + nonzero
  on a silent gh no-op) rather than trust a hardcoded success string.
