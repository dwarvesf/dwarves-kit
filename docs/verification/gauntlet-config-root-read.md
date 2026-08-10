# Proof of done: root-only config read for gauntlet security-bearing keys

Change: `run-remote.sh` resolved `gauntlet.runner_host` and
`gauntlet.probe_key_ref` via `kit_config_get`, which honors a project
`.kit.toml`. A committed project toml rides inside an untrusted PR, so a PR
could redirect a gauntlet round to an arbitrary ssh host that then resolves a
1Password secret there. Fix: add `kit_config_get_root` (kit-root file only)
and switch both reads to it.

## Green run

| Field | Value |
|---|---|
| Command | `bash lib/config/kit-config.sh selftest` |
| Exit | 0 |
| Verdict | PASS |

```
ok   root-only ignores project override
ok   root-only reads kit-root value
ok   root-only falls to caller default
ok   legacy accessor still overridable
PASS kit-config selftest
```

The selftest fixture plants `[gauntlet] runner_host = "evil-host"` in the
project `.kit.toml`. `kit_config_get_root gauntlet.runner_host` returns
`local` (override ignored); `kit_config_get gauntlet.runner_host` returns
`evil-host` (legacy accessor still overridable, proving the project toml IS
read and the two accessors genuinely differ).

## Negative control (revert -> RED -> restore)

Broke `kit_config_get_root` to consult the project overlay first (simulates
the pre-fix hole), re-ran the selftest:

```
FAIL root-only ignores project override: got [evil-host] want [local]
SELFTEST FAILED   (exit 1)
```

The injected `evil-host` then wins, exactly the redirect the fix prevents.
Restored via `git checkout -- lib/config/kit-config.sh`; selftest returns to
`PASS kit-config selftest`.

## Regression check

- `bash -n tests/gauntlet/cleanroom/run-remote.sh` parses.
- `shellcheck` clean on both changed files (two SC2015 infos are on
  pre-existing selftest lines, not this change).
- `tests/test-config-registry.sh`: 17/19, identical on pristine
  `origin/master` (the 2 fails are pre-existing `bin/config` drift, unrelated
  to this change; flagged, not touched, per surgical-changes).
