# Spec: ship-gate judges a vendor fork branch on the operator's own commits

Generated: 2026-10-02
Status: DRAFT
Lane: full (hooks/ship-gate.sh is a hard path; V4 narrows what satisfies the floor on one configured repo)
Depth: standard (one resolver script, a hook wiring change, one config block; every git fact below was measured on the real fork)
References: `hooks/ship-gate.sh` (`_resolve_base`, `MBASE`, `_floor_check`), `lib/classify/lane-classify.sh` `floor`, `lib/config/kit-config.sh` `kit_config_get_root`, `lib/gate/gate-policy.sh` (the "hooks never read config" pattern), `tests/test-lanes-data.sh` (ship-gate fixtures), SPEC-381 (root-only config precedent)
Source: board item "ship-gate demanded 12 full-lane overrides to push a vendor fork branch", session of 2026-10-02 in `~/dev/hermes-agent`

## Problem

`~/dev/hermes-agent` is a fork of upstream `NousResearch/hermes-agent`. The operator's local patches sit as commits on `dwarves/<release>-personal`, on top of an upstream release tag. Each patch is gated on its own in ops-toolkit `tools/hermes/patches`, with its own PR and proof.

The ship-gate diffs a pushed branch against the merge base with the remote default branch. In this repo `origin` is upstream and fetches tags only, so `origin/main` is a stale ref from 2026-08-05. The merge base is that stale commit. The gate then reads 33,636 commits and 11,737 files as "this change", including upstream's own `.github/` tree. The floor hits `full ci: .github/actionlint.yaml` and demands all 12 required full-lane gates. The session cleared the push by writing 12 override reasons in 13 seconds. That ledger is audit noise, not review.

The operator's real delta on that branch is 36 commits and 63 files.

## Grounding

Live block message (2026-10-02T02:28:57Z, `ship-gate.log`: `BLOCKED | ship-gate | v2026.9.21-personal (hard-path ci)`), command `git push dwarves dwarves/v2026.9.21-personal`:

```
BLOCKED: ship-gate. This diff touches a hard path (ci: .github/actionlint.yaml); the full lane's gates apply whatever the spec's Lane says:
(no spec found for 'v2026.9.21-personal'; a hard-path diff owes the full lane's gates with or without one)
  MISSING-GATE: think ...
  ... (12 MISSING-GATE lines: think design design-critique spec validate design-record test-plan build review docs ship reflect)
Run the missing gate(s), or log an explicit override (recorded for audit):
  bash ".../gate-ledger.sh" override v2026.9.21-personal <phase> "<reason>"
```

Measured on the real checkout (read-only):

| Fact | Value |
|---|---|
| remotes | `origin` = upstream (fetch refspec `+refs/tags/*:refs/tags/*`), `dwarves` = the mirror |
| `origin/HEAD` | unset, so `_resolve_base` picks `origin/main` (`edf0a7e`, 2026-08-05) |
| merge base with `origin/main` | `edf0a7e`: 33,636 commits, 11,737 files |
| upstream release commit under the stack | `d337b73` "chore(release): v0.21.4 (v2026.9.21)" |
| `refs/tags/v2026.9.21` | on upstream (`git ls-remote` peels it to `d337b73`), NOT fetched locally; newest local tag is `v2026.9.14` |
| `d337b73..HEAD` | 36 commits, 63 files, every committer `nntruonghan@gmail.com` |
| `lane-classify.sh floor` vs stale base | `full ci: .github/actionlint.yaml` |
| `lane-classify.sh floor` vs `d337b73` | `full ci: .github/dependabot.yml` (operator commit `e5800b3` "chore: strip Dependabot config on the mirror") |
| `git log -1 --committer=<operator> d337b73` | no hit, 0.36 s over 33,601 commits |
| same check from `HEAD~1` (a tag planted on the stack) | hits `e976e6c`, so the guard rejects it |

