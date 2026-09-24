# Spec: wrap follow-through runs the in-lane leftovers without a second prompt

Generated: 2026-09-24
Status: VALIDATED (branch `feat/wrap-follow-through`), revised after three review lenses and two operator scope changes
Lane: full
Type: spec-feature
File: `docs/specs/SPEC-310-wrap-follow-through.md`
References: `commands/wrap.md` (step -1 knobs, step 0, step 7b, step 9, step 10); `lib/wrap/report-lint.sh`; `lib/wrap/wrap.sh` (`cmd_follow_mode`, `cmd_start`, `cmd_land`, `cmd_merge`, `_pr_gate`, `cmd_apply --own`); `kit.toml [wrap]`; `lib/config/module-registry.md`; `docs/consumer-contract.md`; `docs/workflow-map.md`; `tests/test-wrap.sh`.

## Problem

An operator ran `/kit:wrap distill` at the end of two sessions on 2026-09-23 and 2026-09-24. Both reports listed candidates as `REPORTED` and FYI rows the session could finish itself. Both times the operator then typed the same prompt: "proceed all the built and also check if we need to do anything re. FYI". The session then built the candidates, opened and merged the PRs, and fixed the FYI follow-ups. That prompt carried no decision, so the round trip bought nothing.

Two root causes:

1. **Step 0's stop is scoped too wide.** Step 0 said "leave that repo alone for the rest of the pass" on foreign activity. Sessions applied that to step 7b too, so an in-lane candidate (lane `normal`, listed in `wrap.build_lanes`) came back `reported: ops-toolkit hit the step 0 foreign-activity stop`. A 7b build runs in a new worktree off `origin/<default>`. It never writes the main checkout that the stop protects.
2. **FYI is report-only.** A follow-up the session can finish (a failing check it caused, drift it caused, a doc line now wrong) sits in FYI until the operator asks.

A third gap: a `tiny` 7b build "ends at that commit" on a branch in a worktree. Steps 3 and 5 already ran, so nothing pushes or merges that branch in the pass.

## Solution

### Approaches considered

1. **A post-report follow-through phase behind one root-only knob.** After step 9 prints, wrap builds the leftovers in background workers, lands them through the existing step 3 and step 5 verbs, and prints a short second report. Prose in `commands/wrap.md`, one resolver verb, one lint change, one knob.
2. **Widen step 7b and FYI handling inside the first pass.** No second report, but the operator waits for every build and PR check before seeing any result.
3. **A shell verb that drives the builds.** A shell verb cannot dispatch model workers or judge whether an FYI row is finishable.

### Chosen approach + why

Approach 1. The judgment (which FYI row is finishable, which home a candidate joins) is model work and belongs in the command prose. The write verbs already exist: `wrap start`, `wrap land`, `wrap merge --apply`, `wrap apply --own`. Background workers keep the operator unheld. One small new verb, `wrap follow-mode`, resolves the knob so the loud fallback for a bad value is testable.

## Design

Design-bearing: yes (a new phase in an existing command, a new knob, a resolver verb, a lint rule change). No new component, no schema.

### Design record

**Step 0 scope (root cause 1, regardless of the knob).** Foreign activity stops every write to that repo's MAIN CHECKOUT for the rest of the pass: the board flip (step 1), the commit (step 2), the merge (step 3), the tidy and pull (step 5), the activity line (step 6), and a seam write into that checkout. The re-check before steps 3, 5, and 6 stays. The stop does not cover a build in an isolated worktree created by `bin/wrap start` off `origin/<default>` (step 7b and step 10). Such a build never writes the main checkout's working tree, index, or HEAD. Stated exception: `wrap start` fetches `origin/<default>` into the shared `.git` before its lock check; a fetch writes remote-tracking refs only. `wrap start` refuses by name while an `index.lock` is held. A PR such a build opens in a stopped repo stays `OPEN`, because its merge is a step 3 write.

