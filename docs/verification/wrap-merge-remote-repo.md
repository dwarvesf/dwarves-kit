# Verification -- wrap-merge-remote-repo

`bin/wrap merge --repo <owner>/<name>` merges one own green PR with no local checkout: same gate and settle wait, squash through gh, verified through gh, local steps skipped and named.

## Green run
```
Command: bash tests/test-wrap-merge-nopull.sh; bash tests/test-wrap-merge.sh; bash tests/test-wrap.sh
Exit: 0
Output:
test-wrap-merge-nopull: all 50 passed
test-wrap-merge: all 410 passed
test-wrap: all 2858 passed
Verdict: PASS
```
Real primary flow, read-only half (no PR merged): the dry run against GitHub with no clone on this machine.
```
Command: bin/wrap merge --repo dwarvesf/brainery
Exit: 0
Output:
remote dwarvesf/brainery: no local checkout, so the re-merge push, tree verify and pull are skipped
SKIP #402 draft: A graphics upgrade took ten hours to build: draft
dry run; pass --apply to merge one PR.
Verdict: PASS
```

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap-merge-nopull.sh" "sed -i '' 's/\[ \"\$mb\" = \"\$3\" \]/[ -n \"\$mb\" ]/' lib/wrap/wrap-merge.sh"
Exit: 1 (under mutation, RED expected)
Output:
test-wrap-merge-nopull: 48 passed, 2 FAILED of 50
Verdict: PASS (RED under the mutation, GREEN after `git checkout HEAD -- lib/wrap/wrap-merge.sh`)
```
The mutation makes `_remote_merge_verify` accept any merge base, so a merge commit absent from the default branch would pass.

## Not proven
- A real `--apply` squash-merge by slug: it would merge a live PR. The merge, verify and refusal paths run against the gh stub only.
- The check wait (`gh pr checks --watch`): by slug, as locally, pending checks are refused by the gate, not waited on.