Two findings shape the design. First, a correct base still leaves one honest hard-path hit: the operator does change a CI file. A base fix alone still costs 12 overrides on every release rebase. Second, the right tag is often absent locally, so the base resolver must say how to fetch it, never fetch inside the hook.

Dry trace, negative control (a non-vendor branch touching `.github` must still be blocked). Operator config names `~/dev/hermes-agent` with template `dwarves/<tag>-personal`. A branch `feat/ci-tweak` in the same repo edits `.github/workflows/ci.yaml`:

```
push feat/ci-tweak
  -> vendor-base.sh: repo matches, branch "feat/ci-tweak" does not fit "dwarves/<tag>-personal" -> no output
  -> MBASE stays merge-base(HEAD, origin/main)
  -> floor: "full ci: .github/workflows/ci.yaml"
  -> check full ci-tweak --kit-lanes: 12 gaps -> exit 2 BLOCKED (unchanged from today)
  -> a "vendor-fork" override in the ledger is not consulted: V4 applies only when V3 applied
```

Second trace: same repo, branch `dwarves/v9.9-personal`, with an agent-made `git tag v9.9 HEAD~1`. Check (e) finds a commit under the tag committed by a committer of the delta. The resolver prints `not applied: tag v9.9 sits on this fork's own commits`, the stale base stays, and the push is BLOCKED as today.

## Picture

```
 git push <remote> <branch>
        |
        v
 push-refs.sh --> BRANCH, PHEAD          (unchanged, fails closed)
        |
        v
 MBASE = merge-base(PHEAD, origin default)   (today)
        |
        v
 vendor-base.sh base ROOT BRANCH PHEAD
   reads [vendor_fork] root-only (operator kit.toml / kit root, never .kit.toml)
   (a) ROOT's git common dir == configured repo's?   no -> silent, keep MBASE
   (b) BRANCH fits template, <tag> well formed?        no -> silent, keep MBASE
   (c) refs/tags/<tag> exists locally?                 no -> "fetch the upstream tag", keep MBASE
   (d) tag is an ancestor of PHEAD, != PHEAD?          no -> reason, keep MBASE
   (e) no commit under the tag committed by a
       committer of tag..PHEAD?                        no -> reason, keep MBASE
        | all yes
        v
 MBASE = tag commit; advisory + ship-gate.log VENDOR-BASE + ledger ACTION
        |
        v
 proof gate / floor / doc-projection / registry / build-ran all read MBASE
        |
        v
 floor hit on a vendor base? -> pass on full-lane gates OR one "vendor-fork" override (V4)
```

## Rules

