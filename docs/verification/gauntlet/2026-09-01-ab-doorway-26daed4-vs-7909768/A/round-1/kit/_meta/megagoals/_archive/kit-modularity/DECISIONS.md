# DECISIONS, kit-modularity (WARM: durable invariants, append-only)

## 2026-07-05 SCAFFOLD (from the kit-modularity design note, decisions A-G)

**Origin + binding.** Executes `research/2026-07-05-kit-modularity-design.md` (decisions A-G). That note is BINDING for the WHY; this scaffold is the HOW. Decisions map: A -> SG-03, B+C -> SG-04, D -> SG-05+SG-06, E -> SG-02, F -> a per-module GATE in 01/02/03 (not a sub-goal), G -> SG-07, H -> a SEPARATE later mega (not here).

**Middle-level invariant (Han, rejected "kit as product").** Standalone per-subsystem commands, install/wire a-la-carte, no uber-binary, no central runtime feature-registry. A consumer installs the spine + only the modules they want. The kit must never feel like one big appliance.

**Event-sourcing invariant (E).** Append-only ledger = the ONE source of truth (write plane, harness-internal writers). `stats` = stateless projection (read plane), recomputable, renamed from `ledger-observatory` (read-side NEVER carries `-ledger`, Han's naming rule). A derived ledger is a VIEW, never persisted as a second source , that is the board-mirror drift bug (row-hash git-wins / refuse-all-on-missing-snapshot) by construction avoided. RUN_REPORT stays the mega flow's closing verb, not a `stats` subcommand.

**One ledger root (E2).** `KIT_LEDGER_DIR` via `--repo-root`/`_repo_root()`, essential-tier config (not a `[modules]` toggle), one-root-per-consumer (never per-stream), mktemp in tests.

**lib-vs-tools is packaging-accident, not architecture (E3, Han: "they're the same").** Retire it into self-contained subsystem modules. "tool" vs "lib" describes a module's SURFACE (leaf/human vs internal-helper), not its LOCATION. Only `agents`/`commands`/`hooks`/`skills` stay top-level (loader-mandated). Keep the top dir name `lib/` (renaming touches every call-site) unless a neutral `modules/` clearly wins , decide in SG-01.

**NO ALIAS SHIMS , proper restructure (Han directive 2026-07-05, INVARIANT).** kit-foldin's SG-01 took the cheap route: it moved files into subsystem dirs but left ~34 SYMLINK ALIASES at `lib/` root (`lib/board.sh -> board/board.sh`, `lib/gate-ledger.sh -> gate/gate-ledger.sh`, ...) so call-sites did not have to change. Han rejects scattered aliases. So kit-modularity SG-01 does the PROPER restructure: REMOVE every lib-root alias, and UPDATE every call-site to the real subsystem path via ONE `LIB_ROOT` anchor (each script computes `lib/` root from `BASH_SOURCE`, references `$LIB_ROOT/<subsystem>/<file>.sh`). No per-file wrapper, no dispatcher (that is aliases by another name). Gate: `find lib -maxdepth 1 -type l` EMPTY + full suite + orchestrate/mega-merge run e2e. This makes SG-01 a HIGH-blast-radius call-site refactor (opus, over-tested), not a cheap move , the cost Han is choosing for a clean tree.

**Module completeness bar (F) = a per-module GATE, not a phase.** Each module's PR carries (1) a co-located usage doc + (2) a named workflow firing point (a lane / `/kit:*` / hook / documented cron-human entry). No orphan modules. Adopts the parked ID-273 kit-wiring audit's firing-point discipline. SG-06 audits the doc half across all modules; the firing half is per-module in 01/02/03.

**Never-diverge (G).** `plan-for-goal` / `plan-for-mega-goal` / `/kit:mega` must agree after the surface changes; SG-07 re-runs the mirror check (the runner-fastpath SG-01/02 byte-identical-block + checklist-row contract), spanning dotfiles (skills) + dwarves-kit (`/kit:mega`).

**Precondition (MET 2026-07-05).** kit-foldin (ID-276) SHIPPED + archived (dwarves-kit #183-189, ops #720/#721; `_meta/megagoals/_archive/kit-foldin/`). This scaffold was drafted AHEAD of that on Han's direction, then GROUNDED against the real merged state once Han flagged kit-foldin had already run: `lib/` subsystem dirs EXIST (board/classify/gate/goal/queue/session/spec/telemetry) + ~34 flat shim/helper files at lib root; `tools/` = ledger-observatory/session-observe/recall/intel/skill-curator/plugin-check; hooks renamed backlog-stage/citation-guard/context-hints/harvest. **Consequence: SG-01 REFRAMED** , the subsystem dirs already exist, so SG-01 folds `tools/` INTO them + resolves the ~34 flat shims, it does NOT create dirs. The earlier "03/07 provisional / 04 best-guess module list" hedges are RESOLVED against real names. LESSON (Han caught it): verify actual merged state (git + real dirs) before executing, never operate off a stale scaffold snapshot , the whole kit-foldin re-scaffold this session was redundant because the mega had already shipped on origin.

## 2026-07-05 SG-08 outcomes (mega-status, PR #194 merged 5e7ca71)

**`mega` = bare orphan `lib/mega.sh`, NOT a subsystem dir, NOT a `board` subcommand.** Single verb (`status`) today -> SG-03's rule reserves grouped `lib/<x>/<x>.sh` dispatchers for 2+-verb subsystems, so it stays bare (adopt/explain/pitch/precedent/mega precedent). Not under `board` because `mega status` reconciles a CODE repo's git truth against a THIRD location (wherever `_meta/megagoals/` lives), a wider consumer-config shape than board's single-repo `_meta/BACKLOG.md` domain. If `mega` grows a 2nd verb, promote to a grouped entry then.

**Drift-class taxonomy (settled).** OK (`[x]`+merged PR), CLAIM-UNVERIFIED (`[x]`+PR not merged, the green-wash guard), MERGED-UNCHECKED (`[ ]`+PR merged, roadmap lagging), STALLED (`[ ]`+branch 0 commits vs base+NO open PR), WIP (`[ ]`+commits OR an open PR), PENDING (`[ ]`+nothing), INFO (`[~]` rehomed, quiet). CRITICAL nuance: 0-commits + an OPEN PR = WIP, never STALLED (an in-flight worker must not false-positive as stalled , the conductor's own lesson from the SG-02 stale-snapshot this run).

**`--with-mega` opt-in, never default.** The mega rollup rides an opt-in `--with-mega` flag on board render, NOT the default output , protects board's byte-identical non-regression NC and avoids making every plain `board render` slow/network-dependent (real `gh` calls). Commit-count truth uses the branch ref (`rev-list --count base..branch`, local then origin), not a literal worktree walk , survives worktree cleanup after merge. Branch name read from the sub-goal goal file's `**Branch:**` line (authoritative), not guessed.

## 2026-07-05 SG-04 outcomes (install-wire, PR #193 merged bc5bf56)

**Spine vs optional split (settled, reconciled against the real tree).** SPINE (wired unconditionally): safety-gate, ship-gate, spec-drift-guard, secrets-guard, commit-format, anti-rationalization (the SDD ship discipline). OPTIONAL, opt-in via `install.sh --with <a,b,c>`: board, session, advisor, cosmetic (hook-bearing) + queue, stats, quiz_gate, weekend_batch, bridge (hookless modules). team_mode = reserved slot, false, not installable.

**`kit.toml [modules]` = per-CONSUMER install artifact, NOT a repo file, NOT a runtime registry (Decision B enforcement).** install.sh WRITES it into the consumer's install to record enabled modules + tier for reproducible re-install; it is the ONLY thing that touches it. A standing CI lint (`grep -rl kit.toml hooks/` must be empty) prevents a future hook from reading the manifest at runtime (the named anti-pattern: manifest-as-runtime-registry). So there is no repo-root kit.toml to look for , it lives in the consumer.

**Existing-consumer migration = additive/idempotent.** Re-running install.sh never retroactively un-wires a previously-wired hook (ops-toolkit/console-labs/family-office already ran the old all-hooks install). Trimming to spine-only is an explicit `--prune --with <modules>` opt-in, never a silent fleet-wide change.

**test.yml co-edit hazard (for merge).** SG-04 added test-install-modules.sh to `.github/workflows/test.yml`. SG-08 (parallel) also edits test.yml , expect a conflict when 08 merges; resolve by keeping BOTH test additions.

## 2026-07-05 SG-03 outcomes (subsystem-commands, PR #192 merged b2e8717)

**Grouped standalone entries = only 2+-verb subsystems (ponytail).** Built: gate/classify/spec/goal/session (thin `lib/<x>/<x>.sh` case-dispatchers, board/orchestrate shape, exec the sibling). board+stats already had the shape. Bare (untouched): adopt/explain/pitch/precedent/skill-curator/plugin-check.

**`kit` uber-dispatcher SKIPPED (Middle-level invariant enforcement).** 7 named commands is too small to earn a `kit list`; no MANIFEST/registry convention exists to back it without hardcode-drift; building it risks becoming the required-front-door "appliance" seam Han rejects. Each entry's own `--help` is the discovery surface. If a future consumer count makes discovery hard, revisit , but never as a required front door.

**Ship-gate proof-of-done PATH pattern (LESSON for every future kit sub-goal, esp. the parallel 04/05/06/08).** The ship-gate greps specifically for `docs/verification/.+\.md` OR `*/proof-of-done.md`. SG-01/SG-02 satisfied it only INCIDENTALLY (their call-site sweeps happened to touch pre-existing compliant `docs/verification/*.md`). A surgical diff that touches no such file will hit the gate cold. So a subsystem-command-shaped sub-goal must ship TWO proof files: the rich table-first `docs/proof/<slug>.md` AND a `docs/verification/<slug>.md` (flat back-compat shape) so the gate sees it. Inject this into parallel-wave worker prompts.

## 2026-07-05 SG-02 outcomes (stats-plane, PR #191 merged 053c381)

**Ledger substrate contract (`lib/ledger/ledger.sh`).** CLI: `ledger append <stream> <text...>` / `ledger read <stream>` / `ledger root`. Sourced: `ledger_append` / `ledger_read` / `ledger_root`. `<stream>` = root-relative path (`runs/<rid>.log`, `proof-overrides.log`); append = one line, newlines collapsed. gate-ledger.sh + proof-ledger.sh route their writes through it. This is the ONE place row-append + location live (DRY).

**KIT_LEDGER_DIR precedence (E2, settled).** `$KIT_LEDGER_DIR` (canonical, wins) -> `$DWARVES_KIT_LOG_DIR` (back-compat alias) -> `${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs`. Set-but-EMPTY `KIT_LEDGER_DIR` = clean fatal (the real silent-wrong-path footgun); genuinely-UNSET falls back (erroring there would break every existing consumer). One root per consumer.

**Persistent DuckDB cache REMOVED (event-sourcing enforcement, not scope creep).** `stats` now materializes `:memory:` per invocation , mandatory to satisfy the no-persisted-projection invariant. Consequence: source-quality warnings emit to stderr on every invocation (was once-at-cache-build); a standing anti-drift CI grep-lint asserts stats opens only `:memory:` so a future "perf cache" cannot silently re-introduce a second source of truth.

**Homeless-tools home (extends SG-01 orphan precedent).** skill-curator + plugin-check -> bare orphan module DIRS at `lib/` root (`lib/skill-curator/`, `lib/plugin-check/`): each is a single cohesive tool with no sibling to form a subsystem; a synthetic `meta/` subsystem would be premature abstraction. session-observe/recall/intel -> `lib/session/` (shared transcript domain + parser). `-type l` at lib root stays empty.

**Historical-doc scope (rename boundary).** Renamed all LIVE/read-side refs (code, entry `stats`, env `STATS_*`, skill, tool.toml, live usage docs, kit-command prose). Left FROZEN provenance unchanged (the stats module's own `docs/megagoals/{harness-observatory,ledger-observatory}/` + `docs/specs/SPEC-126..137` narratives) , archival records of past builds, not read-side identifiers. CAVEAT: conductor caught one MISSED read-side label (`anomalies.py:689` output string) that slipped this boundary , swept in-place. SG-06/SG-07 audits should re-grep live `.py`/`.sh`/README surfaces (not just paths/identifiers) for stray `ledger-observatory` labels.

## 2026-07-05 SG-01 outcomes (module-collapse, PR #190 merged cb64f15)

**Top-dir name = `lib/` (kept, not `modules/`).** Renaming re-touches every call-site a second time for zero behavioral gain; `lib/` is the design-note E3 default and `modules/` did not clearly win. Settled.

**Orphan reals stay bare at `lib/` root.** `adopt`/`explain`/`pitch`/`precedent` are single-purpose orphans with no subsystem; per the design note they stay bare standalone scripts at `lib/` root. The load-bearing NC is `-type l` (symlinks only), so orphan REAL files at root are compliant , the invariant is "no alias shims", not "nothing at root".

**LIB_ROOT resolution mechanism (the anti-alias fix).** Each script computes `LIB_ROOT` (the `lib/` dir) from its own `BASH_SOURCE` and references cross-subsystem siblings as `$LIB_ROOT/<subsystem>/<file>.sh`. ONE mechanism, zero scattered aliases. Removing the aliases exposed 6 sites that computed repo-root as `$DIR/..` assuming root-alias invocation (dirname=`lib/`): KIT_ROOT/SCRIPT_ROOT/KIT/BACKLOG_FILE/TASK_TYPE_REGISTRY + `proof-table-gen.py`'s gate-ledger resolver , all needed an extra `/..` post-move. Over-test caught a 7th: `lane-telemetry.sh`'s `$KIT_LIB/gate-ledger.sh` was `2>/dev/null`-guarded and silently mis-flagged complete runs. LESSON: removing aliases surfaces latent path assumptions; the suite + e2e NCs are what catch them.

**tools/ physical fold DEFERRED to SG-02 (scope-boundary call, ACCEPTED).** SG-01's Done= is the 4 NCs + F-bar (all met); the tools/ fold was an Outcome-step, not a Done= criterion. Folding `ledger-observatory` here would double-churn against SG-02's `stats` rename, and skill-curator/plugin-check/session-* need a home decision. Reassigned to SG-02 (conductor addendum in goals/02 ## Notes). The mega terminus "lib-vs-tools retired" now completes at SG-02, not SG-01.

**Machine note:** this box's `find` is a `rtk find` shim that mis-parses `-type l` when not piped. Verify symlink NCs with `/usr/bin/find` or python, not bare `find`.

**Reused runner-fastpath patterns.** Hand-made worktrees for kit sub-goals (`git -C <kit> worktree add`, NEVER Agent isolation:worktree); conductor-transcribes bookkeeping; OPERATE.md run contract; ship-gate proof-of-done; over-test behavioral sub-goals (01/02/03/04) with named NCs; gated-final (SG-07 held).
