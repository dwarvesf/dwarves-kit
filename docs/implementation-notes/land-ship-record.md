# Impl notes: land-ship-record (SPEC-317)

Delta from the spec. Only off-spec calls live here.

## Comment wording changed after the run-all `test-no-scattered-ids` lint

The first implementation pass named the spec inline in two `lib/wrap/wrap.sh` comments
(`ship-gate record (SPEC-317): ...`). `tests/run-all.sh --changed` failed `test-no-scattered-ids`:
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

## Review pass: four findings folded in before merge

`## Design critique` (appended to the spec) raised one High and three Medium findings against
the first cut of this feature; all four are resolved in this branch, not deferred:

- **H1 (unverified ship line):** the recorded reason is now `shipping pr=#<n> via=land`, not
  the bare `shipping pr=#<n>` a real `hooks/ship-gate.sh` pass writes, so a `land`-written line
  is never mistaken for one the push hook actually verified. `/kit:wrap` step 8's anchored
  `shipping pr=#<n>([^0-9]|$)` grep still matches it unchanged (the next character is a space).
- **M1 (reused-slug collision) + M2 (duplicate ship line):** `land` now reads the rid's ledger
  BEFORE recording and looks for an existing `| GATE | ship |` line (matched case-insensitively
  on the phase, since `record()`'s own `normalize_phase` always lowercases what it writes but a
  defensive match costs nothing). A line naming this exact PR is idempotent, skip and say so; a
  line naming a *different* PR is a reused-slug collision (a `type/` prefix swap sharing the
  same stripped slug), skip and say so, never overwrite.
- **M3 (opaque failure line):** the FAILED message now captures the `record` call's own stderr
  (`2>&1 1>/dev/null` into a variable) and prints the exact manual command, `via=land` reason
  included, instead of a bare "record it by hand".

Both test gaps the critique named (a nested-branch rid, a MISMATCH-never-records case) are
covered too, alongside the two new skip cases (same-PR, different-PR). Total: eight new
`tests/test-wrap.sh` cases beyond the original three; two negative controls (the `show`
prior-ledger guard, the same-PR idempotent-skip guard), both PASS.
