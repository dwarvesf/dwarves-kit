# Proof of done: the Built line refuses an all-prose outcome

Date: 2026-09-10. Branch: feat/wrap-prose-only-gate.

## Green run

| Check | Result | Verdict |
|---|---|---|
| `bash tests/test-wrap.sh` before the change | 308 passed, 0 failed | PASS |
| `bash tests/test-wrap.sh` after the change | 319 passed, 0 failed | PASS |
| All-prose LIST Built (a `.claude/memory/` bullet plus a `research/` bullet) | exit 1, finding names the prose rule | PASS |
| Same Built plus `PROSE-ONLY: <reason over twelve characters>` | `report-lint: clean`, exit 0 | PASS |
| Same Built plus `PROSE-ONLY: none` | exit 1, the token cannot silence the rule | PASS |
| Mixed Built (`lib/wrap/wrap.sh` plus a memory note) | exit 0, something was built | PASS |
| Inline Built naming one memory note | exit 1 | PASS |
| Inline Built naming a code path | exit 0 | PASS |
| `NOTHING: no candidates` and `SKIPPED: <reason>` | exit 0, untouched | PASS |

## Negative control

Run after the commit, through `lib/gate/negctl.sh`. The mutation neuters the prose
classification by replacing `PROSE_TARGET_RE` with a pattern no target matches.

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' "s|^PROSE_TARGET_RE=.*|PROSE_TARGET_RE='zzz-never-matches-any-target'|" lib/wrap/report-lint.sh
Changed: lib/wrap/report-lint.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/report-lint.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Reproduce

```
bash tests/test-wrap.sh
bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh" \
  "sed -i '' \"s|^PROSE_TARGET_RE=.*|PROSE_TARGET_RE='zzz-never-matches-any-target'|\" lib/wrap/report-lint.sh"
```
