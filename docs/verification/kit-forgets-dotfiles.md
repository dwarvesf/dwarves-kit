# Proof of done: the kit stops reading the operator's dotfiles skill

Branch `fix/kit-forgets-dotfiles`. Behavioral surface: `tests/test-weekend-batch.sh` drops AC2 and
AC4 (which grepped a skill file in a sibling dotfiles checkout by path) and gains a replacement
assertion that neither the test nor `lib/learn/weekend-batch.sh` names a dotfiles skill path or
expands `KIT_SIBLING_ROOT`. The lib's header comment no longer names any consumer skill.

## Runs

| # | Command | Exit | Verdict |
|---|---|---|---|
| 1 | `bash tests/test-weekend-batch.sh` | 0 | PASS (39 pass, 0 fail, 0 skip; was 38 with 2 skips in CI) |

## Negative control

```
## Negative control (negctl)
Command: bash tests/test-weekend-batch.sh
Exit: 0 (green before mutation)
Mutation: printf '%s\n' 'KIT_SIBLING_ROOT:-/dotfiles/home/x' >> lib/learn/weekend-batch.sh
Changed: docs/verification/weekend-batch/sample-digest.md, lib/learn/weekend-batch.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- docs/verification/weekend-batch/sample-digest.md lib/learn/weekend-batch.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Reproduce:

```bash
bash lib/gate/negctl.sh . "bash tests/test-weekend-batch.sh" "printf '%s\n' 'KIT_SIBLING_ROOT:-/dotfiles/home/x' >> lib/learn/weekend-batch.sh"
```

Planting a sibling-checkout path back into the lib turns the replacement assertion red. The
`sample-digest.md` entry in `Changed:` is the suite regenerating its own fixture on every run, not
part of the mutation; the restore line returns both.

## Not proven here

That the moved assertions land in the consumer's own tests. That is sub-goal 02 of the
learning-boundary mega-goal (`_meta/megagoals/learning-boundary/`), which restores them in
learning-kit beside the skill they assert on.
