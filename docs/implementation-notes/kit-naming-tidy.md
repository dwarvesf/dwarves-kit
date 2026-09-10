# Implementation notes: kit-naming-tidy (delta from the assigning task)

No spec backs this batch (a maintainer-driven repo-tidy sweep, not a feature); this note
records where the actual repo state diverged from the scout report's proposals.

## Decisions

- **Claimed SPEC-253** for the renamed `cc-hyg-04-stop-tax` spec (max existing was SPEC-252
  at the time of the git mv; re-verified against `git log --all` before commit).
- **Renamed only the filenames the scout table named**, not every substring occurrence of the
  old name in prose. A blind repo-wide find/replace of `cc-intel`, `cc-plugin-check`,
  `cc-worktree-provision` etc. would have rewritten live external identifiers (launchd job
  labels, a registered vps-mon heartbeat id, env var names, another repo's own tool name) and
  dated proof-of-done run-tables recording what a command literally was at the time it ran.
  Repointed only: (a) literal path references to a file I renamed, and (b) that file's own
  title/header when it names itself.

## Deviation from the assigned instructions

- **`lib/skill-curator/bin/cc-improve` is NOT renamed.** The task described it as "a live
  entry point" to rename to `improve`. It is not: it is already a deliberate, one-release
  deprecated shim that execs `skill-improve` (the actual current name, landed 2026-07-27).
  Its own header says so, and `tests/test-kit-contract.sh` (C2 wiring check, line ~129)
  explicitly grandfathers it by literal name: `grep -v '/cc-improve$'` with the comment "the
  deprecated cc-improve shim". Renaming it to `improve` would collide with nothing (no such
  name exists) but would break that test's exemption AND `tests/test-no-scattered-ids.sh`
  line 50, which also names it by the literal string `cc-improve`. Left untouched; flagging
  for the maintainer to decide whether "one release" has now elapsed (VERSION is 2.2.0,
  shim last touched 2026-09-08) and the shim should be deleted outright (not renamed).

- **`docs/research/architecture.md` and `docs/research/features.md` are NOT renamed.**
  The scout listed both as undated stray research snapshots with 0 inbound refs (checked by
  bare filename, which is a very common name and returned noise). A precise path grep found
  both are load-bearing generic output paths: `agents/research-architecture.md` and
  `agents/research-context.md` write to them by contract, `commands/spec.md` dispatches
  naming these exact paths, and `docs/specs/SPEC-210-research-architecture-contract.md` +
  `tests/test-research-arch-contract.sh` pin the literal path string. These are scratch
  targets a `/kit:spec` research pass overwrites each run, not permanent dated artifacts;
  renaming either breaks a tested contract.

## Left as historical record, not repointed

Per the task's own two named exceptions (gauntlet frozen captures, CHANGELOG/retro dated
lines), plus the same judgment applied consistently to equivalent categories found along the
way:

- Archived megagoal records (`_meta/megagoals/_archive/**`) naming a real historical git
  branch or a past PR's file locations at merge time (e.g. `fix/cc-hyg-04-stop-tax`, or
  `docs/proof/loop-07-mega-dashboard/` in a 2026-07-12 PR-merge line).
- Dated proof-of-done run-tables (`docs/verification/briefs-out/proof-of-done.md`) and the
  one-off dated audit (`docs/audits/skillspector-report-2026-06-25.md`), which record what a
  scan actually found at that timestamp.
- `lib/bench/examples/renders/dashboard-2026-07-25.html`, a frozen dated render example
  (same category as a gauntlet transcript, just outside that directory).

Editing any of these to match the new names would misrepresent what was literally true at
the time they were recorded.

## Open question for the operator

Should `lib/skill-curator/bin/cc-improve` be deleted now (its "one release" grace period
looks to have passed) rather than kept as a permanent grandfathered exception? Not acted on
here since deletion was out of scope for a rename-only batch and the task said never delete.
