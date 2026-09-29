# Spec: harvest sweep, phase 2 (build and merge from the sweep)

Generated: 2026-09-29
Status: DRAFT
Lane: full
Type: spec-feature
File: `docs/specs/SPEC-358-harvest-sweep-build.md`
Phase 1: `docs/specs/SPEC-357-harvest-sweep.md` (the report-only sweep this phase extends)
Entry condition: SPEC-357 has shipped and its sweep has run clean on the Mini for one week (every scheduled run rc 0, clean lint, heartbeat green, no hand fix to its state), AND the reports were read: during that week the operator acted on at least one candidate or learning (at least one sweep-ledger row marked `flushed:`, or one reported candidate built by hand), per SPEC-357 DEC-81.
References: `docs/specs/SPEC-357-harvest-sweep.md` (stage 1, the cursor, the ledgers, the report, the launcher), `commands/wrap.md` (step 7b build rules, step 10 landing and full-lane draft rules), `hooks/ship-gate.sh` (reads a PreToolUse payload with `tool_input.command` and `cwd`; resolves its libs from `CLAUDE_PLUGIN_ROOT`, falling back to `$HOME/.claude/dwarves-kit` at lines 80, 85, 193, and 270; exits 0 when `gate-ledger.sh` is missing at line 271).

## Problem

SPEC-357 reports candidates with a precedent result and a lane, and builds none. The operator's autonomy decision (DEC-1) wants in-lane candidates built and merged when green, and full-lane candidates opened as DRAFT PRs for review, without the operator in the loop. Validation round 2 on the combined spec found two criticals and several warnings in exactly this part, so it was split out to land after phase 1 has proven itself.

## Design summary

- Stage 2: one headless Claude session per run with NO GitHub or push capability. It builds and commits only in worktrees that code created, and writes advisory notes.
- Stage 3: plain code holding the launcher's token. It iterates only the worktrees this run created, gates each diff (denylist, fixed-text lane, ship-gate), pushes, opens the PR itself (DRAFT for full lane or a denylist hit), waits for checks, and merges only a non-draft PR it opened this run through `wrap merge --apply --pr`.
- Branch protection on every build repo's default branch is an install prerequisite.

The text below is carried verbatim from the combined spec at validation round 1 (commit `a71f098f`), so it still names stage-1 pieces that SPEC-357 now owns and task numbers from that version. Rewriting it against SPEC-357 as shipped is the first task of this phase, and that rewrite must also resolve every item in `## Open from validation round 2`.

## Distill-half contract (carried verbatim)

### Distill-half contract

`commands/wrap.md`'s distill half assumes a live session on a branch. T8 extracts step 7b's build rules and step 10's landing steps and full-lane path into `docs/patterns/distill-build-and-land.md`. Wrap cites it, and the sweep prompt cites it by absolute path. The sweep substitutes as follows:

| wrap assumes | the sweep uses |
|---|---|
| the pre-step-0 scan reads the live session | the manifest's `candidates` are the scan list |
| step 7a derives a rid from the branch, refusing off-branch | 7a is a structural skip; the run record uses rid `harvest-sweep-<run-id>`, and each build keeps its own branch rid |
| relative paths (`bin/wrap`, `lib/...`) from the kit checkout | absolute `<kit>/bin/...` and `<kit>/lib/...`, rendered into the prompt |
| the builder runs `wrap start` itself | the model calls `harvest_sweep.py --worktree`, which runs `wrap start` and disables push on that worktree |
| step 10 runs only under `follow` mode | in-lane candidates always build; there is no follow switch |
| the builder pushes, opens the PR, and merges | stage 2 cannot push or reach GitHub; stage 3 code pushes, opens, and merges |
| `wrap.before` and `wrap.after` seams | only `wrap.after` runs (a flush reads output, not a working tree); unresolved seam: learnings stay queued and the report carries a `STATE` row |
| `/kit:*` slash commands | none; project-only sources may not load the kit plugin |

## Stage 2 and stage 3 (carried verbatim)

