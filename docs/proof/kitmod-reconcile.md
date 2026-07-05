# Proof of done: kit-modularity SG-07 (reconcile, capstone)

Branch: `docs/kitmod-07-reconcile`. Cross-repo (dotfiles skills + this kit). HELD final PR,
does not merge; edits Han's authoring skills.

Scope: the three goal-scaffolding surfaces (`plan-for-goal` skill, `plan-for-mega-goal`
skill + its `references/`, `/kit:mega` = `commands/mega.md`) agree with the post-SG-01..06+08
kit surface and with each other. This sub-goal only reconciles stale references and re-runs
the never-diverge mirror check; it invents nothing new.

## Acceptance criteria -> confirmation

| # | Criterion | Result |
|---|---|---|
| 1 | Every reference the three surfaces make to kit internals enumerated | PASS, see "Enumeration" below |
| 2 | `ledger-observatory` -> `stats` reconciled everywhere it's live | PASS, zero live hits found (none existed pre-SG-07 either, see baseline note) |
| 3 | `bash lib/<x>.sh` flat paths -> real `lib/<subsystem>/<x>.sh` paths | PASS, 2 stale hits found + fixed (both in dotfiles); `commands/mega.md` was already correct |
| 4 | Old install / lib-vs-tools / `tools/` framing reconciled | PASS, zero hits anywhere (nothing to fix) |
| 5 | Never-diverge mirror check (triage-ladder fence) re-run, still agrees | PASS, byte-identical, shasum `a42939f37e91e61eadfa0a7e4de7034a3309a22c` unchanged before and after this sub-goal's edits |
| 6 | SPEC-142 never-diverge checklist rows still point at valid locations | PASS, all `mega.md` Step numbers / section headers referenced in the checklist table still exist verbatim |
| 7 | NC: grep each retired token across all three -> zero live references | PASS, see NC section |

## Enumeration (what the three surfaces reference)

Surfaces + their real source paths (dotfiles is chezmoi-sourced; `private_` prefix drops perms,
deploys as `SKILL.md`):

- `home/dot_claude/skills/plan-for-goal/SKILL.md` (dotfiles)
- `home/dot_claude/skills/plan-for-mega-goal/private_SKILL.md` (deploys as `SKILL.md`)
- `home/dot_claude/skills/plan-for-mega-goal/references/GUIDE.md`
- `commands/mega.md` (this repo)

Grepped each for: `ledger-observatory`, `bash lib/`, flat `lib/[a-z-]+\.sh` (no subsystem
subdir), `/tools/` top-level fold references, lib-vs-tools framing, old all-hooks install
phrasing.

Baseline (captured by the conductor pre-SG-01, before any subsystem dirs existed):
`ledger-observatory` = 0 refs in all three scaffolders already (they never named it directly).
Flat `lib/<x>.sh` path refs: `plan-for-goal/SKILL.md` 1, `plan-for-mega-goal/SKILL.md` 0,
`GUIDE.md` 2, `commands/mega.md` 33 (+9 `bash lib/` calls). So `commands/mega.md`'s heavy
baseline count was the expected target of this reconciliation, but by the time this sub-goal
ran, SG-08 (`feat(mega): add mega status reconciler...`, PR #194) had already been authored
directly against the final subsystem-path surface (`lib/gate/gate-ledger.sh`,
`lib/queue/orchestrate.sh`, `lib/goal/mega-merge.sh`, `lib/classify/lane-classify.sh`,
`lib/gate/dispatch-gate.sh`, `lib/gate/proof-ledger.sh`, `lib/spec/spec-next.sh`,
`lib/goal/goal-drafts.sh`) -- all 8 distinct subsystem-path files it names were verified to
exist at those exact paths (`ls` per path, all `OK`). So `commands/mega.md` needed ZERO
reconciliation edits; the baseline's 33/+9 flat refs were already resolved upstream of SG-07.

The two dotfiles skills carried the baseline's remaining 3 flat refs (1 in `plan-for-goal`,
2 in `GUIDE.md`), which had NOT been touched by any earlier sub-goal (they're prose in
authoring skills, not code SG-01..06 rewrote). Fixed in this sub-goal:

| File | Line (pre-edit) | Was | Now |
|---|---|---|---|
| `plan-for-goal/SKILL.md` | 68 | `lib/gate-ledger.sh` | `lib/gate/gate-ledger.sh` |
| `plan-for-mega-goal/references/GUIDE.md` | 258 | `lib/gate-ledger.sh` (+ bare `lib/` + `gate-ledger` phrase) | `lib/gate/gate-ledger.sh` (both spots) |
| `plan-for-mega-goal/references/GUIDE.md` | 305 | `lib/dispatch-gate.sh` | `lib/gate/dispatch-gate.sh` |

