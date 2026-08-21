# Decision Brief: zero-think onboarding (three moments, plugin-first)

Date: 2026-07-25 · Source: operator ask ("when they get the kit they know what to do, they don't
have to think; I'm struggling to intro the kit to others"), designed against the onboarding-pattern
survey + a live audit of adopt/onboard/start. Status: DRAFT (design agreed in session; feeds the
ID-408 -> ID-400 -> DF-152 build chain). Consuming rows: ID-408, ID-400, ID-405; dfoundation
DF-152. Survey + verdicts: `docs/research/2026-07-25-skills-repos-onboarding-absorption.md` (§3, §3b mirrors this design).

## Verified current state (2026-07-25)

- `/kit:start` already implements the doctor pattern (state + ONE next action, `--brief/--full`);
  `/kit:onboard` already implements a state-not-owning guided tour (previews every write, decline =
  no-op, Enter-Enter-Enter defaults, honest plugin-gap disclosure). The mechanisms are NOT the gap.
- The teammate install path already ships: `.claude-plugin/plugin.json` + `marketplace.json`
  (v2.0.0), so `/plugin marketplace add dwarvesf/dwarves-kit` + `/plugin install kit` works with no
  clone and no installer. It is just not the story any doc tells.
- THE DEFECT: `lib/adopt.sh` expands `$KIT_ROOT` at render time (the `claude_block` printf and the
  proof-marker heredoc), so adopted repos carry literal `~/.claude/dwarves-kit/...`
  paths (verified: 2 hits in ops-toolkit `CLAUDE.md`). No symlinks are written (audited); the
  operator's "symlinks" recollection is this path-baking. Any non-maintainer machine breaks.

## The design: three moments, one action each, education embedded

```
MOMENT 0  RECEIVE   One message (DF-152 2-pager ends with it):
                    /plugin marketplace add dwarvesf/dwarves-kit
                    /plugin install kit
                    then open your repo, type /kit:onboard
                    No clone. No installer. No choices.

MOMENT 1  INSTALL   The plugin path. Managed bundle, auto-current, zero decisions.
                    Bash installer demoted to the maintainer/power path in all docs.

MOMENT 2  ONBOARD   /kit:onboard in their repo: Enter-Enter-Enter defaults, previews
                    every write, adopts the repo (4 PORTABLE files, needs ID-408),
                    five-sentence tour. The tour IS the lesson.

MOMENT 3  WORK      /kit:start at the top of every session: state + ONE next action.
                    Onboarding never completes; the doctor IS the onboarding.
                    First real task: tiny lane -> ship.
```

Principle: at every moment there is exactly one thing to do; education rides inside the doing.
There is no tutorial to finish, no module catalog at first contact, no adoption levels.

## Build order (strict)

1. **ID-408 portable adopt** (blocker, renumbered from ID-406): templates emit the read-time resolver
   `KIT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}"` + `bash "$KIT/..."` refs; `--refresh`
   migrates existing adopted repos; a lint asserts no `$HOME`-expanded path in rendered files
   (negative control).
2. **ID-400 plugin-first docs**: README leads with the two-command path; `docs/QUICKSTART.md` ~10
   lines; the no-tutorial framing; the add-one-module-later verb per module; honest-disclosure
   generalized.
3. **DF-152** (dfoundation): the Moment-0 message artifact (the 2-pager ending in the install
   block).
4. **ID-405** (later): bounded ambient module self-suggest deepens Moment 3.
5. **ID-407 workflow gallery** (parallel-session direction, same arc): a `flow render <type|mode>`
   verb GENERATES ASCII start-to-end flows from the existing single sources (task-type registry +
   WORKFLOW.md), so a new user SEES each workflow instead of inferring it from command lists;
   surfaced at Moment 2 (onboard tour) and from /kit:start. Generated projection, never a
   hand-maintained diagram (no drift); deepens Moments 2-3 alongside ID-405.

## North-star conformance (§6)

Serves N7 (pickup cost, the 2/5 team dimension) and N4 (portable adopted files are the
delete-the-kit test applied to consumer repos). Respects §1: no init wizard owning module state, no
central registry, no completable tutorial mode (all explicitly rejected shapes). Open operator
check: whether `dwarvesf/dwarves-kit` is visible to each teammate's GitHub account (private-org
marketplace add needs org membership).

## Exit criteria

1. A teammate on a machine that has never seen the kit goes from the Moment-0 message to a merged
   tiny-lane change with zero questions asked (the live UAT; pairs with team-mode SG-07's shape).
2. An adopted repo's kit references resolve on BOTH install modes (plugin, bash) on a second
   machine (ID-408's lint is the mechanical half of this).
3. The README's first screen contains the two-command path and nothing about modules.
