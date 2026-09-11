# Proof of done: lint (scattered-ids.sh)

Spec: `lib/lint/SPEC.md`. Host: macOS, bash. Branch: `chore/strip-ids-surface`.

## Green run

| # | Claim | Command | Result |
|---|---|---|---|
| 1 | the unit suite passes | `bash tests/test-lint-scattered-ids.sh` | `test-lint-scattered-ids: all 9 passed`, exit 0 |
| 2 | the existing ratchet still passes, unchanged behavior for zones 1/2 | `bash tests/test-no-scattered-ids.sh` | `test-no-scattered-ids: all 3 passed` |
| 3 | the tool is wired to an operator surface | `bash bin/lint --zone bin --count` | `0` |
| 4 | zones this batch cleaned report zero | `for z in hooks bin skills; do bash lib/lint/scattered-ids.sh --zone "$z" --count; done` | `0`, `0`, `0` |
| 5 | `--count` and the bare listing agree on every zone | see test 5 in `tests/test-lint-scattered-ids.sh` | 3/3 zones agree |

### Negative control

Planting `# see SPEC-999 for the (nonexistent) rationale` in a tracked `hooks/*.sh` fixture is
caught by `--zone hooks`; a `Relates-to: SPEC-999` line in the same fixture is dropped as
exempt. Both assertions live in `tests/test-lint-scattered-ids.sh` ("planted hit vs exempt
line") and ran green above. The fixture is created, added to the index, and removed in the
same test run (`trap cleanup EXIT`); `git status` carries no leftover after a run.

### Unknown-zone and no-args refusal

```
$ bash lib/lint/scattered-ids.sh --zone made-up-zone; echo $?
scattered-ids: unknown zone 'made-up-zone'
1
$ bash lib/lint/scattered-ids.sh; echo $?
usage: scattered-ids.sh [--zone <name>|--all] [--count]
1
```

## Known gap

`lib` and `docs-specs` zones are enumerable (`--zone lib --count` -> 823, `--zone docs-specs
--count` -> 2989 at the time of this run) but not yet clean; no test asserts them at zero. They
are future cleanup batches, not this one's scope (see `lib/lint/SPEC.md` Non-goals).
