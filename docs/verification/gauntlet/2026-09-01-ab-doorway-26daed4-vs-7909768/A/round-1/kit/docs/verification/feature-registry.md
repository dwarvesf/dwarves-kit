# Proof of done: feature-registry (SPEC-219)

## Acceptance criteria

| AC | Claim | Status |
|---|---|---|
| AC-1 | generator deterministic | MET (byte-identical double run) |
| AC-2 | GENERATED marker + one table per kind, every live file once | MET |
| AC-3 | trigger class, description, spec refs, test refs per row | MET (spot checks below) |
| AC-4 | agents carry dispatched-by; hooks carry event | MET |
| AC-5 | test-meta freshness pin, green on committed tree | MET |
| AC-6 | negative control: dummy feature -> RED, removed -> GREEN | MET |

## Implementation

`lib/registry/feature-registry.sh` (bash + grep/sed/awk/jq, LC_ALL=C, no timestamps in output) emits `docs/FEATURES.md`; `tests/test-meta.sh` gained the SPEC-219 regenerate-and-diff pin.

## Confirmation runs

| # | Check | Command | Result |
|---|---|---|---|
| 1 | determinism | `bash lib/registry/feature-registry.sh generate /tmp/feat2.md; cmp docs/FEATURES.md /tmp/feat2.md` | identical, printed `DETERMINISTIC` |
| 2 | full suite green | `bash tests/test-meta.sh` | `Passed: 733 / 733`, incl. `PASS docs/FEATURES.md is fresh (regenerate == committed, SPEC-219)` |
| 3 | negative control RED | `printf ... > commands/zz-dummy-feature.md; bash tests/test-meta.sh` | `FAIL docs/FEATURES.md is fresh` (+8 sibling count-pin FAILs), `Passed: 726 / 735, Failed: 9` |
| 4 | negative control restore | remove dummy, `bash tests/test-meta.sh` | `PASS docs/FEATURES.md is fresh`, `Passed: 733 / 733` |
| 5 | trigger-class spot checks | `grep -E 'wayfind\|skill-review\|statusline\|safety-gate' docs/FEATURES.md` | `wayfind` = `[H]` (disable-model-invocation true); `doc-drift` = `[I]`; `safety-gate.sh` event `PreToolUse`; `statusline.sh` event `StatusLine` (settings.json key) |

## Run detail

Run 3 is the negative control required by the behavioral proof contract: the dummy feature file is the injected defect; the pin (and the pre-existing derived-count pins) went RED; run 4 is the restore back to GREEN. No revert of the generator itself was needed: the drift-diff pin IS the detection mechanism under test.

Known-true finding surfaced by the registry (not a defect of this change): `skill-review` frontmatter says `disable-model-invocation: false` while `docs/workflow-paths.md` marks it `[H]`; recorded in the implementation notes for the Phase B cross-check.

## Reproduce

```
bash lib/registry/feature-registry.sh generate /tmp/f.md && cmp /tmp/f.md docs/FEATURES.md
bash tests/test-meta.sh
printf -- '---\ndescription: dummy\n---\n' > commands/zz-dummy-feature.md && bash tests/test-meta.sh; rm commands/zz-dummy-feature.md
```
