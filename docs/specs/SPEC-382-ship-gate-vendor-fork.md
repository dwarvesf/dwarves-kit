# Spec: ship-gate judges a vendor fork branch on the operator's own commits

Generated: 2026-10-02
Status: DRAFT
Lane: full (hooks/ship-gate.sh is a hard path; V4 narrows what satisfies the floor on one configured repo)
Depth: standard (one resolver script, a hook wiring change, one config block; every git fact below was measured on the real fork)
References: `hooks/ship-gate.sh` (`_resolve_base`, `MBASE`, `_floor_check`, the validate-by-size ledger read), `lib/classify/lane-classify.sh` `floor`, `lib/config/kit-config.sh` `kit_config_get_root`, `lib/gate/gate-policy.sh` (the "hooks never read config" pattern), `tests/test-lanes-data.sh` (ship-gate fixtures), SPEC-381 (root-only config precedent)
Source: board item "ship-gate demanded 12 full-lane overrides to push a vendor fork branch", session of 2026-10-02 in `~/dev/hermes-agent`; validate round 1 folded in

## Problem

`~/dev/hermes-agent` is a fork of upstream `NousResearch/hermes-agent`. The operator's local patches sit as commits on `dwarves/<release>-personal`, on top of an upstream release tag. Each patch is gated on its own in ops-toolkit `tools/hermes/patches`, with its own PR and proof.

The ship-gate diffs a pushed branch against the merge base with the remote default branch. Upstream cuts its release tags on a line that is not on `main`. The merge base of the fork branch and `origin/main` is therefore `edf0a7e` (2026-08-05), even after a fresh fetch. The gate reads 33,636 commits and 11,737 files as "this change", including upstream's own `.github/` tree. The floor hits `full ci: .github/actionlint.yaml` and demands all 12 required full-lane gates. The session cleared the push by writing 12 override reasons in 13 seconds. That ledger is audit noise, not review.

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

Measured on the real checkout (git 2.55.0):

| Fact | Value |
|---|---|
| remotes | `origin` = upstream (fetch refspec `+refs/tags/*:refs/tags/*`), `dwarves` = the mirror |
| `origin/HEAD` | unset, so `_resolve_base` picks `origin/main` |
| `origin/main` after `git fetch origin main` | `edf0a7e` (2026-08-05); merge base with the fork branch is still `edf0a7e`: 33,636 commits, `.github/` in the diff |
| upstream release commit under the stack | `d337b73` "chore(release): v0.21.4 (v2026.9.21)", NOT an ancestor of `origin/main` |
| `refs/tags/v2026.9.21` | ANNOTATED: tag object `dd2c35f`, peels to commit `d337b73`. Absent locally at block time (newest local tag was `v2026.9.14`); present after a fetch |
| `d337b73..HEAD` | 36 commits, 63 files, every committer `nntruonghan@gmail.com` |
| `lane-classify.sh floor` vs `edf0a7e` | `full ci: .github/actionlint.yaml` |
| `lane-classify.sh floor` vs `d337b73` | `full ci: .github/dependabot.yml` (operator commit `e5800b3` "chore: strip Dependabot config on the mirror") |
| `git log -1 -E --committer=<operator ERE> d337b73` | no hit, 0.36 s over 33,601 commits |
| same check from `HEAD~1` (a tag planted on the stack) | hits `e976e6c` |
| `git log --committer='a\|b'` without `-E` | the alternation matches nothing, so `-E` is required |

Three findings shape the design. First, no upstream branch ref contains the release tag, so a merge base against any upstream remote ref (Option A) reproduces the 33,636-commit diff. Second, a correct base still leaves one honest hard-path hit: the operator does change a CI file. A base fix alone still costs 12 overrides on every release rebase. Third, the right tag is often absent locally, so the resolver must say how to fetch it, never fetch inside the hook.

Dry trace, negative control (a non-vendor branch touching `.github` must still be blocked). Operator config names `~/dev/hermes-agent`, template `dwarves/<tag>-personal`, committers `nntruonghan@gmail.com`. A branch `feat/ci-tweak` in the same repo edits `.github/workflows/ci.yaml`:

```
push feat/ci-tweak
  -> vendor-base.sh: repo matches, "feat/ci-tweak" does not fit "dwarves/<tag>-personal" -> no output
  -> MBASE stays merge-base(HEAD, origin/main)
  -> floor: "full ci: .github/workflows/ci.yaml"
  -> check full ci-tweak --kit-lanes: 12 gaps -> exit 2 BLOCKED (unchanged from today)
  -> a "vendor-fork" override in the ledger is not consulted: V4 applies only when V3 applied
```

