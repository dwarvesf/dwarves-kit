# Spec: the hard-path floor sizes a change by its diff when the change adds a workflow file

Generated: 2026-11-25
Status: DRAFT
Lane: full (the build edits `lib/classify/lane-classify.sh` and `lib/gate/ship-rules.sh`, the push gate's own enforcement path, and narrows a hard-path trigger)
Depth: standard (every behavior below was reproduced with the real `floor` verb on scratch repos; the decision brief and the row fix the intent)
Type: spec-feature
References: `lib/classify/lane-classify.sh` (`floor`, `_floor_scan`, `_floor_comment_only`, `_floor_find`, `_floor_drop`); `lib/gate/ship-rules.sh` (`ship_rule_floor`, `_sr_relay`); `docs/specs/SPEC-410-ceremony-fits-diff.md` (the comment-only and docs rules this spec extends); `docs/briefs/DECISION-BRIEF-team-stamp.md` (build step 2, "Lane gate sizing" exit criterion); `tests/test-ceremony-fits-diff.sh` (the suite that gets the new rows).

## Problem

The full lane fires on any hard-path file whatever the change. In one two-day session on a private product repo, four small CI and config edits each owed twelve recorded phases, most of them overrides, and the repo turned `lane_gates` off. An override that nobody reads is not a gate. The repo lost the floor for every later change too, including the ones that deserve it.

Intent: keep the full lane when a change alters what a gate or a hook does. Size by the diff when the change only adds a workflow file, flips one config key, or edits a comment.

## Where the floor stands today

Real `floor` verb, scratch repo with a committed `.kit.toml` (`lane_gates = true`, `extra_hard_paths = "^hooks/|^lib/gate/"`), one existing workflow, one existing hook, base `main`, head one commit. Reproduced with `bash lib/classify/lane-classify.sh floor <root> main`.

| Case | Change | Floor today | Evidence |
|---|---|---|---|
| Add a workflow file | new `.github/workflows/lint.yml` | `full ci: .github/workflows/lint.yml` | `_HP_ci` matches any path under `.github/` (`lane-classify.sh:113`); no rule looks at status or content of a `ci` hit |
| Flip one config key | `wave_cap = 2` to `3` in `.kit.toml` | `full kit-config: .kit.toml` | `_HP_kitconfig` (`:115`); `_floor_comment_only` accepts only comment lines |
| Flip a gate key | `lane_gates = true` to `false` in `.kit.toml` | `full kit-config: .kit.toml` | same; must stay this way |
| Edit a comment, comment follows a comment or the top | `# guard two` reworded in a hook; `# ci notes` reworded at the top of a workflow; `# header` added at the top of `.kit.toml` | no hit | `_floor_comment_only` (`:628`) |
| Edit a comment, comment follows a code line | `# note` appended below code in `.kit.toml`; `# fresh` added under `name: ci` | `full kit-config` / `full ci` | the change-group rule keeps the floor on purpose (SPEC-410) |
| Turn code into a comment | `if [ ... ]` becomes `# if [ ... ]` in a hook | `full extra: hooks/guard.sh` | a changed non-comment line makes `bad = 1` (`:672`) |
| Change a hook's behavior | `exit 2` becomes `exit 0` | `full extra: hooks/guard.sh` | extras are matched in `_floor_find` (`:594`) |
| Workflow add plus hook change | both in one diff | `full ci` (first line wins) | the loop reports the earliest hit |
| Edit a markdown doc under `hooks/` | `hooks/NOTES.md` | no hit | docs are blanked first (`:787`) |

So: comment edits already pass where the change group follows a comment, a blank line after one, or the top of the file. The hook case already owes the full lane. The workflow add and the config-key flip owe the full lane today. Only the workflow add is needed for the Done line.

Two more facts the design leans on:

- A comment-only drop is silent today. Only `[[gate.hard_path_exempt]]`, the test-path default and the sqli carve-out write a `floor-exempt` line on stderr, which `_sr_relay` turns into an `[advisory]` line and a `EXEMPT | floor |` log line (`ship-rules.sh:120-157`).
- `proof-ledger.sh classify` treats a diff made only of `.kit.toml` as `inert`: it owes no proof (`proof-ledger.sh:129-140`). A workflow file classes `behavioral`.

## Terms

Delta only. The glossary `CONTEXT.md` is not touched.

- sized-down: the floor reports no hit for a path it would otherwise report, because the diff content proves the change adds no gate or hook behavior. The full lane's phase ledger is not owed. The proof gate still applies by its own rule.
- additive workflow: a workflow file the diff creates, with no other `.github/` path in the diff, that passes every check under "Rule A".

## Solution

### Approaches considered

1. Sizer inside the floor (chosen). Add one drop rule beside the existing comment-only drop in `_floor_scan`. No new verb, no new config, no change to the hook.
2. A new `[gate]` or `[lanes]` config key that lists path globs the floor may size down. Rejected: a PR could widen the list in the same diff, and the floor already reads config only at the merge base, so the list would only help on the next PR. It also gives the full-lane trigger a second, reviewable-by-nobody exemption path (the rule `_HP_testpath` already refuses: "a config hook here would be a second, unreviewed exemption path").
3. Size by changed-line count (`deescalate`'s approach). Rejected: a one-line `exit 2` to `exit 0` is the change that most needs the full lane.

### Chosen approach + why

The decision comes from the diff content and the path status, read by constants in `lane-classify.sh`. Nothing the PR writes (title, spec header, config, a comment in the file) can widen it. Every rule fails closed: a check that cannot decide leaves the floor standing, as `_floor_comment_only` does.

### Extensibility and boundaries

The load-bearing dimension is the list of shapes the sizer accepts. Today it is one added-workflow shape plus the existing comment-only shape. A new shape is a new drop rule with its own tests and its own `floor-sized` rule name; it edits `lane-classify.sh`, so it owes the full lane itself. The sizer never reads config.

## Picture

```
 git diff --raw base head (status + modes + paths)
        |
        v
  docs blanked --> comment-only drop (existing) --+
        |                                         |  each drop writes
        v                                         |  floor-sized <kind> <rule> <path>
  _floor_find: first hard-path hit                |  on stderr
        |                                         |
        +--> hit is kind ci, status A, ... ------>+--> Rule A (new): all of A1..A7 hold?
        |                                              yes: drop line, look again
        |                                              no / cannot tell: floor stands
        v
  any hit left --> `full <kind>: <path>` --> ship_rule_floor --> ledger check (full)
  no hit left  --> data-loss scan on added lines --> `full data-loss` or nothing
                                                          |
  ship_rule_floor relays floor-sized lines                v
  as [advisory] + `SIZED | floor |` log          nothing: no phase ledger owed;
                                                 proof gate still applies (workflow = behavioral)
```

## Design

### Rule A: a new workflow file is sized down only when it is purely additive and read-only

All of A1 to A7 must hold for the path the loop picked. Any failure, any read error, any doubt: the floor stands.

| # | Check | Why |
|---|---|---|
| A1 | The raw record status is `A` (added) and the head mode is `100644`. `--no-renames` stays, so a rename is a delete plus an add and the delete keeps the floor. A symlink, an executable bit or a gitlink never qualifies. | a modified or deleted workflow changes what an existing check does |
| A2 | The path is `.github/workflows/<name>.yml` or `.yaml`, at the repo root, no deeper directory, and it matches no other hard-path kind, no `extra_hard_paths` pattern and not the secret pattern. | a `login.yml` name or a nested path is not a shape the checks below were written for |
| A3 | No other path in the diff is under `.github/`, whatever its status. At most one workflow is sized per diff. | a second workflow, `CODEOWNERS`, `dependabot.yml`, a composite action or an issue form each alter what CI or review does |
| A4 | The head image is plain text: at most 200 lines, no NUL, no CR, no byte outside printable ASCII and newline. | an unreadable or hidden-byte file cannot be judged |
| A5 | Triggers come from a closed list. The top-level `on:` key must exist and every event it names must be `push`, `pull_request` or `workflow_dispatch`. `schedule` is not on the list: a standing cron job is new behavior. | `pull_request_target`, `workflow_run`, `issue_comment` and `repository_dispatch` run with the base repo's token or secrets |
| A6 | The file declares a top-level `permissions:` key, and the text `write`, `secrets`, `id-token`, `environment`, `deploy` or `publish` appears nowhere in it, comments included, case-insensitive. | read-only token, no secret, no deploy step: the workflow cannot change repo state or reach outside. Substring match on purpose: a false deny keeps the floor, a false allow does not |
| A7 | No name collision with a workflow at the base. The head image's workflow `name:`, every job key under `jobs:` and every job `name:` are compared, case-insensitive and trimmed, with the same set read from every `.github/workflows/*.y*ml` at the base. Any shared name, or more than 50 base workflows, keeps the floor. | a new always-green job that borrows a required check's name would satisfy branch protection without running the real check |

The data-loss scan still runs on the added lines of a sized workflow, because the scan reads added lines of every non-doc file after the path loop. A `drop table` line in a sized workflow still returns `full data-loss`.

Decision on state-changing workflows: stricter reading. A workflow that can change repo state (write permission, a trigger that carries secrets, a deploy step) still owes the full lane, by A5 and A6. Residual, accepted: any workflow runs the code it names on the runner when its trigger fires. Sizing removes the phase ledger only; the proof gate and review still apply.

### Rule B: comment-only edits (existing, now logged)

Unchanged semantics: `*.sh *.bash *.zsh *.py *.toml *.yml *.yaml *.tf`, `Dockerfile`, `*.dockerfile`, under the change-group, position, suppression and data-line rules of SPEC-410. A change that turns code into a comment is a changed non-comment line and keeps the floor. JSON has no comment syntax, so a JSON change always keeps the floor. Markdown is a doc and is never a hit. The new part is the audit line, see below.

### Rule C: flipping one config key is not sized in this spec

The row names it, the Done line does not need it, and three facts argue against building it now:

1. The config edit that started the row (turning `lane_gates` off) is a gate change. The brief's own rule keeps it full. Every `[gate]` and `[proof]` key, `commit_format`, `board_row_gate`, `[[gate.hard_path_exempt]]`, `[lanes]` and `[lane.*]` is in that class.
2. A `.kit.toml`-only diff classes `inert`, so a sized `.kit.toml` change would owe neither the phase ledger nor a proof. That breaks the bar that a sized change still owes its proof. Fixing it means changing the proof class of `.kit.toml`, a separate gate change.
3. No key in `kit.toml` is both behavior-neutral and worth the surface. The only candidates are advisory thresholds (`[ledger] delivery_ratio_warn`, `delivery_real_floor`). `[mega]`, `[merge]` and `[wrap]` keys change how PRs merge.

If the operator wants it, the follow-on spec adds a closed `(section, key)` constant list in `lane-classify.sh`, requires the diff to be exactly one changed `key = value` line, and first makes `.kit.toml` diffs owe a proof. Any key not on the list, any added or removed key, any change inside `[gate]`, `[proof]`, `[lanes]`, `[lane.*]` or `[[gate.hard_path_exempt]]` keeps the floor.

### The audit line

Every drop by Rule A or Rule B writes one TAB line on the floor's stderr, path last (a path cannot forge a field):

```
floor-sized<TAB><kind><TAB><rule><TAB>-<TAB><reason><TAB>-<TAB><path>
rule = additive-workflow | comment-only
```

`_sr_relay` maps it to `A<TAB>[advisory] hard-path sized <kind>: <path> (<rule>)` and `L<TAB>SIZED | floor | <rid> (<kind>: <path>; <rule>)`, with the same folding of non-ASCII bytes and `|`, and the same cap (20 lines, then one count line). `_floor_check` already carries `SR_NOTICES` into the exit-0 hook message, so `hooks/ship-gate.sh` needs no change. A sized-down diff that still ends in `full ...` (a mixed diff) prints the notices and then the BLOCKED message, as exemptions do today.

### Where the config is read

The sizer reads none. Rule A and Rule B are constants in `lane-classify.sh`. `ship_rule_floor` keeps reading `lane_gates` and the exemptions at the merge base (`ship-rules.sh:172`, `KIT_FLOOR_CONFIG_AT`), so a PR that adds a workflow and sets `lane_gates = false` is a `kit-config` hit in the same diff and the floor reads the switch from the base.

### Callers

`lane-classify.sh floor` has four callers: `ship_rule_floor` (the hook and the mega gate, twice), `_negctl_required` in `proof-ledger.sh` and `battery-gate.sh`. All of them see the new answer. Intended effects: a sized workflow add owes no phase ledger and, in a mega run, passes the merge gate's floor; `battery-gate.sh` may print `SKIP: small change` for it (it owes a proof, not the battery). `_negctl_required` also asks `explain --files`, which still flags `.github/` as a hard path, so under `negative_control = full` a sized workflow keeps its negative-control requirement. That is the stricter side and stays.

## Failure modes

| Class | Mitigation |
|---|---|
| A workflow claims it is trivial (title, spec `Lane: tiny`, a comment saying so) | no rule reads those; a comment holding a deny word keeps the floor; `ship_rule_floor` ignores the spec lane |
| A PR adds a workflow and turns `lane_gates` off in the same diff | the `.kit.toml` change is its own `kit-config` hit; the switch is read at the merge base |
| A PR edits an existing workflow to weaken a check | status `M` fails A1 |
| A PR renames a workflow and weakens it | `--no-renames` gives a delete plus an add; the delete keeps the floor |
| A new workflow shadows a required check name | A7 |
| A new workflow runs on `pull_request_target` or `workflow_run`, or holds a write grant, a secret, a deploy step | A5 and A6 |
| A hidden or odd byte, a CR, an oversized file, an unreadable blob | A4 and fail-closed reads |
| Mixed diff: sized file plus any other hard-path change | the loop drops the sized line and looks again; any other hit decides the answer |
| Two sized workflows in one diff | A3 |
| Sizer slow on a pathological diff | shares the 50 drop and 8 second budget of the comment-only loop; past either, the floor stands |
| A workflow still executes arbitrary code on the runner | accepted and stated above; the phase ledger was never the control for that |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: status and mode capture | `lib/classify/lane-classify.sh` | `_floor_scan` writes a status and a head mode per path line next to `paths`, blanked and dropped in step with it by `_floor_blank` and `_floor_drop` |
| T2: Rule A | `lib/classify/lane-classify.sh` | `_floor_workflow_additive` returns 0 only when A1 to A7 hold; the loop calls it for a `ci` pick the way it calls `_floor_comment_only`; any failure leaves the pick standing |
| T3: audit line | `lib/classify/lane-classify.sh`, `lib/gate/ship-rules.sh` | both drop rules write `floor-sized`; `_sr_relay` turns it into an `[advisory]` and a `SIZED` log line, capped at 20 |
| T4: tests | `tests/test-ceremony-fits-diff.sh` | each row of the test plan has a case; the suite goes red on the merge-base libs |
| T5: docs | `lib/gate/README.md`, `docs/MANUAL.md` (floor paragraph), `docs/WORKFLOW.md` (hard-path paragraph: `ci` is exempt-proof by config, sized only by Rule A), `CHANGELOG.md`, `docs/reference/FEATURES.md` | each names Rule A and the audit line; no file claims a config key sizes the floor |

## Test plan

Date: 2026-11-25
Source: this spec's Acceptance Criteria

All rows are cases in `tests/test-ceremony-fits-diff.sh`, run with `bash tests/test-ceremony-fits-diff.sh <case>`. Fixture: scratch repo, committed `.kit.toml` with `lane_gates = true` and `extra_hard_paths = "^hooks/|^lib/gate/"`, one existing workflow and one existing hook at base.

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|-------------|----------|-------|
| 1 | `floor-additive-workflow-is-sized`: add one valid workflow (`on: [push, pull_request]`, `permissions: contents: read`, one `run` step) | happy-path | AC-1 | `floor` prints nothing; stderr holds one `floor-sized ci additive-workflow` line | case PASS |
| 2 | `ship-rule-floor-sizes-workflow-add`: `ship_rule_floor` on that diff with a ledger holding no phases | happy-path | AC-1, AC-6 | returns 0; the log holds `SIZED | floor |`; no `BLOCKED` | case PASS |
| 3 | `sized-workflow-still-owes-proof`: `proof-ledger.sh classify` on the diff, then `check` with no proof file, then with one | happy-path | AC-3 | class `behavioral`; `check` exits 1 without a proof, 0 with a green proof carrying a negative control | case PASS |
| 4 | `floor-hook-behavior-change-keeps-full`: `exit 2` becomes `exit 0` in `hooks/guard.sh`; and `ship_rule_floor` with a `Lane: tiny` spec | happy-path | AC-2 | `full extra: hooks/guard.sh`; BLOCKED naming the missing gates | case PASS |
| 5 | `floor-workflow-plus-hook-change-keeps-full`: add a valid workflow and change the hook | boundary | AC-4 | `full extra: hooks/guard.sh` | case PASS |
| 6 | `floor-workflow-plus-gate-off-keeps-full`: add a valid workflow and set `lane_gates = false` in `.kit.toml`; then `ship_rule_floor` | security | AC-4, AC-5 | `full kit-config: .kit.toml`; `ship_rule_floor` blocks (switch read at the base) | case PASS |
| 7 | `floor-edited-workflow-keeps-full`: a `run` line changed in the existing workflow | security | AC-4 | `full ci` | case PASS |
| 8 | `floor-renamed-workflow-keeps-full`: existing workflow removed, new name added | security | AC-4 | `full ci` | case PASS |
| 9 | `floor-two-new-workflows-keep-full`: two valid new workflows | boundary | AC-4 | `full ci` | case PASS |
| 10 | `floor-workflow-risky-triggers-keep-full`: `pull_request_target`, `workflow_run`, `issue_comment`, `schedule`, `repository_dispatch`, a missing `on:` | security | AC-4 | each `full ci` | case PASS |
| 11 | `floor-workflow-state-changing-keeps-full`: `permissions: write-all`, `contents: write`, `${{ secrets.X }}`, `environment: prod`, a `deploy` step, `id-token`, no `permissions:` key | security | AC-4 | each `full ci` | case PASS |
| 12 | `floor-workflow-claims-do-not-count`: a valid workflow whose comment says `sized, lane tiny` and holds the word `deploy`; a valid workflow with a `Lane: tiny` spec in the diff | security | AC-4 | the first `full ci`; the second sized (the claim changes nothing) | case PASS |
| 13 | `floor-workflow-name-collision-keeps-full`: the new workflow reuses the base workflow's job key, then its job `name:`, then its workflow `name:`, in a different case | security | AC-4 | each `full ci` | case PASS |
| 14 | `floor-workflow-odd-path-keeps-full`: `.github/workflows/sub/x.yml`, `.github/workflows/x.yml.off`, `.github/workflows/login.yml`, `.github/actions/a/action.yml`, `.github/CODEOWNERS`, `.github/dependabot.yml`, a new `.github/x.json` | boundary | AC-4 | each a hit (`full ci`, or `full auth` for `login.yml`) | case PASS |
| 15 | `floor-workflow-odd-file-keeps-full`: symlink, mode `100755`, a CR byte, a non-ASCII byte, 201 lines, an empty file | failure-injection | AC-4 | each `full ci` | case PASS |
| 16 | `floor-workflow-data-loss-line-keeps-full`: a valid workflow with a `drop table` line in a `run` step | security | AC-4 | `full data-loss: .github/workflows/<name>.yml` | case PASS |
| 17 | `floor-workflow-unreadable-head-keeps-full`: the head ref cannot be read (bad head) | failure-injection | AC-4 | no sizing; the floor result matches today's | case PASS |
| 18 | `floor-code-to-comment-keeps-full`: `if [ ... ]` becomes `# if [ ... ]` in the hook; JSON change under `.github/`; `.kit.toml` comment below code | security | AC-4 | each a hit | case PASS |
| 19 | `floor-comment-edit-is-sized-and-logged`: reword a comment that follows a comment | regression | AC-1, AC-6 | no hit; stderr holds `floor-sized ... comment-only` | case PASS |
| 20 | `floor-config-key-flip-keeps-full`: `wave_cap = 3`, then `lane_gates = false` | regression | AC-5 | each `full kit-config` | case PASS |
| 21 | `sized-notices-relay-and-cap`: feed 25 `floor-sized` lines to `_sr_relay`; one with `|` and a non-ASCII byte in the path | boundary | AC-6 | 20 `A` and 20 `L` lines, one count line; the odd bytes folded to `?` | case PASS |
| 22 | `floor-sized-mixed-flood-keeps-floor`: 51 comment-only files plus one workflow add | boundary | AC-4 | the existing cap leaves a hit (floor stands) | case PASS |
| 23 | regression: `bash tests/test-ceremony-fits-diff.sh`, `bash tests/test-lanes-data.sh`, `bash tests/test-classify-md-inert.sh`, `bash tests/test-hooks.sh`, then `bash tests/run-all.sh --changed` | regression | AC-7 | exit 0 | the command lines |

### Coverage notes
- Categories skipped: none.
- The negative control (Verification) restores `lane-classify.sh` and `ship-rules.sh` from the merge base; rows 1, 2, 3 (via the sizing of row 2), 19 and 21 must go red.
- Not covered by a dedicated case: the real hook end to end on a live push. Row 2 covers `ship_rule_floor`, which the hook calls unchanged.
- This is a coverage target, not an exhaustive list.

## Verification

Each acceptance criterion holds, `bash tests/test-ceremony-fits-diff.sh` passes with the new cases, the negative control (`lib/gate/negctl.sh` with that command; mutation: restore `lane-classify.sh` and `ship-rules.sh` from the merge base) reports PASS, and `bash tests/run-all.sh --changed` exits 0.

## After state

A PR that adds one read-only CI workflow file passes the push gate with a proof and no phase ledger. A PR that changes what a hook or gate does, edits an existing workflow, adds a second one, or turns a gate off still owes the full lane. Every drop the sizer makes is an `[advisory]` line on the push and a `SIZED | floor |` line in the audit log, next to the `EXEMPT` lines.

## Acceptance Criteria (global)

- AC-1: a diff that adds one workflow file passing A1 to A7 yields no `floor` hit; comment-only edits stay sized.
- AC-2: a diff that changes a hook's behavior yields `full extra: <path>` and `ship_rule_floor` blocks it without the full lane's gates.
- AC-3: a sized workflow add still classes `behavioral` and owes its proof.
- AC-4: every check that cannot decide, every mixed diff, and every row of the failure-modes table keeps the floor.
- AC-5: the sizer reads no config; the floor reads `lane_gates` at the merge base; no config-key flip is sized.
- AC-6: every sized drop writes one `floor-sized` line and the push shows one `[advisory]` and one `SIZED` log line, capped at 20.
- AC-7: the existing floor, exemption, data-loss and comment-only suites stay green.

## Out of Scope

- Sizing a config-key flip (Rule C): deferred, with the reasons above.
- Sizing a modified existing workflow, a second workflow in one diff, `CODEOWNERS`, `dependabot.yml` and composite actions.
- Changing `hooks/ship-gate.sh`, the proof class of `.kit.toml` diffs, `_negctl_required` or `battery-gate.sh`.
- `//` and `/* */` comment syntax (SPEC-410's decision stands).

## Touches

`lib/classify/lane-classify.sh`, `lib/gate/ship-rules.sh`, `tests/test-ceremony-fits-diff.sh`, `lib/gate/README.md`, `docs/MANUAL.md`, `docs/WORKFLOW.md`, `CHANGELOG.md`, `docs/reference/FEATURES.md`, `docs/verification/lane-gate-diff-size.md`, `docs/implementation-notes/lane-gate-diff-size.md`.

An open draft PR for an external design citation verb edits `lib/gate/ship-rules.sh` (the BLOCKED block of `ship_rule_floor` and a new helper) and one `hooks/ship-gate.sh` line. This spec edits `_sr_relay` and leaves that block alone, so a later rebase meets only the shared docs files.

## Decision Log

- Scope is Rule A plus the existing Rule B logged, not the three cases in the row. The Done line names two pinned rows; the comment case already passes, and the config-key case conflicts with the proof bar (the `.kit.toml` proof class is `inert`) and with the row's own motivating edit. The smallest honest design that meets the Done line is "add the workflow-file case, log the drops, add the tests".
- The stricter reading for state-changing workflows: a closed trigger list, an explicit read-only `permissions:` key, and a substring deny list that counts comments. A false deny costs one phase ledger; a false allow costs a gate.
- At most one sized workflow per diff, and any other `.github/` path in the diff keeps the floor. This is stricter than the Done line needs and trivial to relax later.
- Name collision (A7) is in because a new workflow whose job reuses a required check's name defeats branch protection without touching any gate file.
- The sizer is constants in `lane-classify.sh`, never config, so a PR cannot widen it and the merge-base rule needs no new branch.
- `hooks/ship-gate.sh` stays untouched: notices ride `SR_NOTICES` already. This also avoids the one-line overlap with the open design-citation PR.
- Comment-only drops now log too, so "every decision the sizer makes" is true of both rules, not only the new one.
