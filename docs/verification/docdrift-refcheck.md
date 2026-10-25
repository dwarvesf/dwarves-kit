# docdrift refcheck: recorded run

Run id: `docdrift-refcheck`. Lane: normal. Type: behavioral. Full record:
`lib/docdrift/docs/proof-of-done.md` (co-located with the module, per SPEC-016). This file is
the ship-gate's recorded run.

## What changed

The doc-drift Tier 1 bullet "every backtick path or file reference resolves" had no script, so
each run hand-rolled one and drowned in sibling-repo, gitignored and placeholder hits.
`lib/docdrift/refcheck.sh` judges a ref only when its first segment is a top-level entry of the
repo (or it is a relative link), and `skills/doc-drift/SKILL.md` step 3 names it.

## Green run
```
Command: bash tests/test-docdrift-refcheck.sh
Exit: 0
Output:
    PASS --docs overrides the default item set
  -- the shipped skill points at the scanner --
    PASS SKILL.md step 3 names refcheck.sh
  
  Passed: 16 / 16
  All doc-drift refcheck tests passed.
Verdict: PASS
```

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
The first-segment filter was removed, 3 of 16 cases went red, and the file was restored from HEAD.

## Not proven
- Bare filenames, and refs meant for a consumer repo, are outside the filter by design.
