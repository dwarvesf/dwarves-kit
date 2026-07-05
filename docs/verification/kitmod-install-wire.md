# Verification: kitmod-install-wire (kit-modularity SG-04, ID-277)

Flat back-compat pointer for the ship-gate (`docs/verification/.+\.md`). Canonical proof:
`docs/proof/kitmod-install-wire.md`.

## Summary

`install.sh` is layered: the SDD spine (`safety-gate`, `ship-gate`, `spec-drift-guard`,
`secrets-guard`, `commit-format`, `anti-rationalization`) wires unconditionally; every
other hook belongs to an opt-in module (`board`, `session`, `advisor`, `cosmetic`, plus the
hookless `queue`/`stats`/`quiz_gate`/`weekend_batch`/`bridge`), wired only via
`--with <a,b,c>` and recorded in a `kit.toml [modules]` manifest. A re-run is additive
(never un-wires a previously-wired hook); `--prune --with <modules>` is the explicit trim.
A reserved `team_mode = false` slot exists and is not installable.

## Green run

Command: `bash tests/test-install-modules.sh`
Exit: 0
Output: `== 21 passed, 0 failed ==`
Verdict: PASS

Command: `bash tests/test-hooks.sh`
Exit: 0
Output: `Passed: 452 / 452`
Verdict: PASS

Command: `bash tests/test-meta.sh`
Exit: 0
Output: `Passed: 679 / 679`
Verdict: PASS

Command: `bash tests/test-install-contract.sh` / `test-install-compat.sh` / `test-kit-foldin-hooks.sh` (updated for `--with`) / `test-adopt.sh` / `test-e2e.sh`
Exit: 0 / 0 / 0 / 0 / 0
Output: `3/3` / `7/7` / `49/49` / `12/12` / `20/20`
Verdict: PASS

Command: `grep -rl kit.toml hooks/` (standing anti-drift lint: no hook reads the manifest at runtime)
Exit: 1 (grep found nothing)
Output: (empty)
Verdict: PASS

## NEGATIVE CONTROL

Reverted `install.sh` to its pre-SG-04 (parent commit) content, re-ran, restored:

```
$ command cp -f /tmp/install.sh.pre install.sh   # revert to the all-hooks installer
$ HOME=$(mktemp -d) bash install.sh
$ jq -r '[.hooks[]?[]?.hooks[]?.command]|.[]' $HOME/.claude/settings.json \
    | grep -oE 'hooks/[A-Za-z0-9._-]+\.sh' | sort -u | wc -l
20                                                # RED: all 20 hooks wired, no layering

$ bash tests/test-install-modules.sh
...
== 6 passed, 15 failed ==                         # RED: 15/21 NCs fail without the layering

$ command cp -f /tmp/install.sh.new install.sh    # restore
$ git diff --stat install.sh
(empty)                                           # byte-identical to the committed version
$ bash tests/test-install-modules.sh
...
== 21 passed, 0 failed ==                         # GREEN again
```

Verdict: PASS (negative control confirms the layering is load-bearing, not a no-op: without
it, every optional hook wires unconditionally and 15 of the 21 new NCs fail).
