# Mega-goal: harness-ops

**Destination:** the kit is a config-driven, cleanly-organized harness , one `kit.toml` (kit-root default + per-project `.kit.toml` override) drives modules/ledger/mega/features through one resolver; consumers reach a stable interface (not deep lib paths); and the doc tree + root are tidy enough that a newcomer isn't overwhelmed.
**Quality bar:** the config surface is the single place to tune the harness, and it reads honestly (inert keys documented, not silently no-op). The docs reorg touches only what's safe or repoints the code that reads a moved path , no broken gate, no lost history. Boring, coherent, welcoming.
**Stacking tool:** gh (stacked PRs)
**Merge mode:** auto-bottom-up
**Merge autonomy:** gated-final
**Started:** 2026-07-06

Single-repo (dwarves-kit, kit-adopted). Run from dwarves-kit cwd via the SDD lane; portable OPERATE.md run contract. TWO tracks share the destination "the harness is config-driven + tidy": Track A (config-layer) is the feature; Track B (docs/root restructure) is the hygiene. Design source: `docs/specs/DECISION-BRIEF-config-layer.md` (Track A), the 2026-07-06 docs+root audits (Track B).

## Sub-goals

### Track A , config-layer (design: docs/specs/DECISION-BRIEF-config-layer.md)

- [x] 01-config-resolver , `lib/config/kit-config.sh` (project `.kit.toml` overrides kit-root `kit.toml`, `kit_config_get`) + selftest , `auto` , merged c84cda5 (landed on master directly; no separate PR needed) , test-config.sh 6/6
- [x] 02-wire-ledger , `[ledger]` (location→KIT_LEDGER_DIR, telemetry, delivery thresholds) read via resolver, precedence env>project>kit-root>default , `auto`, PR #211, merged 877deb4 (CI green; proof docs/verification/wire-ledger.md)
- [ ] 03-wire-mega , `[mega]` (wave_cap, tier4_close, multiplexer, merge_autonomy, mega_merge_posture) via resolver; default_model/over_test as GLOBAL fallback (goal-file field > project > kit-root) , `auto`, PR #215 (open, CI running; proof docs/verification/ho-03-wire-mega/proof-of-done.md; NOTE: also wrote docs/runs/harness-ops-03-mega.md, seam with 11's docs/runs relocation, reconcile at merge)
- [x] 04-manifest-reconcile , repo-root `kit.toml` (default) → `install.sh` renders the install `kit.toml` + `--with` → resolver reads install←project; confirm the no-runtime-manifest-read lint stays hooks-only , `auto`, PR #216, merged 680ea9e (CI green; SPEC-183; proof 37/37)
- [x] 05-stable-interface , expose a stable consumer entrypoint (`kit <sub> <verb>` dispatcher or installed `board`) so consumers stop reaching `$DWARVES_KIT/lib/...`; repoint the adopt contract + make the board-shim fix permanent , `auto`, PR #218 , merged 2df444b (CI green; SPEC-184; pick=per-subsystem bin/ shims; left adopt.sh:72-83 for 12; consumer-repoint follow-ups in PR body). FOLLOW-UP (ops-toolkit): repoint _meta/board + board-all from lib/board/board.sh → bin/board
- [x] 06-project-override , `.kit.toml` support end-to-end; `/kit:adopt` optionally seeds a project `.kit.toml`; per-project module enable via `<project>/.claude/settings.json` , `auto`, PR #219 , merged 8174cde (CI green; SPEC-192; test-adopt 21/21)
- [x] 07-consumer-contract-doc , `docs/consumer-contract.md` (the 4 adopt files + KIT_LEDGER_DIR + optional `.kit.toml`) , one page to onboard a new project/machine , `auto`, PR #220 , merged 958f7cc (CI green; docs-only; doc-vs-code 4-file match vs lib/adopt.sh). TRACK A CLOSED.
- [x] 08-reserved-keys-guard , `[features]` (auto_improvement/learning_ledger) + `[team].*` stay inert + documented; resolver returns them with no side-effect; a test proves an inert key changes nothing , `auto`, PR #217 , merged 865105f (CI green; SPEC-188; additive test+spec+proof)

