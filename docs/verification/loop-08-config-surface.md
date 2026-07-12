# Proof-of-done: SPEC-198 config-surface (harness-loop sub-goal 08)

Spec: `docs/specs/SPEC-198-config-surface.md`. Goal file:
`_meta/megagoals/harness-loop/goals/08-config-surface.md`. Machine, 2026-07-12, branch
`feat/loop-08-config-surface` (based on `origin/docs/loop-01-taxonomy`). Captures below are
post-review (a fresh-context review pass found 2 MAJOR + 2 MINOR defects, all fixed and
regression-tested before this record; see the implementation notes' review-round entry).

## Run table

| # | Check | Command | Result |
|---|---|---|---|
| 1 | `config list` full render, kit-root defaults (no overrides in play) | `env -u PROSE_RAG_INJECT -u MONEY_GATE_REPOS bash bin/config list` | 92 lines, header + 91 declared-key rows. Full text capture below. |
| 2 | `config list`, env + project override fixture | see "Fixture" below | 3 rows shown, each with a DIFFERENT winning provenance level in the SAME render (env / project .kit.toml / kit-root kit.toml) |
| 3 | `config explain <key>`, four-level provenance chain | `bash bin/config explain mega.wave_cap` (fixture env active) | Full chain printed, winner = level 2 (project .kit.toml), shadowed kit-root value shown at level 3 |
| 4 | Drift lint, green | `bash tests/test-config-registry.sh` (AC1) | 0 orphans on the live tree |
| 5 | Drift lint, negative control | `bash tests/test-config-registry.sh` (AC2) | A planted `KIT_TOTALLY_UNREGISTERED_PLANT` in a fixture file IS flagged exactly 1 orphan |
| 6 | Module-leg completeness, green | `bash tests/test-config-registry.sh` (AC3) | 12/12 `KIT_KNOWN_MODULES` entries have a Module-legs row |
| 7 | Module-leg completeness, negative control | `bash tests/test-config-registry.sh` (AC4) | A fake module name (`totally_fake_module`) is correctly absent -- proves AC3 is not vacuous |
| 8 | Resolver selftest, unchanged | `bash lib/config/kit-config.sh selftest` (== `bash tests/test-config.sh`) | 6/6 checks PASS, byte-identical to pre-existing selftest output |
| 9 | Resolver file, zero diff | `git diff --stat origin/docs/loop-01-taxonomy -- lib/config/kit-config.sh hooks/ kit.toml` | Empty output (no diff) -- the ADR-0034 decision-4 fence held: resolver, hooks/, and kit.toml schema are all untouched |
| 10 | Full suite regression | `bash tests/test-meta.sh` | 683/683 passed |
| 11 | Full suite regression | `bash tests/test-hooks.sh` | 453/453 passed |
| 12 | Adjacent regression | `bash tests/test-install-modules.sh`; `bash tests/test-e2e.sh` | 37/37; 20/20 |

Freeze-PNG: not produced. This environment has no headless terminal-screenshot tool available
(no `carbon-now-cli`/equivalent wired into the kit's toolchain, and `bin/config` is a plain-text
CLI with no visual/color output worth rasterizing); the text captures below are the record, per
the goal's own "a freeze-PNG if you can render one headlessly, else note it for the lead."

## #1: `config list` full render (kit-root defaults)

91 declared keys: 58 real env vars from the goal's seed sweep + STATS_* completeness rows +
4 config-bootstrap vars + the kit.toml-only keys (12 modules + gate/mega/ledger/features/team
section keys). Captured with `env -u PROSE_RAG_INJECT -u MONEY_GATE_REPOS` so the runner's own
inherited shell env does not leak non-reproducible `env`-provenance rows into the record; the
controlled fixture in #2 is the reproducible override evidence. VALUE shows the MACHINE default
(the registry cell's backtick literal, annotation stripped -- `config get`'s scripting
contract); a cell with no machine default shows its annotation as-is (`(none; canonical)`,
`**no-default-consumer**`), and a machine-EMPTY default renders `(empty)` in `list` only.

```
KEY                            STATUS     VALUE                          PROVENANCE           MODULE
DWARVES_KIT                    [impl]     $HOME/.claude/dwarves-kit      default              config
KIT_CONFIG_ROOT                [impl]     ${DWARVES_KIT:-$HOME/.claude/dwarves-kit} default              config
KIT_PROJECT_ROOT               [impl]     $PWD                           default              config
DWARVES_KIT_DEBUG              [impl]     0                              default              (none)
KIT_LEDGER_DIR                 [impl]     (none; canonical)              default              ledger
DWARVES_KIT_LOG_DIR            [impl]     (none; alias)                  default              ledger
ledger.location                [impl]     shared                         default              ledger
ledger.telemetry               [design]   (inert: design, no live effect) default              ledger
KIT_DELIVERY_RATIO_WARN        [impl]     3                              default              gate
KIT_DELIVERY_REAL_FLOOR        [impl]     40                             default              gate
STATS_TIDE_DB                  [impl]     **no-default-consumer**        default              stats
STATS_TGCLEANUP_DIR            [impl]     **no-default-consumer**        default              stats
STATS_LEARNED_MD               [impl]     **no-default-consumer**        default              stats
STATS_REPOS                    [impl]     **no-default-consumer**        default              stats
STATS_GIT_REPO_DIR             [impl]     (kit repo root)                default              stats
STATS_MEMORY_REPO_DIR          [impl]     (kit repo root)                default              stats
STATS_SESSIONS_DIR             [impl]     ~/.claude/projects             default              stats
STATS_SECRET_GUARD_LOG         [impl]     ~/.cache/claude-secret-guard.log default              stats
STATS_MEMORY_PROJECTS_ROOT     [impl]     ~/.claude/projects             default              stats
CC_BACKLOG_BACKLOG             [impl]     (none)                         default              stats
CC_BACKLOG_STAGING             [impl]     (none)                         default              stats
STATS_DB_REMOVED               n/a        (inert: n/a, no live effect)   default              n/a
WAVE_CAP                       [impl]     2                              default              mega
TIER4_CLOSE                    [impl]     1                              default              mega
MULTIPLEXER                    [impl]     0                              default              mega
MEGA_MERGE_POSTURE             [impl]     auto-to-final                  default              mega
mega.merge_autonomy            [design]   (inert: design, no live effect) default              mega
mega.default_model             [design]   (inert: design, no live effect) default              mega
mega.over_test                 [design]   (inert: design, no live effect) default              mega
MEGAGOALS_ROOT                 [impl]     (none)                         default              mega
MEGA_MERGE_PR_INFO_CMD         [impl]     (none)                         default              mega
MEGA_MERGE_GATE_LEDGER         [impl]     $LIB_ROOT/gate/gate-ledger.sh  default              mega
MEGA_MERGE_GH                  [impl]     gh                             default              mega
BACKLOG_LIB                    [impl]     $LIB_ROOT/board/backlog.sh     default              mega
PANE_VIEWER                    [impl]     auto                           default              mega
TMUX_CMD                       [impl]     tmux                           default              mega
TMUX_SESSION                   [impl]     (none)                         default              mega
TIER4_CORPUS                   [impl]     (empty)                        default              mega
WAVE_MERGE_CMD                 [impl]     $LIB_ROOT/goal/mega-merge.sh merge default              mega
WAVE_MERGE_LANE                [impl]     full                           default              mega
WAVE_POLL_SECS                 [impl]     0.2                            default              mega
TERMINAL_MUX                   [impl]     tmux                           default              queue
MUX_CMD                        [impl]     $TERMINAL_MUX                  default              queue
QUEUE_MUX_SESSION              [impl]     dk-queue                       default              queue
QUEUE_CLAUDE_CMD               [impl]     claude                         default              queue
QUEUE_CLAUDE_FLAGS             [impl]     --dangerously-skip-permissions default              queue
QUEUE_POLL_SECS                [impl]     15                             default              queue
QUEUE_TIMEOUT_SECS             [impl]     7200                           default              queue
QUEUE_RETRY_SLEEP_SECS         [impl]     1800                           default              queue
QUEUE_STARTUP_SECS             [impl]     20                             default              queue
QUEUE_SUBMIT_SETTLE_SECS       [impl]     2                              default              queue
QUEUE_BOARD_CMD                [impl]     board                          default              queue
QUEUE_JOURNAL                  [impl]     ${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}/queue-journal.tsv default              queue
QUEUE_ALLOWED_POINTER_GLOB     [impl]     _meta/megagoals/* .claude/goals/* default              queue
BACKLOG_FILE                   [impl]     $BACKLOG_DIR/../../_meta/BACKLOG.md default              board
BACKLOG_ID_RE                  [impl]     [A-Z]+-[0-9]+                  default              board
CC_SI_STATE_DIR                [impl]     $HOME/.claude/skill-curator    default              session
CC_SI_PROPOSALS_DIR            [impl]     $HOME/.claude/skill-proposals  default              session
CC_SI_SKILLS_DIR               [impl]     $HOME/.claude/skills           default              session
CC_SI_CONFIG                   [impl]     $CC_SI_STATE_DIR/config.toml   default              session
CC_SI_SETTINGS                 [impl]     $HOME/.claude/settings.json    default              session
CC_SI_MEMORY_LEDGER            [impl]     (empty)                        default              session
CC_SI_CURATOR_CMD              [impl]     (real `claude -p`)             default              session
CC_SI_REVIEWER_CMD             [impl]     (real `claude -p`)             default              session
DWARVES_KIT_SESSION_MARKER     [impl]     /tmp/.dwarves-kit-session-start default              session
gate.understanding_gate        [impl]     true                           default              gate
DWARVES_KIT_PRINT_CDDIR        [impl]     0                              default              gate
KIT_ROOT                       [impl]     $SCRIPT_ROOT                   default              gate
PROSE_RAG_INJECT               [impl]     unset (hook inert)             default              prose_rag
MONEY_GATE_REPOS               [impl]     (unset)                        default              money_gate
modules.board                  [impl]     true                           default              board
modules.session                [impl]     true                           default              session
modules.advisor                [impl]     true                           default              advisor
modules.cosmetic               [impl]     false                          default              cosmetic
modules.queue                  [impl]     true                           default              queue
modules.stats                  [impl]     true                           default              stats
modules.quiz_gate              [impl]     false                          default              quiz_gate
modules.weekend_batch          [impl]     false                          default              weekend_batch
modules.bridge                 [impl]     false                          default              bridge
modules.worktree               [impl]     false                          default              worktree
modules.money_gate             [impl]     false                          default              money_gate
modules.prose_rag              [impl]     false                          default              prose_rag
features.auto_improvement      [design]   (inert: design, no live effect) default              (none)
features.learning_ledger       [consumer] (inert: consumer, no live effect) default              (none)
team.actor_identity            [design]   (inert: design, no live effect) default              (none)
team.attestation               [design]   (inert: design, no live effect) default              (none)
team.ci_recheck                [design]   (inert: design, no live effect) default              (none)
team.spec_reservation          [design]   (inert: design, no live effect) default              (none)
team.policy                    [design]   (inert: design, no live effect) default              (none)
team.onboarding                [design]   (inert: design, no live effect) default              (none)
team.pilot                     [design]   (inert: design, no live effect) default              (none)
```

## #2 + #3: fixture -- env override AND project `.kit.toml` override both visibly win their own rows

Fixture setup (temp dirs, not committed):

```
$FIXDIR/root/kit.toml:
  [mega]
  wave_cap = 2
  tier4_close = true

$FIXDIR/proj/.kit.toml:
  [mega]
  wave_cap = 5

env: KIT_CONFIG_ROOT=$FIXDIR/root  KIT_PROJECT_ROOT=$FIXDIR/proj  KIT_DELIVERY_RATIO_WARN=99
```

`bash bin/config list` (excerpt, full command in `tests/test-config-registry.sh` AC5):

```
KEY                            STATUS     VALUE                          PROVENANCE           MODULE
KIT_DELIVERY_RATIO_WARN        [impl]     99                             env                  gate
WAVE_CAP                       [impl]     5                              project .kit.toml    mega
TIER4_CLOSE                    [impl]     true                           kit-root kit.toml    mega
```

Three rows, three DIFFERENT winning levels in one render: `KIT_DELIVERY_RATIO_WARN` wins at env
(99, overriding both toml files' absence), `WAVE_CAP` wins at project `.kit.toml` (5, shadowing
the kit-root default of 2), `TIER4_CLOSE` falls all the way to kit-root `kit.toml` (true, no env
or project override exists for it in this fixture).

`bash bin/config explain mega.wave_cap` (same fixture env):

```
WAVE_CAP (module=mega, status=[impl])
  Max concurrent sub-goals admitted per wave.

  1. env             WAVE_CAP             = (unset)
  2. project .kit.toml [mega.wave_cap]     = 5   [$FIXDIR/proj/.kit.toml]
  3. kit-root kit.toml [mega.wave_cap]     = 2   [$FIXDIR/root/kit.toml]
  4. default          = `2`

Effective: 5   (source: project .kit.toml)
```

The full four-level chain, the shadowed kit-root value (2) still visible at level 3, and the
winner named explicitly at the bottom. (Level 4 shows the registry's human-annotated Default
cell verbatim; the `Effective:` line and `config get` emit the machine value.)

## #4-#7: `tests/test-config-registry.sh` full output

```
=== AC1: drift lint -- every seed-regex hit in lib/hooks/bin is registered or allowlisted ===
  PASS 0 orphans on the live tree (drift lint green)

=== AC2: NEGATIVE CONTROL -- a planted unregistered env var IS flagged ===
  PASS the plant is flagged exactly 1 orphan
  PASS the flagged orphan is specifically KIT_TOTALLY_UNREGISTERED_PLANT

=== AC3: module-leg completeness -- every KIT_KNOWN_MODULES entry has a registry row ===
  PASS every KIT_KNOWN_MODULES entry (12 modules) has a Module-legs row

=== AC4: NEGATIVE CONTROL -- a module NOT in KIT_KNOWN_MODULES is correctly absent ===
  PASS a fake module name is correctly NOT found in the registry (the check is not vacuous)

=== AC5: bin/config functional smoke (list/get/explain + provenance fixture) ===
  PASS get WAVE_CAP (default, no overrides) is the clean scalar 2
  PASS get mega.wave_cap (dotted-key lookup) is the clean scalar 2
  PASS get TIER4_CLOSE strips the annotation ((truthy)) from the default cell
  PASS get MEGA_MERGE_POSTURE unquotes the default (one " layer, like _kit_toml_get)
  PASS get on an unknown key fails (exit != 0)
  PASS get with set-but-empty env falls through to the default (${VAR:-} semantics)
  PASS list with a missing registry file fails (exit != 0), no silent header-only success
  PASS list: a project .kit.toml override visibly wins WAVE_CAP's row (5, project .kit.toml)
  PASS list: an env override visibly wins KIT_DELIVERY_RATIO_WARN's row (99, env)
  PASS list: no override falls to kit-root kit.toml (TIER4_CLOSE = true, kit-root kit.toml)
  PASS explain mega.wave_cap: the winner line names project .kit.toml + the resolved 5
  PASS explain mega.wave_cap: level 2 (project) shows the winning value 5
  PASS explain mega.wave_cap: level 3 (kit-root) shows the shadowed value 2
  PASS get ledger.location resolves via the first (canonical KIT_LEDGER_DIR) row

=== 19/19 passed ===
```

## #8-#9: resolver unchanged

```
$ bash lib/config/kit-config.sh selftest
ok   project overrides kit-root
ok   kit-root default when no proj
ok   inline comment stripped
ok   commented key -> caller default
ok   missing key -> caller default
ok   missing section -> empty
PASS kit-config selftest

$ git diff --stat origin/docs/loop-01-taxonomy -- lib/config/kit-config.sh hooks/ kit.toml
(no output -- zero diff)
```

## #10-#12: full suite regression

```
$ bash tests/test-meta.sh
...
Passed: 683 / 683
All meta tests passed.

$ bash tests/test-hooks.sh
...
Passed: 453 / 453
All tests passed.

$ bash tests/test-install-modules.sh
...
== 37 passed, 0 failed ==

$ bash tests/test-e2e.sh
...
Passed: 20 / 20
Golden run green.
```

## Done= check

Per the goal file: "list/explain captures committed + registry complete against the live
sweep + drift lint green with failing-NC captured + resolver selftest unchanged." All four
hold, evidenced above (#1-#3 captures, #4/#6 green + #5/#7 failing-NC, #8-#9 resolver
unchanged).
