# Implementation notes: ledger durability (SPEC-097)

Delta from SPEC-097. Decisions the spec did not pin, tradeoffs, constraints found.

## 2026-07-02 forced deviation: in-place stacked branches (not worktrees)

Context: the global CLAUDE.md rule is "always branch into a worktree". This
mega-goal runs from a session anchored in `ops-toolkit`, so the native
`EnterWorktree` targets the wrong repo and hand `git worktree add` is forbidden.
Decision: sub-goal branches are created in-place in the `dwarves-kit` main
checkout, one at a time (sequential single-writer). Why: the work is strictly
sequential (stacked PRs), the always-worktree hook is warn-only, and stacking is
by git base-ref not working copy. Impact: no parallel-writer isolation, which is
not needed here.

## 2026-07-02 durable path choice: XDG_STATE_HOME

Context: the blast zone is `~/.claude/dwarves-kit/` (holds real `logs/` beside
symlinks `lib`/`AGENTS.md`/`WORKFLOW.md`); a plugin reinstall recreates the dir
and wipes `logs/`. Decision: default becomes
`${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs`. Why XDG state and not
a `~/.claude` sibling: `~/.local/state` is the canonical home for persistent
state that must survive tooling churn, and it is fully outside anything a
`~/.claude/dwarves-kit*` reinstall would touch. `DWARVES_KIT_LOG_DIR` still wins
when set (tests, operators).

## 2026-07-02 scope: hooks' diagnostic logs stay at the legacy default

Context: ~20 files compute `LOG_DIR` inline. Decision: only the CORPUS-bearing
libs (`gate-ledger`, `proof-ledger`, `lane-telemetry`, `precedent`, `mega-merge`)
move to the durable resolver + migration. The hook *diagnostic* logs
(`ship-gate.log`, `slop-cleaner.log`, `spec-drift-guard.log`, `commit-format.log`,
`secrets-guard.log`, `safety-gate.log`) are ephemeral breadcrumbs, regenerate on
use, and are NOT read by `/kit:retro` or the SPEC-073 eval. Why: keeps the diff
off enforcement hooks (lower review + latency risk; hooks fire on every tool
call, so no per-call `source`). The eval/retro corpus (`runs/*.log` via gate-ledger,
`completeness.log` via BOTH lane-telemetry read AND lane-classify write,
`proof-overrides.log` via proof-ledger) all lives in the moved libs. Tradeoff:
kit logs are split across two roots until a future sweep unifies hooks; noted so
an operator is not surprised. `ship-gate` still READS the ledger through
`gate-ledger.sh check` (resolver-aware), so enforcement is unaffected.

Correction (validate finding B1): the first draft left `lib/lane-classify.sh` out of
the moved set. It WRITES the `completeness.log` LANE-CHECK downgrade lines; the moved
`lane-telemetry.sh` READS them. Split writer/reader across old/new paths = downgrades
invisible to the reader after migration. Fix: lane-classify joined the resolver set so
writer and reader agree. (validate finding B2): `kit_migrate_log_dir` is provably
return-0 and every call site adds `|| true`, so a migration hiccup can never abort a lib
load under `set -e` and fail-close the ship-gate.

## 2026-07-02 migration triggering: sentinel-guarded, on-access, skip when env set

Decision: `kit_migrate_log_dir` no-ops when `DWARVES_KIT_LOG_DIR` is set
(explicit path = caller owns it; prevents tests that point at a temp dir from
sucking in the real machine corpus). Otherwise it copies legacy -> new with
`cp -Rn` (never clobbers, never deletes legacy) once, guarded by a `.migrated`
sentinel in the new dir. Why on-access + sentinel: covers a real reinstall
lazily without a separate install step, and the sentinel + `-n` make it
idempotent and cheap (one `stat`).

## 2026-07-02 override hygiene semantics

Decision: `override <rid> <phase> <reason>` is rejected (exit 65) when `<reason>`
already appears as an override reason for a DIFFERENT phase in the same run's
ledger. This is the "blanket override" the sole surviving pre-July run committed
(one pasted reason across every gate). A distinct reason per gate passes. Same
reason re-applied to the SAME phase (idempotent re-run) is allowed. Why not a
batch-reject-in-one-call form: the observed defect is one reason spread across
gates over several calls; checking the ledger catches both the multi-call and
any future batch form.
