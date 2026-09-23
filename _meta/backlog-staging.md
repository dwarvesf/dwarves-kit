# Backlog staging (auto, via learn propose)

Candidates auto-extracted from the ledger. Review + promote by hand (`board promote`).
Gitignored: may name unfiled work. NEVER the source of truth.

## [staged] Audit high override rate on reflect gate
- Intent: Bring the reflect gate's override rate down from its current outlier level.
- Approach: Sample reflect-gate override reasons to find the common cause; adjust gate criteria or the retro flow that keeps triggering it.
- Tags: #u-hi #f-hi
- Home: dwarves-kit
- Source: learn propose 2026-07-12 | lens=gate-yield figure="reflect override_pct=28.0" rids=SPEC-105-hardening,SPEC-106-admin-moderation,SPEC-107-launch-pack,SPEC-108-account-settings,SPEC-109-onboarding,advisor-visibility,board-mirror,board-tool,+143 more

## [staged] Add a token-runaway guard for sessions
- Intent: Stop sessions from ballooning into billions of tokens unnoticed.
- Approach: Add a session-level token ceiling check that alerts or halts; separately root-cause the 2.1B-token session that triggered this.
- Tags: #u-hi #f-mid
- Home: ops-toolkit
- Source: learn propose 2026-07-12 | lens=anomalies:token_runaway figure="session_id=8ae69411-07d1-474e-a33d-64b1531ce251 project_slug=-Users-tieubao-workspace-tieubao-ops-toolkit total_tokens=2115144012" rids=SPEC-105-hardening,SPEC-106-admin-moderation,SPEC-107-launch-pack,SPEC-108-account-settings,SPEC-109-onboarding,advisor-visibility,board-mirror,board-tool,+143 more

## [staged] Tighten the observability spec against its deviation log
- Intent: Bring the 01-observability spec out of under-specced territory.
- Approach: Review the 15 logged implementation deviations and fold the recurring ones back into the spec.
- Tags: #u-mid #f-hi
- Home: dwarves-kit
- Source: learn propose 2026-07-12 | lens=deviation-rate figure="repo=dwarves-kit; slug=01-observability; file=lib/session/observe/docs/implementation-notes/01-observability.md; n_deviations=15; zero_marker=False; first_ts=2026-06-14 00:00; last_ts=2026-06-15 14:40; class=UNDER-SPECCED" rids=SPEC-105-hardening,SPEC-106-admin-moderation,SPEC-107-launch-pack,SPEC-108-account-settings,SPEC-109-onboarding,advisor-visibility,board-mirror,board-tool,+143 more

## [staged] Sweep memory notes pointing at dead paths
- Intent: Stop memory notes from citing paths that no longer exist in the repo.
- Approach: Run a dead-path scan across memory notes and remove or repoint the stale ones.
- Tags: #u-lo #f-hi
- Home: dwarves-kit
- Source: learn propose 2026-07-12 | lens=memory-sweep figure="21 memory notes reference dead paths, 0 stale (>180d)" rids=SPEC-105-hardening,SPEC-106-admin-moderation,SPEC-107-launch-pack,SPEC-108-account-settings,SPEC-109-onboarding,advisor-visibility,board-mirror,board-tool,+143 more

## [staged] Add a self-answer detection check to `/kit:think` (and any other forcing-question command):
- Intent: Action item a retro committed to; it lived only as a checkbox nobody could promote.
- Approach: Add a self-answer detection check to `/kit:think` (and any other forcing-question command):
- Tags: #u-mid #f-mid
- Source: retro 2026-08-01 | RETRO-2026-08-01-backlog-reconcile.md

## [staged] Make "fetch origin before cutting any new branch" a reflex step in the
- Intent: Action item a retro committed to; it lived only as a checkbox nobody could promote.
- Approach: Make "fetch origin before cutting any new branch" a reflex step in the
- Tags: #u-mid #f-mid
- Source: retro 2026-08-01 | RETRO-2026-08-01-backlog-reconcile.md

## [staged] wrap merge union retry
- Intent: bin/wrap merge: on a CONFLICTING squash caused by GitHub ignoring merge=union, merge the default branch into the branch worktree and retry once
- Approach: (no approach extracted)
- Tags: #u-lo #f-mid
- Home: dwarves-kit
- Source: session 2026-09-08

## [staged] wrap merge: wait for CI instead of returning on pending
- Intent: This session hand-rolled the same watch-then-merge-then-clean script three times (merge-527/528/529.sh in scratch). bin/wrap merge returns immediately on a pending PR, so every caller reinvents the wait. Enhancement belongs in wrap merge, not a fourth script. The fork that makes it a judgment: blocking wrap on CI holds the landing step for the full macOS leg (~9 min observed today), so it likely wants a --watch flag plus a timeout, not a new default.
- Approach: (no approach extracted)
- Tags: #u-lo #f-mid
- Home: dwarves-kit
- Source: session 2026-09-08

