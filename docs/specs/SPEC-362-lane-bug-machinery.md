# Spec: kit-machinery bug fixes size as bug, not full

Generated: 2026-09-29
Status: DRAFT (round 4: kit-repo-only allowlist, plus the lead's rulings on the proof-gate condition, refusal and guard signals, and commands/)
Lane: full (policy change to the lane classifier itself)
Type: spec-feature
File: `docs/specs/SPEC-362-lane-bug-machinery.md`
References: `lib/classify/lane-classify.sh` (`_extract_files`, `_files_touch_machinery`, `classify_core`, `main`, the precedence comment at line 19), `tests/test-lane-classify.sh`, `hooks/ship-gate.sh` (proof gate, spec lookup), `lib/gate/proof-ledger.sh`, `lib/gate/negctl.sh`, `kit.toml` (`[gate] proof_of_done`), `docs/WORKFLOW.md` (lane table), `README.md` (lane-classify row), `commands/wrap.md` (step 10 re-size)

## Problem

`lib/classify/lane-classify.sh` sends every change that touches `lib/` or `hooks/` to `full`. The `--files` path does it through `_files_touch_machinery` (line 89). The text-only path does it through the kit-machinery hard-gate regex (line 60). Neither path asks whether the change is a defect fix, or whether the code it touches enforces anything.

Real data from this repo's history. `git log --no-merges` holds 1071 commits since 2026-03-29. Of those, 116 have a subject starting `fix` and a diff touching `lib/` or `hooks/`. Today's classifier, fed each commit's subject and `--files` = its file list, sizes 115 of the 116 `full` and one `tiny`. Each paid for think, spec, validation, docs and reflect, whether the fix sat in a ship gate or in a board-sync helper.

The operator approved a policy change: a kit-machinery change that is a bug fix and introduces no new contract sizes `bug`. Rounds 1 and 2 tried a vocabulary rule and then an enforcement denylist; both leaked (a relaxation phrased as a fix; files the gates source but the denylist missed; a newline-separated `--files` list read only to its first line). The lead redesigned the rule as a kit-repo-only ALLOWLIST: demotion happens only when every touched machinery path is on a verified list of advisory, non-gate kit code.

Replayed through the prototype of this design with `proof_of_done` on, 17 of the 116 fix commits size `bug`: `lib/sync` 4, `lib/board` 4, `hooks` 4 (context-budget, auto-format), `lib/spec` 2, `lib/session` 2, `lib/stats` 1. The other 99 stay as today: 83 touch a path outside the allowlist, 10 carry another hard flag, 5 carry a contract signal, and 1 stays `tiny`. With `proof_of_done` off, none demote. The SPEC-360 wrap-merge fix stays `full`, because `lib/wrap/wrap.sh` is a merge gate.

This spec is itself a policy change to the classifier, so it sizes `full` under both rules. AGENTS.md "Pause if" lists a risk-classification change as a human decision; the operator made it.

## Change

All code lands in `lib/classify/lane-classify.sh`.

1. The allowlist, defined once near the flag arrays as two quoted bash arrays with a header comment:
   ```
   # Demotable kit paths: advisory, non-gate code where a bug fix with no contract signal may size
   # `bug` instead of `full`. Kit repo only, --files only, EVERY touched path must be on this list
   # (or be a neutral test/doc path) and none on the EXCEPT list. Verified: nothing under hooks/,
   # lib/gate, lib/classify, lib/ledger, lib/wrap or lib/goal sources or calls these paths; no
   # listed hook blocks; nothing listed reads or filters secrets. tests/test-lane-classify.sh pins it.
   _DEMOTABLE_GLOBS=(
     'lib/bench/*' 'lib/cosmetic/*' 'lib/precedent/*' 'lib/prose-rag/*' 'lib/reflect/*'
     'lib/repohygiene/*' 'lib/session/*' 'lib/skill-curator/*' 'lib/spec/*' 'lib/stats/*'
     'lib/sync/*' 'lib/webcheck/*'
     'lib/board/board-mirror.sh' 'lib/board/board-run.sh' 'lib/board/board-writeback.sh'
     'lib/board/parse-board.sh' 'lib/board/bin/*'
     'hooks/auto-format.sh' 'hooks/batch-debt-warn.sh' 'hooks/codebase-index.sh'
     'hooks/context-budget.sh' 'hooks/context-hints.sh' 'hooks/context-hints.py'
     'hooks/context-readiness.sh' 'hooks/notification.sh' 'hooks/post-compact-reinject.sh'
     'hooks/pre-compact-backup.sh' 'hooks/prose-rag.sh' 'hooks/session-state-save.sh'
     'hooks/slop-cleaner.sh' 'hooks/statusline.sh'
   )
   # Carve-outs inside the globs above; EXCEPT wins.
   _DEMOTABLE_EXCEPT=(
     'lib/bench/dashboard.py'               # SECRET_PATTERNS redaction
     'lib/precedent/inventory.py'           # SECRET_SHAPE_RE filter
     'lib/reflect/staging-format.py'        # called by lib/wrap/wrap.sh
     'lib/session/recall/session_recall.py' # SECRET_SHAPE_RE filter
     'lib/session/observe/bin/session-report' # reads a key and token from op:// refs
     'lib/skill-curator/lib/common.sh'      # the secret filter
     'lib/skill-curator/lib/promote.sh'     # refuses a secret-bearing draft
     'lib/skill-curator/lib/reviewer-run.sh' # drops a secret-bearing draft
     'lib/skill-curator/deploy/*'           # install surface
     'lib/stats/src/stats/adapters.py'      # parses the secret-guard audit log, secret canary
     'lib/sync/cockpit.py' 'lib/sync/sources/hermes.py' 'lib/sync/sources/multica.py'
     'lib/sync/sources/notion*'             # external-service credentials
     'lib/sync/deploy/*'                    # cron job credentials, install surface
   )
   # Paths that ride along with any fix and never block demotion. Contract files among them
   # (docs/WORKFLOW.md) still force full through the file contract signal (item 4).
   _DEMOTE_NEUTRAL=( 'tests/*' 'docs/*' '_meta/*' 'README.md' )
   ```
   Every other path blocks demotion: `commands/`, `agents/`, `skills/`, `bin/`, `.github/`, root files other than `README.md`, and every `lib/` or `hooks/` path not listed. Verification of each candidate is recorded in Grounding.

2. Shared bug terms. One string feeds step 4 and the machinery decision:
   ```
   _bug_core='\bbug\b|regression|failing test|broken|crash|defect|hotfix|stack ?trace|exception|fix the|fix a '
   ```
   Step 4 greps `"$_bug_core|repro"`, which is byte-for-byte today's alternation. The machinery bug signal is `_mbug_re="$_bug_core"'|\bfix(es|ing)?\b|\bbroke\b|wrong|root[ -]cause'`: no `fixed` (so "fixed-width" does not count), `broke` only as a word (not "broker"), no bare `repro` (not "reprocess").

3. The text contract signal `_mcontract_re`, matched against the lowercased description. The relaxation lines of round 2 are gone; the allowlist replaces them. `refus...` and `guard...` are kept by lead ruling: adding a refusal or a guard changes a promise, whatever the wording around it. Written out in full, one alternative per line (the variable joins them with `|` and no whitespace):
   ```
   \bnew .{0,20}\b(flags?|verbs?|knobs?|options?|subcommands?|commands?|gates?|checks?|guards?|hooks?|lanes?|phases?|markers?|columns?|fields?|env vars?|config keys?)\b
   \badd(s|ed|ing)?\b.{0,20}\b(flags?|verbs?|knobs?|options?|subcommands?|commands?|gates?|checks?|guards?|hooks?|lanes?|phases?|markers?|columns?|fields?|env vars?|config keys?)\b
   (^|[^a-z0-9-])--[a-z]
   renam[a-z]*\b.{0,20}(--|\b(flags?|verbs?|knobs?|options?|subcommands?|commands?|gates?|checks?|guards?|hooks?|lanes?|phases?|markers?|columns?|fields?|env vars?|config keys?)\b)
   now also
   no longer
   now (refuses|blocks|merges|allows|skips|accepts|requires)
   \bsize[sd]? (tiny|normal|bug)\b
   (ledger|log|line|output) format\b
   install\.sh
   \badopt
   kit\.toml
   hooks\.json
   settings\.json
   workflow\.md
   agents\.md
   \brefus(e|es|ed|ing)\b
   \bguard(s|ed|ing)?\b
   \bpolicy\b
   \b(bug|full|tiny|normal|backfill) lane\b
   \blane (table|rule|trigger|floor)\b
   ```

4. The file contract signal, case-insensitive, over the normalized file list:
   ```
   (^|/)(install\.sh|adopt\.sh|hooks\.json|codex-hooks\.json|settings\.json|\.?kit\.toml|WORKFLOW\.md|AGENTS\.md)$|(^|/)lib/config/module-registry\.md$|(^|/)\.claude-plugin/
   ```
   Under the allowlist it only matters for a contract file on a neutral path (`docs/WORKFLOW.md`); every other contract file already blocks as outside the allowlist.

5. One helper, `_contract_signal <text|all> <lc>`: `text` tests item 3; `all` tests item 3, then item 4 when `--files` was passed. Every `grep` over a stored regex uses `grep -qE -e`.

6. FILES normalization, once, in `_extract_files`: after reading `--files`, `FILES="$(printf '%s' "$FILES" | tr '\n\t' '  ')"`. One helper, `_files_arr`, splits it with `IFS=' ' read -ra FARR <<< "$FILES"` into a quoted array; no caller iterates an unquoted `$FILES`. Globs are matched with `case "$f" in $g) ...` inside `for g in "${ARRAY[@]}"`, so no pattern ever expands against the working directory. `_files_touch_machinery` switches to `_files_arr`, which fixes the pre-existing bug where a newline-separated list (the form `commands/wrap.md:318` passes) was read only to its first line.

7. Kit-repo machinery surface. `_files_touch_machinery` keeps `lib/*|hooks/*|*/lib/*|*/hooks/*` and, only when `_in_kit_repo` holds, also fires on a root `install.sh` or a root `settings.json`. `_in_kit_repo` is `[ -f "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/lib/classify/lane-classify.sh" ]`.

7a. The proof-gate condition, `_proof_gate_on`, resolved the way `hooks/ship-gate.sh` resolves its proof gate, and read-only. With `root` = the git toplevel (else `pwd`), it holds only when all three hold: `$root/docs/verification/README.md` exists (ship-gate's adoption marker), `$LIB_ROOT/gate/gate-policy.sh` exists, and `bash "$LIB_ROOT/gate/gate-policy.sh" enabled proof_of_done "$root"` exits exactly 0. Any other outcome, a missing script, exit 1 (off by config) or any other exit, means no demotion. This is deliberately stricter than ship-gate's `_gate_on`, which treats every exit but 1 as on: a demotion must be able to show that the gate which will hold it is on. Inside `gate-policy.sh`, a missing `kit-config.sh` still resolves to on (its own fail-on rule); the classifier cannot see that case and inherits it.

8. Machinery contract outranks tiny, for `classify`, `explain` and `check` only. `main` sets `TINY_CONTRACT=1` for those three verbs; `escalate` and `deescalate` leave it unset. In step 2, when the tiny regex matches and `TINY_CONTRACT=1`, the kit-machinery flag would fire, and `_contract_signal text` holds, skip the tiny return and fall through. Tiny behavior is otherwise exactly today's: a tiny match returns `tiny` whatever the files, including files outside the allowlist.

9. The demotion (step 3, the kit-machinery branch, today lines 150-163). When the flag would fire, add `kit-machinery` to `hard` unless ALL of these hold, in this order:
   a. the text matches `_mbug_re`;
   b. `_in_kit_repo`;
   c. `--files` was passed and the normalized list is non-empty (one guard line at the top of `_all_demotable`);
   d. `_all_demotable`: every path matches `_DEMOTABLE_GLOBS` or `_DEMOTE_NEUTRAL`, and none matches `_DEMOTABLE_EXCEPT`;
   e. `_proof_gate_on` (item 7a);
   f. `_contract_signal all` is false.
   When all hold, set `mbug=1` instead. Record the first failed check among b to f for the reason line.

10. After the hard-gate verdict: a non-empty `hard` gives `full` as today. When the text carried a bug signal but a later check failed, the reason gains one suffix: ` (not the kit repo)`, ` (no --files)`, ` (a path outside the demotable allowlist)`, ` (proof gate off)`, or ` (contract signal outranks the bug signal)`. An empty `hard` with `mbug=1` gives `LANE=bug`, `REASON="kit-machinery bug fix (bug signal, no contract signal, every path demotable)"`, `FIRED="kit-machinery-bug"`.

11. The header precedence comment (line 19) becomes: `backfill > tiny (unless classify/explain/check + machinery + text contract signal) > hard-gate (kit-machinery demotes to bug only in the kit repo, with --files, every path on the demotable allowlist, the proof gate on, a bug signal and no contract signal) > bug > soft-count > normal`.

12. Docs:
    - `docs/WORKFLOW.md` lane table: the `full` row's "hooks" becomes "a hook contract"; the `bug` row's "When" cell becomes "a defect, regression, or failing test (not a new feature), incl. a kit-machinery fix with no contract change on an allowlisted path". One sentence under the table names `_DEMOTABLE_GLOBS` as the list and says the demotion is kit-repo only.
    - `README.md` lane-classify row: one clause, "in the kit repo, a bug fix whose files are all on the demotable allowlist and that carries no contract signal sizes bug".
    - `commands/wrap.md` step 10 landing item 1: "(it touched auth, a hook, a data model, a contract)" becomes "(it touched auth, a gate or hook outside the demotable allowlist, a data model, a contract)".

## Picture

```
 description + --files (normalized: newlines and tabs -> spaces, quoted array)
        |
        v
 backfill? --yes--> backfill                                       (unchanged)
        | no
 tiny? --yes--> [classify|explain|check] AND machinery AND text contract signal?
        |             | no --> tiny                        | yes (fall through)
        | no  <-----------------------------------------------+
        v
 other hard flags (auth, data-model, audit-security, ...) --any--> full
        |
 kit-machinery would fire?  (lib/ | hooks/ path; kit-repo root install.sh | settings.json;
        |                    or machinery text when no --files)
        | no                              | yes
        v                                 v
   step 4 bug / soft / normal     bug signal? --no--> full (kit-machinery)
   (step 4 = _bug_core|repro,              | yes
    unchanged)                             v
                                  kit repo? --no--> full (not the kit repo)
                                           | yes
                                  --files given, non-empty? --no--> full (no --files)
                                           | yes
                                  every path demotable or neutral, none EXCEPT?
                                           | no --> full (a path outside the allowlist)
                                           | yes
                                  proof gate on (marker + gate-policy exit 0)? --no--> full
                                           | yes                          (proof gate off)
                                  contract signal, text or files? --yes--> full (contract)
                                           | no
                                           v
                                    bug (kit-machinery-bug)
```

## Design

The allowlist is the primary defence and the contract signal the second. A path the kit has not verified as advisory never demotes, so a gate relaxation phrased as a fix cannot reach `bug` through vocabulary. The proof-gate condition makes sure the one hook that holds a demoted fix is actually on. Consumer repos and text-only callers see no demotion at all.

### Neutral paths

`tests/*`, `docs/*`, `_meta/*` and `README.md` ride along with almost every fix (112 of the 116 historical fix commits touch one) and carry no runtime behavior, so they neither qualify nor block a demotion. A contract file on a neutral path (`docs/WORKFLOW.md`) still forces `full` through the file contract signal. Every other non-machinery path blocks demotion, including `commands/*.md`: commands are the kit's operate contracts (lead ruling, round 4).

### Diagram

See `## Picture` above for the decision flow.

### Approaches considered

1. Kit-repo-only allowlist with a contract signal inside it (chosen, lead redesign after round 2).
2. Enforcement denylist plus vocabulary (round 2). Rejected by round-2 review: the denylist missed files the gates source (`lib/config/kit-config.sh`, `lib/ledger/ledger.sh`, `lib/telemetry/kit-log-dir.sh`, `lib/registry/feature-registry.sh`), missed `codex-hook-adapter` in its word list, and inherited the newline bug.
3. Vocabulary only (round 1). Rejected: nine gate-relaxation texts carried a bug signal and no contract word.
4. "Every path on the allowlist", literally, with no neutral paths. Rejected on the history data: 112 of the 116 fix commits also touch `tests/`, `docs/` or `_meta/`, so the literal rule would demote almost nothing. Neutral paths carry no behavior, and a contract file among them still forces `full`.
5. Demote without checking the proof gate. Rejected by lead ruling: `proof_of_done` defaults off (`kit.toml:111`), so a demoted fix could be held by no hook. The classifier gains a read-only call into `lib/gate/gate-policy.sh`; it already calls `lib/gate/gate-ledger.sh` for `deescalate`.

### Deliberate tradeoff: a demoted fix is held by the proof gate alone

Accepted by the lead in round 0. A demoted fix usually has no spec, so `hooks/ship-gate.sh` never runs its lane-gate check. The only hook that can block it is the diff-keyed proof-of-done gate (green run plus negative control). `gate.proof_of_done` defaults to `false` in `kit.toml:111`; in this kit checkout it is on only through the operator overlay. Item 7a makes the demotion itself conditional on that gate: where the overlay is absent, nothing demotes. If `/kit:wrap` step 10 builds a demoted fix (only when an operator adds `bug` to `wrap.build_lanes`), it merges it only through `wrap merge --apply`'s green gate.

## Grounding

### Method

A scratch prototype sources the real `lib/classify/lane-classify.sh` (for today's `classify_core` and hard regexes) and adds items 1 to 10 on top. Every run sets `KIT_CONFIG_OPERATOR=tests/fixtures/gates-on` (the suite's own overlay, `proof_of_done = true`) so the result does not depend on the developer's overlay; P1 and the proof-off replay point it at an empty temp dir instead. "Today" is the real CLI (`bash lib/classify/lane-classify.sh classify [--files "<list>"] "<text>"`) run from the kit worktree root on base `ad901924`; "After" is the prototype. A `\n` in a file list is a real newline. None of this is the built classifier.

### Allowlist verification

- Callers checked: every tracked file under `hooks/*.sh`, `hooks/*.py`, `lib/gate/`, `lib/classify/`, `lib/ledger/`, `lib/wrap/`, `lib/goal/` that is not itself allowlisted (61 files). A prototype of the drift test (T57) searches their non-comment lines for each allowlisted path, its `lib/`-relative suffix, a hook's basename, and `bin/<dir>`. Result: 92 allowlisted code files, 0 callers.
- The negative checks of that prototype: adding `lib/board/backlog.sh` reports `CALLED: lib/board/backlog.sh <- lib/goal/wt.sh`; adding `lib/config/kit-config.sh` reports `<- lib/gate/gate-policy.sh`; adding `hooks/ship-gate.sh` reports `BLOCKING: hooks/ship-gate.sh`.
- Excluded from the lead's candidate list, with the reason:
  - `lib/board/backlog.sh`: `lib/wrap/wrap.sh:111` and `lib/goal/wt.sh:41` call it.
  - `lib/board/board.sh`: named in the docstrings of `hooks/harvest.py` and `hooks/backlog-stage.py`, so the mechanical drift test would flag it. It also calls `backlog.sh` and `lib/config/kit-config.sh`.
  - `lib/reflect/staging-format.py`: `lib/wrap/wrap.sh:110` calls it.
  - The secret and credential files in `_DEMOTABLE_EXCEPT`, each with its reason inline.
  - `lib/worktree-provision` (env linking) was never a candidate.
- Included beyond the lead's list: `lib/prose-rag/*`. Its only caller is `hooks/prose-rag.sh` (through `bin/prose-rag`), which is an allowlisted advisory hook, and it touches no credentials.
- Hooks: every allowlisted hook has no non-comment `exit 2`, `sys.exit(2)`, `permissionDecision` or `"decision":` line. Excluded advisory-looking hooks: `backlog-stage.*`, `harvest.*`, `intake-sweep.*` (they write the board and staging, and `harvest.py` carries a secret filter), `output-offload.sh` (reuses the secret-guard extraction), `money-gate.sh` (fronts the blocking `money-gate.py`), `anchor-root.sh` (relays blocking hooks).

### Classifier output today and after the change

Kit worktree root unless noted. T-ids in the test plan equal the G-ids here.

| ID | --files | Text | Today | After | Decided by |
|---|---|---|---|---|---|
| G01 | `lib/sync/sync_core.py tests/test-sync.sh` | fix sync_core dropping the last row when the backlog has no trailing newline | full | bug | demotion |
| G02 | `hooks/context-budget.sh tests/test-hooks.sh` | fix context-budget reading the wrong window size from a stale statusline file | full | bug | demotion |
| G03 | `lib/session/session.sh\ntests/test-session.sh` | fix session resolving entrypoint paths without realpath | full | bug | demotion, newline list |
| G04 | `lib/spec/spec-next.sh tests/test-spec-next.sh _meta/BACKLOG.md docs/verification/x.md` | fix spec-next handing out a number the reservation ledger already holds | full | bug | demotion, neutral paths |
| G05 | `lib/wrap/wrap.sh tests/test-wrap.sh` | fix wrap merge merging before the ci-label runs registered | full | full | outside allowlist (SPEC-360) |
| G06 | `lib/board/backlog.sh tests/test-backlog.sh` | fix backlog next picking a parked row | full | full | outside allowlist |
| G07 | `lib/sync/sync_core.py` | fix sync_core so it now also pulls archived rows | full | full | text contract |
| G08 | `lib/sync/sync_core.py` | fix the sync --dry-run output | full | full | text contract (bare flag) |
| G09 | `lib/sync/sync_core.py AGENTS.md` | G01 text | full | full | outside allowlist |
| G10 | `lib/sync/sync_core.py lib/config/module-registry.md` | G01 text | full | full | outside allowlist |
| G11 | `lib/sync/sync_core.py commands/sync.md` | G01 text | full | full | outside allowlist (commands/) |
| G12 | (none) | G01 text | normal | normal | machinery text never fires |
| G13 | (none) | fix the parser in lib/gate/gate-ledger.sh | full | full | no --files (existing suite case) |
| G14 | `hooks/ship-gate.sh` | fix ship-gate wrongly blocking a push whose proof doc has no negative control | full | full | outside allowlist |
| G15 | `hooks/safety-gate.sh` | fix safety-gate wrongly refusing a force push to main | full | full | outside allowlist |
| G16 | (none) | fix the bug: remove the proof check from ship-gate | full | full | no --files |
| G17 | (none) | fix ship-gate by skipping the proof check on docs-only diffs | full | full | no --files |
| G18 | `lib/gate/proof-ledger.sh` | fix proof-ledger so md-only diffs are exempt from the negative control | full | full | outside allowlist |
| G19 | `lib/wrap/wrap.sh` | fix wrap merge to drop the green-gate requirement | full | full | outside allowlist |
| G20 | `lib/classify/lane-classify.sh` | fix lane-classify so machinery edits size normal | full | full | outside allowlist (and text contract) |
| G21 | `hooks/ship-gate.sh` | add an exception for docs-only diffs in ship-gate | full | full | outside allowlist |
| G22 | `lib/wrap/wrap.sh` | fix(wrap): accept a --force flag for merge | full | full | outside allowlist (and bare flag) |
| G23 | `lib/config/kit-config.sh` | fix kit-config reading the operator overlay before the project file | full | full | outside allowlist (gate-sourced) |
| G24 | `lib/ledger/ledger.sh` | fix ledger root falling back to the XDG default when the env var is empty | full | full | outside allowlist (gate-sourced) |
| G25 | `lib/telemetry/kit-log-dir.sh` | fix kit-log-dir resolving the wrong durable dir | full | full | outside allowlist (gate-sourced) |
| G26 | `lib/registry/feature-registry.sh` | fix feature-registry check failing on a new test file | full | full | outside allowlist (ship-gate exits 2 on it) |
| G27 | `hooks/codex-hook-adapter.sh` | fix codex-hook-adapter wrongly dropping a block decision | full | full | outside allowlist |
| G28 | `lib/sync/sync_core.py\nhooks/ship-gate.sh` | G01 text | full | full | outside allowlist, 2nd line of a newline list |
| G29 | `lib/session/removed.sh` | fix session crash on a removed helper | full | bug | a missing path inside an allowlisted glob |
| G30 | `lib/board/removed.sh` | fix board crash on a removed helper | full | full | a missing path outside the allowlist |
| G31 | `lib/skill-curator/lib/common.sh` | fix the secret filter missing a bearer token shape | full | full | audit-security flag (and EXCEPT) |
| G32 | `lib/skill-curator/lib/surface.sh` | fix surface printing the wrong draft count | full | bug | demotion |
| G33 | `lib/sync/cockpit.py` | fix cockpit crashing on an empty channel list | full | full | EXCEPT (credentials) |
| G34 | `lib/sync/sync_core.py` | fix sync_core fixed-width column parse | full | bug | `fix` counts, `fixed-width` does not |
| G35 | `lib/sync/sync_core.py` | update sync_core for the new broker endpoint | full | full | no bug signal (`broker`) |
| G36 | `lib/sync/sync_core.py` | reprocess sync_core rows after an import | full | full | no bug signal (`reprocess`) |
| G37 | `lib/wrap/wrap.sh tests/test-wrap.sh` | rename the --foo flag in lib/wrap/wrap.sh | tiny | full | contract beats tiny |
| G38 | `lib/session/session.sh` | rename a local variable in lib/session/session.sh | tiny | tiny | not a contract rename |
| G39 | `escalate tiny <spec file holding the text>` | rename the --json flag in gate-ledger.sh | HOLD tiny | HOLD tiny | contract-beats-tiny off for escalate |
| G40 | (none) | rename the --json flag in gate-ledger.sh | tiny | full | contract beats tiny, text-only classify |
| G41 | `install.sh` | fix install.sh crashing on a missing config dir | bug | full | kit-repo install.sh is machinery, outside allowlist |
| G42 | `settings.json` | register the observe hook for every event in settings.json | normal | full | kit-repo settings.json is machinery |
| G43 | `scripts/install.sh config/settings.json` | add a retry loop to the installer | normal | normal | not root files |
| G44 | `lib/gate/x.sh` | fix the token refresh crash | full | full | audit-security flag |
| G45 | (none) | fix wrong total in the invoice page | normal | normal | machinery does not fire |
| G46 | `hooks/statusline.sh .github/workflows/ci.yml` | fix statusline printing the wrong model name | full | full | outside allowlist (.github/) |
| G47 | `lib/sync/sync_core.py tests/test-sync.sh` | fixed-width parse in sync_core breaks on tabs | full | full | no bug signal |
| G48 | `docs/x.md\nhooks/ship-gate.sh` | tweak a message | normal | full | newline fix: today reads only `docs/x.md` |
| G49 | `lib/sync/sync_core.py docs/WORKFLOW.md` | G01 text | full | full | file contract (neutral path) |
| C1 | `install.sh`, in a temp non-kit git repo | G41 text | bug | bug | consumer: item 7 is kit-only |
| C2 | `settings.json`, same repo | G42 text | normal | normal | consumer |
| C3 | `lib/sync/sync_core.py`, same repo | G01 text | full | full | consumer: no demotion outside the kit |
| P1 | `lib/sync/sync_core.py tests/test-sync.sh`, `KIT_CONFIG_OPERATOR` = an empty temp dir | G01 text | full | full | proof gate off |

Every round-1 and round-2 critical text (G14 to G28) stays `full`. All 38 existing cases in `tests/test-lane-classify.sh` keep their lane under the prototype.

History replay after the round-4 rulings: 17 demote (was 20 in round 3). The refusal and guard signals catch `d819be88` "refuse bulk status flips", `c79471f1` "refuse id-collided spoke items" and `d2fe0359` "identity guards stop cross-row title corruption". The other two contract hits are `6cfb5958` (`--backlog-file` flag) and `abc7ccc3` ("no longer crashes"). With the operator overlay replaced by an empty dir, the replay demotes 0 of 116: the 22 commits that pass checks a to d all stop at the proof gate.

### Where the classifier's answer changes elsewhere

- Consumer repos: unchanged. The demotion and item 7 both require `_in_kit_repo`. The only consumer-visible changes are item 8 (a tiny text with a machinery signal and a contract signal now sizes `full`) and item 6 (a newline-separated `--files` list is read in full, which can only raise a lane).
- Text-only callers (`/kit:assign`, `lib/queue/orchestrate.sh:833` which classifies a sub-goal title with no `--files` and records it as the run's START lane): never demote. Item 8 can raise such a START lane from `tiny` to `full`; nothing lowers it.
- `escalate`: unchanged; item 8 does not apply (R2 measured it flipping 101 of 269 specs from HOLD to ESCALATE).

### Is this a gate bypass? No: the proof is still owed where the proof gate runs

- The proof-of-done gate (`hooks/ship-gate.sh:98-110`) runs before the spec lookup and keys on the branch diff, not the lane. It engages in a repo carrying `docs/verification/README.md` with `proof_of_done` on; this checkout has both (the second through the operator overlay).
- `proof-ledger.sh classify` (`:77-116`) returns `inert` only for a markdown, txt or `.kit.toml`-only diff. An allowlisted `.sh` or `.py` change is `behavioral`, which needs a green run AND a negative control (`:411-415`), and `:377-404` rejects an override for source files.

### What the change does relax

- Spec-less bug-lane runs skip the lane-gate check at `hooks/ship-gate.sh:223-225` (the deliberate tradeoff above).
- A negative control on a false-positive fix proves the code now lets the case through, not that doing so was right. The allowlist keeps gate files out, so that judgment only arises in advisory code.
- `proof_of_done` defaults off (`kit.toml:111`). Without the operator overlay, no hook holds a demoted fix.
- `f9b88744` "mark intake-born board rows as untrusted data" adds a trust boundary without the words refuse or guard, and still demotes. The vocabulary is a second defence, not a complete one.
- The review-escalation rule (`docs/WORKFLOW.md` "Review escalation") is lane-independent and stays advisory. `significance-classify.sh` loses its `full`-lane leg for a demoted fix; that gate is advisory.

### Accepted limit: the text is pre-diff

The classifier reads the task line and file names, never diff content. `/kit:wrap` step 10 re-sizes against `git diff --name-only`, so a behavior change inside an allowlisted file described with clean bug text sizes `bug`. The upgrade path, out of scope: a diff-content probe that flags an added or removed `--flag` definition, a removed `exit 2`, or a changed gate-ledger phase name.

### Negative controls

`lib/gate/negctl.sh` discards the suite output (`negctl.sh:189`), so each NC's test command is a wrapper that records its own red set:

```
bash -c 'log="$1"; shift; bash tests/test-lane-classify.sh >"$log" 2>&1
  fails=$(grep -F FAIL "$log"); [ -n "$fails" ] || exit 0
  for e in "$@"; do printf "%s\n" "$fails" | grep -qF -e "$e" || exit 0; done
  n=$(printf "%s\n" "$fails" | grep -c .); [ "$n" -eq "$#" ] || exit 0
  exit 1' _ "$TMPDIR/nc-<name>.log" <expected label 1> <expected label 2> ...
```

It exits 1 (red) only when the FAIL lines are exactly the expected labels, one each; the baseline (no FAIL) and any other outcome exit 0, which `negctl.sh` then reports as a control that never went red. The log path sits outside the repo; the proof copies each log's FAIL lines. New test labels carry `[S362-Tnn]`, so an expected label is `S362-Tnn` or an existing label verbatim.

| NC | Mutates | Red on at least | Expected set |
|---|---|---|---|
| NC1 demotion | step 3: the `mbug=1` condition becomes `false` | T01, T02, T03, T04 | T01 T02 T03 T04 T29 T32 T34 T53 T56 |
| NC2 contract | `_contract_signal`: `return 1` first | T07, T08 | T07 T08 T37 T40 T49 T54 T56 |
| NC2F file contract | `_contract_signal`: the item 4 file test removed | T49 | T49 |
| NC3 contract beats tiny | step 2: the item 8 check removed | T37, T40 | T37 T40 |
| NC4 kit-repo surfaces | `_files_touch_machinery`: the `_in_kit_repo` install/settings branch removed | T41, T42 | T41 T42 |
| NC5 allowlist | `_all_demotable`: the per-path loop replaced by `return 0` after the guard line | T05, T14, T23, T28 | T05 T06 T11 T14 T18 T19 T21 T23 T24 T25 T26 T27 T28 T30 T33 T46 T55 |
| NC6 kit-repo gate | step 3 check b: `_in_kit_repo` replaced by `true` | T52 | T52 |
| NC7 no-files guard | `_all_demotable`: the guard line (item 9c) removed | T13, T16 | T13 T16 T17, plus the existing label "AC6 gate-ledger still full" (the suite runs from the kit root under negctl) |
| NC8 normalization | `_extract_files`: the `tr '\n\t' '  '` removed | T28, T48 | T28 T48 |
| NC9 drift guard | `_DEMOTABLE_GLOBS`: `'lib/board/backlog.sh'` appended | T57 | T06 T57 |
| NC10 proof-gate condition | `_proof_gate_on`: `return 0` first | T58 | T58 |

The expected sets come from the prototype (NC2, NC2F and NC5 simulated over G01 to G49 after the round-4 rulings; T15 left NC5's set because "wrongly refusing" is now a contract signal; the rest traced by hand). The build records the observed set per NC; any delta goes to the implementation notes before the wrapper's expected list is fixed.

## Acceptance criteria

- AC1: every Grounding row G01 to G49 and C1 to C3 gives its "After" answer from the built classifier.
- AC2: `explain` on G01 prints `reason: kit-machinery bug fix (bug signal, no contract signal, every path demotable)` and `flags: kit-machinery-bug`; on G07 the reason ends `(contract signal outranks the bug signal)`; on G05 it ends `(a path outside the demotable allowlist)`.
- AC3: `_DEMOTABLE_GLOBS` and `_DEMOTABLE_EXCEPT` are each defined once, as quoted arrays, with the header comment; no code iterates an unquoted file or glob list.
- AC4: run in a subshell with `KIT_LEDGER_DIR` and `DWARVES_KIT_LOG_DIR` both set to one temp dir, from the kit root: `check bug --files lib/sync/sync_core.py "<G01 text>"` prints no `LANE-DOWNGRADE`, and `check bug --files lib/sync/sync_core.py "<G07 text>"` prints it.
- AC5: every existing case in `tests/test-lane-classify.sh` keeps its expected lane.
- AC6: `bash tests/run-all.sh` passes.
- AC7: NC1 to NC10 each go red on exactly their observed set through the wrapper, which includes at least the named cases, and green after restore.
- AC8: T57 passes on the tree, and fails when a gate-called path or a blocking hook joins `_DEMOTABLE_GLOBS` (NC9 plus the Grounding negative checks).
- AC9: `bash lib/registry/feature-registry.sh check --fix docs/FEATURES.md` runs last before the final commit and leaves no diff after that commit.
- AC10: with `KIT_CONFIG_OPERATOR` pointed at an empty temp dir, G01 classifies `full` and `explain` ends its reason in `(proof gate off)` (P1, T58).

## Test plan

New section in `tests/test-lane-classify.sh`, `=== kit-machinery bug fixes size as bug (SPEC-362) ===`. Labels carry `[S362-Tnn]`. The suite already exports `KIT_CONFIG_OPERATOR=tests/fixtures/gates-on`, so the proof gate is on for every row except T58. Classifier calls run inside `(cd "$KIT_DIR" && ...)` so `_in_kit_repo` holds; T50 to T52 run in a `mktemp -d` git repo instead. T53 to T56 export `KIT_LEDGER_DIR` and `DWARVES_KIT_LOG_DIR` to one `mktemp -d` dir inside their subshell.

| T | Row | What it pins |
|---|---|---|
| T01 to T49 | G01 to G49 | the After answer in the Grounding table (T13 repeats the existing AC6 text with a new label; T39 runs `escalate tiny` on a temp spec file) |
| T50 to T52 | C1 to C3 | consumer scope |
| T53 | G01 | explain reason and flags, demote path |
| T54 | G07 | explain reason, contract overrule |
| T55 | G05 | explain reason, allowlist overrule |
| T56 | G01, then G07, chosen `bug` | floor check: no warning, then `LANE-DOWNGRADE` |
| T58 | P1 | proof gate off: `KIT_CONFIG_OPERATOR` exported to an empty `mktemp -d` dir inside the subshell; lane `full` and the `(proof gate off)` reason |
| T57 | whole tree | drift guard: (a) no non-allowlisted file under `hooks/*.sh`, `hooks/*.py`, `lib/gate/`, `lib/classify/`, `lib/ledger/`, `lib/wrap/`, `lib/goal/` names an allowlisted code path, its `lib/`-relative suffix, an allowlisted hook's basename, or `bin/<allowlisted dir>` on a non-comment line; (b) no allowlisted `hooks/*.sh` or `hooks/*.py` has a non-comment `exit 2`, `sys.exit(2)`, `permissionDecision` or `"decision":` line. One corpus pass, well under a second. |

## Out of scope

- A diff-content probe (see "Accepted limit").
- Neutral status for `commands/*.md`: declined by lead ruling (commands are operate contracts). 17 of the 83 blocked history commits touch `commands/`.

## Verification

```bash
bash tests/run-all.sh
( T=$(mktemp -d); export KIT_LEDGER_DIR="$T" DWARVES_KIT_LOG_DIR="$T"
  bash lib/classify/lane-classify.sh explain --files "lib/sync/sync_core.py" "fix sync_core dropping the last row when the backlog has no trailing newline"
  bash lib/classify/lane-classify.sh check bug --files "lib/sync/sync_core.py" "fix sync_core so it now also pulls archived rows" )
```

Record: `docs/verification/lane-bug-machinery.md`, with the run table, NC1 to NC10 through `lib/gate/negctl.sh` and the wrapper (each NC's FAIL lines copied in), and the Grounding table re-run against the built classifier.

## Tasks

- [ ] T1: items 1 to 11 (with 7a) in `lib/classify/lane-classify.sh`. No dependency.
- [ ] T2: the new test section (T01 to T58) in `tests/test-lane-classify.sh`. Depends on T1.
- [ ] T3: item 12 docs (`docs/WORKFLOW.md`, `README.md`, `commands/wrap.md`). Depends on T1.
- [ ] T4: run the Verification block; record every deviation from this spec in `docs/implementation-notes/lane-bug-machinery.md` as it arises. Depends on T2 and T3.
- [ ] T5: commit, then NC1 to NC10 via `lib/gate/negctl.sh` and the wrapper on the clean tree; write the proof. Depends on T4.
- [ ] T6: `bash lib/registry/feature-registry.sh check --fix docs/FEATURES.md` as the last step, then the final commit. Depends on T5.