Deliberate deviation from the brief: the brief named steps 3, 5, and 6. Steps 1 and 2 also write the main checkout, so the stop keeps them.

**Switch.** One root-only knob, `wrap.follow_through = "off" | "lanes" | "all"`, default `"off"`. `bin/wrap follow-mode [lanes|all]` resolves it once at step -1 and prints `<mode> <lanes>`: `<lanes>` is `wrap.build_lanes` without `full`, plus `full` under `all`, or `none` under `off`. The invocation word `follow` passes `lanes` and `follow all` passes `all`, for one run, over the knob. `all` is an argument only right after `follow`. Any other knob value prints one line, `wrap.follow_through: unknown value '<v>' (allowed: off, lanes, all); running as off`, and resolves as `off`. An unknown override argument exits 64.

**When it runs.** After the step 9 report prints, its lint is clean, and its ledger line is written. The first report never waits on step 10.

**Off.** Step 10 does nothing. When the work set would not be empty, step 9 drafts one FYI row: `| STATE | wrap.follow_through is off, <n> in-lane items stay REPORTED; /kit:wrap follow builds them | |`.

**The work set,** drafted from the first report:

- (a) BUILD: every `REPORTED` Built item whose lane is in the printed lanes and is not `full`, including one reported because of a step 0 stop. An item reported with `build_candidates off` stays reported. LAND only: every step 7b `BUILT` branch with no merged PR.
- (b) FINISH: every FYI row naming work the pass left undone in a repo it touched, classified by `lane-classify.sh` into a printed lane other than `full`. A fact, a resolved incident, or a skipped step is not work. A credential, GUI, 2FA, device, irreversible, or outward-facing row stays a `Needs you` item.
- (c) FULL, `all` only: every `REPORTED` item with `lane=full`.

Empty set: print `[kit:wrap] follow-through: nothing in lane`, no second report.

**Execution.** The lead creates every worktree first, serially, with `bin/wrap start <home> <type>/<slug>`, so parallel `worktree add` calls never race on one `.git`. It prints one line, dispatches one background worker per worktree on step 7b's tier rule, and ends its turn. An (a) or (b) worker builds, runs one verification, quotes it, and commits only when green; it never pushes, merges, or touches a main checkout. Workers are bounded by the Agent tool's lifecycle; no timer.

**Full-lane worker (`all`).** In its worktree: `spec-next.sh reserve` in the home repo (never `next`), the spec, the `kit:spec-validate` lenses, build, `negctl.sh`, the proof, the gate-ledger records, commit, push by name, and `gh pr create --draft`. A CRITICAL, BLOCKING design-record finding stops it before the build; the item stays `REPORTED` with `reported: spec-validate BLOCK: <finding>`.

**Wrap never merges a full-lane PR.** The draft is the mechanism. `_pr_gate` already skips a draft, so no later plain wrap can merge it either. The second report lists it `OPEN` and adds `REVIEW #<pr>: <why>` to `Needs you`. Reason: a full lane marks an architecture, auth, data-model, or contract change; an unattended validate pass cannot stand in for the operator's direction call (AGENTS.md "Pause if").

**Landing, one repo at a time.** Re-run the step 0 check. Clear repo and `merge_own_prs` true: `bin/wrap land <worktree>` per branch. Stopped repo or `merge_own_prs` false: push by name, `gh pr create --head <branch> --fill`, report `OPEN`. Leftover worktrees in a clear repo: `bin/wrap apply --own <wt> <repo>`. Every existing refusal holds.

**Second report.** Heading `## Follow-through: <slug>`, step 9 grammar, linted. Its `Needs you` lists only step 10's items. No `**Seam:**` line. Ledger: `gate-ledger.sh record <rid> wrap-follow ran "<summary>"`, or a structural-skip line when the rid refuses.

