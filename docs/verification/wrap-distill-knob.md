# Verification -- wrap-distill-knob

`[wrap] distill` (default `false`) gates the distill half of `/kit:wrap`: the pre-step-0 candidate scan, both step -1 seams, and all of step 7 with its drain. A plain wrap lands only; `/kit:wrap distill [repo...]` or `distill = true` in the operator or kit-root `kit.toml` runs both halves. The report carries `Built:` and `Seam:` as `SKIPPED: distill off` when the switch is off.

## Green run
```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: PASS
```
`test-wrap: all 515 passed`. The seven cases this branch adds:

| Case | Checks |
|---|---|
| `commands/wrap.md reads wrap.distill` | the command resolves the key |
| `kit.toml declares distill` | the key is declared with its default |
| `wrap.distill ships as false` | kit-root default is off |
| `wrap.distill honours the operator kit.toml` | operator `true` wins over the root |
| `wrap.distill ignores a project .kit.toml` | a project toml cannot turn the distill half on |
| `commands/wrap.md takes the distill argument` | `/kit:wrap distill` is documented as the per-run override |
| `Built and Seam both SKIPPED: distill off passes` | `lib/wrap/report-lint.sh` accepts the off-switch report shape |

Also green from the same tree: `tests/test-config-registry.sh` (50), `tests/test-reserved-config-guard.sh` (9), `tests/test-config-stamp.sh` (17), `tests/test-config.sh`.

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh" "sed -i '' 's/^distill = false /distill = true  /' kit.toml"
Exit: 0 (green before mutation)
Mutation: sed -i '' 's/^distill = false /distill = true  /' kit.toml
Changed: kit.toml
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- kit.toml
Exit: 0 (green after restore)
Verdict: PASS
```
The mutation flips the shipped default to `true`; `wrap.distill ships as false` goes red; the restore brings the suite back to 515 green and the tree back to clean.

## Not proven
- A live `/kit:wrap` run with the switch off. The command is a prompt file; the tests prove the key resolves, the fence holds, and the lint accepts the report shape. The first real wrap after merge is the end-to-end run, and its report must show both `SKIPPED: distill off` lines.
- A live `/kit:wrap distill` run proving the argument re-enables the half. Same reason.