### Track B , docs/root restructure (design: 2026-07-06 docs + root audits, recorded below)

- [x] 09-proof-verif-reconcile , the 8 slugs present in BOTH docs/proof/ and docs/verification/ with DIVERGENT content , pick the canonical per slug, fold into verification/, retire docs/proof/. INTEGRITY (not a move) , `gate` (per-slug content judgment) , PR #214 , merged 7081121 (GATE APPROVED by Han 2026-07-06; 7/8 proof-base + 1 reversal, both sides kept; docs/proof/ retired empty; proof tests green)
- [x] 10-briefs-out , move `docs/specs/DECISION-BRIEF*` + `CONTEXT.md` → `docs/briefs/`; repoint the 4 command files + goal-drafts `GOAL_SPECS_DIR` , `auto`, PR #213, merged cd63271 (CI green; proof docs/verification/briefs-out/proof-of-done.md)
- [x] 11-runs-to-generated , move `docs/runs/` → `docs/verification/generated/`; repoint the realpath jail in `proof-table-gen.py`/`.sh` , `auto`, PR #212, merged b7374e3 (CI green after SPEC-135 assert-134 fix e4639fd; proof docs/verification/goal-11-runs-to-generated/run-table.txt; NOTE 03-orphan docs/runs/harness-ops-03-mega.md → fold relocation into 13)
- [x] 12-root-slim , the 3 giant machine-parsed root files (WORKFLOW/MANUAL/CHANGELOG): thin stub at root + bulk into docs/, repoint every reader (gate-ledger, dispatch-gate, test-meta, ship, adopt) , the newcomer "welcoming root" win , `auto`, PR #221 , merged da4b49f (CI green; SPEC-185; roots now 19/11/11 lines; install.sh docs/WORKFLOW.md copy + ~13 readers repointed; integrated 15-test seam check green)
- [ ] 13-doc-tidy , safe doc-moves: `docs/audits/` for one-off reports (skillspector), `kit.toml.example` home decision, `docs/README.md` map refresh , `auto`, PR #222 (open, CI running; FINAL PR, HELD for Han's click; skillspector→audits/, orphan docs/runs/harness-ops-03-mega.md→verification/generated/, docs/runs/ gone, README map refreshed, kit.toml.example pre-settled by 04; proof docs/verification/harness-ops-13-doc-tidy/proof-of-done.md)

## Dependencies

- 01 done (resolver). 02, 03, 08 depend on 01, independent of each other → parallel wave after 01.
- 04 depends on 01 (resolver reads the reconciled manifest). 05 depends on 04 (stable interface + adopt repoint). 06 depends on 05 (project override + adopt). 07 depends on 05+06 (documents the final contract).
- Track B is mostly independent of Track A. 09 (integrity, gate) is standalone. 10, 11 are independent doc-moves-with-repoint. 12 (root-slim) is the biggest B item. 13 depends on 09 + 11 (its README refresh must reflect the final tree).
- **Cross-track collision (advisor P5 #2): `lib/adopt.sh:72-83` is edited by BOTH 05 (Track A, stable-interface) and 12 (Track B, root-slim).** They are NOT fully parallel. Land 05 before 12, or the second-to-merge rebases and reconciles that block by hand (auto-bottom-up does not detect file-level overlap). Every other file is disjoint across tracks.

## Assumptions (front-loaded)

- Config-read timing = HYBRID: commands/feature libs read at invocation; hot spine hooks never source the resolver (keeps the hooks-only kit.toml lint green). Locked in the brief.
- Precedence: explicit env var > project `.kit.toml` > kit-root `kit.toml` > hardcoded default. Locked.
- Track B canonical for divergent proofs = verification/ is the home; pick the fuller version per slug (Han, 2026-07-06).
- Terminus = build + merge (internal tooling; no deploy/UAT gate). Stated intentionally.
- 09 is tagged `gate` because the per-slug canonical pick is a content-integrity judgment a human should eyeball; every other sub-goal is `auto`.

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read _ pr; do
      gh pr view "$pr" --json state,reviewDecision,statusCheckRollup
    done