Second trace, the planted tag with a foreign top commit. Branch `dwarves/v9.9-personal`. The agent commits the top commit as `noreply@github.com` and runs `git tag v9.9 HEAD~1`. The identity set comes from config, never from the delta. Check (e) runs `git log -1 -E --committer='nntruonghan@gmail\.com' v9.9^{commit}` and hits the operator commits under the tag. The resolver prints `not applied: tag v9.9 sits on commits by a configured fork committer`. MBASE stays, and the push is BLOCKED as today.

## Picture

```
 git push <remote> <branch>
        |
        v
 push-refs.sh --> BRANCH, PHEAD          (unchanged, fails closed)
        |
        v
 MBASE = merge-base(PHEAD, origin default)   (today)
        |  MBASE empty? -> resolver not called, today's fail-open stays
        v
 vendor-base.sh base ROOT BRANCH PHEAD
   reads [vendor_fork] root-only (operator kit.toml / kit root, never .kit.toml)
   (a) config complete and well formed; ROOT's common dir == repo's?  no -> silent
   (b) BRANCH fits the template literally; <tag> well formed?       no -> silent
   (c) refs/tags/<tag>^{commit} resolves locally?                   no -> "fetch the upstream tag"
   (d) tag commit is an ancestor of PHEAD and != PHEAD?             no -> reason
   (e) no commit under the tag committed by a configured committer? no -> reason
        | all yes: one line "<sha> <tag> <n>"
        v
 hook validates the line (3 fields, 40-hex, commit exists)  bad -> keep MBASE
        |
        v
 MBASE = tag commit; advisory + ship-gate.log VENDOR-BASE + ledger ACTION (once per head)
        |
        v
 proof gate / floor / doc-projection / registry / build-ran all read MBASE
        |
        v
 floor hit of kind ci on a vendor base? -> full-lane gates OR one covering "vendor-fork" override (V4)
 any other kind                         -> full-lane gates only (today)
```

## Rules

| # | Rule | Lands in |
|---|---|---|
| V1 | New config block `[vendor_fork]` with three keys, all default empty (feature off, hook behaviour unchanged). `repo`: one path, absolute or `~/`-prefixed, of a vendor-fork checkout. `branch`: a branch template holding exactly one `<tag>` placeholder, e.g. `dwarves/<tag>-personal`. `committers`: space-separated emails of the operator identities that commit on the fork. Read with `kit_config_get_root` only: the operator `kit.toml` or the kit root, never a project `.kit.toml`, because the block decides which commits a ship gate ignores and a project file rides inside the PR it would judge. An empty or malformed key is a silent no-op. | `kit.toml`, `lib/config/module-registry.md` |
| V2 | New resolver `lib/gate/vendor-base.sh base <root> <branch> <head>`, with a `# kit-verb:` header. Always exits 0. On a hit it prints exactly one line `<sha> <tag> <n>`: the 40-hex peeled tag commit, the tag, and the commit count of `<sha>..<head>`. It builds the line in a variable and prints it only after every check passes, so it never leaves a partial line. Checks (a) to (e), in order, are specified below. A miss on (a) or (b) prints nothing anywhere. A miss on (c), (d) or (e) prints nothing on stdout and one `vendor-base: not applied: <reason>` line on stderr. Any non-zero git exit inside (c), (d) or (e) is a miss, never a hit. Every git call pins `-c core.quotePath=false` and reads local refs only: no fetch, no network. | `lib/gate/vendor-base.sh` |
| V3 | `hooks/ship-gate.sh` calls the resolver once, right after `MBASE` is computed, with the push-refs `BRANCH` and `PHEAD`, only when `MBASE` is non-empty. It accepts the stdout line only when it has exactly three fields, the first is 40 hex characters, and `git cat-file -e <sha>^{commit}` succeeds; anything else keeps today's base. On an accepted hit it sets `MBASE` to the sha and prints `[vendor-fork] judging <n> commit(s) since upstream tag <tag> (<sha12>); upstream history below it is not this change` on stderr. It appends `VENDOR-BASE \| <slug> \| <tag> <sha12> \| <n>` to `ship-gate.log`. It records `gate-ledger.sh action <slug> "vendor-base tag=<tag> sha=<sha12> head=<head12> commits=<n>"` once per head sha, skipping the write when that exact line already exists. On a stderr reason it prints `[vendor-fork] <reason>` and keeps today's base. A missing resolver file means today's behaviour. | `hooks/ship-gate.sh` |
| V4 | (Operator approval required at validate.) Residual floor hit on a vendor base, kind `ci` only. `_floor_check` passes when the full lane's gates are all recorded (today's rule) OR when a covering `vendor-fork` override exists. The block message prints the exact command with the reason prefix filled in: `override <slug> vendor-fork "hit=ci:<path> head=<head12> <reason>"`. The hook reads the ledger by fields (awk split on ` \| `, `$2=="GATE" && $3=="vendor-fork" && $4=="override"`), the same way as the existing validate-by-size read. A recorded override COVERS the current push when three things hold. Its `hit=` path equals the current first hit. Its `head=` commit is an ancestor of, or equal to, `PHEAD`. `lane-classify.sh floor <root> <recorded head> <PHEAD>` prints nothing, so nothing new hit a hard path since the override. Any other floor kind (secrets, auth, migration, data-loss, submodule, extra) and every push where V3 did not apply ignore the override. | `hooks/ship-gate.sh` |
| V5 | The floor still reads `[gate] lane_gates` at `MBASE`. On a vendor base that is the upstream tag, where the fork has no `.kit.toml`, so the operator layer decides. push-refs still fails closed. safety-gate still owns pushes to the default branch and force pushes. A repo or branch outside V1 sees no change in output or exit code. | (no change) |

