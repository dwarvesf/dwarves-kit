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

## SG-02 (2026-07-12, PR #237 merged 76fbafe)

Call sites deliberately left unbracketed (per the handoff contract):

- `commands/grill.md` skipped branch: a skip runs no work, so there is no duration to bracket honestly.
- `commands/ship.md` `record <rid> Ship ran`: excluded from the goal's literal inventory by its own prose (the line contains the word "outcome" in an unrelated clause, so `rg -v outcome` dropped it). Needs no bracket: `hooks/ship-gate.sh` already emits the `ship` OUTCOME pair (SPEC-129's original live emit) and `normalize_phase()` folds Ship/ship to one key. The standing lint carries an explicit `ship` exemption with a load-bearing NC.
- `caught=` omitted at 8 of 22 sites whose recorded text carries no verdict/count; the verb's documented `false` default stands (inventing verdicts would change gate-decision logic, forbidden by the quality bar).

Durable: `tests/lib/contract-lint.sh` is the shared grep-diff-against-manifest primitive; SG-08's registry drift lint MUST reuse it (goal 02 scope edge).

## SG-07 (2026-07-12, PR #238 merged c2eb239)

- Dashboard output location convention: `<megagoals-root>/<slug>/REVIEW.html`, sibling of RUN_REPORT.md, overridable via `--out` (SPEC-197 Technical Design). A projection, never a stored source of truth.
- `lib/mega.sh` -> `lib/mega/mega.sh` directory promotion DEFERRED to SG-04 (SPEC-197 DEC-001; the ADR census names it SG-04's target).

## SG-04 (2026-07-12, PR #239 open + stacked; merge after #236)

bin/learn verb table (final): `debt list|collect|mark-paid` live -> lib/learn/weekend-batch.sh (git mv, byte-identical); `propose` REFUSES exit 1 "ships in SPEC-195"; `drain` REFUSES exit 1 "ships in SPEC-196". bin/ census AFTER: board classify gate goal learn mega queue session spec stats + prose-rag worktree-provision (12 entries, 2 classes; config lands in SG-08); enforced by a standing set-equality test. Recorded exceptions: guidance strings naming add-backlog repointed to `board promote` (byte-level-unchanged exception, impl-notes); lib/stats tests' dormant cc-backlog probe self-SKIPs, not repointed. Deploy note for merge time: re-run install.sh (PATH shims) + re-copy vps-mon bridge per its README.

## SG-08 (2026-07-12, PR #240 open + stacked; merge after #236)

- Registry home: lib/config/module-registry.md (ADR decision-3 pinned). 12 module->leg rows (completeness-linted vs KIT_KNOWN_MODULES) + 91 env<->key rows.
- Drift-lint allowlist policy: 17 tokens excluded, each with a stated reason (script-local computed paths, test-fixture-only names, prefix false-positives); the allow-regex is derived from the registry's own Allowlist table (single-sourced). Lint scope = the goal's exact seed regex; ~18 real vars outside the prefix family documented as Known gaps for a future structural lint.
- prose_rag leg = Learn, WORKER-ASSIGNED (absent from the ADR table); Han confirms or the ADR gets amended at gate review.
- ledger.telemetry: [impl] in kit.toml but reader-less; retagged [design] in the registry only.

## SG-06 (2026-07-12, PR #241 open + stacked; merge after #239)

- Expiry constant: DEFAULT_EXPIRE_DAYS=30 in lib/learn/drain.py with --days override; never a kit.toml key (pinned).
- Shared staging-block grammar: lib/learn/staging-format.py landed by SG-06 (first to land); ONE definition of the [staged]/[expired] block edges; SG-05 consumes or rebases onto it at fan-in.
- add-backlog needed zero changes: its existing state=="staged" filter already makes [expired] rows unselectable.
