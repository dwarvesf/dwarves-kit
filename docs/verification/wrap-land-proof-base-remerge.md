# Verification -- wrap land proof block ignores merged-in proof files

`wrap land` took its proof base once, before the push. When the PR came back CONFLICTING, land merged origin/<default> into the branch, and the closing PROOF OF DONE block still diffed from the old base. Every proof file that reached the branch through the merge was printed as the branch's own proof. The fix re-takes the base right after the merge-in. Files: `lib/wrap/wrap-land.sh`, `tests/test-wrap-land.sh`.

## Green run

```
Command: bash tests/test-wrap-land.sh
Exit: 0
Output:
test-wrap-land: 15 sections, 15 ran, 0 cached (0 checks credited)
test-wrap-land: all 727 passed
Verdict: PASS
```

The new case PB7 builds a real branch with no proof file, advances origin/main with `tools/x/docs/proof-of-done.md`, forces the CONFLICTING cycle, and checks that the closing output carries no PROOF OF DONE block.

```
Command: LAND_CACHE=0 LAND_SECTION=sec_proofbody bash tests/test-wrap-land.sh
Exit: 0
Output:
  PASS PB7: exits 0
  PASS PB7: the land really merged origin/main in
  PASS PB7: the merge commit brought the other proof file in
  PASS PB7: no PROOF OF DONE block
  PASS PB7: the merged-in proof file is not listed
  PASS PB7: the merged-in proof output is not shown
land-section-result: 32 0 32
Verdict: PASS
```

## Negative control

```
Command: git checkout lib/wrap/wrap-land.sh && LAND_CACHE=0 LAND_SECTION=sec_proofbody bash tests/test-wrap-land.sh
Exit: 1
Output:
  FAIL PB7: no PROOF OF DONE block
  FAIL PB7: the merged-in proof file is not listed
  FAIL PB7: the merged-in proof output is not shown
land-section-result: 29 3 32
Verdict: PASS (the unfixed code fails exactly the three PB7 checks)
```

The fix was reverted to the committed `lib/wrap/wrap-land.sh`, run, then re-applied from a saved patch. The final run above is on the fixed file.

## Not proven

- The draft exit and the no-merge-in path keep the base taken before the push; PB1 to PB6 cover them and still pass.
- A real GitHub squash merge is stubbed; the fixture merges through the bare remote.