**Lint.** The first `## ` line decides the report kind. A follow-through report is exempt from the Seam rule only. A `lane=full` item closed with `verified:` passes only in a follow-through report, only as `#<pr> DRAFT`, and only when a lettered `Needs you` item opening with `REVIEW` names the same number (exact match, so `#7` never covers `#71`). The permission rule judges that REVIEW item independently.

### Picture

```
step 9 report printed + linted + ledger
        |
        v
bin/wrap follow-mode [lanes|all] --off--> FYI STATE row if work was left; done
        | lanes / all
        v
work set: (a) REPORTED in-lane candidates + unlanded 7b BUILT branches
          (b) finishable FYI follow-ups
          (c) all only: REPORTED full-lane candidates
        |
        v
lead: wrap start per item, serially  -->  background workers
   (a)(b): build -> verify -> commit                (no main-checkout writes)
   (c):    reserve SPEC -> spec-validate -> build -> negctl -> proof -> draft PR
        |
        v
per repo: step 0 check --stopped--> push + gh pr create, OPEN
        | clear
        v
wrap land <wt> (green own PR only, tree verify, ff, remove wt); wrap apply --own
(c) drafts: never landed -> Needs you: REVIEW #<pr>
        |
        v
## Follow-through report -> report-lint -> gate-ledger wrap-follow
```

### Extensibility & boundaries

Prose in one command, one resolver verb, one lint change, one knob. No daemon, no timer. Background workers live and die with the session.

## After state

`/kit:wrap follow` (or `follow_through = "lanes"`) builds and lands the in-lane leftovers in the background and prints a second linted report. `follow all` also takes full-lane candidates to a draft PR for review. Step 0's stop no longer blocks an isolated-worktree build.

## Task Breakdown

| Task | Files | Depends on |
|---|---|---|
| T1: step 0 scope, follow arguments, step 10, tiny landing note, admission-test REVIEW class | `commands/wrap.md` | none |
| T2: `follow-mode` verb | `lib/wrap/wrap.sh` | none |
| T3: knob declaration and registry rows | `kit.toml`, `lib/config/module-registry.md` | T2 |
| T4: lint: follow-through Seam exemption, full-lane DRAFT + REVIEW pairing | `lib/wrap/report-lint.sh` | none |
| T5: tests | `tests/test-wrap.sh` | T1 to T4 |
| T6: docs, FEATURES regen, proof | `docs/CHANGELOG.md`, `docs/consumer-contract.md`, `docs/workflow-map.md`, `docs/FEATURES.md`, `docs/verification/wrap-follow-through.md` | T5 |

## Acceptance Criteria (global)

- AC1: `wrap.follow_through` ships `"off"`: `kit_config_get_root wrap.follow_through lanes` at the kit root returns `off`. `follow-mode` prints `off none` by default, honors the operator `kit.toml`, and ignores a project `.kit.toml`.
- AC2: `follow-mode lanes` prints `lanes` with `build_lanes` minus `full`; `follow-mode all` adds `full`; an unknown override exits 64.
- AC3: an unknown knob value (`true`) prints exactly one stderr line naming the knob and the allowed values, and resolves `off none` with exit 0.
- AC4: `commands/wrap.md` step 0 scopes the stop to main-checkout writes, exempts an isolated-worktree build with the reason, and no longer says "leave that repo alone for the rest of the pass".
- AC5: `commands/wrap.md` step 10 sits after the step 9 lint line, resolves through `follow-mode`, takes `follow` and `follow all` (with `all` only after `follow`), drafts the exact off-mode FYI row, keeps `build_candidates off` items and Needs-you class rows out, builds full-lane items only in `all`, creates worktrees serially, opens full-lane PRs as drafts, never merges them and says why, stops on a design-record BLOCK, and restates the own-PR and no-force-push refusals.
- AC6: `report-lint.sh`: a `## Follow-through:` report with no Seam line passes, also after a preamble line; the same body under `## Wrap:` fails, also when its body mentions a Follow-through heading; a follow-through report with no Built line fails; the permission and FYI-tag rules still fail in a follow-through report; the off-mode FYI row passes.
- AC7: `report-lint.sh`: a follow-through `BUILT ... lane=full ... #71 DRAFT` item passes with a lettered `REVIEW #71` item; fails with none, with `REVIEW #7`, with `DECIDE #71`, with a REVIEW line outside Needs you, or when closed `#71 OPEN`; a paired REVIEW item that asks permission still fails; a full-lane BUILT item in a `## Wrap:` report fails.
- AC8: a plain `wrap merge` skips a draft PR (existing case, pinned as the mechanism behind "never merged").
- AC9: every existing `tests/test-wrap.sh` case passes; `tests/test-config-registry.sh` and `tests/test-meta.sh` pass.

