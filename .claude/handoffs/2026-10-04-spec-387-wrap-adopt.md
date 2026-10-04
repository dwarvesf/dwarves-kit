# Handoff: SPEC-387 `wrap adopt` (full lane, ends as a DRAFT PR)

## Goal

One kit verb, `wrap adopt [--apply] <repo>...`, replaces the hand loop that adopted six repos (wrap start, adopt.sh, commit, override, wrap land, adopt --check). Dry run by default. Full lane: it ends as a draft PR plus a `REVIEW #<pr>` item for the operator, never merged by the agent.

## Anchors

- Worktree: `dwarves-kit/.claude/worktrees/adopt-land`, branch `feat/adopt-land`, rid `adopt-land`
- Spec: `docs/specs/SPEC-387-adopt-land.md` (renamed from `-wrap-adopt` so the rid binds)
- Validation round: OPEN on rid `adopt-land`; its token is the last line of `/tmp/claude-501/vr-token.txt` (machine-local, Air). If lost: `bash lib/gate/gate-ledger.sh validate-round incomplete adopt-land --stale "<reason>"`, then reopen.
- Hand loop it replaces: session scratch `adopt-one.sh` (gone after reboot; the spec's Grounding quotes it)
- Six repos adopted by hand: pr-evidence-check #11, learning-kit #19, context-kit #15, vibedex #18, homebrew-tools #27, spacedown #16

## Decisions (do not relitigate)

- Home is a `wrap adopt` verb, not `adopt.sh --land` (spec DEC-A). Dry run unless `--apply`.
- It calls `cmd_start` and `cmd_land`; never reimplements them.
- Operator directed this build (`operator_directed_build: true` for the re-validate rule).

## Round 1 findings to fold (exist nowhere else)

- R7 sustainability: clean.
- R6 design record (BLOCKING lens): PASS, 4 warnings. Link ADR 0024, 0025, 0013; record the machine-written override as a DEC citing 0024 ("operator-authored"); name the ship-gate gap (G4) in Boundaries; make the state-machine rows match R5/R6 texts.
- R4 scope: CRITICAL, T1 is not atomic. Split: T1a preflight and dry run (R1-R4, cases 1-16, 22, 24); T1b apply, guard, override, R8 parse (R5-R9, R12; cases 17-21); T1c batch and summary (R10, R11; case 23); T1d test-header edits. Also: `--apply` is operator-only (say so in R1 and commands/wrap.md); drop `--title`; R5 same-process vs `tee` (use a file or PIPESTATUS); label live-repo checks as observed.
- R1 security: CRITICAL, the path guard allows `.claude/settings.json` without a content check. Add: every added hook command must match `^\$HOME/\.claude/dwarves-kit/hooks/[A-Za-z0-9_-]+\.sh$`, no other key changes; fix the override reason text. Warnings: honor `WRAP_ADOPT_SH` only under a test flag; log the override only after `merged #<n>` and include `pr=#<n>`. Notes: refuse one `--body-file` for a multi-repo batch; run repo args through `_reject_packed`.
- R2 failure modes: CRITICAL, a pre-merge failure has no recovery (apply skips unproven worktrees, R3f refuses a re-run). Fix: print `resume: wrap land <wt>`, fix R12 and two Failure-mode rows, add a test. Warnings: capture land's `2>&1`, fall back to its last stderr line plus exit code, prefer the TREE line after a merge; refuse gitignored ADOPT_PATHS (`status --ignored`); R3f: exit codes other than 0 or 2 mean `origin unreachable`, and check the tracking ref. Note: print each summary row as its repo finishes.
- R5 design: CRITICAL, plain `git status --porcelain` collapses new dirs (`?? .claude/`) and shows renames (`RM CLAUDE.md -> AGENTS.md` in single-source mode, the operator's live config), so R6 fails nearly every real adoption. Fix: guard on `git add -A` then `git diff --cached --name-only --no-renames -z` (R3 agrees). Warnings: R8 checks land's exit code first (3 = TREE MISMATCH), count a merge only on `merged #<n> (<sha>): tree verified`; add R3j refusing a default branch ahead of origin. Notes: fix edge-1 wording; set a style knob in case 22.
- R3 assumptions: CRITICAL, same porcelain defect as R5. Warnings: capture land with `2>&1` via process substitution (keeps R5 same-process), fall back to its last stderr line; preflight `git check-ignore` on ADOPT_PATHS; when R3f finds an open `chore/kit-adopt` PR print `resume: wrap land <wt>` (required review, squash disabled, non-GitHub origin). Notes: only `ls-remote` exit 2 means absent; stale-read note when HEAD differs from local origin/<def>; R3g also checks `@{u}`.

## Next step

1. Round 1 is CLOSED (NEEDS-REVISION, 5 critical, 15 warnings). Start by folding the findings.
2. Fold every finding into the spec, commit.
3. Re-open, re-validate once (all seven, Reviewer 6 on Opus), close.
4. Build T1a to T1d with Devin workers (`tools/worker-launch/worker-launch devin <brief> --cwd <wt>`, it now auto-accepts the trust prompt), serially or on disjoint files.
5. `lib/gate/negctl.sh`, proof at `docs/verification/adopt-land.md` with captured output, gate-ledger entries.
6. `bin/wrap rebase <wt>`, push, `gh pr create --draft`, remove the worktree, report `REVIEW #<pr>`.

## Landmines

- Sonnet is at its weekly limit until Oct 8: use Devin for builds, Opus for review.
- branch-guard blocks any Bash heredoc whose text contains a push command: write briefs with the Write tool.
- The ship-gate never sees a push made inside `wrap land` (spec G4).

## Also open (operator only)

- Mini cannot upload proof images: needs a Cloudflare dashboard login in Helium, then mint an R2-scoped token, set `asset_token_ref`.
- dotfiles adoption: the untracked root `AGENTS.md` is a stale Codex copy of `CLAUDE.md`; waits on the operator saying "move it".

## Start prompt

```
Repo: dwarves-kit, cwd /Users/tieubao/workspace/dwarvesf/dwarves-kit/.claude/worktrees/adopt-land.
Read .claude/handoffs/2026-10-04-spec-387-wrap-adopt.md first.
Next: round 1 is closed; fold the findings into docs/specs/SPEC-387-adopt-land.md.
Verify: bash lib/gate/gate-ledger.sh show adopt-land shows the closed round; bash lib/spec/spec-depth.sh check passes on the revised spec.
Scope: SPEC-387 only, full lane, ends as a DRAFT PR plus REVIEW item; never merge it. Leave other worktrees and sessions alone.
Check origin + open PRs before minting an ID. Close with /kit:wrap.
```
