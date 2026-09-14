# Proof of done: config-probe-fence

## Claim

`tests/test-config-registry.sh`'s AC9 command-autonomy probes fenced
`KIT_CONFIG_ROOT` but not `KIT_CONFIG_OPERATOR`. Two of the three probes per
key assert the shipped default and inherited the ambient operator config, so
any key an operator's real `kit.toml` overrides fails on that machine while
staying green in CI (no operator config there). `wrap.drain_staged` is the
key Han's `~/.config/dwarves-kit/kit.toml` overrides (`true` vs shipped
`false`), failing "ships as false" and "ignores a project .kit.toml".

## Fix

Point `KIT_CONFIG_OPERATOR` at `$AUTONOMY_DIR/no-operator`, a path under the
probe's own temp dir that cannot exist, on the same two probes. The third
probe (`honours the operator kit.toml`) is untouched: it sets
`KIT_CONFIG_OPERATOR` on purpose and that is the behavior under test.

## Acceptance criteria

| AC | Claim | Proof |
|---|---|---|
| AC1 | fix makes the suite green on a machine with an operator override | run table |
| AC2 | the fix does not work by disturbing Han's real config | grep of `~/.config/dwarves-kit/kit.toml` |
| AC3 | failure is caused by the missing fence, not something else | negative control: remove fence, same 2 named failures return |
| AC4 | fix does not regress the rest of the suite | `tests/test-meta.sh` |
| AC5 | fix carries no lint violations | `bin/lint --all` |

## Confirmation runs

| Run | Command | Result |
|---|---|---|
| failing-first (baseline) | `bash tests/test-config-registry.sh` pre-fix | 48/50; FAIL `wrap.drain_staged ships as false`, FAIL `wrap.drain_staged ignores a project .kit.toml` |
| green | `bash tests/test-config-registry.sh` post-fix | 50/50 |
| operator config untouched | `grep -n drain_staged ~/.config/dwarves-kit/kit.toml` | `drain_staged = true` (unchanged) |
| negative control | fence removed, `bash tests/test-config-registry.sh` | 48/50; same 2 FAILs by name |
| restore | fence restored (`git checkout -- tests/test-config-registry.sh`), re-run | 50/50 |
| meta suite | `bash tests/test-meta.sh` | 852/852 |
| lint | `bash bin/lint --all` | exit 0 |

Verdict: PASS (claim: the fixture, not the resolver or the shipped default,
was leaking Han's ambient operator config; metric: named-failure identity
across baseline and negative control; threshold: 50/50 with the fence in
place, 48/50 with the identical 2 failures without it, operator config
byte-identical throughout).

## Notes

All six keys in the AC9 table (`ship.confirm_commit`, `ship.confirm_bump`,
`ship.create_changelog`, `debug.confirm_fix`, `review.apply_findings`,
`wrap.drain_staged`) share the same probe loop, so all six are now fenced,
not only the one Han's operator config happened to override.

## Reproduce

```
bash tests/test-config-registry.sh   # 50/50
bash tests/test-meta.sh              # 852/852
bash bin/lint --all                  # exit 0
```
