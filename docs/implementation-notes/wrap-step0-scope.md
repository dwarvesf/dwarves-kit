# Implementation notes -- wrap-step0-scope

Deltas from `docs/specs/SPEC-383-wrap-step0-scope.md`. Nothing here repeats what the spec already states.

## `_autoland_on` carries the `--no-pull` guard, not each call site

- Context: the spec says `--no-pull` suppresses the autoland leg of the stray-line carry. `lib/wrap/wrap-carry.sh` reads the knob at six sites (held-branch landing, two dry-run WOULD lines, the post-push landing, and the stray-commits landing and its `not landed` note).
- Decision/Change: one guard line at the top of `_autoland_on` (`[ "$NO_PULL" != 1 ] || return 1`), so every site agrees.
- Why: six call-site edits would drift. The stray-commits branch never runs under `--no-pull` anyway, so the shared helper is the smallest change that covers all six.
- Impact: a dry run under `--no-pull` also prints no `WOULD open and merge its PR` line; the test pins that.

## Round 2 warnings the build absorbed instead of the spec

- The `index.lock` limit reads "every local removal" in `commands/wrap.md`: `_apply_origin_branches` and the carry have no `_write_guard`, so they still run under a held lock. Both write no checkout state.
- AC7's many literals became one assertion each in `tests/test-wrap-deploy.sh`, so a red test names the sentence that drifted.
- NC1 and NC2 mutate two different `NO_PULL` gates, told apart by the preceding line (`echo "-- pull:"` versus the 4-space `-- stray commits:` block), each with an exact-once match guard in the mutator.
- The pre-existing assertion that greps `STOP every write to that repo's MAIN CHECKOUT` stays: the new stop bullet keeps that literal, and the 7b isolated-worktree literal is unchanged.

## Known residue

- The re-merge exception (a CONFLICTING PR whose head the main checkout holds) is a doc protocol with no verb gate. `wrap merge` has no stop input. A verb-level refusal is a separate change.
- Validate round 2 ended NEEDS REVISION with its three criticals folded; no third round ran. The gate ledger holds a logged override for `validate`.
