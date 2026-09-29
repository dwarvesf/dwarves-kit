# Spec: kit-machinery bug fixes size as bug, not full

Generated: 2026-09-29
Status: DRAFT
Lane: full (policy change to the lane classifier itself; kit-machinery hard gate on lib/)
Type: spec-feature
File: `docs/specs/SPEC-362-lane-bug-machinery.md`
References: `lib/classify/lane-classify.sh` (`_files_touch_machinery`, the kit-machinery branch of `classify_core`), `tests/test-lane-classify.sh`, `hooks/ship-gate.sh` (proof gate, spec lookup), `lib/gate/proof-ledger.sh` (`classify`, the override guard), `docs/WORKFLOW.md` (lane table), `README.md` (lane-classify row)

## Problem

`lib/classify/lane-classify.sh` sends every change that touches `lib/` or `hooks/` to `full`. The `--files` path does it through `_files_touch_machinery` (line 89). The text-only path does it through the kit-machinery hard-gate regex (line 60). Neither path asks whether the change is a defect fix.

A 20-line bug fix with a proven root cause then pays for think, spec, fresh-context validation, docs and reflect. The `wrap merge` fix (SPEC-360: the merge ran before the ci-label runs registered) paid that cost this week. The fix changed no flag, no verb and no promise.

The operator approved a policy change: a kit-machinery change that is a bug fix and introduces no new contract sizes `bug`. A machinery change that changes a contract stays `full`. When both signals fire, contract wins.

This spec is itself a policy change to the classifier, so it sizes `full` under both the old and the new rule. AGENTS.md "Pause if" lists a risk-classification change as a human decision; the operator made it.

## Change

1. Add two index-free signal regexes to `lib/classify/lane-classify.sh`, matched against the lowercased description:
   - `_mbug_re`, the machinery bug signal: `\bfix(es|ed|ing)?\b`, `\bbug\b`, `regression`, `broke`, `wrong`, `root[ -]cause`, plus the existing step-4 bug terms (`failing test`, `crash`, `defect`, `hotfix`, `stack ?trace`, `exception`, `repro`).
   - `_mcontract_re`, the contract signal: a new or added flag, verb, knob, option, subcommand, gate, check, guard, hook, lane, phase, marker, column, field, env var or config key (`\bnew (...)`, `\badd(s|ed|ing)? (a |an |the )?(new )?(--?[a-z]|...)`); `renam`; a changed promise (`now also`, `no longer`, `now (refuses|blocks|merges|allows|skips|accepts|requires)`); a relaxed gate (`relax`, `loosen`, `weaken`, `narrow`, `bypass`, `disabl`, `opt[ -]out`); a format change (`(ledger|log|line|output) format`); install and adopt surfaces (`install\.sh`, `adopt`, `kit\.toml`, `hooks\.json`, `settings\.json`); policy (`policy`, `(bug|full|tiny|normal|backfill) lane`, `lane (table|rule|trigger|floor)`).
2. Add one file-list contract check, case-insensitive, over the `--files` list: `(^|/)(install\.sh|adopt\.sh|hooks\.json|settings\.json|WORKFLOW\.md|AGENTS\.md)$` or a path under `.claude-plugin/`.
3. In the kit-machinery branch of `classify_core` (lines 150-163), when the flag would fire on either path: if the description matches `_mbug_re` and neither the description nor the file list carries a contract signal, do not add `kit-machinery` to the hard list and set a local `mbug=1`. Otherwise add `kit-machinery` as today. When the bug signal fired but a contract signal overruled it, remember that for the reason line.
4. After the hard-gate verdict (line 166): if `hard` is non-empty, the lane is `full` as today. The reason gains ` (contract signal outranks the bug signal)` when step 3 recorded an overrule. If `hard` is empty and `mbug=1`, set `LANE=bug`, `REASON="kit-machinery bug fix (bug signal, no contract signal)"`, `FIRED="kit-machinery-bug"`.
5. Every other flag, step and precedence stays: backfill, then tiny, then the other hard flags (auth, data-model, audit-security, ...), which still force `full` for a bug fix. The extended bug terms apply to the machinery decision only; step 4's general bug regex is unchanged, so non-machinery text keeps its lane.
6. Docs, one sentence each: the `docs/WORKFLOW.md` lane table (below the table, beside "When in doubt"), the `README.md` lane-classify row, and the header comment of `lane-classify.sh`. The `commands/wrap.md` step-10 parenthetical "(it touched auth, a hook, a data model, a contract)" becomes "(it touched auth, a hook contract, a data model, a contract)".

