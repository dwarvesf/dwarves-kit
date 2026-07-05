Objective: dwarves-kit becomes the MIDDLE-LEVEL composable toolkit (a toolbox you install a-la-carte, NOT a monolith): standalone per-subsystem `<subsystem> <verb>` commands, lib-vs-tools retired into subsystem modules, enablement by install/wire + a light `kit.toml [modules]` manifest, the observability domain an event-sourcing split (append-only ledger = SoT; `stats` = stateless projection, renamed from ledger-observatory, over a configurable KIT_LEDGER_DIR), every module documented+wired, operate-contract + the three scaffolders reconciled. Scaffold: _meta/megagoals/kit-modularity/ (ROADMAP.md = SoT + ## Assumptions; goals/01..07; research/2026-07-05-kit-modularity-design.md = BINDING A-G). You own ONLY this scaffold.

RUN CONTRACT: ops-toolkit _meta/megagoals/OPERATE.md BINDING.

PRECONDITION MET: kit-foldin (ID-276) SHIPPED+archived; real state grounded 2026-07-05 (lib/ subsystem dirs EXIST + ~34 lib-root symlink aliases; tools/ = ledger-observatory/session-*/skill-curator/plugin-check; hooks renamed). First action: confirm no drift, then dispatch SG-01 (dirs already exist , see the 01 absolute below).

RUN MODE: subagent-delegate; THIN CONDUCTOR, never run a sub-goal inline. HOME: dwarves-kit (SG-07 also touches ~/.claude/skills = dotfiles). Conductor owns ALL mega-dir bookkeeping (workers report, you transcribe). CROSS-REPO: kit sub-goals use HAND-MADE worktrees (git -C <kit> worktree add), NEVER Agent isolation:worktree. WORKER HYGIENE: fixtures in mktemp/tests only; a worker NEVER git add/commit/init in a real checkout; tests point KIT_LEDGER_DIR at mktemp.

ORDER (gh-sequential, LINEAR): 01 module-collapse (first, opus) -> 02 stats-plane (opus) -> 03 subsystem-commands (wraps `stats`, needs 02) -> 04 install-wire (needs 03) -> 05 operate-contract + 06 docs (parallel) -> 07 reconcile (LAST, HELD). F (completeness bar) = a per-module GATE in 01/02/03 (usage doc + firing point per module; 06 audits docs). C (team-mode) = reserved [modules] slot (04) + philosophy para (06), PARKED. H (Hermes) = SEPARATE mega.

TIER 0: dwarves-kit kit-adopted: read AGENTS.md+WORKFLOW.md, lane-classify per sub-goal, record gate-ledger phases before push (drive lanes via lib/ + gate-ledger, NOT /kit:* which binds to cwd).

TIER 1: SKIP grill/think/design; framing done (design note A-G + DECISIONS). Middle-level/stats-name/lib-vs-tools all DECIDED.

TIER 3: build to the NAMED Proof per goal file. OVER-TEST 01/02/03/04. Absolutes: 01 NO ALIAS SHIMS (Han) , kit-foldin left ~34 lib-root symlink aliases; REMOVE all + update every call-site to the real subsystem path via one LIB_ROOT anchor; NC `find lib -maxdepth 1 -type l` EMPTY + full suite identical + orchestrate/mega-merge e2e; 02 event-sourcing , `stats` persists NOTHING (NC: no derived ledger written), one KIT_LEDGER_DIR/consumer, honest-zero, read-side never carries `-ledger`; 03 standalone commands work if you DELETE the optional `kit` dispatcher; 04 spine-only install wires ONLY the spine (un-opted hook NEVER enters settings.json); 05 grep-audit AGENTS/WORKFLOW = zero stale; 06 per-module doc audit = zero gaps; 07 all three scaffolders zero-stale + never-diverge mirror re-passes.

MERGE: gh-sequential, auto-bottom-up, gated-final. 07 = HELD final PR (edits Han's authoring skills, do NOT merge). Never merge red CI or CHANGES_REQUESTED; audit/merge each PR from its own repo.

CONVERGENCE GATE (terminus = build+merge, non-deployable): full suite green on merged master + spine-only temp-HOME install wires only the spine + every module has a doc+firing point + the 3 scaffolders pass the mirror check + /kit:verify + review + advisor P5/P6 + recheck. Write+render RUN_REPORT.md. Before complete: SPEC-005 LAB_LOG on 07's branch + flip the backlog row.

STOPS: precondition unmet (kit-foldin not shipped), the held final PR 07, all-blocked-unchanged, token budget. Fingerprints in NOTES ## Active blockers; Event log gets the final summary once. One PR per sub-goal; a checked box carries PR #N.
