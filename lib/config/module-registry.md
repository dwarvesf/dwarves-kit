# lib/config/module-registry.md , module<->leg + env<->key registry (SPEC-198)

Machine home pinned by ADR-0034 decision 3: ONE checked-in file carrying both the
module -> primary-leg table (decision 3's authoritative assignment) and the
env<->key rows (decision 4's `bin/config` read surface). Parsed by
`lib/config/config.sh` (the `bin/config` engine) and by
`tests/test-config-registry.sh` (the drift + completeness lints). Both readers are
line-oriented `awk`/`grep` over these markdown tables , this file is NOT a second
TOML reader; VALUE resolution for any row still goes through
`lib/config/kit-config.sh` (`kit_config_get` / `kit_config_root` /
`kit_config_project` / `_kit_toml_get`), the ADR-0034 decision-4 fence
("`lib/config/kit-config.sh` stays the ONLY reader of TOML").

Generated-from-nothing-else: seeded from a fresh sweep (`rg -ohE
'\$\{?(KIT|WAVE|QUEUE|MEGA|CC_SI|PROSE_RAG|MONEY_GATE|TIER4|MUX|TMUX|PANE|TERMINAL|STATS|CC_BACKLOG|HARVEST|BACKLOG|DWARVES)[A-Z_]*'
lib hooks bin | sort -u`), then every hit's reader + default verified at its
source by hand (no pre-existing table existed before this file), plus every
`kit.toml`-declared key (whether or not it has an env override), so `bin/config
list` can render "every declared key," not just the env-shaped subset.

## Module legs

Authoritative assignment per ADR-0034 decision 3. Every `KIT_KNOWN_MODULES` entry
(`install.sh:170`, 12 modules) has exactly one row. `team_mode` is excluded from
`KIT_KNOWN_MODULES` itself (install.sh hard-rejects it until team-mode ships), so
it is not a row here either , the completeness rule is scoped to
`KIT_KNOWN_MODULES`, not to every `[modules]` line in `kit.toml`.

| Module | Primary leg | Notes |
|---|---|---|
| board | Specify | spanner: input side (Specify) + staging/promote (Learn) |
| session | Observe | spanner: capture side (Observe) + harvest (Learn) |
| advisor | Govern | |
| cosmetic | (none) | orthogonal to the loop; statusline |
| queue | Execute | |
| stats | Observe | |
| quiz_gate | Execute | |
| weekend_batch | Learn | |
| bridge | Observe | presentation side; board mirror to the Hermes cockpit |
| worktree | Execute | |
| money_gate | Govern | |
| prose_rag | Learn | **deviation, not in ADR-0034's decision-3 table** (checked: `grep -n prose_rag docs/decisions/0034-harness-loop-taxonomy.md` has zero hits in the leg table). Assigned Learn by this sub-goal's own judgment: prose-rag is a recall/retrieval read over the user's own accumulated corpus (til/research/learned-ledger), the same read-side shape as the Learn leg's other members, not an Observe-class run-telemetry capture. Flagged for Han; a later ADR-0034 amendment may reassign it. |

## Env <-> key registry

One row per declared knob. `Env var` is `-` for a `kit.toml`-only key (no env
override exists); `kit.toml key` is `env-only` for a var with no TOML backing.
Every row has at least one of the two populated. `Status` reuses `kit.toml`'s own
tags (`[impl] [design] [reserved] [consumer]`); an env-only var is `[impl]` iff a
real reader consumes it today (all rows below are, except where noted).

### config (the resolver's own bootstrapping knobs + the kit install root)

| Env var | kit.toml key | Default | Status | Module | Doc |
|---|---|---|---|---|---|
| DWARVES_KIT | env-only | `$HOME/.claude/dwarves-kit` | [impl] | config | The kit install root; `KIT_CONFIG_ROOT`'s own fallback. |
| KIT_CONFIG_ROOT | env-only | `${DWARVES_KIT:-$HOME/.claude/dwarves-kit}` | [impl] | config | Override where the kit-root `kit.toml` itself is read from (this IS the resolver's own bootstrap knob; it cannot have a `kit.toml` key). |
| KIT_PROJECT_ROOT | env-only | `$PWD` | [impl] | config | Override which project's `.kit.toml` is consulted. |
| DWARVES_KIT_DEBUG | env-only | `0` | [impl] | (none) | Verbose hook/command debug logging; cross-cutting, not config-subsystem-specific. |

### Data-plane keys ([ledger] section + the durable telemetry root)

| Env var | kit.toml key | Default | Status | Module | Doc |
|---|---|---|---|---|---|
| KIT_LEDGER_DIR | ledger.location | (none; canonical) | [impl] | ledger | The durable run-telemetry/ledger root override; wins over `DWARVES_KIT_LOG_DIR` and the toml key. Set-but-empty is a FATAL error, never silent fall-through. Two-env special case (see `DWARVES_KIT_LOG_DIR` below); the authoritative precedence lives in `lib/telemetry/kit-log-dir.sh::kit_resolve_log_dir` , this row resolves independently under the generic 4-level model, it does not replay that function's exact tie-break. |
| DWARVES_KIT_LOG_DIR | ledger.location | (none; alias) | [impl] | ledger | Back-compat alias, precedence #2 under `KIT_LEDGER_DIR`, over the toml key. Pre-SPEC-182 name for the same root; kept for every existing test pin + the live corpus. |
| - | ledger.location | `"shared"` | [impl] | ledger | The toml-level default consulted only when neither env var above is set: `"shared"` -> XDG (`${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs`); `"isolated"` -> `$PWD/.kit/logs`; any other value = an explicit path. |
| - | ledger.telemetry | `true` | [design] | ledger | Comment says `[impl]` in `kit.toml`, but no reader was found (grepped `ledger.telemetry` and `kit_config_get ledger` across lib/hooks; only the kit-config.sh selftest matches, not a real consumer) , retagged `[design]` here; flagged as a `kit.toml` status-tag drift for the lead, not fixed in this sub-goal (no kit.toml schema changes, no resolver changes, scope fence). |
| KIT_DELIVERY_RATIO_WARN | ledger.delivery_ratio_warn | `3` | [impl] | gate | Proof-to-real line ratio that triggers a delivery (THIN-WARN) warning. |
| KIT_DELIVERY_REAL_FLOOR | ledger.delivery_real_floor | `40` | [impl] | gate | Real-work line-count floor; below it + a high proof ratio flags a run THIN-WARN. |

### STATS_* source vars (explicit per goal instruction; every one has NO hardcoded fallback , unset means "skip this source," not "use a default path")

| Env var | kit.toml key | Default | Status | Module | Doc |
|---|---|---|---|---|---|
| STATS_TIDE_DB | env-only | **no-default-consumer** | [impl] | stats | ops-toolkit-specific: path to tide's sqlite state db. Unset -> `config.tide_db_path()` returns `None` -> that source's table renders empty, skip-safe (no hardcoded fallback path). |
| STATS_TGCLEANUP_DIR | env-only | **no-default-consumer** | [impl] | stats | ops-toolkit-specific: root of the tg-cleanup tool's data. Unset -> `None` -> that source is skipped. |
| STATS_LEARNED_MD | env-only | **no-default-consumer** | [impl] | stats | ops-toolkit-specific: path to the learned-ledger markdown file. Unset -> `None` -> that source is skipped. |
| STATS_REPOS | env-only | **no-default-consumer** | [impl] | stats | Comma-separated repo ROOTs for `rejected_findings` / `stats review-yield` (SPEC-137). Unset -> `""` splits to `[]`, zero repos scanned. |
| STATS_GIT_REPO_DIR | env-only | (kit repo root) | [impl] | stats | Where `stats` looks for its own git history; kit-internal, computed dynamically, never hardcoded. |
| STATS_MEMORY_REPO_DIR | env-only | (kit repo root) | [impl] | stats | Where `stats` looks for memory-lens data; kit-internal, computed dynamically. |
| STATS_SESSIONS_DIR | env-only | `~/.claude/projects` | [impl] | stats | Claude Code's own session-transcript dir; host-generic. |
| STATS_SECRET_GUARD_LOG | env-only | `~/.cache/claude-secret-guard.log` | [impl] | stats | The secret-guard hook's audit log path; host-generic. |
| STATS_MEMORY_PROJECTS_ROOT | env-only | `~/.claude/projects` | [impl] | stats | Root `stats` scans for cross-project memory-lens data; host-generic. |
| CC_BACKLOG_BACKLOG | env-only | (none) | [impl] | stats | ops-toolkit-specific: read-only backlog file `--propose` dedups new findings against. Unset -> dedup source unavailable. |
| CC_BACKLOG_STAGING | env-only | (none) | [impl] | stats | ops-toolkit-specific: the feedback loop's ONLY write target. Unset -> `--propose` errors "no destination configured" if it has a real proposal to stage. |
| STATS_DB_REMOVED | (none , not a real config var) | n/a | n/a | n/a | **Registered, not excluded** (scope fence: never delete an undocumented var without registering it first): grepped `lib/stats/src/stats/{config,materialize,adapters}.py` , zero references. Only appears in `lib/stats/tests/*.sh` as an exported scratch path used purely for test-fixture cleanup (`rm -f "$STATS_DB_REMOVED"`). Not read by any product code path; the drift lint allowlists it (see Allowlist below) as dead/vestigial rather than a live knob. |

### mega (WAVE_CAP / TIER4_CLOSE / MULTIPLEXER / merge posture)

| Env var | kit.toml key | Default | Status | Module | Doc |
|---|---|---|---|---|---|
| WAVE_CAP | mega.wave_cap | `2` | [impl] | mega | Max concurrent sub-goals admitted per wave. |
| TIER4_CLOSE | mega.tier4_close | `1` (truthy) | [impl] | mega | Enables the Tier-4 mega-close auto-verify+hold sequence (SPEC-118). |
| MULTIPLEXER | mega.multiplexer | `0` (off) | [impl] | mega | Opt-in wave pane multiplexing (SPEC-119); only engages when a wave actually admits >=1 sub-goal concurrently. |
| MEGA_MERGE_POSTURE | mega.mega_merge_posture | `"auto-to-final"` | [impl] | mega | `"auto-to-final"` or `"per-pr-review"` merge posture. |
| - | mega.merge_autonomy | `"gated-final"` | [design] | mega | `"gated-final"` or `"full-auto"`; no env override found. |
| - | mega.default_model | `"sonnet"` | [design] | mega | GLOBAL model fallback; real control is the per-sub-goal goal-file `Model:` field. Precedence: goal-file `Model:` > project cfg > this default. |
| - | mega.over_test | `false` | [design] | mega | GLOBAL scaffold-rigor default; real control is per-sub-goal `Done-mode: over-test` (SPEC-112). |
| MEGAGOALS_ROOT | env-only | (none) | [impl] | mega | Root dir where mega-goal folders live; unset falls through to further path resolution in `lib/mega.sh`. |
| MEGA_MERGE_PR_INFO_CMD | env-only | (none) | [impl] | mega | Override the command used to fetch PR info at merge time; called directly when set. |
| MEGA_MERGE_GATE_LEDGER | env-only | `$LIB_ROOT/gate/gate-ledger.sh` | [impl] | mega | Which `gate-ledger.sh` `mega-merge.sh` shells out to. |
| MEGA_MERGE_GH | env-only | `gh` | [impl] | mega | Override the `gh` binary/wrapper used for PR ops at merge. |
| BACKLOG_LIB | env-only | `$LIB_ROOT/board/backlog.sh` | [impl] | mega | Which `backlog.sh` `orchestrate.sh` shells out to for wave admission reads. |
| PANE_VIEWER | env-only | `auto` | [impl] | mega | Which terminal-viewer surface to push-open on wave spawn (SPEC-119). |
| TMUX_CMD | env-only | `tmux` | [impl] | mega | Override the tmux binary `orchestrate.sh` drives for wave panes. |
| TMUX_SESSION | env-only | (none) | [impl] | mega | Override the tmux session name for a mega run; unset falls to `_mux_session_name` derivation. |
| TIER4_CORPUS | env-only | `""` (empty) | [impl] | mega | Override the corpus path used by Tier-4 close checks. |
| WAVE_MERGE_CMD | env-only | `$LIB_ROOT/goal/mega-merge.sh merge` | [impl] | mega | Override the merge command a completed wave invokes. |
| WAVE_MERGE_LANE | env-only | `full` | [impl] | mega | Override the risk lane used at wave-merge time. |
| WAVE_POLL_SECS | env-only | `0.2` | [impl] | mega | Polling interval while waiting for wave admission. |

### queue (single-goal driver, `lib/queue/queue.sh`)

| Env var | kit.toml key | Default | Status | Module | Doc |
|---|---|---|---|---|---|
| TERMINAL_MUX | env-only | `tmux` | [impl] | queue | Which multiplexer the single-goal queue drives; `tmux` is the only value supported today. |
| MUX_CMD | env-only | `$TERMINAL_MUX` | [impl] | queue | Override the multiplexer binary. |
| QUEUE_MUX_SESSION | env-only | `dk-queue` | [impl] | queue | tmux session name the queue drives. |
| QUEUE_CLAUDE_CMD | env-only | `claude` | [impl] | queue | Override the Claude CLI binary the queue launches. |
| QUEUE_CLAUDE_FLAGS | env-only | `--dangerously-skip-permissions` | [impl] | queue | Flags passed to the launched Claude CLI. |
| QUEUE_POLL_SECS | env-only | `15` | [impl] | queue | Polling interval for queue status. |
| QUEUE_TIMEOUT_SECS | env-only | `7200` | [impl] | queue | Max time a queue item may run. |
| QUEUE_RETRY_SLEEP_SECS | env-only | `1800` | [impl] | queue | Sleep before retrying a failed queue item. |
| QUEUE_STARTUP_SECS | env-only | `20` | [impl] | queue | Grace period for the launched session to start. |
| QUEUE_SUBMIT_SETTLE_SECS | env-only | `2` | [impl] | queue | Settle time after submitting a prompt. |
| QUEUE_BOARD_CMD | env-only | `board` | [impl] | queue | Override the board CLI command name. |
| QUEUE_JOURNAL | env-only | `${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}/queue-journal.tsv` | [impl] | queue | Path to the queue's TSV journal. |
| QUEUE_ALLOWED_POINTER_GLOB | env-only | `_meta/megagoals/* .claude/goals/*` | [impl] | queue | Glob allowlist for pointer files the queue may submit. |

### board

| Env var | kit.toml key | Default | Status | Module | Doc |
|---|---|---|---|---|---|
| BACKLOG_FILE | env-only | `$BACKLOG_DIR/../../_meta/BACKLOG.md` | [impl] | board | Override which `BACKLOG.md` the CLI reads/writes. |
| BACKLOG_ID_RE | env-only | `[A-Z]+-[0-9]+` | [impl] | board | Regex for what counts as a backlog item ID. |

### session (incl. session-intel / skill-curator, prefix `CC_SI_*`)

| Env var | kit.toml key | Default | Status | Module | Doc |
|---|---|---|---|---|---|
| CC_SI_STATE_DIR | env-only | `$HOME/.claude/skill-curator` | [impl] | session | Root of the skill-curator tool's state (ledger, lock, log, config). |
| CC_SI_PROPOSALS_DIR | env-only | `$HOME/.claude/skill-proposals` | [impl] | session | Where drafted skill proposals land. |
| CC_SI_SKILLS_DIR | env-only | `$HOME/.claude/skills` | [impl] | session | Where curated/promoted skills are written. |
| CC_SI_CONFIG | env-only | `$CC_SI_STATE_DIR/config.toml` | [impl] | session | skill-curator's own config file (a separate file, not `kit.toml`). |
| CC_SI_SETTINGS | env-only | `$HOME/.claude/settings.json` | [impl] | session | Which `settings.json` the skill-curator installer patches. |
| CC_SI_MEMORY_LEDGER | env-only | `""` | [impl] | session | Path to the learning ledger surface.sh cross-references; feature is off if unset. |
| CC_SI_CURATOR_CMD | env-only | (real `claude -p`) | [impl] | session | Override the curator's model-invocation command (test injection point). |
| CC_SI_REVIEWER_CMD | env-only | (real `claude -p`) | [impl] | session | Override the async reviewer's model-invocation command. |
| DWARVES_KIT_SESSION_MARKER | env-only | `/tmp/.dwarves-kit-session-start` | [impl] | session | Path of the session-start marker file. |

### gate

| Env var | kit.toml key | Default | Status | Module | Doc |
|---|---|---|---|---|---|
| - | gate.understanding_gate | `true` | [impl] | gate | `hooks/anti-rationalization.sh` (ADR-0031). Always-on today; no env override exists , exposing an on/off toggle is new work. |
| DWARVES_KIT_PRINT_CDDIR | env-only | `0` | [impl] | gate | Debug: print the resolved cwd/repo-root and exit. |
| KIT_ROOT | env-only | `$SCRIPT_ROOT` | [impl] | gate | Mixed usage: most files compute this internally from `BASH_SOURCE`, not the environment; `lib/gate/proof-table-gen.sh` alone treats it as an operator-settable override, defaulting to `$SCRIPT_ROOT`. |

### prose_rag / money_gate

| Env var | kit.toml key | Default | Status | Module | Doc |
|---|---|---|---|---|---|
| PROSE_RAG_INJECT | env-only | unset (hook inert) | [impl] | prose_rag | The engine's own opt-in master switch for the recall-inject hook , deliberately NOT `modules.prose_rag` (that toggle only gates hook *install*, this gates whether the installed hook actually fires). |
| MONEY_GATE_REPOS | env-only | (unset) | [impl] | money_gate | Colon-separated list of repo names the guard treats as financial; hook is inert (exits 0) without it. |

### modules (install-time manifest, `install.sh:170` `KIT_KNOWN_MODULES`, 12 of 12)

No env var exists for any of these , they are install-time flags recorded in the
consumer's own `kit.toml [modules]` section (an install RECORD, never read at
runtime by a hook per the standing "no runtime manifest read" lint), read at
COMMAND invocation via `kit_config_get modules.<name>`.

| Env var | kit.toml key | Default | Status | Module | Doc |
|---|---|---|---|---|---|
| - | modules.board | `true` | [impl] | board | Enables board's hooks + CLI. |
| - | modules.session | `true` | [impl] | session | Enables session's hooks + CLI. |
| - | modules.advisor | `true` | [impl] | advisor | Enables the advisor's hook-bearing surface. |
| - | modules.cosmetic | `false` | [impl] | cosmetic | Statusline; orthogonal to the loop. |
| - | modules.queue | `true` | [impl] | queue | Hookless; orchestrate/dispatch are commands. |
| - | modules.stats | `true` | [impl] | stats | Hookless read-plane projection. |
| - | modules.quiz_gate | `false` | [impl] | quiz_gate | Hookless; backs `commands/quiz-gate.md`. |
| - | modules.weekend_batch | `false` | [impl] | weekend_batch | Hookless; backs `lib/queue/weekend-batch.sh`. |
| - | modules.bridge | `false` | [impl] | bridge | Hookless; Hermes cockpit mirror. |
| - | modules.worktree | `false` | [impl] | worktree | Hookless; exposes the `worktree-provision` CLI. |
| - | modules.money_gate | `false` | [impl] | money_gate | `money-gate.sh` PreToolUse guard; inert without `MONEY_GATE_REPOS`. |
| - | modules.prose_rag | `false` | [impl] | prose_rag | `prose-rag.sh` recall inject + CLI; dormant without `PROSE_RAG_INJECT=1`. |

### features / team (reserved / design, all inert by contract)

| Env var | kit.toml key | Default | Status | Module | Doc |
|---|---|---|---|---|---|
| - | features.auto_improvement | `false` | [design] | (none) | Read-plane loop over the ledger -> backlog proposals; design-doc only. |
| - | features.learning_ledger | `true` | [consumer] | (none) | Orchestration lives in an external consumer skill (ops-toolkit/dotfiles, SPEC-126); the kit only collects + routes. |
| - | team.actor_identity | `false` | [design] | (none) | `actor=` on gate rows + Owner col + `claim` verb. |
| - | team.attestation | `false` | [design] | (none) | `docs/runs/<rid>.md` branch-riding + `attested-for=`. |
| - | team.ci_recheck | `false` | [design] | (none) | Report-only GitHub Action, always exit 0. |
| - | team.spec_reservation | `false` | [design] | (none) | Pushed spec-stub branch = SPEC-number reservation. |
| - | team.policy | `false` | [design] | (none) | Git-tracked `[policy]`: path fences, guarded verbs. |
| - | team.onboarding | `false` | [design] | (none) | `adopt --with team` -> `TEAM.md`. |
| - | team.pilot | `false` | [design] | (none) | End-to-end UAT (held). |

## Allowlist (internal, excluded from the drift lint)

Tokens the seed regex matches that are NOT real user-facing env vars , either a
script-local computed path (assigned before any read, never inherited from the
environment), a test-fixture-only name, or an unrelated false positive of the
prefix match. The drift lint (`tests/test-config-registry.sh`) treats a hit
against any of these bare tokens as covered without a registry row.

| Token | Why excluded |
|---|---|
| BACKLOG_DIR | `lib/board/backlog.sh`: computed via `pwd`, script-local. |
| BACKLOG_SH | `lib/board/board.sh`: computed path, not env-overridable. |
| CC_BACKLOG_BACKLOG_FIX | `lib/stats/tests/test-deviation-rate.sh`: test-fixture-local, assigned then used in the same file, never read as inherited env. |
| CC_SI_LEDGER | `lib/skill-curator/lib/common.sh`: derived from `CC_SI_STATE_DIR`, not independently env-read. |
| CC_SI_LIB | `lib/skill-curator/lib/common.sh`: computed via `BASH_SOURCE`. |
| CC_SI_LOCK | `lib/skill-curator/lib/common.sh`: derived path. |
| CC_SI_LOG | `lib/skill-curator/lib/common.sh`: derived path. |
| CC_SI_ROOT | `lib/skill-curator/lib/common.sh`: computed `$CC_SI_LIB/..`. |
| KIT | `lib/gate/verif-counts.sh`: computed repo-root var, script-local. |
| KITLOG | `lib/stats/tests/test-defect-correlation.sh`: test-fixture-local. |
| KITTY_WINDOW_ID | The Kitty terminal emulator's own env var; an unrelated false positive of the `KIT` prefix match, not a kit config surface at all. |
| KIT_DIR | `lib/plugin-check/tests/smoke.sh`: test-fixture scratch dir. |
| KIT_KNOWN_MODULES | `install.sh`: a hardcoded bash array literal, never read from the environment. |
| KIT_LIB | Script-local computed dir in most readers (e.g. `lib/telemetry/lane-telemetry.sh`); the real env-overridable cousin is `DWARVES_KIT_LIB` (Python, `lib/stats/src/stats/config.py`), which the bash-oriented seed regex cannot see (no `$` sigil in Python source) , documented here rather than silently dropped: see `lib/stats/README.md`'s own env table for `DWARVES_KIT_LIB`'s default (this repo's own `lib/`, kit-internal). |
| MEGA_SH | `lib/board/board.sh`: computed `$BOARD_DIR/../mega.sh`. |
| PANE_VIEWER_ALLOWED | `lib/queue/orchestrate.sh`: a hardcoded allowlist string, not itself env-read; it validates `PANE_VIEWER`. |
| STATS_DB_REMOVED | Dead/vestigial test-fixture token, see its row above , no product reader exists. Kept OUT of the drift-fail set (registered above instead of silently dropped, per the scope fence) but also allowlisted so the lint does not double-count it as a live undocumented knob. |

## Known gaps (documented, not enforced by this lint , out of this sub-goal's scope)

The seed regex is deliberately the exact reproducible command named in
`_meta/megagoals/harness-loop/goals/08-config-surface.md` step 2, scoped to a
fixed prefix family (`KIT|WAVE|QUEUE|MEGA|CC_SI|PROSE_RAG|MONEY_GATE|TIER4|MUX|TMUX|PANE|TERMINAL|STATS|CC_BACKLOG|HARVEST|BACKLOG|DWARVES`)
and to bash `$VAR`/`${VAR}` tokens only. During verification, real user-facing env
vars were found OUTSIDE that family; they are NOT covered by the drift lint
(a future sub-goal widening the prefix family, or switching the lint's detection
to the structural `${VAR:-`/`[ -n "${VAR:-}" ]` pattern instead of a prefix
allowlist, would close this), but are named here so they are not lost:
`LANE_DEESCALATE_FLOOR` (`lib/classify/lane-classify.sh`), `MONEY_GATE_STRICT`
(`hooks/money-gate.py`, Python-only, no `$` token), `MUTATION_SMOKE_BASE` /
`MUTATION_SMOKE_TEST_CMD` / `MUTATION_SMOKE_RID` / `MUTATION_SMOKE_MAX`
(`lib/gate/mutation-smoke.sh`), `HANDOFF_MAX_LINES` / `WATCHDOG_STALL_SECS` /
`WATCHDOG_POLL_SECS` / `FLIP_LOCK_STALE_SECS` / `FLIP_LOCK_POLL_SECS` /
`VIEWER_CMD` / `STREAM_RETENTION_DAYS` / `NC_SKIP_WAVE_START` /
`NC_SKIP_WAVE_TOKENS` (`lib/queue/orchestrate.sh`), `GOAL_SPECS_DIR`
(`lib/goal/goal-drafts.sh`), `SPEC_RESERVE_FILE` / `SPEC_RESERVE_TTL` /
`SPEC_RESERVE_MAX_TRIES` (`lib/spec/spec-next.sh`), `SIGNIFICANCE_WORTHINESS_MIN`
(`lib/classify/significance-classify.sh`), `HERMES_BIN` (`lib/board/board-mirror.sh`),
`REPO_FILTER` (`lib/learn/weekend-batch.sh`), `OFFLOAD_MAX_TOKENS`
(`hooks/output-offload.sh`), `KIT_WEEKLY_JOBS` (`deploy/macos/kit-weekly`; its
predecessor `INTEL_DIR` retired with the per-job session-intel launcher,
ADR-0034 decision 9).
