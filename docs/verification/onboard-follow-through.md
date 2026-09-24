# Verification -- onboard-follow-through

`[wrap] distill` now ships `true` (was `false`): operators asked for the distill half every
session, and the landing half still lands regardless of the knob. `[wrap] follow_through` keeps
its shipped default `"off"`, unchanged. `/kit:onboard` section D gains one always-offered question
(not tied to any module choice): whether `/kit:wrap`'s follow-through phase should build and merge
follow-ups itself (`off` / `lanes` / `all`), writing the answer into the OPERATOR `kit.toml` under
`[wrap]`, never a project `.kit.toml`, matching `follow_through`'s existing root-only fence.

## Green run
```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: PASS
```
`test-wrap: all 978 passed`. The cases this branch changes or adds:

| Case | Checks |
|---|---|
| `wrap.distill ships as true` | kit-root default is now on |
| `wrap.distill honours the operator kit.toml` | operator `false` still wins over the root |
| `wrap.distill ignores a project .kit.toml` | a project toml still cannot flip the distill half |
| `built-in default (no operator file): wrap.distill resolves true` | no operator file at all still resolves to the new built-in default |
| `built-in default (no operator file): wrap.follow_through resolves off` | `follow_through`'s built-in default is unchanged |
| `commands/wrap.md takes the distill argument` | `/kit:wrap distill` is still documented as the per-run override |
| `Built and Seam both SKIPPED: distill off passes` | `lib/wrap/report-lint.sh` still accepts the off-switch report shape (an operator can still set `distill = false`) |

```
Command: bash tests/test-config-registry.sh
Exit: 0
Verdict: PASS
```
`56/56 passed` -- the registry's `wrap.distill` row text and default match `kit.toml`.

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh" "sed -i '' 's/^distill = true  /distill = false /' kit.toml"
Exit: 0 (green before mutation)
Mutation: sed -i '' 's/^distill = true  /distill = false /' kit.toml
Changed: kit.toml
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- kit.toml
Exit: 0 (green after restore)
Verdict: PASS
```
The mutation reverts the shipped default back to `false`; `wrap.distill ships as true` and the two
built-in-default cases go red; the restore brings the suite back to 978 green and the tree back to
clean.

## Not proven
- A live `/kit:onboard` run walking the new question end to end (accept `lanes`, decline, and
  answer `off` explicitly) and checking the operator `kit.toml` write. `onboard.md` is a prompt
  file with no executable test harness of its own; the config-resolution tests above prove the key
  it writes resolves correctly at every level, not the wizard's own prompt/preview/confirm flow.
- A live `/kit:wrap` run with no `distill` argument and no operator override, confirming its first
  real report runs the distill half by default rather than reporting `SKIPPED: distill off`.