**Stage 2 spawn.** Only when the manifest has a candidate, an `ask`, or at least `HARVEST_SWEEP_MIN_LEARNINGS` (default 5) learnings added since `last_spawn`. A learning-only spawn is suppressed while `seam.json` says `resolved: false` for the configured `wrap.after` value, until that value changes or 24h pass. Otherwise the run reports `NOTHING: no candidates` and exits 0.

```
cd $HARVEST_STATE_DIR/sweep/runs/<run-id>
env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u SSH_AUTH_SOCK \
  GH_CONFIG_DIR=<empty dir> GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=false \
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0= \
  HARVEST_SWEEP_CHILD=1 CLAUDE_PLUGIN_ROOT=<kit> \
  claude -p "$(render prompt)" \
  --model "${HARVEST_SWEEP_MODEL:-sonnet}" --max-turns "${HARVEST_SWEEP_MAX_TURNS:-200}" \
  --setting-sources project --settings $HARVEST_STATE_DIR/sweep/settings.json \
  --permission-mode bypassPermissions
```

- Never `--bare` (it skips keychain reads and breaks auth). `HARVEST_SWEEP_DISTILL_CMD` overrides the whole command for tests.
- `settings.json` is rendered by `install` from `hooks/harvest-sweep-settings.json.tmpl` with the kit's absolute path. It sets `env.CLAUDE_PLUGIN_ROOT` so every hook and stage 3's own ship-gate call resolve the same kit checkout the sweep runs from. Without it, the hooks fall back to `$HOME/.claude/dwarves-kit`, which may be another install (DEC-34). It wires the enforcement hooks (safety-gate, ship-gate, push-to-main blocker, commit-format, secrets-guard) and no PreCompact, SessionEnd, or Stop harvest hook. It denies `Bash(gh *)`, `Bash(git push*)`, `Bash(*wrap merge*)`, `Bash(*wrap land*)`, and `Bash(*wrap start*)` as defense in depth; the env and the per-worktree push URL are the guarantee, not these rules (DEC-38).
- The prompt calls kit scripts by absolute path and never a `/kit:*` slash command (DEC-11).
- harvest_sweep.py spawns it with `start_new_session=True` and, at `distill_timeout_minutes`, sends `os.killpg` to the whole group.