Resolver checks (V2):

| Check | Exact rule |
|---|---|
| (a) config and repo | All three keys non-empty. `repo` expands a leading `~/` with `$HOME` by string substitution, never `eval`; a path that does not exist is a miss. Both sides resolve with `git -C <dir> rev-parse --path-format=absolute --git-common-dir`, then `cd <dir> && pwd -P`; the two physical paths must be equal. So a worktree of the fork counts, and `/tmp` vs `/private/tmp` compare equal. Each committer must match `^[^[:space:]@]+@[^[:space:]@]+$`, else miss. |
| (b) branch | The template holds exactly one literal `<tag>`. The text before it (prefix) or after it (suffix) is non-empty. The branch must start with the prefix and end with the suffix by literal string comparison (bash `${var#"$prefix"}` with quoting, so `.`, `*` and `[` stay literal). The captured `<tag>` is non-empty and matches `^[A-Za-z0-9][A-Za-z0-9._-]*$`. |
| (c) tag | `git rev-parse --verify -q "refs/tags/<tag>^{commit}"` gives the sha. A lightweight or an annotated tag both peel to a commit. A failure prints `tag <tag> is not in this clone; fetch it from upstream (git fetch <upstream-remote> tag <tag>)`. |
| (d) ancestry | `git merge-base --is-ancestor <sha> <head>` exits 0 and `<sha>` differs from the peeled head. |
| (e) identity | One ERE from the configured committers, each with regex characters escaped, joined with `\|`. `git log -1 -E --format=%H --committer=<ERE> <sha>` must print nothing with exit 0. A hit prints `tag <tag> sits on commits by a configured fork committer`. |

Boundaries:

- One vendor-fork repo per operator config. A second fork needs a sectioned config; out of scope until it exists.
- The hook never fetches. A missing local tag degrades to today's block plus a fetch hint.
- Out of scope: incremental bases (diff against the pushed remote branch), auto-detecting forks from remote names, and the dependabot strip commit itself.

## Security

The ship gate already trusts local refs: an agent that runs `git update-ref refs/remotes/origin/main HEAD` empties today's diff. This spec does not make the gate adversary-proof; a native pre-push hook or a server-side check is the structural fix, as the push-refs comment already says. The design keeps the new path no easier to abuse than an override:

| Abuse | What stops it |
|---|---|
| Any branch declares itself a vendor fork | V1: only the operator's own `kit.toml` names the repo, template and committers; a project `.kit.toml` is never read for `[vendor_fork]` |
| A PR adds the config to switch itself on | same: the block is root-only, and the PR cannot touch the operator file |
| Feature branch in the fork repo skips the floor | (b): only branches that fit the template get the vendor base |
| `git tag <x> HEAD` | (d) rejects a tag equal to the head |
| Tag planted mid-stack, with or without a foreign top commit | (e) takes the identity set from config, so any operator commit under the tag rejects it |
| A web-UI or bot commit in the stack | no effect: the delta's committers are never read, so a stray identity neither rejects a good tag nor admits a bad one |
| A forged resolver line | V3 validates field count, sha shape and commit existence |
| Silent use | V3: every applied vendor base writes a log line and a ledger ACTION, visible in `lane-telemetry.sh trace` |
| Residual hard path waved through | V4: `ci` kind only, one written override naming the hit and head, re-checked on every re-push |

