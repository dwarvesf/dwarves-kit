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

## Verification run

```
$ bash tests/test-install-modules.sh
== 21 passed, 0 failed ==

$ bash tests/test-hooks.sh   # 452/452
$ bash tests/test-meta.sh    # 679/679
$ bash tests/test-install-contract.sh   # 3/3
$ bash tests/test-install-compat.sh     # 7/7
$ bash tests/test-kit-foldin-hooks.sh   # 49/49 (updated for --with)
$ bash tests/test-adopt.sh              # 12/12
$ bash tests/test-e2e.sh                # 20/20
```

All green. Anti-drift lint (`grep -rl kit.toml hooks/`) confirmed empty: no hook reads the
manifest at runtime.
