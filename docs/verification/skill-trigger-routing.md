# Proof of done: trigger phrases on think, design, debug and the AGENTS.md routing paragraph

Branch `fix/skill-trigger-routing`. Behavioral surface: the `description` frontmatter of
`commands/think.md`, `commands/design.md`, `commands/debug.md` (what the Skill listing shows the
model at selection time), the skill-routing paragraph in `AGENTS.md` section 2, and the
regenerated `docs/FEATURES.md` projection.

## Runs

| # | Command | Exit | Verdict |
|---|---|---|---|
| 1 | routing check (below) | 0 | PASS (seven surfaces carry their phrase) |
| 2 | `bash lib/gate/doc-projection-check.sh .` | 0 | PASS |
| 3 | `bash lib/registry/feature-registry.sh generate && git diff --quiet docs/FEATURES.md` | 0 | PASS (projection fresh) |
| 4 | `bash tests/run-all.sh` | see below | test-config-registry red on master too; test-config-seams re-run alone |

Routing check, the exact command:

```bash
for p in 'commands/think.md:thiết kế X' 'commands/think.md:superpowers:brainstorming' \
         'commands/design.md:thiết kế giải pháp' 'commands/debug.md:bị lỗi' \
         'commands/debug.md:superpowers:systematic-debugging' \
         'AGENTS.md:Skill routing in an adopted repo' \
         'docs/FEATURES.md:Use when the operator brings a new idea'; do
  grep -q -- "${p#*:}" "${p%%:*}" || { echo "MISS $p"; exit 1; }
done; echo ok
```

Run 4 detail: `tests/test-config-registry.sh` fails two `wrap.drain_staged` assertions on the
untouched master clone as well (the operator `~/.config/dwarves-kit/kit.toml` sets the key to
`true`; the fixture reads ambient config). `tests/test-config-seams.sh` hit the 300s ceiling
under the full-suite load and passed when re-run alone; its result is recorded in the PR.

## Negative control

```
## Negative control (negctl)
Command: bash routing-check.sh .
Exit: 0 (green before mutation)
Mutation: git checkout origin/master -- commands/think.md
Changed: commands/think.md
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- commands/think.md
Exit: 0 (green after restore)
Verdict: PASS
```

Reproduce (save the routing check above as `routing-check.sh`):

```bash
bash lib/gate/negctl.sh . "bash routing-check.sh ." "git checkout origin/master -- commands/think.md"
```

The mutation puts the pre-branch one-line description back, so the `thiết kế X` probe on
`commands/think.md` misses and the check exits 1. Restoring the committed file returns it to 0.

## Not proven here

Live skill selection is model behavior: whether a "thiết kế X" prompt now lands on `/kit:think`
instead of `superpowers:brainstorming` shows only in a session started after this merge, because
a running session holds the description it loaded at start. The check above proves the
selection surface carries the phrases; the first post-merge session with a design or bug
prompt is the live run.