Residual risk: an agent that rewrites the operator commits under a forged committer and plants a local tag can still narrow the diff. That is the same tier as forging `origin/main` today, and the tag name and narrowed base land in the log.

## Failure modes

| Condition | Behaviour |
|---|---|
| `[vendor_fork]` absent, partial or malformed | silent no-op, today's gate |
| configured `repo` path missing | (a) miss, silent, today's gate |
| `MBASE` empty (no origin default resolved) | resolver not called; today's fail-open stays |
| resolver file missing or crashes | stdout empty or invalid, today's base |
| tag absent locally | today's block plus the fetch hint |
| tag not an ancestor, or equal to head | today's block plus the reason |
| tag sits on configured-committer commits | today's block plus the reason |
| garbage on resolver stdout | V3 validation rejects it, today's base |
| git error inside (c) to (e) | miss, today's base |
| non-`ci` floor hit on a vendor base | full-lane gates required, override ignored |
| re-push adds a new hard-path change after a V4 override | the coverage floor run hits, block again |
| hook timeout | the hook fails open (unchanged); (e) costs about 0.4 s on 33,601 commits |

## Tasks

| ID | Task | Files | Depends on | Done when |
|---|---|---|---|---|
| T1 | Resolver and config block | `lib/gate/vendor-base.sh`, `kit.toml`, `lib/config/module-registry.md` | none | `vendor-base.sh base` prints `<sha> <tag> <n>` on the vendor fixture and nothing on stdout for each (a) to (e) miss, with the stated stderr reasons |
| T2a | Hook wiring for V3 (base fix, ships without V4) | `hooks/ship-gate.sh` | T1 | the vendor fixture with a clean operator delta exits 0; every negative case below exits 2 |
| T2b | Hook wiring for V4 (the covering override) | `hooks/ship-gate.sh` | T2a, operator approval | the V4 rows below pass; dropping T2b leaves T2a's cases green |
| T3 | Hook cases | `tests/test-lanes-data.sh` | T1, T2a (T2b for V4 rows) | cases below green; each negative control turns red when its guard is removed |
| T4 | Docs and projection | `lib/gate/README.md`, `docs/WORKFLOW.md` gate-ledger section, `docs/FEATURES.md` (regenerate) | T1 to T3 | README names the block, the five checks and the single override; registry freshness check clean |

T3 fixture: an "upstream" history carrying `.github/workflows/ci.yml`, committed by an upstream identity. An ANNOTATED tag `v1.0` sits on it. An `origin` remote is added and `git update-ref refs/remotes/origin/main` points below the tag, off the tag's line. Two operator commits (committer `op@example.com`) with a clean file change sit on `dwarves/v1.0-personal`. The operator config arrives through `HOOK_OPERATOR`.

| Case | Expect |
|---|---|
| vendor branch, config on | exit 0, stderr has `[vendor-fork] judging 2 commit(s)`, log has `VENDOR-BASE`, one ledger ACTION |
| same push run twice | still exactly one ledger ACTION for that head |
| same branch, config off | exit 2, hard path `ci` (today) |
| `feat/x` in the configured repo touching `.github` | exit 2 (negative control from Grounding) |
| config only in a committed project `.kit.toml` | exit 2 |
| (a) miss: configured repo is another path | exit 2, no `[vendor-fork]` line |
| configured repo path does not exist | exit 2, no `[vendor-fork]` line |
| repo configured as `/tmp/...`, hook sees `/private/tmp/...` | same as the vendor branch case |
| configured repo reached through a worktree | same as the vendor branch case |
| malformed template (no `<tag>`, two `<tag>`, empty prefix and suffix) | exit 2, silent |
| template with regex characters (`dwarves/<tag>.personal`) vs branch `dwarves/v1.0xpersonal` | exit 2, silent |
| malformed tag captured (`dwarves/-x-personal`) | exit 2, silent |
| tag missing locally | exit 2, stderr names the tag and the fetch hint |
| tag equal to HEAD | exit 2, reason |
| tag not an ancestor of HEAD | exit 2, reason |
| tag planted on an operator commit | exit 2, `sits on commits by a configured fork committer` |
| tag planted on `HEAD~1`, top commit by a foreign committer | exit 2, same reason |
| mixed committers in the stack (one `noreply@github.com` commit), real tag | exit 0 (the stray identity is ignored) |
| `MBASE` empty: no origin remote default | exit 0 as today, resolver not called |
| resolver replaced by a stub printing garbage | today's base, exit 2 on the `.github` fixture |
| (V4) operator commit edits `.github/dependabot.yml` | exit 2 listing both options; after the printed `vendor-fork` override, exit 0 |
| (V4) a new hard-path commit after the override | exit 2 again |
| (V4) a `secrets`-kind hit on a vendor base with a `vendor-fork` override | exit 2 |
| (V4) a `vendor-fork` override on a non-vendor hard-path push | exit 2 |

