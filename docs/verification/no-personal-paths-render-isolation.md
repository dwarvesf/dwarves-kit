# Verification -- no-personal-paths-render-isolation

`tests/test-no-personal-paths.sh`'s RENDER half isolates `KIT_CONFIG_OPERATOR`
(empty tmp dir) around its `lib/adopt.sh` call, so the test no longer reads this
machine's real operator overlay.

**Root cause.** `~/.config/dwarves-kit/kit.toml` (chezmoi-managed, this machine
only) sets `[adopt] single_source = true`, added deliberately alongside #744.
`kit_config_get_root` reads the operator overlay ahead of the kit-root default
(`lib/config/kit-config.sh`), so the RENDER half's `bash lib/adopt.sh "$T"` call
(no `--single-source`/`--no-single-source` flag) picked up the true knob, entered
single-source mode against a fresh empty `$T`, and refused (`--single-source
refuses: neither CLAUDE.md nor AGENTS.md exists`). `$T/CLAUDE.md` was never
written, so the "rendered files still point at the kit" grep failed. `#744`
itself is correct: the knob and its default (`false` in the shipped `kit.toml`)
work as documented; `tests/test-adopt.sh` already isolates the same way at line
14. This test was the one caller of `lib/adopt.sh` in the suite that had not
picked up that isolation.

## Green run
```
Command: bash tests/test-no-personal-paths.sh
Exit: 0
Verdict: PASS (3/3) -- "rendered files still point at the kit" now passes with
  KIT_CONFIG_OPERATOR pointed at a fresh empty tmp dir.

Command: RUN_ALL_TIMEOUT_SECS=600 bash tests/run-all.sh --changed
Exit: 0
Verdict: PASS -- 6 suites (test-boundary-lint, test-config-registry,
  test-kit-contract, test-meta, test-no-personal-paths, test-no-scattered-ids),
  0 skipped.
```

## Negative control
```
Command: git stash && bash tests/test-no-personal-paths.sh; git stash pop
Exit: 1 (pre-fix)
Verdict: RED -- "NOT ok - rendered files lost their kit reference", Passed: 2/3,
  reproducing the reported failure exactly. `git stash pop` restored the fix;
  re-running green confirmed restoration.
```

## Not proven
- Does not re-verify the rest of #744's behavior (adopt.single_source /
  wrap.roots knobs themselves); those were proven green in #744's own PR and are
  untouched here.
- Only exercised on this machine's operator overlay (single_source=true); the
  fix is isolation-only so the specific operator value does not matter, but no
  second machine's overlay was tried.