| # | Rule | Lands in |
|---|---|---|
| V1 | New config block `[vendor_fork]` with two keys, both default empty (feature off, hook behaviour unchanged). `repo`: one path (absolute or `~/`) of a vendor-fork checkout. `branch`: a branch template holding exactly one `<tag>` placeholder, e.g. `dwarves/<tag>-personal`. Read with `kit_config_get_root` only: the operator `kit.toml` or the kit root, never a project `.kit.toml`, because the block decides which commits a ship gate ignores and a project file rides inside the PR it would judge. | `kit.toml`, `lib/config/module-registry.md` |
| V2 | New resolver `lib/gate/vendor-base.sh base <root> <branch> <head>`. Always exits 0. On a hit it prints one line `<sha> <tag> <n>` (n = commits in `tag..head`). It checks (a) to (e) from the picture in order. A miss on (a) or (b) prints nothing anywhere (the common, non-vendor case). A miss on (c), (d) or (e) prints nothing on stdout and one `vendor-base: not applied: <reason>` line on stderr; for (c) the reason names the tag and says to fetch it from upstream. `<tag>` must match `^[A-Za-z0-9][A-Za-z0-9._-]*$`. The repo match compares absolute `git rev-parse --git-common-dir` values, so a worktree of the fork counts. Check (e) builds one ERE from the escaped committer emails of `tag..head` and runs `git log -1 --committer=<ERE> <tag>`; a hit rejects the tag. All git calls pin `-c core.quotePath=false` and read local refs only: no fetch, no network. | `lib/gate/vendor-base.sh` |
| V3 | `hooks/ship-gate.sh` calls the resolver once, right after `MBASE` is computed, with the push-refs `BRANCH` and `PHEAD`. On a hit it sets `MBASE` to the tag commit, prints `[vendor-fork] judging <n> commit(s) since upstream tag <tag> (<sha12>); upstream history below it is not this change` on stderr, appends `VENDOR-BASE | <slug> | <tag> <sha12> | <n>` to `ship-gate.log`, and records `gate-ledger.sh action <slug> "vendor-base tag=<tag> sha=<sha12> commits=<n>"`. On a stderr reason it prints `[vendor-fork] <reason>` and keeps today's base. Every diff-keyed check already reads `MBASE`, so all of them judge the operator's delta. A missing resolver file fails to today's behaviour. | `hooks/ship-gate.sh` |
| V4 | Residual floor hit on a vendor base: `_floor_check` passes when the full lane's gates are all recorded (today's rule) OR the slug's run ledger holds a `GATE | vendor-fork | override` line. The block message names both options when V3 applied, and only today's option otherwise. The single override path exists only when V3 applied in the same hook run. Reason: each patch already passed its own gates in the repo that owns the patch stack, and 12 pasted reasons carry no more audit value than one that names where the patch was gated. | `hooks/ship-gate.sh` |
| V5 | Nothing else moves. `lane_gates` still switches the floor at the merge base. push-refs still fails closed. safety-gate still owns pushes to the default branch and force pushes. A repo or branch outside V1 sees no change in output or exit code. | (no change) |

Boundaries:

- One vendor-fork repo per operator config. A second fork needs a sectioned config; out of scope until it exists.
- The hook never fetches. A missing local tag degrades to today's block plus a fetch hint.
- Out of scope: incremental bases (diff against the pushed remote branch), auto-detecting forks from remote names, and the dependabot strip commit itself.

## Security

The ship gate already trusts local refs: an agent that runs `git update-ref refs/remotes/origin/main HEAD` empties today's diff. This spec does not make the gate adversary-proof; a native pre-push hook or a server-side check is the structural fix, as the push-refs comment already says. The design keeps the new path no easier to abuse than an override:

| Abuse | What stops it |
|---|---|
| Any branch declares itself a vendor fork | V1: only the operator's own `kit.toml` names the repo and template; a project `.kit.toml` is never read for `[vendor_fork]` |
| A PR adds the config to switch itself on | same: the block is root-only, and the PR cannot touch the operator file |
| Feature branch in the fork repo skips the floor | (b): only branches that fit the template get the vendor base |
| `git tag <x> HEAD` or a tag on a mid-stack commit | (d) rejects HEAD; (e) rejects any tag with a fork committer under it |
| Silent use | V3: every applied vendor base writes a log line and a ledger ACTION, visible in `lane-telemetry.sh trace` |
| Residual hard path waved through | V4: still needs one written, audited override, and only on a vendor base |

Residual risk: an agent that forges both the committer identity and a local tag can still narrow the diff. That is the same tier as forging `origin/main` today, and both the tag name and the narrowed base land in the log.

## Tasks

| ID | Task | Files | Done when |
|---|---|---|---|
| T1 | Resolver and config block | `lib/gate/vendor-base.sh`, `kit.toml`, `lib/config/module-registry.md` | `vendor-base.sh base` prints `<sha> <tag> <n>` on the vendor fixture and nothing for each (a) to (e) miss, with the stated stderr reasons |
| T2 | Hook wiring for V3 and V4 | `hooks/ship-gate.sh` | the vendor fixture passes with only operator gates or one `vendor-fork` override; every negative case below blocks with exit 2 |
| T3 | Hook cases | `tests/test-lanes-data.sh` | cases below green; each negative control fails red when its guard line is removed |
| T4 | Docs and projection | `lib/gate/README.md`, `docs/WORKFLOW.md` gate-ledger section, `docs/FEATURES.md` (regenerate) | README names the block, the five checks and the single override; registry freshness check clean |