## Picture

```
 description + --files
        |
        v
 backfill? --yes--> backfill            (unchanged)
        | no
 tiny?     --yes--> tiny                (unchanged)
        | no
 other hard flags (auth, data-model, audit-security, ...) --any--> full
        |
 kit-machinery would fire (lib/|hooks/ file, or machinery text)?
        | no                                    | yes
        v                                       v
   step 4 bug / soft / normal         bug signal?  --no--> full (kit-machinery)
   (unchanged)                                  | yes
                                                v
                                      contract signal in text or files?
                                         | yes                  | no
                                         v                      v
                                   full (contract            bug (kit-machinery-bug)
                                   outranks bug)
```

## Design

The decision sits inside the existing kit-machinery branch because that flag is the only one the policy narrows. Auth and data-model stay subject-risky and keep forcing `full`.

### Approaches considered

1. Demote inside the kit-machinery branch with a bug regex and a contract regex (chosen). One place, both paths (`--files` and text-only) behave the same, and the other hard flags still win.
2. Widen step 4's general bug regex and move it above the hard gate. Rejected: `wrong` and bare `fix` would move non-machinery text such as "fix wrong total in the invoice page" from `normal` to `bug`, and a bug above the hard gate would let "fix the token refresh crash" escape the audit-security flag.
3. Apply the demotion on the `--files` path only. Rejected: the same bug text would size `full` without `--files` and `bug` with it, and `/kit:assign` calls `classify` without `--files`.

## Grounding

### Classifier output today and after the change

Run from the worktree root with `bash lib/classify/lane-classify.sh explain --files "<files>" "<text>"`. The "today" column is real output from this branch's base (`ad901924`). The "after" column is the expected output; the signal columns come from running the proposed regexes against the lowercased text in a scratch script, not from the built classifier.

| # | Kind | --files | Text | Today | Bug sig | Contract sig | After |
|---|---|---|---|---|---|---|---|
| S1 | machinery bug fix | `lib/wrap/wrap.sh tests/test-wrap.sh` | fix wrap merge merging before the ci-label runs registered | full (hard-gate flag(s): kit-machinery) | yes (`fix`) | no | bug |
| S2 | machinery bug fix | `hooks/ship-gate.sh tests/test-hooks.sh` | ship-gate wrongly resolves the repo root for a relative cd target; root cause is the missing REAL_CWD join | full (hard-gate flag(s): kit-machinery) | yes (`wrong`, `root cause`) | no | bug |
| S3 | machinery contract change | `lib/gate/gate-ledger.sh tests/test-gate-ledger.sh` | add a --json flag to gate-ledger check | full (hard-gate flag(s): kit-machinery) | no | yes (`add a --`) | full |
| S4 | machinery contract change, both fire | `lib/wrap/wrap.sh tests/test-wrap.sh` | fix wrap merge so it now also merges stacked PRs | full (hard-gate flag(s): kit-machinery) | yes (`fix`) | yes (`now also`) | full, reason adds "contract signal outranks the bug signal" |
| S5 | this spec | `lib/classify/lane-classify.sh tests/test-lane-classify.sh docs/WORKFLOW.md` | lane-classify: route kit-machinery bug fixes to the bug lane instead of full | full (hard-gate flag(s): kit-machinery) | yes (`fixes`, `bug`) | yes (`bug lane`, file `WORKFLOW.md`) | full |
| S6 | text-only machinery bug | (none) | fix the parser in lib/gate/gate-ledger.sh | full (hard-gate flag(s): kit-machinery) | yes | no | bug |
| S7 | non-machinery, regression guard | (none) | fix wrong total in the invoice page | normal | n/a | n/a | normal |
| S8 | other hard flag wins | `lib/gate/x.sh` | fix the token refresh crash | full | yes | no | full (audit-security) |

### Is this a gate bypass? No: the proof is still owed

Traced through `hooks/ship-gate.sh` and `lib/gate/proof-ledger.sh` on this branch:

