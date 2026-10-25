# Proof of done: docdrift + kit:doc-drift Tier 1 path check

Run id: `docdrift-refcheck`. Lane: normal. Type: spec-feature, behavioral. Contract owed
(`lib/gate/proof-gate.sh contract`): the real primary flow run end to end, plus a negative control.

## Green run

```
Command: bash tests/test-docdrift-refcheck.sh
Exit: 0
Output:
    PASS a dead directory ref is reported
    PASS exactly the two dead refs are reported
    PASS --docs overrides the default item set
  -- the shipped skill points at the scanner --
    PASS SKILL.md step 3 names refcheck.sh
  
  Passed: 16 / 16
  All doc-drift refcheck tests passed.
Verdict: PASS. 16 of 16, including the fixture case where only the dead in-repo ref is reported.
```

Adjacent suites on the same tree: `bash tests/test-meta.sh` 930/930, `bash tests/test-audit-cadence.sh`
13/0, `bash tests/test-kit-contract.sh` clean for `lib/docdrift` after this file and `SPEC.md` landed.

## Live run of the primary flow

```
Command: bash lib/docdrift/refcheck.sh scan --repo <ops-toolkit>
Exit: 0
Output:
  docs/flow-from-intake-to-ship.md	4	tick	docs/WORKFLOW.md
  SUMMARY	7 docs	89 refs checked	1 dead
Verdict: PASS. The docs-fix pass on that repo left one dead pointer in the default item set.
```

With ops-toolkit's own living-doc pathspec (tool READMEs, `docs/ref`, `.claude/rules`, `_meta`,
tool docs; dated and generated records excluded) the same scan prints `SUMMARY  447 docs  2144
refs checked  113 dead`, against about 900 hits from the unfiltered hand-rolled script.

## Negative control

```
## Negative control (negctl)
Command: bash tests/test-docdrift-refcheck.sh
Exit: 0 (green before mutation)
Output:
  -- resolution rules --
    PASS a dead relative link is reported
    PASS a dead directory ref is reported
    PASS exactly the two dead refs are reported
    PASS --docs overrides the default item set
  -- the shipped skill points at the scanner --
    PASS SKILL.md step 3 names refcheck.sh
  
  Passed: 16 / 16
  All doc-drift refcheck tests passed.

Mutation: sed -i.bak 's/if (!(c in TOP)) return/if (0) return/' lib/docdrift/refcheck.sh && rm -f lib/docdrift/refcheck.sh.bak
Changed: lib/docdrift/refcheck.sh
Exit: 1 (under mutation, RED expected)
Output:
  -- resolution rules --
    PASS a dead relative link is reported
    PASS a dead directory ref is reported
    PASS exactly the two dead refs are reported
    PASS --docs overrides the default item set
  -- the shipped skill points at the scanner --
    PASS SKILL.md step 3 names refcheck.sh
  
  Passed: 13 / 16
  FAILED: 3

Restore: git checkout HEAD -- lib/docdrift/refcheck.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation removes the first-segment filter. Three cases go red: the sibling-repo ref, the
"only row" count, and the SUMMARY line, because `othertool/src/main.go` is reported once the
filter is gone. Restored from HEAD and re-run green.

## Not proven

- Refs written as bare filenames (no `/`) are never judged; that is the filter, by design.
- A ref whose first segment is a top-level entry but that is meant for a consumer repo (for
  example `.claude/settings.json` in the kit's own docs) is reported; the scan cannot tell.
- Inventory tables, counts and flags (the other Tier 1 bullets) are out of scope.
