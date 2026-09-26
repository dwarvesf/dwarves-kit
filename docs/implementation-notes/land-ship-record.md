# Impl notes: land-ship-record (SPEC-315)

Delta from the spec. Only off-spec calls live here.

## Comment wording changed after the run-all `test-no-scattered-ids` lint

The first implementation pass named the spec inline in two `lib/wrap/wrap.sh` comments
(`ship-gate record (SPEC-315): ...`). `tests/run-all.sh --changed` failed `test-no-scattered-ids`:
`lib/` is a scanned zone, and a spec id in a `lib/` comment is not one of the sanctioned
homes (CONTRIBUTING.md "Where an ID may appear"). Reworded both comments to state the
behavior plainly with no id, matching the estate-wide "state the thing plainly, git tracks
it" convention. Also dropped the same inline id from two `tests/test-wrap.sh` comments,
which the lint's `lib` zone does not scan (nested `tests/` is excluded) but which carried
the same id-in-a-comment shape regardless.

## Spec-validate folded three advisory findings before build

`/kit:spec-validate`'s self-run (Reviewer 4, Reviewer 2, Reviewer 5) raised three warnings,
all folded into the spec before Task Breakdown/Test plan were finalized:

- Reviewer 4: the original Task Breakdown had no task for the `docs/verification/` and
  `docs/implementation-notes/` proof artifacts the header already named. Added T4.
- Reviewer 2: the Failure modes table carried a row ("non-numeric PR number") that is not a
  new risk this feature introduces, `cmd_land` already validates `n` numerically upstream,
  both on the adopted-open-PR and newly-created-PR paths. Dropped the row; the inherited
  guard needed no new mitigation.
- Reviewer 5: the `## Design` section's state diagram duplicated `## Picture` at the same
  granularity. Trimmed Design to reference Picture and keep only the approach-comparison
  table, which is the part Picture does not carry.

No Reviewer 6 (blocking) finding: the spec was judged design-bearing (a new cross-subsystem
call with rejected alternatives), and `## Design` already carried a non-empty diagram plus a
chosen approach, so the design-record check passed clean on the first pass.

## No deviation from the Contract or Test plan otherwise

The shipped `lib/wrap/wrap.sh` change, the three `tests/test-wrap.sh` cases, and the
negative control match the spec's Contract, Picture, and Test plan sections as written.