## Test plan

| Case | AC | Kind |
|---|---|---|
| knob default through `kit_config_get_root ... lanes`; `follow-mode` default, operator, project | AC1 | unit |
| `follow-mode lanes`, `follow-mode all` with and without `full` in build_lanes, unknown override | AC2 | unit |
| operator toml `follow_through = true`: stdout `off none`, one stderr line, exit 0 | AC3 | unit |
| step 0 literals present, old phrase absent | AC4 | doc contract |
| step 10 literals; line of `### Step 10` greater than the step 9 lint line | AC5 | doc contract |
| lint fixtures per AC6 | AC6 | unit |
| lint fixtures per AC7 | AC7 | unit |
| existing `merge: a draft skips` case | AC8 | unit |
| full `tests/test-wrap.sh`, `tests/test-config-registry.sh`, `tests/test-meta.sh` | AC9 | regression |
| sample first and second reports linted | AC6, AC7 | behavioral |
| negative controls NC1 to NC5 below | AC1, AC3, AC4, AC7, AC8 | negative control |

## Verification

```
bash tests/test-wrap.sh
bash tests/test-config-registry.sh
bash tests/test-meta.sh
bash lib/wrap/report-lint.sh <sample first report>
bash lib/wrap/report-lint.sh <sample second report>
```

Negative controls, each after the change is committed, `T="bash tests/test-wrap.sh"`:

- NC1 step 0 revert: `bash lib/gate/negctl.sh "$PWD" "$T" "sed -i '' 's/STOP every write to that repo.s MAIN CHECKOUT/STOP, report what was found, and leave that repo alone for the rest of the pass/' commands/wrap.md"`
- NC2 knob default on: `bash lib/gate/negctl.sh "$PWD" "$T" "sed -i '' 's/^follow_through = \"off\"/follow_through = \"lanes\"/' kit.toml"`
- NC3 silent fallback: `bash lib/gate/negctl.sh "$PWD" "$T" "sed -i '' '/unknown value .\${mode}/d' lib/wrap/wrap.sh"`
- NC4 pairing dropped: `bash lib/gate/negctl.sh "$PWD" "$T" "sed -i '' 's/\[ \"\$_l_reviewed\" = 1 \] && continue/continue/' lib/wrap/report-lint.sh"`
- NC5 draft no longer skipped: `bash lib/gate/negctl.sh "$PWD" "$T" "sed -i '' 's/if (.isDraft == true) then \"SKIP draft\"/if false then \"SKIP draft\"/' lib/wrap/wrap.sh"`

Proof of done: `docs/verification/wrap-follow-through.md`. The phase itself (work-set drafting, background dispatch, `wrap land`, the second report) is model-executed prose; the proof names it unproven until a real `/kit:wrap follow` run.

## Failure modes

