# Implementation notes: wrap-carry-autoland (SPEC-322)

Delta from `docs/specs/SPEC-322-wrap-carry-autoland.md` only.

## Decisions not in the spec

- The handoff anchors (lib/wrap/wrap.sh:1015 and on) predate #778 and #779; the functions sit about 60 lines lower now. Located by name.
- `_autoland_carry` calls `_autoland_on` at every call site, not inside itself, so a knob-off run never prints a new line. The existing-branch SKIP with the knob off stays byte-identical, and the "open its PR with" line stays the knob-off output.
- The gate-refusal message moved after the tree-verified check rather than a separate branch; same text as the spec.
- `apply`'s closing line `PR merges, deploy dispatch and board rows stay with the command.` is left as is. It stays true for every PR that is not a carry, and tests pin it.
- The test stub gained two seams: `GH_STUB_LAND_OID=1` (merge lands the `--match-head-commit` oid on the `--repo` bare remote) and `%CARRY_TIP%` (the newest `wrap/stray-*` branch on `GH_STUB_CARRY_REMOTE`). A carry branch name carries the run's minute, so no fixture can name it in advance.
- The orphan fixture is stamped `20260101-0000` so the remainder carry never collides with it in the same minute.

## Deviations

- None from the revised spec.

## Not covered by a test

- The squash-fallback path under autoland (close of the superseded PR, `-squash` merged counted as landed). The fallback needs the CONFLICTING-then-remerge stub chain; the close is three lines and its trigger is the anchored `superseded #<n>:` line `cmd_merge` prints.
- A real GitHub run. The fixture is local bare repos plus the gh stub; no scratch GitHub repo was created, because that is an outward-facing write for a knob that ships off.

## Open questions for the operator

- `KIT_WRAP_CARRY_CHECKS_SECS` defaults to 300 per carry, serial. ops-toolkit carry PRs run no checks, so the wait there is zero reads past the first. A repo with slow CI would hold `apply` up to five minutes per carry branch.
- Flip `wrap.autoland_carry = true` in the operator `kit.toml` after merge; the default ships `false`.
- Orphan `wrap/stray-*` branches whose file has no stray lines left are not swept (spec Design). They stay on origin until a human deletes them or their PR merges.
