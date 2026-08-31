# Proof of done: ship-clean distribution (SPEC-239)

Date: 2026-09-01. Branch: fix/ship-clean-distribution.

## Recorded run

- Command: `grep -c 'op://Toolkit' tests/gauntlet/cleanroom/run-remote.sh`
- Exit: 0; Output: `0`
- Command: `grep -c colima tests/gauntlet/cleanroom/run-remote.sh`
- Exit: 0; Output: `0`
- Command: `shellcheck -S warning tests/gauntlet/cleanroom/run-remote.sh`
- Exit: 0; Output: clean
- Command: `grep -rn 'op://Toolkit\|colima start' tests/gauntlet commands agents docs/guides docs/specs` (excluding SPEC-239 itself)
- Exit: 0; Output: `0` hits
- Command: `grep -iE 'default.*claude' docs/specs/SPEC-238-prepared-room.md`
- Exit: 0; Output: the Scope banner (default probe = Tier-1 claude CLI)
- Command: `bash tests/test-meta.sh`
- Output: 815/822, the 7 failures byte-identical to the branch parent (worker stash-diffed to confirm no new failure)
- Verdict: PASS

## Negative control

The pre-fix state is the red arm: on the branch parent, `grep -c 'op://Toolkit' run-remote.sh` returned nonzero (Han's vault as the literal default), `grep -c colima` returned nonzero (Han's runtime as the docker fallback), and SPEC-238 had no default-probe scoping banner. An external adopter reaching the remote-runner path hit a 1Password vault they do not have and a `colima start` for a runtime they may not run. Post-fix all three greps are 0 / present-and-scoped; the default becomes Tier-1 (neutral op:// placeholder set via kit.toml, runtime-agnostic docker check). Han's own runs are unchanged (his kit.toml supplies the real ref, so the placeholder default is never reached, edge case 1).

## Rollback

Doc/config reframes, single squash commit, `git revert`-able; no state, no logic change.
