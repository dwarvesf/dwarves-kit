# Spec: kit-machinery bug fixes size as bug, not full

Generated: 2026-09-29
Status: DRAFT (round 2: folds the round-1 NEEDS REVISION findings and the lead's enforcement-file ruling)
Lane: full (policy change to the lane classifier itself; `lib/classify/*` is an enforcement file)
Type: spec-feature
File: `docs/specs/SPEC-362-lane-bug-machinery.md`
References: `lib/classify/lane-classify.sh` (`_files_touch_machinery`, `classify_core`, the precedence comment at line 19), `tests/test-lane-classify.sh`, `hooks/ship-gate.sh` (proof gate, spec lookup), `lib/gate/proof-ledger.sh` (`classify`, the override guard), `docs/WORKFLOW.md` (lane table), `README.md` (lane-classify row), `commands/wrap.md` (step 10 re-size)

## Problem

`lib/classify/lane-classify.sh` sends every change that touches `lib/` or `hooks/` to `full`. The `--files` path does it through `_files_touch_machinery` (line 89). The text-only path does it through the kit-machinery hard-gate regex (line 60). Neither path asks whether the change is a defect fix.

A 20-line bug fix with a proven root cause then pays for think, spec, fresh-context validation, docs and reflect. The `wrap merge` fix (SPEC-360: the merge ran before the ci-label runs registered) paid that cost this week.

The operator approved a policy change: a kit-machinery change that is a bug fix and introduces no new contract sizes `bug`. A machinery change that changes a contract stays `full`. When both signals fire, contract wins.

Round 1 found the critical hole in that rule: a gate relaxation phrased as a fix ("fix ship-gate wrongly blocking a push whose proof doc has no negative control") carries a bug signal and no contract word. Vocabulary alone cannot close it. The lead ruled a structural guard as the primary defence: a change to an enforcement file never demotes. That ruling has a direct cost: `lib/wrap/wrap.sh` is an enforcement file, so the SPEC-360 fix itself still sizes `full` (Grounding G3). The demotion lands on the rest of the machinery: telemetry, board, session, queue, goal libraries and the non-blocking hooks.

This spec is itself a policy change to the classifier, so it sizes `full` under both the old and the new rule. AGENTS.md "Pause if" lists a risk-classification change as a human decision; the operator made it.

## Change

All code lands in `lib/classify/lane-classify.sh`.

1. Shared bug terms and the machinery bug signal. One string feeds both step 4 and the machinery decision, so step 4's behavior is byte-identical:
   ```
   _bug_terms='\bbug\b|regression|failing test|broken|crash|defect|hotfix|stack ?trace|exception|fix the|fix a |repro'
   _mbug_re="$_bug_terms"'|\bfix(es|ed|ing)?\b|broke|wrong|root[ -]cause'
   ```
   Step 4's `grep -qE` uses `$_bug_terms`. The extra terms apply to the machinery decision only.

2. The text contract signal, matched against the lowercased description, written out in full:
   ```
   \bnew .{0,20}\b(flags?|verbs?|knobs?|options?|subcommands?|commands?|gates?|checks?|guards?|hooks?|lanes?|phases?|markers?|columns?|fields?|env vars?|config keys?)\b
   |\badd(s|ed|ing)?\b.{0,20}\b(flags?|verbs?|knobs?|options?|subcommands?|commands?|gates?|checks?|guards?|hooks?|lanes?|phases?|markers?|columns?|fields?|env vars?|config keys?)\b
   |(^|[^a-z0-9-])--[a-z]
   |renam[a-z]*\b.{0,20}(--|\b(flags?|verbs?|knobs?|options?|subcommands?|commands?|gates?|checks?|guards?|hooks?|lanes?|phases?|markers?|columns?|fields?|env vars?|config keys?)\b)
   |now also|no longer|now (refuses|blocks|merges|allows|skips|accepts|requires)
   |relax|loosen|weaken|narrow|bypass|disabl|opt[ -]out
   |\b(skip|remov|drop|exempt|ignor|turn(s|ed|ing)? off|allow|accept|permit)[a-z]*\b.{0,40}\b(gate|check|guard|hook|proof|override|lane|negative control|requirement|validation)
   |\b(gate|check|guard|hook|proof|override|lane|negative control|requirement|validation)[a-z-]*\b.{0,40}\b(skip|remov|drop|exempt|ignor|turn(s|ed|ing)? off|allow|accept|permit)
   |stop (check|block|requir)|exception for|false positive
   |(wrong(ly)?|incorrectly|falsely) (block|refus|reject|den)
   |\bsize[sd]? (tiny|normal|bug)\b
   |(ledger|log|line|output) format\b
   |install\.sh|\badopt|kit\.toml|hooks\.json|settings\.json
   |\bpolicy\b|\b(bug|full|tiny|normal|backfill) lane\b|\blane (table|rule|trigger|floor)\b
   ```
   The line breaks are for reading; the variable `_mcontract_re` joins them with no whitespace. A bare `--[a-z]` token counts, so a bug text that names an existing flag sizes `full` (accepted over-size). `.{0,20}` between `add` and the noun makes "add a missing guard to fix the crash" a contract signal. `wrong(ly)? fail` is deliberately absent: "wrongly failing on an empty board" is an ordinary defect.

3. The file contract signal, case-insensitive, over the `--files` list:
   ```
   (^|/)(install\.sh|adopt\.sh|hooks\.json|codex-hooks\.json|settings\.json|\.?kit\.toml|WORKFLOW\.md|AGENTS\.md)$|(^|/)lib/config/module-registry\.md$|(^|/)\.claude-plugin/
   ```

4. One helper, `_contract_signal <text|all> <lc>`: `text` tests item 2 only; `all` tests item 2, then item 3 when `--files` was passed. Steps 2b and 3 below both call it.

5. The enforcement set, defined once in a header-commented variable near the flag arrays:
   ```
   # Enforcement files: a change here never demotes to bug, whatever the text says. A gate
   # relaxation reads like a fix ("fix X wrongly blocking Y"), so the file, not the wording,
   # decides. Keep in sync with any hooks/*.sh that blocks (exit 2); the suite pins that.
   _ENFORCEMENT_GLOBS='hooks/*-gate.* hooks/*-guard.* hooks/permission-* hooks/anti-rationalization.sh hooks/commit-format.sh hooks/anchor-root.sh hooks/codex-hook-adapter.sh hooks/hooks.json hooks/codex-hooks.json lib/gate/* lib/classify/* lib/wrap/wrap.sh lib/goal/mega-merge.sh lib/goal/stack-merge.sh'
   # Text-only path: with no file list, a text naming any of these stays full.
   _ENFORCEMENT_WORDS_RE='-gate\b|guard|proof|secrets|classif|gate-ledger|gate-policy|negctl|premerge|mutation-smoke|coverage-delta|permission-|anti-rationalization|commit-format|anchor-root|lib/gate/|lib/classify/|wrap\.sh|wrap (merge|land)|mega-merge|stack-merge|hooks\.json'
   ```
   `_enforcement_hit <lc>`: with `--files`, true when any file matches a glob or `*/<glob>`; without `--files`, true when the text matches `_ENFORCEMENT_WORDS_RE`. Every `grep` over a regex that can start with `-` uses `grep -qE -e`.
   The blocking hooks came from `grep` over `hooks/*.sh` for `exit 2`: anti-rationalization, board-row-gate, citation-guard, codex-hook-adapter, commit-format, safety-gate, secrets-guard, ship-gate, tool-policy-guard. The `-gate.*` and `-guard.*` globs also cover `money-gate.sh`/`.py`, `spec-drift-guard.sh` and `citation-guard.py`. `anchor-root.sh` relays exit codes for the hooks it wraps, so it is listed. `lib/goal/mega-merge.sh` and `lib/goal/stack-merge.sh` are merge automation in the same class as `wrap.sh`'s merge gate; adding them is my extension of the lead's list.

6. Machinery surface, kit repo only. `_files_touch_machinery` keeps `lib/*|hooks/*|*/lib/*|*/hooks/*` and, only when `_in_kit_repo` holds, also fires on a root `install.sh` or a root `settings.json`. `_in_kit_repo` is `[ -f "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/lib/classify/lane-classify.sh" ]`. `lib/adopt.sh`, `hooks/hooks.json` and `hooks/codex-hooks.json` already fire through `lib/*` and `hooks/*`; no any-depth `adopt.sh` or `hooks.json` pattern is added.

7. Machinery contract outranks tiny (step 2). When the tiny regex matches, first test whether the kit-machinery flag would fire (item 8's condition) and `_contract_signal text` holds. When both hold, skip the tiny return and fall through; step 3 sizes it `full`. The file check is excluded here, so a typo sweep whose files include `docs/WORKFLOW.md` stays `tiny`. A tiny text that names `install.sh`, `adopt`, `hooks.json` or `settings.json` does size `full` (accepted over-size).

8. The demotion (step 3, the kit-machinery branch, today lines 150-163). When the flag would fire on either path, add `kit-machinery` to `hard` unless all three hold: the text matches `_mbug_re`, `_enforcement_hit` is false, and `_contract_signal all` is false. When all three hold, set a local `mbug=1` instead. Record which check overruled a bug signal (`enforcement` or `contract`) for the reason line.

9. After the hard-gate verdict: a non-empty `hard` gives `full` as today. When item 8 recorded an overrule, the reason gains ` (enforcement file outranks the bug signal)` or ` (contract signal outranks the bug signal)`. An empty `hard` with `mbug=1` gives `LANE=bug`, `REASON="kit-machinery bug fix (bug signal, no contract signal, no enforcement file)"`, `FIRED="kit-machinery-bug"`.

10. The header precedence comment (line 19) becomes: `backfill > tiny (unless machinery + text contract signal) > hard-gate (kit-machinery demotes to bug on a bug signal with no contract signal and no enforcement file) > bug > soft-count > normal`.

11. Docs:
    - `docs/WORKFLOW.md` lane table: the `full` row's "hooks" becomes "a hook contract"; the `bug` row's "When" cell becomes "a defect, regression, or failing test (not a new feature), incl. a kit-machinery fix with no contract change". One sentence under the table names the enforcement-file exception and points at `_ENFORCEMENT_GLOBS`.
    - `README.md` lane-classify row: one clause, "a machinery bug fix with no contract signal and no enforcement file sizes bug".
    - `commands/wrap.md` step 10 landing item 1: "(it touched auth, a hook, a data model, a contract)" becomes "(it touched auth, a hook contract, an enforcement file, a data model, a contract)".

## Picture

```
 description + --files
        |
        v
 backfill? --yes--> backfill                                  (unchanged)
        | no
 tiny? --yes--> machinery AND text contract signal? (file check excluded)
        |            | no --> tiny          | yes (fall through; step 3 sizes full)
        | no  <-------------------------------+
        v
 other hard flags (auth, data-model, audit-security, ...) --any--> full
        |
 kit-machinery would fire?
 (lib/ | hooks/ file; root install.sh | settings.json in the kit repo; or machinery text)
        | no                                  | yes
        v                                     v
   step 4 bug / soft / normal        bug signal? --no--> full (kit-machinery)
   (step 4 uses _bug_terms,                   | yes
    unchanged)                                v
                                  enforcement file (--files) or enforcement word (text-only)?
                                     | yes --> full (enforcement file outranks the bug signal)
                                     | no
                                     v
                                  contract signal, text or files?
                                     | yes --> full (contract signal outranks the bug signal)
                                     | no  --> bug (kit-machinery-bug)
```

## Design

The decision sits inside the existing kit-machinery branch because that flag is the only one the policy narrows. Auth and data-model stay subject-risky and keep forcing `full`. Two defences stand between a gate relaxation and the `bug` lane: the enforcement set (structural, primary) and the contract vocabulary (textual, secondary). Either one alone keeps `full`.

### Diagram

See `## Picture` above for the decision flow.

### Approaches considered

1. Structural enforcement-file guard plus a demotion inside the kit-machinery branch, with a contract vocabulary as a second defence (chosen, lead ruling).
2. Vocabulary only (round 1's design). Rejected: four reviewers found nine gate-relaxation texts with a bug signal and no contract word.
3. Widen step 4's general bug regex and move it above the hard gate. Rejected: `wrong` and bare `fix` would move non-machinery text such as "fix wrong total in the invoice page" from `normal` to `bug`, and "fix the token refresh crash" would escape the audit-security flag.
4. Apply the demotion on the `--files` path only. Rejected: `/kit:assign` calls `classify` without `--files`. The text-only path instead demotes only when the text names no enforcement word.
5. Move the whole hard gate above tiny. Rejected: "fix a typo in lib/telemetry/lane-telemetry.sh" would size `full` (pinned `tiny` by the suite's AC5).

### Deliberate tradeoff: a spec-less bug-lane machinery fix is held by the proof gate alone

Accepted by the lead. A machinery bug fix in the `bug` lane usually has no spec, so `hooks/ship-gate.sh` never runs its lane-gate check (build, review, debug). The only hook that blocks it is the diff-keyed proof-of-done gate: a green run plus a negative control. That is the same hold every other bug-lane fix has today. The full lane's hook-enforced think, spec, validate, docs and reflect phases are the ceremony this policy drops on purpose. If `/kit:wrap` step 10 builds such a fix (only when an operator adds `bug` to `wrap.build_lanes`), it merges it only through `wrap merge --apply`, whose green gate (`_pr_gate`: checks green, no changes requested, mergeable) must pass, and after the ship-gate proof check at push.

## Grounding

### Classifier output today and after the change

"Today" is real `bash lib/classify/lane-classify.sh classify [--files "<files>"] "<text>"` output on this branch's base (`ad901924`), run from the kit worktree root. "After" comes from a scratch prototype that sources the real classifier for its hard regexes and applies items 1 to 9; it is not the built classifier. "Held by" names the check that decides the after lane.

| ID | --files | Text | Today | After | Held by |
|---|---|---|---|---|---|
| G1 | `lib/telemetry/lane-telemetry.sh tests/test-lane-telemetry.sh` | fix lane-telemetry trace printing the wrong step count for a run with two START lines | full | bug | demotion |
| G2 | `hooks/context-readiness.sh tests/test-hooks.sh` | fix context-readiness wrongly reporting spec:ambiguous when one live spec matches the branch | full | bug | demotion |
| G3 | `lib/wrap/wrap.sh tests/test-wrap.sh` | fix wrap merge merging before the ci-label runs registered | full | full | enforcement file (the SPEC-360 case stays full) |
| G4 | `hooks/ship-gate.sh tests/test-hooks.sh` | ship-gate wrongly resolves the repo root for a relative cd target; root cause is the missing REAL_CWD join | full | full | enforcement file |
| G5 | `lib/gate/gate-ledger.sh tests/test-gate-ledger.sh` | add a --json flag to gate-ledger check | full | full | no bug signal |
| G6 | `lib/telemetry/lane-telemetry.sh` | fix lane-telemetry so it now also prints skipped phases | full | full | text contract (`now also`) |
| G7 | `lib/classify/lane-classify.sh tests/test-lane-classify.sh docs/WORKFLOW.md` | lane-classify: route kit-machinery bug fixes to the bug lane instead of full | full | full | enforcement file (this spec) |
| G8 | (none) | fix the parser in lib/gate/gate-ledger.sh | full | full | enforcement word, text-only (existing suite case, unchanged) |
| G9 | (none) | fix lane-telemetry trace printing the wrong step count for a run with two START lines | full | bug | demotion, text-only |
| G10 | (none) | fix wrong total in the invoice page | normal | normal | machinery does not fire |
| G11 | `lib/gate/x.sh` | fix the token refresh crash | full | full | audit-security flag |
| G12 | `lib/wrap/wrap.sh tests/test-wrap.sh` | rename the --foo flag in lib/wrap/wrap.sh | tiny | full | contract beats tiny |
| G13 | `lib/telemetry/lane-telemetry.sh` | rename a local variable in lib/telemetry/lane-telemetry.sh | tiny | tiny | not a contract rename |
| G14 | (none) | rename the --foo flag in the cli docs | tiny | tiny | machinery does not fire |
| G15 | (none) | rename the --json flag in gate-ledger.sh | tiny | full | contract beats tiny, text-only |
| G16 | (none) | fix a typo in lib/telemetry/lane-telemetry.sh | tiny | tiny | no contract signal |
| G17 | `install.sh` | fix install.sh crashing on a missing config dir | bug | full | kit-repo install.sh is machinery, and a contract file |
| G18 | `settings.json` | register the observe hook for every event in settings.json | normal | full | kit-repo settings.json is machinery, no bug signal |
| G19 | `install.sh` | add a --with flag to install.sh | normal | full | kit-repo install.sh is machinery, no bug signal |
| G20 | `scripts/install.sh config/settings.json` | add a retry loop to the installer | normal | normal | not root files |
| G21 | `hooks/ship-gate.sh` | fix ship-gate wrongly blocking a push whose proof doc has no negative control | full | full | enforcement file and text contract |
| G22 | `hooks/safety-gate.sh` | fix safety-gate wrongly refusing a force push to main | full | full | enforcement file and text contract |
| G23 | (none) | fix the bug: remove the proof check from ship-gate | full | full | enforcement word and text contract |
| G24 | (none) | fix ship-gate by skipping the proof check on docs-only diffs | full | full | enforcement word and text contract |
| G25 | (none) | fix proof-ledger so md-only diffs are exempt from the negative control | full | full | enforcement word and text contract |
| G26 | (none) | fix lane-classify so machinery edits size normal | full | full | enforcement word and text contract |
| G27 | (none) | add an exception for docs-only diffs in ship-gate | full | full | enforcement word and text contract |
| G28 | (none) | fix wrap merge to drop the green-gate requirement | normal | normal | machinery never fired on this text; with `--files lib/wrap/wrap.sh` it is G3's enforcement case |
| G29 | (none) | fix(wrap): accept a --force flag for merge | normal | normal | same as G28 |
| G30 | `lib/telemetry/lane-telemetry.sh` | fix lane-telemetry by skipping the proof check for docs-only runs | full | full | text contract only |
| G31 | `lib/telemetry/lane-telemetry.sh` | fix lane-telemetry by adding an exception for docs-only runs | full | full | text contract only |
| G32 | `lib/board/backlog.sh` | fix backlog next to accept a --force flag | full | full | text contract only |
| G33 | `lib/telemetry/lane-telemetry.sh` | fix lane-telemetry wrongly blocking a run whose proof doc has no negative control | full | full | text contract only |
| G34 | `lib/telemetry/lane-telemetry.sh` | fix lane-telemetry so machinery edits size normal | full | full | text contract only |
| G35 | `hooks/ship-gate.sh` | fix ship-gate resolving the base from a stale origin/HEAD | full | full | enforcement file only |
| G36 | (none) | fix mega-merge.sh skipping the last sub-goal | full | full | enforcement word only |
| G37-G44 | `lib/telemetry/lane-telemetry.sh` plus one of `AGENTS.md`, `hooks/hooks.json`, `lib/adopt.sh`, `.claude-plugin/plugin.json`, `settings.json`, `kit.toml`, `lib/config/module-registry.md`, `docs/WORKFLOW.md` | G1's text | full | full | file contract (`hooks/hooks.json` is also an enforcement file) |

Every existing case in `tests/test-lane-classify.sh` (38 cases) keeps its expected lane under the prototype. Round 1's planned flip of "fix the parser in lib/gate/gate-ledger.sh" is gone: the enforcement word keeps it `full` (G8).

### Consumer effects (the classifier also sizes consumer repos)

- Item 6 is kit-only. In a consumer repo, a root `install.sh` or `settings.json` sizes as today (G17 there gives `bug`, G18 `normal`). `_in_kit_repo` reads the caller's working directory, so a caller that sizes a consumer diff from inside the kit checkout gets the kit rule. That only raises a lane, the safe direction.
- The demotion reaches consumer repos. Today any consumer `lib/` or `hooks/` edit sizes `full` through `lib/*`. After this change, a consumer `lib/` bug fix with no contract signal sizes `bug`, unless its path matches an enforcement glob (a consumer `lib/gate/*` or `lib/classify/*` keeps today's `full`). Under `/kit:wrap` that matters only when an operator lists `bug` in `wrap.build_lanes`.

### Is this a gate bypass? No: the proof is still owed

Traced through `hooks/ship-gate.sh` and `lib/gate/proof-ledger.sh` on this branch:

- The proof-of-done gate (`hooks/ship-gate.sh:98-110`) runs before the spec lookup and keys on the branch DIFF, not the lane. It engages in any repo carrying `docs/verification/README.md`; this repo carries it.
- `proof-ledger.sh classify` (`:77-116`) returns `inert` only for a markdown, txt or `.kit.toml`-only diff. A `.sh` change under `lib/` or `hooks/` is `behavioral` (or `stateful` on deploy or migration words).
- A `behavioral` change needs a `docs/verification/<slug>.md` with a green run AND a negative control (`proof-ledger.sh:411-415`).
- An override does not excuse it: `proof-ledger.sh:377-404` rejects an override when the branch changes any source file.

So a bug-lane machinery change still owes the proof with a negative control. The change removes lane ceremony, not the proof.

### What the change does relax

- `hooks/ship-gate.sh:223-225` exits 0 when no `docs/specs/SPEC-*-<slug>.md` exists. A bug-lane run usually has no spec, so its lane gates (build, review, debug; `gate-ledger.sh plan bug`) are not hook-enforced (the deliberate tradeoff above).
- A negative control on a false-positive fix proves the gate now lets the case through. It does not prove that letting it through was right. That judgment is exactly what the enforcement guard keeps in the `full` lane for gate files; in a non-enforcement file it rests on the review.
- The proof gate itself can be switched off per repo with `[gate] proof_of_done = false` in a committed `.kit.toml`, and a `.kit.toml`-only diff owes no proof. In such a repo a bug-lane machinery fix is held by nothing but the advisory review rule.
- The review-escalation rule (`docs/WORKFLOW.md` "Review escalation": a `lib/` or `hooks/` run owes `/kit:review-team`) is lane-independent and stays advisory.
- `/kit:wrap` step 10 builds and merges non-full items in `wrap.build_lanes`. The default `build_lanes = "tiny"` keeps `bug` out; opting in lets wrap merge a machinery bug fix through `wrap merge --apply`'s green gate with no draft-PR design review.
- `lib/classify/significance-classify.sh` uses a `full` lane as one significance leg. A demoted fix loses that leg; the understanding gate is advisory.

### Accepted limit: the text is pre-diff

The classifier reads the task line and file names, never the diff content. `/kit:wrap` step 10 re-sizes against `git diff --name-only`, so a behavior-relaxing edit inside a non-enforcement machinery file, described with clean bug text, sizes `bug`. The upgrade path, out of scope here: a diff-content probe that flags an added or removed `--flag` definition, a removed `exit 2`, or a changed gate-ledger phase name.

### Negative controls, dry trace

Each runs as `lib/gate/negctl.sh <root> "bash tests/test-lane-classify.sh" "<mutate-cmd>"` on a clean tree after the build commit. "Red on at least" is the minimum the proof must show; "expected set" is the full set traced from the prototype, and the proof records the observed set.

| NC | Mutates | Red on at least | Expected set |
|---|---|---|---|
| NC1 demotion | the `mbug=1` branch in `classify_core` step 3: its condition becomes `false` | T1, T2, T3 | T1, T2, T3, T39, T41 |
| NC2 text contract | `_contract_signal`: the `_mcontract_re` test returns false | T5, T23, T24, T25 | T5, T10, T13, T23, T24, T25, T26, T27, T40, T41 |
| NC2F file contract only | `_contract_signal`: the item 3 file test returns false | T31, T33 | T31, T33, T34, T35, T36, T37, T38 |
| NC3 contract beats tiny | step 2: the item 7 check is removed, tiny returns unconditionally | T10, T13 | T10, T13 |
| NC4 kit-repo surfaces | `_files_touch_machinery`: the `_in_kit_repo` branch is removed | T14, T15 | T14, T15, T16 |
| NC5 enforcement guard | `_enforcement_hit` returns false | T28, T29 | T7, T28, T29, T30, T43 |
| NC6 both defences | `_enforcement_hit` and the `_mcontract_re` test both return false | T19, T20, T21, T22 | T5, T7, T10, T13, T19, T20, T21, T22, T23 to T30, T40, T41, T43 |

NC6 is the control for the pinned round-1 texts: each is held by both defences, so only turning off both reddens them. NC5 and NC2 each prove their own defence on rows the other cannot reach.

## Acceptance criteria

- AC1: every Grounding row G1 to G44 gives its "After" lane from the built classifier.
- AC2: `explain` on G1 prints `reason: kit-machinery bug fix (bug signal, no contract signal, no enforcement file)` and `flags: kit-machinery-bug`. `explain` on G6 ends its reason in `(contract signal outranks the bug signal)`; on G35, in `(enforcement file outranks the bug signal)`.
- AC3: each contract file in item 3 keeps a demotable machinery bug fix `full` (G37 to G44).
- AC4: with `KIT_LEDGER_DIR` and `DWARVES_KIT_LOG_DIR` both set to a temp dir, `check bug --files lib/telemetry/lane-telemetry.sh "<G1 text>"` prints no `LANE-DOWNGRADE`, and `check bug --files lib/telemetry/lane-telemetry.sh "<G6 text>"` prints it.
- AC5: every existing case in `tests/test-lane-classify.sh` keeps its expected lane; no existing expectation changes.
- AC6: `tests/test-lane-classify.sh`, `tests/test-lane-escalation.sh`, `tests/test-significance-classify.sh`, `tests/test-meta.sh`, `tests/test-hooks.sh`, `tests/test-wrap.sh` and `tests/test-e2e.sh` pass. `docs/FEATURES.md` is regenerated when the registry check reports drift.
- AC7: NC1 to NC6 each go red on at least their named cases and green after restore, recorded by `lib/gate/negctl.sh`.
- AC8: every `hooks/*.sh` with a non-comment `exit 2` line matches `_ENFORCEMENT_GLOBS` (T42).
- AC9: in a temp git repo with no `lib/classify/lane-classify.sh`, `--files install.sh` with G17's text gives `bug` and `--files settings.json` with G18's text gives `normal` (T18).

## Test plan

New section in `tests/test-lane-classify.sh`, `=== kit-machinery bug fixes size as bug (SPEC-362) ===`, reusing `classify_is` and `classify_files_is`. Every test that can write a log (T39 to T41) exports `KIT_LEDGER_DIR` and `DWARVES_KIT_LOG_DIR` to one `mktemp -d` dir first.

| T | Row | Category | Expect |
|---|---|---|---|
| T1 | G1 | demotion, lib file | bug |
| T2 | G2 | demotion, hooks file | bug |
| T3 | G9 | demotion, text-only | bug |
| T4 | G5 | no bug signal guard | full |
| T5 | G6 | bug and text contract | full |
| T6 | G7 | this spec's own line | full |
| T7 | G8 | enforcement word, text-only (existing AC6 case, referenced, not duplicated) | full |
| T8 | G10 | non-machinery regression guard | normal |
| T9 | G11 | other hard flag wins | full |
| T10 | G12 | contract beats tiny | full |
| T11 | G13 | non-contract rename stays tiny | tiny |
| T12 | G14 | non-machinery rename stays tiny | tiny |
| T13 | G15 | contract beats tiny, text-only | full |
| T14 | G17 | kit install.sh bug fix | full |
| T15 | G18 | kit settings.json | full |
| T16 | G19 | no bug signal guard, install.sh | full |
| T17 | G20 | consumer-style paths | normal |
| T18 | G17, G18 in a temp non-kit repo | consumer scope of item 6 | bug, normal |
| T19 | G21 | round-1 text, file guard | full |
| T20 | G22 | round-1 text, file guard | full |
| T21 | G23 | round-1 text, text-only | full |
| T22 | G26 | round-1 text, text-only | full |
| T23 | G30 | vocabulary only, skip | full |
| T24 | G31 | vocabulary only, exception for | full |
| T25 | G32 | vocabulary only, bare flag | full |
| T26 | G33 | vocabulary only, wrongly blocking | full |
| T27 | G34 | vocabulary only, size normal | full |
| T28 | G35 | enforcement file only | full |
| T29 | G3 | enforcement file only, the SPEC-360 line | full |
| T30 | G36 | enforcement word only, text-only | full |
| T31 to T38 | G37 to G44 | one row per contract file | full |
| T39 | G1 | explain reason and flags | per AC2 |
| T40 | G6 | explain reason, contract overrule | per AC2 |
| T41 | G1 then G6, chosen `bug` | floor check | no warning, then `LANE-DOWNGRADE` |
| T42 | all `hooks/*.sh` | drift guard: a blocking hook outside `_ENFORCEMENT_GLOBS` fails | pass |
| T43 | G4 | enforcement file, bug text with `root cause` | full |

## Out of scope

- The text-only kit-machinery regex does not list `lib/wrap/` or `wrap.sh`. "rename the --foo flag in lib/wrap/wrap.sh" without `--files` never fires the flag and stays `tiny`; with `--files` it sizes `full` (G12).
- A diff-content probe (see "Accepted limit").
- The keyword lists are a heuristic. A bug fix phrased with a contract word ("add a missing guard to fix the crash") sizes `full`; over-sizing is the safe direction.

## Verification

```bash
bash tests/test-lane-classify.sh
bash tests/test-lane-escalation.sh
bash tests/test-significance-classify.sh
bash tests/test-hooks.sh
bash tests/test-wrap.sh
bash tests/test-e2e.sh
bash tests/test-meta.sh
T=$(mktemp -d); export KIT_LEDGER_DIR="$T" DWARVES_KIT_LOG_DIR="$T"
bash lib/classify/lane-classify.sh explain --files "lib/telemetry/lane-telemetry.sh" "fix lane-telemetry trace printing the wrong step count for a run with two START lines"
bash lib/classify/lane-classify.sh check bug --files "lib/telemetry/lane-telemetry.sh" "fix lane-telemetry so it now also prints skipped phases"
```

Record: `docs/verification/lane-bug-machinery.md`, with the run table, NC1 to NC6 from `lib/gate/negctl.sh`, and the Grounding table re-run against the built classifier.

## Tasks

- [ ] T1: items 1 to 10 in `lib/classify/lane-classify.sh`. No dependency.
- [ ] T2: the new test section (T1 to T43) in `tests/test-lane-classify.sh`. Depends on T1.
- [ ] T3: item 11 docs (`docs/WORKFLOW.md`, `README.md`, `commands/wrap.md`), then regenerate `docs/FEATURES.md` if the registry check drifts. Depends on T2 (the test file is a registry input).
- [ ] T4: run the Verification block; record every deviation from this spec in `docs/implementation-notes/lane-bug-machinery.md` as it arises. Depends on T1 to T3.
- [ ] T5: commit, then the proof-of-done with NC1 to NC6 via `lib/gate/negctl.sh` on the clean tree. Depends on T4.