- The proof-of-done gate (`hooks/ship-gate.sh:98-110`) runs before the spec lookup and keys on the branch DIFF, not the lane. It engages in any repo carrying `docs/verification/README.md`; this repo carries it.
- `proof-ledger.sh classify` (`:77-116`) returns `inert` only for a markdown, txt or `.kit.toml`-only diff. A `.sh` change under `lib/` or `hooks/` is `behavioral` (or `stateful` on deploy or migration words).
- A `behavioral` change needs a `docs/verification/<slug>.md` with a green run AND a negative control (`proof-ledger.sh:411-415`).
- An override does not excuse it: `proof-ledger.sh:377-404` rejects an override when the branch changes any source file, and a `lib/` or `hooks/` `.sh` file counts.

So a bug-lane machinery change still owes the proof with a negative control. The change removes lane ceremony, not the proof.

What the change does relax, stated plainly:

- `hooks/ship-gate.sh:223-225` exits 0 when no `docs/specs/SPEC-*-<slug>.md` exists. A bug-lane run usually has no spec, so its lane gates (build, review, debug; `gate-ledger.sh plan bug`) are not hook-enforced. Today the full lane's spec made think, spec, validate, build, review, docs, ship and reflect hook-enforced for the same fix. That is the ceremony the operator chose to drop.
- The review-escalation rule (`docs/WORKFLOW.md` "Review escalation": a `lib/` or `hooks/` run owes `/kit:review-team`) is lane-independent and stays. It was advisory before and stays advisory.
- `/kit:wrap` step 10 builds and merges non-full items in `wrap.build_lanes` and never merges a `full` one. The shipped default `build_lanes = "tiny"` keeps `bug` out. An operator who adds `bug` to that list lets wrap build and merge a machinery bug fix after its checks pass and its proof gate clears, with no draft-PR design review. This is the intended effect of the policy, and it stays opt-in.
- `lib/classify/significance-classify.sh` uses a `full` lane as one significance leg. A machinery bug fix loses that leg; its other text triggers still apply. The understanding gate is advisory.

### Negative control, dry trace

NC1, the demotion. Mutation: in the kit-machinery branch, replace the demotion condition with `false`, so `kit-machinery` is always added (the old behavior). Run `bash tests/test-lane-classify.sh`. Red cases: T1 (S1 expects `bug`, gets `full`), T2 (S2), T6 (S6). Restore, rerun, green.

NC2, contract wins. Mutation: make the contract check always report "no contract signal" (the text regex match and the file check both short to false). Red cases: T4 (S4 expects `full`, gets `bug`), T5 (S5), T7 (the `WORKFLOW.md` file case), T8 (the `bypass` case). Restore, rerun, green.

Both run through `lib/gate/negctl.sh <root> "bash tests/test-lane-classify.sh" "<mutate-cmd>"` on a clean tree after the build commit, and the output lands in the proof doc.

## Acceptance criteria

- AC1: S1, S2 and S6 classify `bug`. S3, S4 and S5 classify `full`. S7 stays `normal`. S8 stays `full`.
- AC2: `explain` on S1 prints `reason: kit-machinery bug fix (bug signal, no contract signal)` and `flags: kit-machinery-bug`. `explain` on S4 prints a reason ending in `(contract signal outranks the bug signal)`.
- AC3: a contract file in `--files` (`WORKFLOW.md`, `install.sh`, `hooks.json`, `settings.json`, `AGENTS.md`, `adopt.sh`, `.claude-plugin/`) keeps a machinery bug fix `full`.
- AC4: `check bug --files lib/wrap/wrap.sh "<S1 text>"` prints no `LANE-DOWNGRADE`. `check bug --files lib/wrap/wrap.sh "<S4 text>"` prints it.
- AC5: every other existing case in `tests/test-lane-classify.sh` keeps its expected lane. The one planned flip is the AC6 gate-ledger case, noted in the implementation notes.
- AC6: `tests/test-lane-classify.sh`, `tests/test-lane-escalation.sh`, `tests/test-significance-classify.sh` and `tests/test-meta.sh` pass. `docs/FEATURES.md` is regenerated if the registry check reports drift.
- AC7: NC1 and NC2 each go red on the named cases and green after restore, recorded by `lib/gate/negctl.sh`.