## [promoted ID-651] wrap Step 7a is unreachable when landing from a default branch
- Intent: gate-ledger.sh rid refuses on master/main ('not on a work branch'), so /kit:wrap Step 7a silently skips the DEBT marker for exactly the sessions most likely to need it: a long multi-repo session landed from the default branch. Either derive a rid from the session rather than the branch, or make Step 7a say the marker was skipped for a structural reason rather than reporting a clean skip.
- Approach: (no approach extracted)
- Tags: #u-lo #f-mid
- Home: dwarves-kit
- Source: session 2026-09-09

## [staged] wrap apply: name the untracked file that blocks an ff pull
- Intent: Twice this session a git pull --ff-only aborted because an untracked local file was byte-identical to one that had just merged (a research note, then a handoff), and the fix was manual both times: git show origin/main:<path> > tmp, cmp, mv the local copy aside, pull again. wrap apply owns the pull and reports it as FAILED with no reason the operator can act on. Judgment fork, which is why this is staged rather than built: reporting the blocking path and the identical-or-not verdict is safe, but moving or deleting an operator file to unblock a pull is a write on something wrap did not create, and that call belongs to the operator.
- Approach: (no approach extracted)
- Tags: #u-lo #f-mid
- Home: dwarvesf/dwarves-kit
- Source: session 2026-09-10

## [dropped: fixed upstream by #574] wrap log prepends above the LAB_LOG header
- Intent: bin/wrap log's fallback path writes the new entry above the '# LAB_LOG' header instead of below it, so the header drifts down the file one session at a time; the 2026-09-10 compaction found it at line 878 of 4190 and had to move it back by hand. Fix the fallback insertion point and add a test asserting the header stays at line 1 after a log write.
- Approach: (no approach extracted)
- Tags: #u-lo #f-mid
- Home: dwarves-kit
- Source: session 2026-09-10

## [promoted ID-829] repo-hygiene audit-loop instance
- Intent: Add a repo-hygiene instance to the kit's audit-loop family (siblings: doc-drift, topology-drift, ci-drift, backlog-reconcile, web-drift; shared read-only audit-scanner). Detectors: a non-code file nothing references after N days; a gitignored dir that is large and cold; an _inbox item older than 30 days; a _meta entry that is an owned record; a log past its line threshold. Each finding carries evidence (file:line, or the grep that proves nothing references it) because verification, not detection, was 90 percent of the cost when this ran by hand on 2026-09-10. Surfaces findings only, never deletes: route-versus-trash needed Han's call four times in one pass, and twice he decided against the recommendation.
- Approach: (no approach extracted)
- Tags: #u-lo #f-mid
- Home: dwarves-kit
- Source: session 2026-09-10

## [built 67cbc53] worker brief template for subagent dispatch
- Intent: Twenty-plus dispatch prompts repeated the same preamble by hand: pwd, fetch origin main and merge, absolute paths, git -C, rename branch, do not edit shared modules, verification file required, LAB_LOG line, STE-lite, no dashes, commit not push, report in N lines. Drift between copies caused two real defects: workers blind to merged docs, and a fenced worker leaving stale doc lines. Fork: a kit doc the commands cite, versus a lib helper that emits the block, versus fields on the agent definitions.
- Approach: Built as `docs/patterns/worker-brief.md`, the kit-doc-a-command-cites option (the reversible first step). The lib-helper and agent-definition-fields alternatives are still open; see the fork note above.
- Tags: #u-lo #f-mid
- Home: dwarves-kit
- Source: session 2026-09-11

## [built 4595dea] proof-gate contract emits the verification skeleton
- Intent: Fifteen-plus workers each wrote docs/verification/<slug>.md from a prose description re-specified in every dispatch: run table with Command/Exit/Verdict, negative control, determinism hash, rollback note, Not proven. proof-gate.sh contract already tells a work type what it owes; it could emit the file skeleton too. Fork: contract prints it versus a separate verb writes the file, and whether the skeleton belongs in the kit or in each adopting repo.
- Approach: Built as a new `proof-gate.sh skeleton "<slug>" ["<task>"]` subcommand; `contract` prints a pointer to it rather than the skeleton itself. Lives in the kit since proof-gate.sh already does. The determinism-hash field named in the intent did not carry into the built shape; the skeleton carries Green run, Negative control, Rollback (stateful only), and Not proven.
- Tags: #u-lo #f-mid
- Home: dwarves-kit
- Source: session 2026-09-11