## Verification

```bash
bash tests/test-lanes-data.sh
bash tests/test-hooks.sh
bash tests/test-meta.sh
bin/test-affected --base origin/master
grep -nP '\x{2013}|\x{2014}' docs/specs/SPEC-382-ship-gate-vendor-fork.md lib/gate/vendor-base.sh   # no output
```

Negative controls, each restored with `git checkout --` after it goes red:

| Mutation | Case that turns red |
|---|---|
| `kit_config_get_root` -> `kit_config_get` in the resolver (it sets `KIT_PROJECT_ROOT=$ROOT`) | config only in a project `.kit.toml` |
| drop check (b) | `feat/x` touching `.github` |
| drop check (d) | tag equal to HEAD |
| check (e) reads the delta's committers instead of config | tag on `HEAD~1` with a foreign top commit; mixed committers |
| drop `-E` from (e) | tag planted on an operator commit |
| drop the V3 stdout validation | garbage resolver output |
| drop the "V3 applied" condition in V4 | override on a non-vendor push |
| drop the `ci`-only condition in V4 | `secrets`-kind hit |
| drop the coverage floor run in V4 | new hard-path commit after the override |

Live check after merge (operator machine): `git fetch origin tag v2026.9.21` in `~/dev/hermes-agent`. Add the `[vendor_fork]` block to the operator `kit.toml`. Rerun the hook on `dwarves/v2026.9.21-personal` with a dry payload. Expect `judging 36 commit(s) since upstream tag v2026.9.21`, then a block on `.github/dependabot.yml` that one `vendor-fork` override clears (with T2b).

## After state

- A push of a configured vendor fork branch is judged on the commits above its upstream tag: 36 commits, not 33,636.
- A real hard-path change in the patch stack still blocks. A `ci` hit clears with one covering `vendor-fork` override (if V4 is approved) or the full lane's gates. Every other kind needs the full lane's gates.
- Every other repo and branch behaves exactly as today, including a feature branch inside the fork repo.
- The operator adds to `~/.config/dwarves-kit/kit.toml`: `[vendor_fork]`, `repo = "~/dev/hermes-agent"`, `branch = "dwarves/<tag>-personal"`, `committers = "nntruonghan@gmail.com"`.

## Design

Diagram: see ## Picture.

Options weighed:

| Option | Verdict |
|---|---|
| A. Merge base against an upstream remote ref | Rejected. Measured live after `git fetch origin main`: the merge base is still `edf0a7e`, 33,636 commits, `.github` in the diff. The release tag `d337b73` is not on upstream `main`. |
| B. Root-only config naming the repo, a branch-to-tag template and the fork's committers; base = the peeled upstream tag | Chosen (V1 to V3). The tag is how the operator's rebase workflow already names the base. Local refs only. A branch outside the template is untouched. |
| C. One audited "vendor fork" override in place of the 12 | Chosen as V4, scoped to `ci` hits on top of B, behind operator approval. Alone it would wave through upstream noise and real operator hard-path changes alike. |
| D. Diff against the pushed remote branch (incremental push) | Rejected. It changes the floor for every repo, and a hard path pushed once outside the hook would never be judged. |
| E. Identity set from the delta's own committers | Rejected in validate round 1. A foreign top commit swaps the set and admits a planted tag, and a stray web-UI commit rejects every real tag. |

Decision for validate (Pause-if: risk-classification change): V4 lets one override satisfy the floor where 12 were required, for `ci` hits on one operator-configured repo only. T2b is its own task. Drop it and T2a still fixes the base, but each release rebase of this fork costs 12 overrides again for the dependabot strip.

## Decision Log

- 2026-10-02, spec drafted from the board item; base option B plus override option C chosen, V4 flagged for operator approval at validate.
- 2026-10-02, validate round 1 (NEEDS REVISION, 1 critical): check (e) now reads a root-only `committers` key, never the delta. Folded in: tag peeling, physical-path repo match, `-E`, resolver output validation, literal template match, V4 split into T2b and scoped to `ci` with a covering-override rule, empty-MBASE behaviour, the live Option A measurement, a failure-mode table, more negative controls, task dependencies.
