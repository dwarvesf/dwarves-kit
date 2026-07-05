# Proof of done: detect co-located proof-of-done.md

Recorded 2026-06-09. Change: `_fresh_proof_files()` in `lib/gate/proof-ledger.sh` now also accepts
a proof file co-located with its subject (any path ending `/proof-of-done.md`, e.g. a
monorepo's `tools/<name>/docs/proof-of-done.md`), in addition to the repo-root
`docs/verification/<slug>.md` convention. The content check in `check()` is unchanged, so a
tool-folder proof must still carry a green run + negative control to pass.

Why: a monorepo (ops-toolkit) keeps each tool's proof beside the tool, not at repo root. The
old grep only saw repo-root `docs/verification/*.md`, so a tool-folder proof was invisible and
the gate falsely blocked. The fix is generic (a `proof-of-done.md` anywhere counts), not
coupled to any one repo's layout.

## GREEN + NEGATIVE CONTROL + backward-compat (one harness, three cases)

Temp git repo: base commit on `main` (with `docs/verification/README.md` marker), then a
behavioral branch adding `tools/widget/src/app.py`. Ran `proof-ledger.sh check <repo> <base> thing`.

| Case | Setup | Expected | Observed |
|---|---|---|---|
| GREEN (tool-folder proof) | `tools/widget/docs/proof-of-done.md` with GREEN + NEGATIVE CONTROL | PASS, exit 0 | exit 0 |
| NEGATIVE CONTROL | remove that proof file, re-run | BLOCK, exit 1 | exit 1 |
| backward-compat | add old-style `docs/verification/thing.md` instead | PASS, exit 0 | exit 0 |

`classify` reported `behavioral` for the branch, so the gate was genuinely engaged (not
short-circuited as inert). The negative control flips RED exactly when the proof is absent,
so the green is not trivially green.

## Reproducible

Re-run the harness (a temp repo + the three `proof-ledger.sh check` invocations above). The
one-line grep change is the whole diff; revert it and case 1 (tool-folder proof) goes BLOCK
while case 3 (root proof) still passes, which is the pre-change behavior.

## Rollback

Pure detection-logic change to one function; `git revert` restores the prior grep. No state,
no migration, no deploy. The install symlink (`~/.claude/dwarves-kit/lib`) points at this
checkout's working tree, so the change is live as soon as it is on the checked-out branch.
