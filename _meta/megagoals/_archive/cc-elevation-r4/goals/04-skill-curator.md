# Sub-goal 04: skill-library curator + round close-out (Phase C)

**Time budget:** ~4-5h · **Depends on:** 03 · **Branch:** feat/cc-elev-r4-04-curator · **PR base:** feat/cc-elev-r4-03-promote · **Merge policy:** gate (final + host-touching launchd)

## Outcome

The curator (the explicitly-missing piece) + the round close-out. SPEC-103 TASK-011..014.

- `cc-improve curate`: a `claude -p --allowedTools ""` pure-function reads skill frontmatter +
  first-paragraph and returns a JSON plan (umbrella clusters + stale-by-mtime candidates); the
  trusted bash wrapper writes a human-readable report. **Propose-only by default; no change without `--apply`.**
- `--apply`: archives via `git mv` to `~/.claude/skills/_archive/` (NEVER deletes); `cc-improve
  restore <name>`; non-git host falls back to `mv` + manifest with a warning.
- Optional weekly `mini.cc-curator` LaunchAgent, **propose-only** (writes a report, never `--apply`),
  BTM-friendly (ProgramArguments[0] = `bin/cc-improve`, no `.sh`), wired into vps-mon.
- Close-out: docs (`proof-of-done.md` multi-feature index, README, tool.toml, MANIFEST + INVENTORY
  rows), cc-elevation suite docs note the memory/skill split, and the **round-level Hermes-parity
  assertion** (01 + 02/03 + 04 + cc-harvest = the full loop).

## Quality bar

Curator never deletes (git mv only); the model has no write (`--allowedTools ""`); the wrapper does
the git mv. The launchd job is propose-only (the plist has no `--apply`; the human runs `--apply`
after reading) , preserves the autonomy gate. A new background job is not done until vps-mon shows
it `monitored` (job-monitoring-onboarding).

## How to close the loop

- Build `bin/cc-improve curate` (pure-function plan + report) + `prompts/curator.md`; archive +
  `restore` (trusted git mv); the propose-only launchd plist; vps-mon wiring. **`prompts/curator.md`
  MUST start from `tools/cc-self-improve/docs/hermes-prompt-patterns.md` section C** (umbrella-building
  framing, the hard rules incl. pairwise-distinctness-is-the-wrong-bar + use=0-is-not-evidence,
  prefix-cluster method, package integrity, the DRY-RUN/propose-only banner, `absorbed_into` forwarding).
- Tests: curate produces a report and changes nothing without `--apply`; `--apply` archives via git
  mv (assert no `rm` in the path) + restore round-trips; non-git fallback warns.
- `launchctl print` shows `bin/cc-improve`; vps-mon catalog shows the job `monitored`.
- Finalize `tools/cc-self-improve/docs/proof-of-done.md` index; update README/tool.toml/MANIFEST/INVENTORY.
- Round close-out: draft the `_meta/LAB_LOG.md` entry for the whole cc-elevation-r4 arc on THIS
  branch (SPEC-005), update cc-harvest README + the cc-elevation predecessor note with the
  memory/skill split, and write the round-level parity assertion into the ROADMAP.

**Done =** `cc-improve curate` reports clusters + stale candidates and changes nothing without
`--apply`; `--apply` archives via `git mv` (no `rm`) + restore works; the weekly launchd is
propose-only + `monitored` in vps-mon; docs/proof finalized; LAB_LOG entry + suite-docs split +
parity assertion on this branch; on PR #NN.

## Scope edges

**In:** curate + archive/restore, propose-only launchd + vps-mon, docs close-out, LAB_LOG, parity assertion.
**Out:** the reviewer/promote/surfacing (02/03); the per-turn memory trigger (01).
**Not:** an auto-applying curator; a launchd that runs `--apply`; deleting any skill.

## Where to look

SPEC-103 TASK-011..014 + DEC-008, `tools/cc-harvest/.../proof-of-done.md` for the multi-feature
index shape, the BTM-friendly plist rule (repo CLAUDE.md), `job-monitoring-onboarding` skill +
the vps-mon catalog, `feedback_stacked_pr_delete_branch` for the merge note, SPEC-005 LAB_LOG
discipline, the cc-elevation r1/r2/r3 ROADMAPs for the close-out shape.

## PR body

Outcome: cc-self-improve Phase C , skill-library curator (propose-only, git-mv archive never delete) + weekly propose-only launchd + round close-out + Hermes-parity assertion.
Verify: curate report changes nothing without --apply; --apply archives via git mv (no rm) + restore round-trips; launchd monitored in vps-mon; proof index finalized.
Roadmap: `_meta/megagoals/cc-elevation-r4/ROADMAP.md` (sub-goal 04, close-out).