## [promoted ID-873] Test fixtures can write the tester git identity into the real repo when the temp dir var is empty #test #u-mid #f-lo
- Intent: On 2026-09-13 the shared checkout's `.git/config` carried `user.name=tester` / `user.email=t@t.dev`, so three commits landed under that identity before a worker noticed and rewrote them; four tests (tests/test-cheap-guards.sh:75, tests/test-queue.bats:40, tests/test-runaway-guards.sh:86, tests/test-notes-sanitization.sh:164) run `git -C "$d" config user.email t@t.dev; git -C "$d" config user.name tester` right after `git -C "$d" init`, and with `$d` empty (a failed `mktemp -d`, an unset var under a subshell) `git -C ""` targets the caller's cwd, the real repo.
- Approach: Root cause is the missing guard, not any one test; the fix is a shared helper `fixture_repo()` that does `d=$(mktemp -d) || exit 1` then init then identity, or `set -u` plus `[ -n "$d" ]` before every `git -C "$d"` call, plus a one-line check at test start that the real repo's `git config --local user.email` is not `t@t.dev`.
- Tags: #test #u-mid #f-lo
- Home: dwarves-kit
- Source: incident 2026-09-13 | shared checkout identity clobber
||||||| Stash base
## [staged] wrap: land a worker branch in one verb
- Intent: Every worker branch this session took the same 8 commands by hand, 20+ times: fetch main, merge FETCH_HEAD, push -u, gh pr create, gh pr view for head sha, gh pr merge --squash --match-head-commit, gh pr view for state, worktree remove. Twice main moved mid-sequence and the cycle repeated. Fork: a --land flag on wrap merge versus a new wrap land verb, and how either interacts with SPEC-065 chain ordering.
- Approach: (no approach extracted)
- Tags: #u-lo #f-mid
- Home: dwarves-kit
- Source: session 2026-09-11

## [staged] wrap merge: clear a CONFLICTING verdict caused only by merge=union log files
- Intent: GitHub squash-merge ignores .gitattributes merge=union, so a branch that prepended a LAB_LOG line reads CONFLICTING after main moves; three PRs in one session (ops-toolkit 2642, 2643, 2644) each needed a hand git merge origin/main in the worktree plus a push before wrap merge could proceed. Enhance bin/wrap merge: when the PR is CONFLICTING and the conflicting paths are all declared merge=union, merge the base into the branch in its worktree, push, re-check, then merge. Never touch a branch whose conflict includes a non-union path.
- Approach: (no approach extracted)
- Tags: #u-lo #f-mid
- Home: dwarves-kit lib/wrap/wrap.sh merge verb
- Source: session 2026-09-12

## [staged] kit-weekly: render the staging buffer weekly and post it
- Intent: The staging buffers fill (ops-toolkit held 105 candidates on 2026-09-12, last hand triage 2026-07-18) because reflect drain has no trigger. Add a kit-weekly step that runs reflect drain --days 7 over every registered board, posts the render to the mac-mini-ops channel through the existing notify rail, and pings the air.kit-weekly heartbeat as today. Read-only over the buffers; promotion stays board promote by hand.
- Approach: (no approach extracted)
- Tags: #u-lo #f-mid
- Home: dwarves-kit kit-weekly scheduler (lib/session/observe or the kit-weekly runner) plus reflect drain
- Source: session 2026-09-12

## [staged] wrap apply: remove a proven-merged LOCKED agent worktree
- Intent: Agent-tool worktrees are locked by default; git worktree remove --force no-ops on them and needs -f -f. This run removed about twenty by hand after wrap scan proved each squash-merged. wrap apply --worktrees should unlock and remove a clean worktree whose branch scan marks SQUASH-MERGED per gh, and report it, instead of skipping it as held. Lane normal, kit machinery.
- Approach: (no approach extracted)
- Tags: #u-lo #f-mid
- Home: dwarves-kit lib/wrap/wrap.sh
- Source: session 2026-09-13

## [promoted ID-886] board promote <n> fails through a consumer shim: the appended --backlog-file flag is parsed as a candidate index
- Intent: Consumer shims (ops-toolkit _meta/board) exec bin/board with --backlog-file <path> appended; board.sh promote forwards argv verbatim to lib/board/bin/add-backlog, whose parser does int() on every token and prints usage. Reproduced 2026-09-16 on ops-toolkit: promote list works, promote 3 fails; direct call with BACKLOG_STAGE_BACKLOG and BACKLOG_STAGE_STAGING env works. Fix: strip or honour --backlog-file in add-backlog, add a shim-path test.
- Source: session 2026-09-16
## [staged] Converge the bash and python board parsers on the `\|` escape contract
- Intent: A correctly-escaped `\|` inside a row's status cell is legal for `sync_core.CELL_SPLIT` but invisible to bash `board` — five files index `$(NF-1)` on raw pipe splits, so the status keyword reads as a mid-cell fragment and the row lands in UNRECOGNIZED.
- Approach: Neutralize `\|` before splitting in the bash awk spots (lib/board/backlog.sh `_rows`/`set`/`dedupe`/`dedupe_all`, hooks/context-readiness.sh `_rows` twin, lib/board/parse-board.sh, lib/board/board.sh x2, lib/session/handoffs.sh), keep the sync parser's contract, pin with a row carrying `\|` in each cell position. Until then `&#124;` is the row-side workaround (used by ID-021/420/445).
- Tags: #board #correctness #u-mid #f-lo
- Source: session 2026-09-19 | follow-up named in PR #713 (folded 8 six-cell rows + re-escaped 3 status cells); next correctly-escaped status cell hits the same bash-side invisibility