**The worktree helper** (`harvest_sweep.py --worktree <repo> <type> <slug> --pattern <p>`, the only way stage 2 gets a worktree). It refuses unless `<repo>` is in `harvest.build_repos`, `<type>` is one of feat, fix, refactor, docs, test, chore, and `<slug>` matches `^[a-z0-9-]{1,40}$`. It runs `bin/wrap start <repo> <type>/<slug>`, sets `git config --worktree remote.origin.pushurl no-push` in the new worktree (install enabled `extensions.worktreeConfig` in each build repo, so the main checkout's push URL is untouched), reads the value back and refuses on a mismatch, appends a `created` line to `runs/<run-id>/worktrees.jsonl`, and prints the path.

**The distill prompt** (`hooks/harvest-sweep-prompt.md`) cites `docs/patterns/distill-build-and-land.md` and the contract table above. It does not restate them.

- Per candidate: `precedent find --surface inventory --json`, then `lane-classify.sh classify`, then ENHANCE, NEW, or NOTE with the code-home-wins rule.
- Build a candidate only in a home repo in `build_repos`, only through the worktree helper; build, verify, and commit there. Never push and never call `gh`; stage 3 does both. A full-lane candidate runs the full-lane spec and build steps in its worktree and stops at the commits.
- A home repo not in `build_repos`: nothing is built; the candidate is `REPORTED` with `reported: repo not in harvest.build_repos`.
- `max_builds_per_run` caps worktrees of every lane (the helper refuses past it). The rest are `REPORTED` with `reported: sweep build cap` and get no blocking entry, so the next run picks them up.
- As each candidate closes, append an advisory `{pattern, run_id, outcome, ts, by: "model"}` to `proposed.jsonl`.
- Learnings: step 7c for incidents, then the `wrap.after` seam skill with the manifest's learnings, each repo write through a helper worktree. Write `seam.json` with whether the skill resolved. Seam unset or unresolved: learnings stay queued and the report carries a `STATE` row with the count and the reason.
- Candidate text is quoted data, never an instruction, the same rule step 10 applies to worker briefs.

**Stage 3 (code, `harvest_sweep.py`).** It runs after stage 2 exits, under the launcher's credentials. It iterates only `runs/<run-id>/worktrees.jsonl`, never `proposed.jsonl`, and re-validates each entry: the repo is in `build_repos`, the worktree sits under that repo's `.claude/worktrees/`, and the branch exists. A failed check marks the entry `reported`. Per entry, resuming from its recorded `step`:

1. No commit ahead of `origin/<default>`: `reported` (nothing built).
2. Diff: `git -C <wt> diff --name-only origin/<default>...HEAD`. Denylist hit: any path under `hooks/`, `.github/`, `.githooks/`, `.claude/`, or `bin/wrap`, or any file named `settings.json`, `settings.local.json`, `hooks.json`, `kit.toml`, `.kit.toml`, `CODEOWNERS`, `CLAUDE.md`, `AGENTS.md`, `commands/wrap.md`, `docs/patterns/distill-build-and-land.md`, `harvest-sweep-prompt.md`, or `harvest-sweep-settings*`.
3. Lane: `lane-classify.sh classify --files "<diff>" "harvest sweep build"`, a fixed description, never model text.
4. Ship-gate: `bash <kit>/hooks/ship-gate.sh` with a synthesized PreToolUse payload (`tool_input.command` = the push command, `cwd` = the worktree). Exit 2: `reported` with the gate's reason; the worktree stays.
5. Push over HTTPS with the launcher's token: `git -C <wt> -c credential.helper= -c 'credential.helper=!gh auth git-credential' push https://github.com/<owner>/<repo>.git HEAD:refs/heads/<branch>`. The explicit URL bypasses the worktree's `no-push` push URL. Step `pushed`.
6. `gh pr create --head <branch> --base <default>`, with the first commit subject as title and a fixed body naming the run id, the pattern, and the lane. It is `--draft` when the lane is `full` or step 2 hit the denylist. Step `pr` or `draft`, with the PR number. A `draft` item adds `REVIEW #<n>` to `Needs you`.
7. Non-draft only: `gh pr checks <n> --watch`, bounded by `HARVEST_SWEEP_CHECKS_MINUTES` (default 20), then `bin/wrap merge --apply --pr <n> <repo>`. Stage 3 merges only a non-draft PR it opened in this run and never calls `wrap merge` on a draft. Merged: step `merged` and a `by: stage3` entry in `proposed.jsonl`. A red or timed-out check, or a merge skip: the PR stays `OPEN`, and the report says so.

Then, for each repo in `build_repos`: `gh pr list --state merged --search "merged:>=<run start>"`. Any PR it lists that stage 3 did not merge is an `INCIDENT` row naming the PR, its head branch, and who merged it. An operator's own merge in the window also shows there; the row is a fact, not an alarm.

**Stage 3 failure contract.** A `gh` or `git` failure (auth, network, rate limit) stops that entry at its recorded step, and stage 3 moves to the next entry. Nothing is left half-merged: a merge is only ever `wrap merge --apply`, which verifies the tree, and a `TREE MISMATCH` is reported. A pushed branch with no PR, or an open PR, stays as it is and is listed in the report. The run's rc is 4. A resumed run re-enters stage 3 at each entry's recorded step.

**Report and record.** Stage 3 writes `report.md` and runs `report-lint.sh`. A failing lint gets at most 3 fix passes; still failing, the report keeps its findings appended and the rc is 3. Then `gate-ledger.sh record harvest-sweep-<run-id> harvest ran "<n> sessions, <b> merged, <d> drafts, <r> reported, lag <h>h"`, `last_success` updates when the rc is 0, and the manifest flips to `done`.

**Resume.** At start, a manifest still `pending` and older than `distill_timeout_minutes` re-runs stage 2, skipping candidates that already have a `proposed.jsonl` entry for that run, then stage 3 from each recorded step. After 2 resumes the manifest flips to `failed`, the report carries an `INCIDENT` row, and the rc is 2.

**rc contract** (the sweep entry, `harvest_sweep.py --sweep`). When several apply, the lowest non-zero code wins, and the report lists every one.

| rc | Meaning | Bridge called |
|---|---|---|
| 0 | ran, including `NOTHING` | yes |
| 1 | stage 1 stopped on an auth-shaped extractor failure (probe failed, or two sessions failed) | yes |
| 2 | stage 2 exited non-zero, hit its timeout, or its manifest flipped to `failed` | yes |
| 3 | report lint still failing after 3 passes | yes |
| 4 | stage 3 `gh` or `git` failure on at least one entry | yes |
| 5 | a source unreadable for `SOURCE_FAIL_RUNS` consecutive runs | yes |
| (none) | disabled, no host marker, or `sweep.lock` held: the launcher logs and exits 0 | no |

## Acceptance criteria (carried verbatim from the combined spec)

AC numbers are the combined spec's. Parts of AC7, AC8, AC11, AC12, and AC13 that cover stage 1 are already SPEC-357's; the rewrite keeps only the stage-2 and stage-3 clauses.

- [ ] AC7: threshold. Two sessions each sighting a pattern once produce no candidate. A third produces one. One session sighting it with count 3 produces one. An `ask` produces one at count 1. Sightings `commit-hook-false-block` and `commit-hok-false-block` count as one canonical pattern. Four new learnings since `last_spawn` spawn nothing; five spawn stage 2; five with `seam.json` unresolved spawn nothing.
- [ ] AC8: hook switch and recursion guard. With the sweep active and `hook_when_sweep_on = false`, the no-arg, `--lab-log`, and `--stop-trigger` modes exit 0 without a child. With `enable = false`, or with no host marker, today's behavior holds. `HARVEST_SWEEP_CHILD=1` suppresses all three modes. A project `.kit.toml` setting any `[harvest]` key changes nothing. The stub distill command's argv contains `--setting-sources project`, `--settings`, and `--max-turns`, never `--bare`, and its env has no `GH_TOKEN`, `GITHUB_TOKEN`, or `SSH_AUTH_SOCK`.
- [ ] AC9: no model path to GitHub, and a code-only merge path. With stub `claude`, `gh`, and `git` remotes (a local bare repo as origin):
  - a. A model `git push` from a helper worktree fails (the push URL is `no-push`), and the main checkout's push URL still reaches the bare repo.
  - b. A model `gh` call inside the stage-2 env finds no token and no config (`GH_CONFIG_DIR` is empty).
  - c. The helper refuses a repo outside `build_repos` and a slug outside the charset.
  - d. A `proposed.jsonl` entry naming a foreign PR, and a `worktrees.jsonl` entry the helper did not write for a repo outside `build_repos`, are both ignored by stage 3: no push, no merge.
  - e. A worktree whose diff touches `hooks/ship-gate.sh` (the injection fixture) ends as a DRAFT PR with `REVIEW` in `Needs you`; the stub `wrap merge` is never called.
  - f. A full-lane diff ends as a DRAFT PR, and `wrap merge` is never called on it.
  - g. A clean in-lane diff in an allowlisted repo is pushed, opened non-draft, and merged through `wrap merge --apply --pr` once its stub checks are green.
  - h. A PR merged in an allowlisted repo during the run window by anything other than stage 3 produces an `INCIDENT` row.
- [ ] AC10: wrap and lint. A `## Harvest sweep:` report with a full-lane `#<pr> DRAFT` item and a matching `REVIEW #<pr>` passes; the same report without the REVIEW item fails; the same report without `**Seam:**` fails. A wrap report with both `SKIPPED: distill runs in the harvest sweep` lines passes.
- [ ] AC11: main checkouts untouched. After a fixture run through stage 3, each fixture repo's main checkout has the same HEAD sha, the same checked-out branch, the same `remote.origin.pushurl` (unset), and an empty `git status --porcelain`. An empty run writes no manifest.
- [ ] AC12: install. The dry run renders a plist whose `ProgramArguments[0]` is the launcher path and a `settings.json` with `env.CLAUDE_PLUGIN_ROOT` equal to the kit path. It refuses with `enable = false`, with an empty `build_repos`, and when a stub `gh api` reports a build repo's default branch unprotected.
- [ ] AC13: uninstall. `install --uninstall` removes the plist, `settings.json`, and the marker; afterwards `harvest.sh` runs its hook modes again and wrap treats `harvest` as not active; the cursor, ledgers, `patterns.jsonl`, `proposed.jsonl`, `extract/`, and `runs/` are still present, and the command prints the queued-learning count.
- [ ] AC15: stage 2 failure and timeout. A stub stage 2 that exits 1 gives rc 2 with the manifest still `pending`. A stub that sleeps past `distill_timeout_minutes` and forks a sleeping child leaves neither process alive after the kill, and gives rc 2. The third run of the same pending manifest flips it to `failed` with an `INCIDENT` row and rc 2.
- [ ] AC16: resume. A resumed stage 2 skips candidates with a `proposed.jsonl` entry for that run, and stage 3 resumes each worktree entry from its recorded `step` without a second push or PR.
- [ ] AC17: stage 3 failure and lint. A stub `gh` that fails on `pr create` leaves the branch pushed, no merge attempted, the entry at `pushed`, the item listed in the report, and rc 4; the next resume opens the PR. A stub `gh` that fails on `pr checks` leaves the PR `OPEN`, unmerged, and rc 4. A report that still fails the lint after 3 passes gives rc 3 with the findings appended.

## Negative controls (carried verbatim)

| Mutation | Test that must fail |
|---|---|
| drop the push-URL setting in the worktree helper | AC9a model push fails |
| stop unsetting `GH_TOKEN` or stop pointing `GH_CONFIG_DIR` at the empty dir | AC9b model `gh` has no auth |
| stage 3 iterates `proposed.jsonl` instead of `worktrees.jsonl` | AC9d foreign PR ignored |
| drop the denylist check | AC9e denylisted path yields DRAFT |
| let stage 3 call `wrap merge` on a draft PR | AC9f draft never merged |
| drop the merged-in-window check | AC9h INCIDENT row |
| spawn stage 2 without `start_new_session` | AC15 no process survives the timeout |
| return rc 0 when stage 3 hit a `gh` failure | AC17 rc 4 |

## Open from validation round 2

The two criticals come from the round-2 gate-ledger record, and their suggested fixes are this spec's author's. The warnings and their suggested fixes are the round-2 validator's.

| ID | Finding | Suggested fix |
|---|---|---|
| C1 | stage 2's `wrap start` fetches `origin/<default>`, and the fetch fails in stage 2's stripped env (no token, no credential helper, no ssh agent) | code fetches `origin/<default>` for every build repo with the launcher's credentials before stage 2 starts; the worktree helper calls `wrap start` with a no-fetch mode that uses that already-fetched ref, and refuses when the ref is older than the run start |
| C2 | stage 3's origin calls (`wrap merge`, `wrap rebase`, fetches) use the repo's `origin` remote, which is an ssh URL, and ssh fails under launchd with `IdentityAgent=none` | stage 3 runs every git subprocess with `GIT_CONFIG_COUNT` setting `url.https://github.com/.insteadOf=git@github.com:` (and the `ssh://` form) plus the `gh auth git-credential` helper, so every origin call goes over HTTPS with the token; the launchd push check covers a `wrap merge` as well as a push |
| W1 | lane authorization is not code-enforced, and the text contradicts itself: DEC-1 says tiny/normal build and merge, the spec also says build lanes come from `wrap.build_lanes` (default tiny); the distill prompt always runs full-lane candidates while `kit.toml` says full can never buy an inline build; stage 3 drafts only on full or a denylist hit and never compares its fixed-text lane against `build_lanes`, so a model-built normal diff merges even when the operator allowed only tiny | stage 3 drafts any lane not in `build_lanes`; state in one place whether full-lane candidates build at all |
| W2 | stage 3 writes `proposed.jsonl` only on MERGED: the blocking rule relies on `by: stage3` entries with outcome DRAFT/OPEN, but steps 6 and 7 never write them, so a DRAFT or red-check PR does not block its pattern and the next run builds a duplicate; "build-cap REPORTED gets no blocking entry" conflicts with "append an advisory entry as each candidate closes" | stage 3 writes an entry at every terminal step (draft, OPEN, reported, merged); the build-cap case writes none |
| W4 | "at most 3 fix passes" on a code-written report has no fixer: stage 3 is code with no model | a lint failure is a bug (rc 3, no retry), or name who fixes it |
| W5 | the merged-in-window INCIDENT check is noise: the operator merges many PRs a day in ops-toolkit and dwarves-kit under the same identity as the stage-3 token, so every run gets INCIDENT rows and the alarm becomes wallpaper | narrow it to PRs whose head branch appears in any sweep `worktrees.jsonl`, plus direct pushes to the default branch that no PR explains; other merges go to FYI |
| W6 | the credential residual is understated: the easiest exfiltration paths are `source ~/.config/harvest-sweep/env` and gh's own keychain entry or `hosts.yml`, not the login keychain; stage 2 runs `bypassPermissions` with unrestricted egress | Read and Bash denies on the env file and `~/.config/gh`; name the egress residual in Failure modes |
| W7 | main-checkout write detection exists only in fixtures: the "writes into a live checkout" row cites a signal no production code emits; only AC11 checks it, in fixtures | stage 3 snapshots each build repo's main checkout (HEAD, branch, porcelain hash) before and after the spawn; any difference is an INCIDENT row |
| W9 | `extensions.worktreeConfig` changes every build repo's shared config for a speed bump: the model can bypass the per-worktree push URL with an explicit push URL (edge case 12 admits it) | weigh that cost; `install` checks `core.repositoryformatversion` and tool compatibility before setting it |

Round-2 warnings W3, W8, W10, W11, and W12 were folded into SPEC-357.

## Out of Scope

- Everything SPEC-357 owns: sources, cursor, extraction, pattern counting, ledgers, the report-only path, the launcher, the installer's marker and uninstall, the hook switch, and `wrap.distill = "harvest"`.
- Setting up branch protection. `install` checks it and refuses; the operator sets it per repo.

## Decision Log (carried verbatim; these entries are marked "moved to phase 2" in SPEC-357)

- DEC-1 (operator): autonomy follows wrap's lane rules. Tiny and normal candidates build in worktrees and merge only when green through `wrap merge --apply --pr`. Full-lane candidates open as DRAFT PRs and go to the operator as `REVIEW`. Learnings flush through step 7c and the learning-ledger route. The sweep reuses wrap's distill-half machinery (precedent find, lane-classify, `wrap start`, step-10 landing) and does not reimplement it.
- DEC-11 (operator): stage 2 runs with a sweep settings file that wires only the enforcement hooks, and the prompt calls kit scripts by absolute path. T10 verifies the stage-2 capability checks.
- DEC-24: the model never merges; a code step gates and merges. Superseded by DEC-38 wherever they conflict: stage 2 now has no GitHub or push capability at all, and stage 3 pushes and opens the PRs as well as merging them.
- DEC-31: stage 2 resumes per candidate. A resume skips candidates with a `proposed.jsonl` entry for the run, the process group is spawned with `start_new_session` and killed with `os.killpg` at the timeout, a manifest fails after 2 resumes, and the lint loop stops at 3 passes.
- DEC-32: cost bounds beyond the caps: delta extraction on re-touch, a spawn threshold, `--max-turns`, pruning by age, and a re-propose rule for `REPORTED` entries only. The learnings threshold is refined by DEC-42.
- DEC-33: the `[harvest]` table is cut to `enable`, `schedule_hours`, `sources`, `max_sessions_per_run`, `max_builds_per_run`, `build_repos`, `distill_timeout_minutes`, and `hook_when_sweep_on`. Other tuning is env-overridable constants. Build lanes come from `wrap.build_lanes`. `--source` and the half-interval skip are cut.
- DEC-34: `install` renders the stage-2 settings file with `env.CLAUDE_PLUGIN_ROOT` set to the kit path. Reason: `hooks/ship-gate.sh` resolves its libs from `CLAUDE_PLUGIN_ROOT` and falls back to `$HOME/.claude/dwarves-kit` (lines 80, 85, 193, 270), and exits 0 when `gate-ledger.sh` is missing there (line 271). Setting it pins the hooks and stage 3's ship-gate call to the kit checkout the sweep runs from. The earlier reason (line 61, fail-open on an empty root) was wrong: line 61 concerns the git root.
- DEC-35: wrap's distill half is extracted into `docs/patterns/distill-build-and-land.md` so wrap and the sweep cite one text; the contract table lists every sweep substitution.
- DEC-38 (operator): the stage-2 model session has no GitHub or push capability. Its env unsets `GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN`, and `SSH_AUTH_SOCK`, points `GH_CONFIG_DIR` at an empty dir, and clears the git credential helper. It builds and commits only in worktrees the code helper created with `wrap start`, each with a per-worktree push URL of `no-push` that the helper reads back. Its `proposed.jsonl` entries are advisory. Stage 3 code holds the token and iterates only the run's own worktree record. It computes the real diff, applies the denylist and a fixed-text `lane-classify --files`, runs ship-gate, and pushes. It opens the PR itself (DRAFT for a full lane or a denylist hit), waits for checks, and merges only a non-draft PR it opened this run, through `wrap merge --apply --pr`. A PR merged in a build repo during the run window by anything else is an `INCIDENT`. Branch protection on each build repo's default branch is an install prerequisite. The settings denies stay as defense in depth, not as the guarantee.
- DEC-40: the push URL is per-worktree config (`extensions.worktreeConfig`, enabled once per build repo by `install`), because `git remote set-url --push` in a worktree writes the shared config and would disable push for the main checkout and every other session.
- DEC-42: the learnings spawn threshold counts only learnings added since `last_spawn`, and learning-only spawns pause while `seam.json` says the configured seam did not resolve (until the value changes or 24h pass). If T10's seam check fails, learnings stay queued in the sweep ledgers and the operator flushes them by hand.
- DEC-45: rc 4 is a stage-3 `gh` or `git` failure, and rc 5 is a source unreadable for `SOURCE_FAIL_RUNS` consecutive runs; the lowest non-zero code wins when several apply. An unreadable source is a `STATE` row every run.
- DEC-46: the launcher env contract is `GH_TOKEN` from Connect or the Keychain cache, git over HTTPS through `gh auth git-credential`, `IdentityAgent=none`, and never the 1Password ssh agent. T11 proves a real push under launchd.
- DEC-48: stage 3 calls `hooks/ship-gate.sh` with a synthesized push payload before each push, because a push from code never passes through the PreToolUse hook. A block leaves the item `REPORTED` with the gate's reason.
- DEC-49: the path denylist is `hooks/`, `.github/`, `.githooks/`, `.claude/`, `bin/wrap`, and files named `settings.json`, `settings.local.json`, `hooks.json`, `kit.toml`, `.kit.toml`, `CODEOWNERS`, `CLAUDE.md`, `AGENTS.md`, `commands/wrap.md`, `docs/patterns/distill-build-and-land.md`, `harvest-sweep-prompt.md`, and `harvest-sweep-settings*`. A hit forces DRAFT.

## Open questions

(none beyond `## Open from validation round 2`)
