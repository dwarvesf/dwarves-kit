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

---

## 2026-06-10 review-driven hardening (PR #24)

The kit's own 3-lens review-team (dogfooded) returned two real findings:

1. **Security HIGH:** the install block did `[ -f "$LINK" ] && rm -f "$LINK"`, which would
   silently destroy a user's REAL `AGENTS.md`/`WORKFLOW.md` placed at `~/.claude/dwarves-kit/`.
   Fixed: only a symlink is removed-and-refreshed; a real file is left intact with a `[skip]`
   notice (adopt resolves the source from `$KIT_ROOT` either way).
2. **Test-coverage HIGH:** `test-install-contract.sh` simulated the install layout (hand-built
   symlinks) but never invoked `install.sh`, so the shipping installer could regress undetected.
   Fixed: `test-meta.sh`'s real-install block now asserts `install.sh` materializes AGENTS.md +
   WORKFLOW.md, and that `--uninstall` removes them.

### GREEN: a pre-existing real file is preserved (security fix)

```
$ H=$(mktemp -d); mkdir -p "$H/.claude/dwarves-kit"
$ printf 'MY-REAL-AGENTS-FILE-DO-NOT-DESTROY\n' > "$H/.claude/dwarves-kit/AGENTS.md"
$ HOME="$H" bash install.sh
[skip] AGENTS.md at .../dwarves-kit/AGENTS.md is a real file, not a symlink; leaving it untouched
[ok] Linked AGENTS.md + WORKFLOW.md into .../dwarves-kit/
$ grep -c MY-REAL-AGENTS-FILE-DO-NOT-DESTROY "$H/.claude/dwarves-kit/AGENTS.md"   # 1 (survived)
$ [ -L "$H/.claude/dwarves-kit/WORKFLOW.md" ] && echo linked                       # WORKFLOW still linked
```

Negative-control framing: pre-fix, the `rm -f` would delete the real file and the `grep -c`
would print `0`.

### Suite (expanded)

`bash tests/test-install-contract.sh` -> PASS=3 FAIL=0. `bash tests/test-meta.sh` -> 395/395
(added: install materializes AGENTS.md + WORKFLOW.md, uninstall removes the two symlinks).

## Verdict: PASS (review-hardened)