## Test plan

New section in `tests/test-lane-classify.sh`, `=== kit-machinery bug fixes size as bug (SPEC-362) ===`, reusing `classify_is` and `classify_files_is`, plus an `explain` and a `check` assertion in the file's style.

| # | Category | --files | Text | Expect |
|---|---|---|---|---|
| T1 | happy, lib bug | `lib/wrap/wrap.sh tests/test-wrap.sh` | S1 text | bug |
| T2 | happy, hooks bug | `hooks/ship-gate.sh tests/test-hooks.sh` | S2 text | bug |
| T3 | contract, no bug signal | `lib/gate/gate-ledger.sh` | add a --json flag to gate-ledger check | full |
| T4 | both fire, text | `lib/wrap/wrap.sh` | S4 text | full |
| T5 | both fire, policy | `lib/classify/lane-classify.sh docs/WORKFLOW.md` | S5 text | full |
| T6 | text-only bug (flipped AC6 case) | (none) | fix the parser in lib/gate/gate-ledger.sh | bug |
| T7 | contract by file | `lib/wrap/wrap.sh install.sh` | fix wrap crashing on a missing config | full |
| T8 | relaxed gate | `hooks/ship-gate.sh` | fix the bug where ship-gate lets a push bypass the proof check | full |
| T9 | other hard flag wins | `lib/gate/x.sh` | fix the token refresh crash | full |
| T10 | non-machinery regression guard | (none) | fix wrong total in the invoice page | normal |
| T11 | no bug signal, unchanged | `hooks/ship-gate.sh` | tweak a message | full (existing case) |
| T12 | explain reason, bug | `lib/wrap/wrap.sh` | S1 text | reason and flags per AC2 |
| T13 | explain reason, overrule | `lib/wrap/wrap.sh` | S4 text | reason suffix per AC2 |
| T14 | floor check | `lib/wrap/wrap.sh` | S1 text, then S4 text, chosen `bug` | no warning, then `LANE-DOWNGRADE` (stderr; `DWARVES_KIT_LOG_DIR` pointed at a temp dir so the suite writes no operator log) |
| T15 | new gate-ledger contract guard | (none) | add a --json flag to lib/gate/gate-ledger.sh | full |

Negative controls: NC1 turns T1, T2 and T6 red. NC2 turns T4, T5, T7 and T8 red.

## Out of scope

- `tiny` precedes the hard gate, so "rename the --foo flag in gate-ledger" sizes `tiny` today, not `full`. The operator's "a renamed flag stays full" is not met by the current classifier either. This spec does not change tiny precedence; the lead decides whether that is a separate change.
- `_files_touch_machinery` matches only `lib/` and `hooks/`. With `--files install.sh` alone, the kit-machinery flag does not fire and the change sizes by text. Widening the machinery surface is a separate change.
- The keyword lists are a heuristic. A bug fix phrased with a contract word ("add a missing guard to fix the crash") sizes `full`; over-sizing is the safe direction.

## Verification

```bash
bash tests/test-lane-classify.sh
bash tests/test-lane-escalation.sh
bash tests/test-significance-classify.sh
bash tests/test-meta.sh
for s in 'lib/wrap/wrap.sh tests/test-wrap.sh|fix wrap merge merging before the ci-label runs registered' \
         'lib/wrap/wrap.sh tests/test-wrap.sh|fix wrap merge so it now also merges stacked PRs'; do
  bash lib/classify/lane-classify.sh explain --files "${s%%|*}" "${s#*|}"
done
```

Record: `docs/verification/lane-bug-machinery.md`, with the run table, NC1 and NC2 from `lib/gate/negctl.sh`, and the Grounding table re-run against the built classifier.

## Tasks

- [ ] T1: signals, file check and the demotion in `lib/classify/lane-classify.sh`; header comment sentence.
- [ ] T2: the new test section and the flipped AC6 case in `tests/test-lane-classify.sh`.
- [ ] T3: one sentence each in `docs/WORKFLOW.md`, `README.md`, `commands/wrap.md`; regenerate `docs/FEATURES.md` if the check drifts.
- [ ] T4: proof-of-done with NC1 and NC2.
