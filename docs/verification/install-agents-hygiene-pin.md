# Proof of done: plugin-mode install skips the bare agent copy; detector 3 honors project pins

2026-09-18. Lane: full (board sweep, two rows on one branch). Board: ID-924, ID-833.
Files: `install.sh` (section 4b), `lib/repohygiene/repohygiene.sh` (mega-goal loop),
`tests/test-install-compat.sh`, `tests/test-repohygiene.sh`.

## The failure this closes

Two small defects swept in one branch.

1. `KIT_FORCE_FULL=1 bash install.sh` bypassed the compat branch and re-copied every kit agent
   into `~/.claude/agents`, reopening the duplicate agent roster the compat branch retires
   (found by the battery on PR #691). The full install now skips the agent copy whenever
   `PLUGIN_LIB` resolves: `KIT_FORCE_FULL` bypasses compat for hooks and commands, not for the
   bare agent copies.
2. repo-hygiene detector 3 emitted a possibly-closed finding for a completed mega-goal that a
   `projects/<slug>/` record cites as its predecessor audit trail. The promote-to-project rule
   pins such folders in `_meta/megagoals/`; moving one would orphan the citation. Any
   `projects/**/*.md` naming `megagoals/<base>` now suppresses the folder.

## Green run

Command: `bash tests/test-install-compat.sh`
Exit: 0
Output: `PASS: install compat` (includes `KIT_FORCE_FULL with plugin cached copies no bare agents`,
`install log says agents come from the plugin`, `no plugin cached: full install still copies agents`)
Verdict: PASS.

Command: `bash tests/test-repohygiene.sh`
Exit: 0
Output: `100/100 passed, 0 failed` (includes `a closed mega-goal cited by a projects/ record is
pinned, not a finding` and `the same folder with no projects/ citation still earns FIX`)
Verdict: PASS.

Command: `bash tests/test-meta.sh`
Exit: 0
Output: `Passed: 853 / 853. All meta tests passed.`
Verdict: PASS.

## Negative control

- `install.sh` stashed, `bash tests/test-install-compat.sh` -> exit 1, stopping at the new
  `KIT_FORCE_FULL with plugin cached copies no bare agents` assertion (agents were copied).
  Restored -> `PASS: install compat`.
- `lib/repohygiene/repohygiene.sh` stashed, `bash tests/test-repohygiene.sh` -> `99/100 passed`,
  `FAIL a closed mega-goal cited by a projects/ record is pinned, not a finding`. Restored -> 100/100.

## Rollback

Revert the branch's two fix commits; `agents/` copying returns to unconditional and detector 3
re-emits the pinned folder. No runtime state, no deploy.
