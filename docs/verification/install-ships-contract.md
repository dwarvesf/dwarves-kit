# Verification: install ships the operate-contract (SPEC-049)

Proof class: behavioral (changes what the install deploys). Reproduce:
`bash tests/test-install-contract.sh` (3/3) + the live check below. Last run: 2026-06-09.

## GREEN: adopt + gate-ledger work FROM a simulated install

`tests/test-install-contract.sh` builds an install dir with install.sh's out-of-place symlink
layout (lib + AGENTS.md + WORKFLOW.md symlinked), then:

- `bash $INSTALL/lib/adopt.sh <tmp>` -> creates the contract (the source AGENTS.md now resolves
  at `$KIT_ROOT/AGENTS.md`).
- `gate-ledger required full` (KIT_ROOT=$INSTALL) -> prints the 11-gate matrix (reads
  `$INSTALL/WORKFLOW.md`).

## GREEN: the LIVE install (the sub-goal 03 failure, re-tested)

After symlinking the two files into `~/.claude/dwarves-kit/` (what the new install.sh does):

```
$ bash ~/.claude/dwarves-kit/lib/adopt.sh <tmp>
adopt: <tmp> (updated)          # was: "no source AGENTS.md" before this fix
$ bash ~/.claude/dwarves-kit/lib/gate-ledger.sh required full | wc -l
11                              # was: "awk: can't open WORKFLOW.md" before this fix
```

## NEGATIVE CONTROL: an install WITHOUT the contract symlinks

`tests/test-install-contract.sh` scenario 3: a bare install (lib only, no AGENTS.md/WORKFLOW.md)
-> `adopt.sh` exits non-zero with "no source AGENTS.md". The fix is load-bearing: remove the
symlinks and adopt breaks again.

## Suite

`bash tests/test-install-contract.sh` -> PASS=3 FAIL=0. `bash tests/test-meta.sh` -> 392/392.

## Verdict: PASS