`plan-for-mega-goal/private_SKILL.md` had zero stale hits (it doesn't name any `lib/` path
directly; it defers to `GUIDE.md` for depth).

## Never-diverge mirror check (re-run)

The runner-fastpath SG-01/02 contract: the `<!-- BEGIN triage-ladder -->` /
`<!-- END triage-ladder -->` fenced block in `plan-for-goal/SKILL.md` (the canonical source)
must be byte-identical to the same fence in `commands/mega.md` (the kit-native mirror). This
is recorded in `docs/specs/SPEC-142-mega-mirror-sync.md`'s "Never-diverge checklist" table,
shasum `a42939f37e91e61eadfa0a7e4de7034a3309a22c`.

```
$ sed -n '/<!-- BEGIN triage-ladder -->/,/<!-- END triage-ladder -->/p' \
    home/dot_claude/skills/plan-for-goal/SKILL.md > /tmp/a.txt   # dotfiles worktree
$ sed -n '/<!-- BEGIN triage-ladder -->/,/<!-- END triage-ladder -->/p' \
    commands/mega.md > /tmp/b.txt                                 # this worktree
$ /usr/bin/cmp /tmp/a.txt /tmp/b.txt && echo IDENTICAL
IDENTICAL
$ shasum /tmp/a.txt /tmp/b.txt
a42939f37e91e61eadfa0a7e4de7034a3309a22c  /tmp/a.txt
a42939f37e91e61eadfa0a7e4de7034a3309a22c  /tmp/b.txt
```

Re-run BEFORE this sub-goal's edits and AFTER: identical result both times (the edits this
sub-goal made were outside the fenced block, in unrelated prose paragraphs elsewhere in
`plan-for-goal/SKILL.md` and in `GUIDE.md`, neither of which the fence touches).

Bonus check (same mirror pattern, a second fence pair, not the SG-07-mandated one but
confirms the pattern holds elsewhere): `<!-- BEGIN/END done-ladder -->` between
`plan-for-goal/SKILL.md` and `plan-for-mega-goal/references/subgoal-template.md` -- also
byte-identical (`/usr/bin/cmp` clean). Not touched by this sub-goal (out of its named scope,
reported for completeness).

### SPEC-142 checklist-row re-audit

`SPEC-142-mega-mirror-sync.md`'s "Never-diverge checklist" table names 10 beats with a
skill-side location and a `mega.md` location each. Re-checked every `mega.md`-side location
string against the CURRENT file structure (`grep -n '^## \|^### Step' commands/mega.md`):
`Step 1`..`Step 5`, `## Consolidate mode`, `## Intake triage ladder` -- all still exist
verbatim at the names the checklist cites. No row in that table needed a rewrite; none of
SG-01..06+08's edits touched `mega.md`'s section structure, only its internal `lib/` path
prose (already correct, per Enumeration above).

## Named negative control (NC): grep each retired token, all three surfaces

```
$ grep -rn 'ledger-observatory' \
    home/dot_claude/skills/plan-for-goal/SKILL.md \
    home/dot_claude/skills/plan-for-mega-goal/private_SKILL.md \
    home/dot_claude/skills/plan-for-mega-goal/references/GUIDE.md \
    commands/mega.md
(no output, exit 1)

$ grep -noE 'lib/[a-zA-Z_-]+\.sh' <same four files>
(no output, exit 1)                          # zero flat (non-subsystem) lib/<x>.sh paths remain

$ grep -noE '\btools/[a-zA-Z_-]+' <same four files>
(no output, exit 1)                          # zero top-level tools/ references

$ grep -ni 'install all hooks\|install everything\|full install\|kit dispatcher\|uber-dispatcher' <same four files>
(no output, exit 1)
```

Verdict: PASS, zero live references to any retired token across all three scaffolding
surfaces.

## Scaffolder flow changes

None. This is a pure stale-reference reconciliation (3 path corrections) plus a re-asserted
mirror check. No scaffolder logic, ladder content, or flow changed.

## Pre-existing (non-baseline) drift noted, not owned by this sub-goal

None found. The baseline's flat-path refs were fully accounted for (33/+9 in `commands/mega.md`
already resolved upstream by SG-08's authoring against the final surface; the remaining 3 in
the dotfiles skills fixed here). No stray `ledger-observatory`, `tools/`, or old-install
phrasing anywhere in scope.

## Reproduce

```
cd dwarves-kit && git checkout docs/kitmod-07-reconcile
cd dotfiles && git checkout docs/kitmod-07-reconcile
# re-run the grep-audit + mirror-check commands above from each repo root
```