Cases for T3 (fixture: an "upstream" history carrying `.github/workflows/ci.yml`, a tag `v1.0` on it with an upstream committer, a stale `origin/main` below the tag, then two operator commits with a clean file change on `dwarves/v1.0-personal`; operator config through `HOOK_OPERATOR`):

| Case | Expect |
|---|---|
| vendor branch, config on | exit 0, stderr has `[vendor-fork] judging 2 commit(s)`, log has `VENDOR-BASE` |
| same branch, config off | exit 2, hard path `ci` (today) |
| `feat/x` in the configured repo touching `.github` | exit 2 (negative control from Grounding) |
| config only in a committed project `.kit.toml` | exit 2 |
| tag missing locally | exit 2, stderr names the tag and the fetch hint |
| tag planted on an operator commit | exit 2, stderr `sits on this fork's own commits` |
| operator commit edits `.github/dependabot.yml` | exit 2 listing both options; after one `override <slug> vendor-fork "<reason>"`, exit 0 |
| `vendor-fork` override on a non-vendor hard-path push | still exit 2 |
| configured repo reached through a worktree | same as the vendor branch case |

## Verification

```bash
bash tests/test-lanes-data.sh
bash tests/test-hooks.sh
bash tests/test-meta.sh
bin/test-affected --base origin/master
grep -nP '\x{2013}|\x{2014}' docs/specs/SPEC-382-ship-gate-vendor-fork.md lib/gate/vendor-base.sh   # no output
```

Negative control: remove check (b), then (e), then the "V3 applied" condition in V4; the matching case goes red each time; restore with `git checkout --`.

Live check after merge (operator machine): `git fetch origin tag v2026.9.21` in `~/dev/hermes-agent`, add the `[vendor_fork]` block to the operator `kit.toml`, rerun the hook on `dwarves/v2026.9.21-personal` with a dry payload. Expect `judging 36 commit(s) since upstream tag v2026.9.21`, then a block on `.github/dependabot.yml` that one `vendor-fork` override clears.

## After state

- A push of a configured vendor fork branch is judged on the commits above its upstream tag: 36 commits, not 33,636.
- A real hard-path change in the patch stack still blocks, and clears with one audited `vendor-fork` override or the full lane's gates.
- Every other repo and branch behaves exactly as today, including a feature branch inside the fork repo.
- The operator adds to `~/.config/dwarves-kit/kit.toml`: `[vendor_fork]`, `repo = "~/dev/hermes-agent"`, `branch = "dwarves/<tag>-personal"`.

## Design

Options weighed:

| Option | Verdict |
|---|---|
| A. Merge base against an upstream remote ref | Rejected alone. Here `origin` fetches tags only, so its branch refs go stale; the measured merge base is the stale `origin/main`, the same 33,636 commits. |
| B. Root-only config naming the repo and a branch-to-tag template, base = the upstream tag | Chosen. The tag is how the operator's rebase workflow already names the base; local refs only; a branch outside the template is untouched. |
| C. One audited "vendor fork" override in place of the 12 | Chosen as V4, but only on top of B. Alone it would wave through upstream noise and real operator hard-path changes alike. |
| D. Diff against the pushed remote branch (incremental push) | Rejected. It changes the floor for every repo, and a hard path pushed once outside the hook would never be judged. |

Decision for validate (Pause-if: risk-classification change): V4 lets one override satisfy the floor where 12 were required, on one operator-configured repo only. Drop V4 and the spec still fixes the base, but each release rebase of this fork costs 12 overrides again for the dependabot strip.

## Decision Log

- 2026-10-02, spec drafted from the board item; base option B plus override option C chosen, V4 flagged for operator approval at validate.
