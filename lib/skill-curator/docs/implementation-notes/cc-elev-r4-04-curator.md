# Implementation notes: cc-self-improve Phase C curator (cc-elevation-r4 sub-goal 04)

Delta from SPEC-103 (TASK-011..014) + goal `04-skill-curator.md`. Only what the spec/goal does NOT pin.

## 2026-06-19, curator pure-function seam `CC_SI_CURATOR_CMD`
- Mirrors the reviewer's `CC_SI_REVIEWER_CMD`: the `claude -p --allowedTools ""` curator call is
  isolated behind `CC_SI_CURATOR_CMD` (emits a claude -p envelope whose `.result` is the plan JSON),
  so the plan-parse / report / archive / restore logic tests with no live model.

## 2026-06-19, archive uses `git mv`, non-git falls back to `mv` + manifest (never rm)
- `--apply` archives a skill via `git mv skills/<name> skills/_archive/<name>`. If `skills/` is not a
  git repo, fall back to `mv` + append a line to `skills/_archive/manifest.tsv` and WARN that
  git-restore is unavailable. `cc-improve restore <name>` reverses it. No `rm` anywhere in the path
  (asserted by a test that greps the archive code for `rm`).
- `absorbed_into` from the plan is recorded in the archive manifest so `restore` + any references stay
  coherent (hermes-patterns C archive-forwarding).

## 2026-06-19, vps-mon "monitored" is an operator deploy-time check (gate), proof = [UNAVAILABLE]
- vps-mon discovers launchd jobs via the Mini push-collector and reconciles a `scheduled` job to
  green only once it is installed AND emits a heartbeat. That requires deploying the plist to the
  Mini , host-side, and this sub-goal is `gate` (HELD for Han's click). The curator emits a
  heartbeat line on each run (`$STATE_DIR/curator.heartbeat`) so the job CAN be wired green; the
  live `launchctl print` + vps-mon `monitored` confirmation is the documented operator step at
  approval/deploy. The proof records that check as `[UNAVAILABLE: requires live Mini deploy]` with
  the exact commands, which the stateful proof gate accepts.

## 2026-06-19, launchd is propose-only: the plist runs `cc-improve curate` with NO `--apply`
- The weekly `mini.cc-curator` plist's ProgramArguments invoke `bin/cc-improve curate` (report only).
  `--apply` is NEVER in the plist (preserves the autonomy gate; the human runs `--apply` after
  reading the report). BTM-friendly: ProgramArguments[0] = `bin/cc-improve` (no `.sh`).

## 2026-06-19, pinned skills are skipped by frontmatter, not usage
- Curator skips a skill whose SKILL.md frontmatter has `pinned: true` or `cc-si-protected: true`
  (hermes-patterns C hard rule 2). Usage counters are NOT a skip reason (`use=0` is absence of
  evidence, not evidence) , the inventory does not even collect usage.

## 2026-06-19, cross-loop isolation (same as 01-03); 04 is the close-out + GATE
- Runs in a worktree off origin/main; never mutates the OBS-owned main checkout. 04 is HELD (gate):
  open the PR, do NOT merge. Carries the round LAB_LOG entry + the Hermes-parity assertion.

## 2026-06-19 (doc pass) , architect review found two SPEC-vs-code drifts; fixed in favor of code
- A Plan/architect subagent reviewed the tool against the code before the doc set was written. It
  caught two places where SPEC-103 + CONTEXT.md had drifted from the implementation:
  1. **`flock` -> atomic `mkdir` lock.** The spec said `flock`; the code uses an atomic `mkdir` lock
     (macOS has no `flock(1)`). Corrected SPEC-103 lines 114/138/220 + CONTEXT.md to the code, with
     the history recorded in ADR-0004.
  2. **curate logs no cost row.** The spec's cost-AC said "every reviewer/curate run logs
     total_cost_usd"; only the reviewer does (curate writes a report + heartbeat). Corrected the AC.
- Added the full canonical doc set this pass (not part of the original SDD build): `docs/architecture.md`,
  `MANUAL.md`, `RUNBOOK.md`, `SPEC.md` (index), and 9 ADRs under `docs/decisions/`. INVENTORY shape
  corrected to `daemon-service`, tier stays `done`. Other architect findings folded into the docs:
  the `reviewer-spawn.sh` indirection, the `auto_promote` references-add exception, the brittle
  `CC_SI_MEMORY_LEDGER` cc-harvest coupling (RUNBOOK incident 9), the `reviewer.lock` vs `.d` naming wart.