| Failure | Effect | Handling |
|---|---|---|
| session closes mid follow-through | workers die, worktrees keep commits | next wrap's scan lists them; `wrap apply` never removes an unproven branch |
| PR checks pending at landing | `land` refuses | PR stays `OPEN` |
| repo goes foreign before landing | step 0 re-check stops the merge | push + PR only, `OPEN` |
| worker verification red | no commit | item stays `REPORTED` with the check |
| unattended full-lane spec is wrong-headed | a PR nobody wanted | draft, never merged, `REVIEW` item; operator closes it |
| design-record lens BLOCKs | no build | stays `REPORTED` with the finding |
| knob typo (`true`, `yes`) | would start work silently | one stderr line, runs as `off` |
| later plain wrap meets the full-lane PR | could merge it | draft; `_pr_gate` skips it |

## Edge Cases

- Distill off: (a) and (c) are empty; (b) can still run.
- Two items in one home repo: two worktrees created serially, landed one at a time.
- A repo named `all`: an argument only right after `follow`; `./all` names the repo there.
- `merge_own_prs` false: PRs opened, never merged.

## Out of Scope

- A `FOLLOW-UP` FYI tag to make set (b) mechanical (the tag set is a report surface other readers parse).
- An operator ack before a full-lane build (the operator chose build-then-review).
- Auto-merging a full-lane PR under any setting.
- Reordering `wrap start`'s fetch after its lock check.

## Decision Log

- Stop keeps steps 1 and 2 as well as 3, 5, 6: they write the main checkout too.
- One enum knob replaced two booleans at the operator's request; `follow-mode` is the one resolver so the unknown-value fallback is testable.
- `build_candidates = false` wins over follow-through: that knob is the explicit hand-stay.
- Follow-through lands step 7b's unlanded `BUILT` branches too, closing the tiny-commit gap.
- Workers commit only; the lead creates worktrees serially and lands one repo at a time.
- Full-lane PRs open as drafts: `_pr_gate` already skips drafts, so "never merged" survives past the pass with no new code.
- The full-lane worker takes its number from `spec-next.sh reserve`, never `next`.

## Review disposition

Validate ran three fresh-context lenses (verification on Opus; safety and design record, consistency on Sonnet). Verdicts: NEEDS REVISION, NEEDS REVISION with a design-record BLOCK, NEEDS REVISION.

| Finding | Disposition |
|---|---|
| AC5 and AC9 contradicted on full-lane BUILT in a follow-through report | folded: AC6/AC7 split |
| report kind undefined; substring match would exempt a first report | folded: first `## ` line decides, two fixtures |
| PR extraction loose, `#7` vs `#71` | folded: `#<n> DRAFT`, exact set match, fixtures |
| REVIEW could come from outside Needs you; permission interplay | folded: lettered items in the block only, fixtures |
| exemption tested only through Built | folded: permission and FYI-tag fixtures |
| off-mode FYI row untested and could trip the ask rule | folded: exact text pinned, lint fixture |
| grep contracts too loose, order unchecked | folded: literal strings, line-order check |
| negctl placeholders | folded: five verbatim mutations |
| phase never run end to end | folded: the proof names it unproven |
| default test could not catch a deleted key | folded: `get_root ... lanes` must return `off` |
| `full` word parsing | folded: enum; `all` only after `follow` |
| second report template and rid refusal | folded |
| full-lane PR merged by a later plain wrap | folded: draft PR |
| diagram outside `## Design` (design-record BLOCK) | folded: Picture under Design |
| require operator ack before a full-lane build | rejected: operator chose build-then-review; draft plus REVIEW holds the merge |
| `wrap start` fetch before lock check | noted as a stated exception; reorder out of scope |
| reserved argument words | folded: `all` only after `follow`, `./all` edge |
| parallel `worktree add` race | folded: lead creates worktrees serially |
| spec drifted from the enum and the verb | folded: this rewrite |
| no FOLLOW-UP tag makes (b) judgment | rejected: out of scope, worked example added |
| drop `all` mode as over-built | rejected: operator asked for it |
| worker timeout | folded: Agent lifecycle named, no timer |
| first report's Needs you in the second report | folded: second lists only step 10's items |
| workflow-map and consumer-contract stale | folded |
