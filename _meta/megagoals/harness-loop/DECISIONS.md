# DECISIONS, harness-loop (durable invariants appended per sub-goal completion)

## SG-03 (2026-07-12)

- Review found no defects in PR #226; merged as-is (squash, a6c5a9e). No invariants added.

## SG-01 (2026-07-12, PR open + held for Han)

Names locked by ADR-0034 (`docs/decisions/0034-harness-loop-taxonomy.md`); a later sub-goal that wants to deviate amends the ADR first:

- `lib/learn/` + `bin/learn` with exactly `propose | drain | debt <list|collect|mark-paid>`; weekend-batch relocates there; harvest/backlog-stage stay capture-side in their modules.
- `retro` = per-run (`/kit:retro`), `propose` = cross-run (`learn propose`); the recurring goal name `kit-retro-YYYY-WW` is the one recorded exception (proper noun; date-suffix IS the recurrence mechanism).
- Legs are metadata: module -> primary-leg table is authoritative in ADR-0034 decision 3; machine home pinned at `lib/config/module-registry.md` (ONE file for leg + env<->key rows; completeness linted against KIT_KNOWN_MODULES in SG-08).
- Front-door fences: start=detector (never writes), adopt=mechanical injector (never interactive), onboard=interactive orchestrator, config=read/explain; `lib/config/kit-config.sh` stays the only TOML reader.
- `-propose` joins the closed role-suffix vocabulary: propose-only writer, only legal sink = a staging file.
- bin/ one grammar `bin/<subsystem> <verb>`; session-* 5->1 (`session intel|observe|recall|report|semantic`); `add-backlog` -> `board promote` with NO alias; new entries spec/goal/stats/mega/queue (SG-04), config (SG-08), learn (SG-04); module CLIs (`prose-rag`, `worktree-provision`) keep module names (two-class rule).
- Kit-skill rule: agent-auto-fired workflows driving kit machinery earn `skills/`; stats skill relocates to `skills/stats/` (today it never installs: install.sh globs `skills/*/SKILL.md` only).
- ONE weekly scheduler: single LaunchAgent template + dispatcher + declarative jobs list; per-job plists retire (session-intel-weekly.plist.tmpl folds in at SG-10).
- Ledger retention: append-only stands; revisit only at a measured threshold (shared ledger root > 100 MB or `stats digest` > 10 s), via a new ADR, never silent rotation.
