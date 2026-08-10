# Proof of done: cloud-session support (module `cloud`)

Type migration, class stateful, lane full. Acceptance: any kit-adopted repo can
opt into cloud-session support, the two hooks are inert outside a cloud VM, and
no path on the cloud startup surface can exit non-zero.

Design + scope: `lib/cloud/SPEC.md`. Per-invariant assertion map:
`lib/cloud/docs/proof-of-done.md`.

## Green run

Command: `bash lib/cloud/tests/smoke.sh`
Exit: 0
Output: `smoke: all 79 passed` (platform line: `macOS, uname stubbed to answer Linux`)
Verdict: PASS

Command: `bash tests/test-meta.sh`
Exit: 0
Output: `Passed: 799 / 799` / `All meta tests passed.`
Verdict: PASS

Command: `bash tests/test-hooks.sh`
Exit: 0
Output: `Passed: 492 / 492` / `All tests passed.`
Verdict: PASS

Command: `bash tests/test-bin-forwarders.sh`
Exit: 0
Output: `test-bin-forwarders: all 33 passed, 0 skipped`
Verdict: PASS

Command: `bash tests/test-install-modules.sh`
Exit: 0
Output: `== 37 passed, 0 failed ==`
Verdict: PASS

Command: `bash tests/test-adopt.sh`
Exit: 0
Output: `PASS=21 FAIL=0`
Verdict: PASS

Command: `bash tests/test-config-registry.sh`
Exit: 0
Output: `=== 19/19 passed ===`
Verdict: PASS

Command: `bash tests/test-kit-contract.sh`
Exit: 1
Output: `=== kit-contract: 23 passed, 2 failed ===`; both offenders are `lib/bench`
(`lib/bench/SPEC`, `lib/bench` has no test). The same two fail on a pristine
`origin/master` checkout, so this is pre-existing debt, not a regression.
Baseline: `origin/master` -> same 2 offenders.
Verdict: PASS (no new offender; `lib/cloud` satisfies C3 and C4)

Command: `shellcheck -S warning lib/cloud/*.sh hooks/cloud-*.sh bin/cloud lib/cloud/tests/smoke.sh`
Exit: 0
Output: (empty)
Verdict: PASS

## The real flow, exercised on a throwaway copy

Command: `HOME=$(mktemp -d) bash install.sh --with cloud`
Exit: 0
Output: both hooks materialized executable under
`$HOME/.claude/dwarves-kit/hooks/`; `settings.json` carries
`hooks/cloud-session-start.sh` and `hooks/cloud-dash-guard.sh`;
`$HOME/.local/bin/cloud` is present and prints the dispatcher usage.
Verdict: PASS

Command: `bash lib/adopt.sh --with cloud <fresh git repo>`
Exit: 0
Output: the tenant `.kit.toml` records `cloud = true`; the tenant
`.claude/settings.json` carries exactly `cloud-dash-guard.sh` and
`cloud-session-start.sh`; the SessionStart entry keeps the `startup|resume`
matcher. Asserted in section 8 of the suite.
Verdict: PASS

## NEGATIVE CONTROL (break -> RED -> restore)

Command: replace the `CLAUDE_CODE_REMOTE` gate in `hooks/cloud-dash-guard.sh`
with the old `[ -d "$HOME/workspace/sibling" ]` directory probe, then
`bash lib/cloud/tests/smoke.sh`
Exit: 1
Output:
```
FAIL cloud-dash-guard.sh has no '-d $HOME/...' cloud probe
FAIL dash guard ON rewrote the prose dash
PASS 77  FAIL 2
```
Restore: `git checkout -- hooks/cloud-dash-guard.sh`
Verdict: PASS (the gate assertion and the behavior assertion both go red)

Command: hoist the Linux gate in `lib/cloud/install-gh.sh` back to the top of
the file (the exact regression the placement rule exists to prevent), then
`bash lib/cloud/tests/smoke.sh`
Exit: 1
Output:
```
FAIL install-gh.sh dry-run branch precedes its Linux gate
FAIL url amd64
FAIL url arm64
FAIL url without a leading v
FAIL gate: says it skipped
FAIL bin/cloud install-gh reaches the installer
PASS 73  FAIL 6
```
Restore: `git checkout -- lib/cloud/install-gh.sh`
Verdict: PASS (a top gate makes the portable branches unreachable, exactly as
recorded)

Command: `bash lib/cloud/tests/smoke.sh` after both restores
Exit: 0
Output: `smoke: all 79 passed`; `git status --short` clean
Verdict: PASS

Command: spine-only install must wire nothing
(`HOME=$(mktemp -d) bash install.sh`)
Exit: 0
Output: 0 `hooks/cloud-` entries in `settings.json`; no `cloud` shim on PATH.
Verdict: PASS

## Rollback

Reversible in one revert. Every artifact is additive: `lib/cloud/`,
`hooks/cloud-*.sh`, `bin/cloud`, and case-arm entries in `install.sh` /
`lib/adopt.sh` / `kit.toml` / `settings.json` / `hooks/hooks.json`. The module
defaults to `false`, so a consumer that never runs `--with cloud` is unaffected
either way. Reverting the commit and re-running `bash install.sh` removes both
hooks from a consumer's `settings.json` (the installer filters by the enabled
set), and re-running `bash lib/adopt.sh --refresh <repo>` removes them from a
tenant repo. No state is written outside those files, no migration is applied,
and nothing outside a `CLAUDE_CODE_REMOTE=true` Linux session ever executes.

## Not covered here

| Claim | Status |
|---|---|
| the gh release tarball downloads inside a real cloud VM | UNVERIFIED. The cloud GitHub proxy scopes release-asset requests to session-attached repos, so `cli/cli` may answer 403. apt is the fallback for exactly this and every path still exits 0. |
| `cache.agilebits.com` is reachable for the `op` install | UNVERIFIED. Not on the default network allowlist; the environment owner adds it. |
| the Linux install paths | Proved only by the `ubuntu-latest` CI leg wired in `.github/workflows/test.yml`. The macOS run stubs `uname`, which proves which branch is taken, never that the branch works. |
| a plugin installed at SessionStart is usable in the SAME session | PARTIAL. `reloadSkills` is documented for skills and commands; a plugin's hooks arming mid-session is not documented and is not claimed. |
| `drift-check` | NOT PORTED, deferred. Four of its five surfaces audit operator curation. See `lib/cloud/SPEC.md` Scope. |
