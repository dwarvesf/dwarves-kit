# Proof of done: cloud-session support (module `cloud`)

Type migration, class stateful, lane full. Acceptance: any kit-adopted repo can
opt into cloud-session support, neither hook does anything until its own switch
is set in a cloud session, and no path on the cloud startup surface can exit
non-zero.

Pinned to commit `f1612c0` on `feat/cloud-session-support`, tree clean. Every
number below was produced at that commit; re-running at a later commit and
getting a different count is drift, not a discrepancy.

Design + scope: `lib/cloud/SPEC.md`. Per-invariant assertion map:
`lib/cloud/docs/proof-of-done.md`.

## Green run

Command: `bash lib/cloud/tests/smoke.sh`
Exit: 0
Output: `smoke: all 118 passed` (platform line: `macOS, uname stubbed to answer Linux`)
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
(`lib/bench/SPEC`, `lib/bench` has no test).
Baseline: a pristine `origin/master` checkout fails the SAME two, so this is
pre-existing debt, not a regression. `lib/cloud` satisfies C3 and C4.
Verdict: PASS (no new offender)

Command: `shellcheck -S warning lib/cloud/*.sh lib/cloud/tests/smoke.sh hooks/cloud-*.sh bin/cloud`
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

Command: `HOME=$(mktemp -d) bash install.sh` (spine only)
Exit: 0
Output: `cloud hook entries in a spine-only settings.json: 0`; no `cloud` shim.
Verdict: PASS (negative control for the row above)

Command: `bash lib/adopt.sh --with cloud <fresh git repo>`
Exit: 0
Output: the tenant `.kit.toml` records `cloud = true`; the tenant
`.claude/settings.json` carries exactly `cloud-dash-guard.sh` and
`cloud-session-start.sh`; the SessionStart entry keeps the `startup|resume`
matcher. A repo adopted with `--with board` instead carries neither hook.
Asserted in section 8 of the suite.
Verdict: PASS

Command: assemble against a repo carrying a hostile `.kit.toml` that sets
`plugins`, `hooks_path`, `vault`, `canary_ref`, `repos` and `repo_owner`
Exit: 0
Output: none of the six reached its step; `core.hooksPath` stayed unset; the
same file's PROJECT-tier key was still honoured, and the same keys DO take
effect from the operator tier (`CLOUD_HOOKS_PATH`). Section 5b-2, 9 assertions.
Verdict: PASS

## NEGATIVE CONTROL (break -> RED -> restore)

Command: replace the `CLAUDE_CODE_REMOTE` gate in `hooks/cloud-dash-guard.sh`
with the old `[ -d "$HOME/workspace/sibling" ]` directory probe, then
`bash lib/cloud/tests/smoke.sh`
Exit: 1
Output:
```
FAIL cloud-dash-guard.sh has no '-d $HOME/...' cloud probe
FAIL cloud-dash-guard.sh checks the switch before CLAUDE_CODE_REMOTE
FAIL dash guard ON rewrote the prose dash
PASS 114  FAIL 4
```
Restore: `git checkout -- hooks/cloud-dash-guard.sh`
Verdict: PASS

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
PASS 111  FAIL 7
```
Restore: `git checkout -- lib/cloud/install-gh.sh`
Verdict: PASS (a top gate makes the portable branches unreachable, as recorded)

Command: revert the operator tier (read `plugins`, `hooks_path`, `vault`,
`canary_ref` through the project-overridable resolver), then run the suite
Exit: 1
Output:
```
FAIL the project .kit.toml did NOT arm core.hooksPath
FAIL no 'git hooks armed' line from a project-supplied hooks_path
FAIL the project .kit.toml did NOT reach the plugin installer
FAIL the project .kit.toml did NOT reach the secrets step
PASS 82  FAIL 4
```
(run at commit `80f6fa5`, before the later assertions were added)
Restore: `git checkout -- lib/cloud/provision.sh`
Verdict: PASS

Command: `bash lib/cloud/tests/smoke.sh` after every restore
Exit: 0
Output: `smoke: all 118 passed`; `git status --short` clean
Verdict: PASS

Command: the suite's own exit-code self-check (section 9) re-invokes this file
with one planted failure
Exit: 0 for the outer run
Output: the planted sub-run exits 1, the unplanted sub-run exits 0. This is the
one invariant a suite cannot assert about itself inline, and three suites in the
predecessor of this code printed FAIL lines while exiting 0.
Verdict: PASS

## Rollback

Reversible in one revert. Every artifact is additive: `lib/cloud/`,
`hooks/cloud-*.sh`, `bin/cloud`, and case-arm entries in `install.sh` /
`lib/adopt.sh` / `kit.toml` / `settings.json` / `hooks/hooks.json`. The module
defaults to `false` and both hooks are dormant until their switch is set, so a
consumer that never opts in is unaffected on either distribution path.
Reverting the commits and re-running `bash install.sh` removes both hooks from a
consumer's `settings.json` (the installer filters by the enabled set), and
`bash lib/adopt.sh --refresh <repo>` removes them from a tenant repo. No state
is written outside those files and no migration is applied.

## Not covered here

| Claim | Status |
|---|---|
| the gh release tarball downloads inside a real cloud VM | UNVERIFIED. The cloud GitHub proxy scopes release-asset requests to session-attached repos, so `cli/cli` may answer 403. apt is the fallback for exactly this and every path still exits 0. |
| `cache.agilebits.com` is reachable for the `op` install | UNVERIFIED. Not on the default network allowlist; the environment owner adds it. |
| the Linux install paths | NOT YET RUN. `.github/workflows/test.yml` gained an `ubuntu-latest` step for this suite, but the workflow is `workflow_dispatch` only and has not been dispatched for this branch. The macOS run stubs `uname`, which proves which branch is taken, never that the branch works. Dispatch the workflow to close this. |
| a plugin installed at SessionStart is usable in the SAME session | PARTIAL. `reloadSkills` is documented for skills and commands; a plugin's hooks arming mid-session is not documented and is not claimed. |
| an end-to-end run inside a real Claude Code cloud VM | NOT RUN. Every cloud-specific behavior here is exercised behind stubs or on a real Linux CI runner, neither of which is the platform. |
| `drift-check` | NOT PORTED, deferred with its five surfaces named. See `lib/cloud/SPEC.md` Scope. |
