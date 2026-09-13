# Proof of done: the trigger-phrase guard on think, design, debug

Branch `test/command-trigger-guard`. Behavioral surface: `tests/test-command-triggers.sh`, a
regression test asserting the `description:` line of `commands/think.md`, `commands/design.md`,
and `commands/debug.md` keeps its English and Vietnamese trigger phrases and names the
superpowers skill it replaces. Also carries one queued board row.

## Runs

| # | Command | Exit | Verdict |
|---|---|---|---|
| 1 | `bash tests/test-command-triggers.sh` | 0 | PASS (`=== 9/9 passed ===`) |

## Negative control

```
## Negative control (negctl)
Command: bash tests/test-command-triggers.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' 's/thiết kế X/thiet ke X/' commands/think.md
Changed: commands/think.md
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- commands/think.md
Exit: 0 (green after restore)
Verdict: PASS
```

Reproduce:

```bash
bash lib/gate/negctl.sh . "bash tests/test-command-triggers.sh" "sed -i '' 's/thiết kế X/thiet ke X/' commands/think.md"
```

The mutation strips the diacritics from one phrase, the probe for it misses, and the test goes
red. Restoring the file returns it to green in the same run.
