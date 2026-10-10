# Implementation notes: wrap land --draft

Delta from `docs/specs/SPEC-404-wrap-land-draft.md` only. The spec is the contract; this log holds what the spec leaves to the builder.

## Validation round 1: folded criticals

Round 1 closed NEEDS REVISION with two criticals. Both are folded into the spec as DEC-H and DEC-I.

- DEC-H: four reviewers found that the step 10 swap hides the draft push from `hooks/ship-gate.sh`. The draft path now pipes a synthesized push payload to the hook before its push (AC-16).
- DEC-I: two reviewers found that the new step 10 line dropped `--body-file`, so the template check refused it in a repo with a PR template. Step 10 now passes `--body-file` (AC-15, AC-17).

## Round 1 warnings for the builder

The build's tests catch each of these, so they stay out of the spec.

- Post-create `gh pr view <n> --json isDraft`: pass `--repo <url>`. Treat an unreadable or empty answer the same as `false`: exit 2. The `DRAFT REFUSED` message names `gh pr ready --undo <n>` and says the PR stays open.
- The stub's `pr view` default prints `{}`, so `isDraft` reads null. Add the stub switch before any new-PR draft case can pass.
- AC-10 (`draft_no_ship_record`) must seed a ledger run for the rid, as the existing cases do near `tests/test-wrap-land.sh:339`. Without the seed, the Ship path never runs and the control stays green.
- The `noclobber` case: `wrap.sh` runs as a child process, so `set -C` in the test shell does not reach it. Run the child with `bash -C` or export `SHELLOPTS`, or the case proves nothing.
- `--verify` has no given-flag variable today, and `NO_PULL` is a global reset in `cmd_land`. Track each flag's presence for the exit-64 refusals, so `--verify=` with an empty value still refuses.
- Pin the already-landed draft refusal right after `proof` turns non-empty. An open PR on a landed branch reaches the earlier `LAND REFUSED` return first, and that message is acceptable.
- Update the `cmd_land` header comment flag list as well as the usage line.
- AC-3 "byte for byte" excludes the usage text, which TASK-A changes on purpose.
- The Outputs list omits two lines the adopt path already prints: `body set from the proof of done` and the stderr `keeps its own title and body` note. Do not assert an exact line order that excludes them.
- The push runs before the base, author and login checks on an adopted PR, as in `land`. Kept unchanged, because moving them is a `land` change.
- An adopted draft with an empty body and no proof file stays empty. DEC-E covers new PRs only.
- `_land_proof_files` tests `-f`, which follows symlinks, and the body inlines the file. This is a pre-existing `land` risk and out of scope here.
- Step 10's old push set an upstream with `-u`. `land` pushes without it. This is harmless, because step 10 removes the worktree after the draft opens.

## Fold-diff check warnings

- `WRAP_LAND_SHIP_GATE` overrides the gate path, so an exit-0 script there skips the gate. Print one stderr line naming the override whenever it is set.
- AC-16 drives a stub gate only. Add one smoke case that pipes the real `hooks/ship-gate.sh` through `--draft` on a fixture, so a payload mismatch with the real hook goes red.
- Step 10 passes `--body-file docs/verification/<slug>.md`. When that file is missing, `land` exits 64 on the existing-file check. That message is clear enough, so no new refusal.

## Validation round 2 warnings (APPROVED, critical=0)

- Build the hook payload with `jq -n --arg cwd ... --arg cmd ...`, never a printf template. A branch name with a quote would break the JSON, and the hook fails open on an empty command.
- Treat ANY nonzero hook exit as a refusal, not only exit 2. A missing hook file refuses already, so a hook crash should too. Add an exit-1 stub case to AC-16.
- Capture the hook's stdout and stderr. Relay stderr in the refusal. Drop stdout on exit 0 (it can hold a JSON `systemMessage`), so the draft output order stays as the Interfaces list says.
- Export `CLAUDE_PLUGIN_ROOT` to the kit root (`$SELF_DIR/../..`) when unset, before the hook runs, so the hook's libs resolve from the same kit and not a missing install path.
- The real-hook smoke case runs with the libs present. Name the install-path dependency in a comment.
- The ship-gate refusal row covers every hook block (identities, doc-projection, registry freshness), so print the hook stderr verbatim after `DRAFT REFUSED: ship-gate blocked the push`.
- Step 10 keeps the `cd <wt> &&` prefix on the `land --draft` line, because `--body-file docs/verification/<slug>.md` is relative to the cwd.
- Add a `created ready` stub fixture (`GH_STUB_PR_<n>` with `isDraft:false`) and a case for the DEC-G post-create refusal, with a negative control (delete the read: case red).
- TASK-D includes the stub `pr view` switch.
- Refresh the `## Design` Diagram sentence when the build lands: four refusals plus the hook call. Add the DEC-G box to Picture and a row to the refusals table in the same commit.
