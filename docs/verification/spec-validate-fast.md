# Verification -- spec-validate-fast

Docs-only change to four command files (`spec`, `spec-validate`, `wrap`, `execute`) plus a regenerated `docs/FEATURES.md`. The proof is a literal-string grep chain that is red on the base and green after, and a full `tests/test-meta.sh` run.

## Green run
```
Command: bash <grep chain from the spec's Verification section>   (includes bash tests/test-command-emit-sweep.sh)
Exit: 0   (sweep: Passed 18 / 18)
Verdict: green after the change

Command: bash tests/test-meta.sh
Exit: 0   (Passed: 879 / 879)
Verdict: green after T5 regenerated docs/FEATURES.md
```

## Negative control
```
Command: git checkout ad901924 -- commands/spec.md commands/spec-validate.md commands/wrap.md commands/execute.md; <same grep chain>
Exit: 1
Verdict: RED on the base text, as required
```
The four command files were restored with `git checkout HEAD -- commands`, and the chain went green again (exit 0).

## Baseline
`bash tests/test-meta.sh` on the untouched base (`ad901924`): `Passed: 878 / 879`, one failure, `docs/FEATURES.md is fresh (check verb, SPEC-219)`. `tests/test-command-emit-sweep.sh` exits 0. After the edits and before T5 the failing list was the same single assertion (no new failure). After `bash lib/registry/feature-registry.sh check --fix docs/FEATURES.md` it is 879 / 879.

## Not proven
- A live run of the parallel fan-out in a wrap or execute session. Round 2 and 3 of this spec's own validation ran that way (slowest reviewer 72s), but that is the lead's run, not this build's.
- The token multiplier per round.

## Negative control (negctl), after the review batch
```
Command: bash <grep chain script, the spec's Verification block>
Exit: 0 (green before mutation)
Mutation: git show ad901924:commands/spec.md > commands/spec.md
Changed: commands/spec.md
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- commands/spec.md
Exit: 0 (green after restore)
Verdict: PASS
```
Run via `bash lib/gate/negctl.sh "$PWD" "bash <script>" "<mutation>"`. After the review batch: chain exit 0 with `tests/test-command-emit-sweep.sh` 18 / 18, and `tests/test-meta.sh` 879 / 879.
