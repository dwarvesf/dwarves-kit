# Proof of done: meta-writers-adoption-guard (ID-479)

Class: behavioral. Gates the two hooks that write into a consumer's `_meta/` —
`hooks/harvest.py` (both legs: the no-arg ledger harvest and `--lab-log`) and
`hooks/backlog-stage.py` — on the kit's existing adoption marker,
`docs/verification/README.md`. Before this, both resolved `<repo-root>/_meta/...`
and wrote unconditionally; because `.claude-plugin` registers all 25 hooks globally
and unconditionally, a SessionEnd in any repo the operator merely opened created a
`_meta/` there.

Marker choice is deliberate: it is the same file `hooks/ship-gate.sh:75-78` already
opts in on, and the third leg of `lib/adopt.sh:71`'s adopted triple (the one adopt
never overwrites). One adoption signal for the whole kit, not a second convention.

Rejected alternatives: `_meta/BACKLOG.md` (an adopted repo that never ran
`board init` has no board, so the guard would silence a legitimately adopted repo);
`AGENTS.md` (now a cross-tool standard, carried by plenty of non-kit repos); a
`kit.toml` flag (the hot spine hooks deliberately never read `kit.toml`, so config
cannot gate a hook).

## GREEN (real run)

Seven new assertions in `tests/test-kit-foldin-hooks.sh` — rows `3-nc`
(backlog-stage) and `4-nc` (both harvest legs), each pairing a marker-LESS negative
control with a positive control that proves the silence is the guard rather than a
broken hook.

Command: `bash tests/test-kit-foldin-hooks.sh`
Exit: 0
Verdict: PASS
Output (new rows plus tail):

```
  PASS row 3-nc: non-adopted repo, hook still exits 0 (inert, never blocks) (exit 0)
  PASS row 3-nc: no _meta/ written into a non-adopted repo
  PASS row 3-nc: positive control -- marker present, candidate stages
  PASS row 4-nc: --lab-log in a non-adopted repo exits 0 (inert, never blocks) (exit 0)
  PASS row 4-nc: no-arg (ledger) harvest in a non-adopted repo exits 0 (exit 0)
  PASS row 4-nc: neither leg wrote _meta/ into a non-adopted repo
  PASS row 4-nc: positive control -- marker present, draft lands

=== Results ===
Passed: 101 / 101
All kit-foldin hooks tests passed.
```

The same suite was 94 / 94 on the pre-patch tree, so the count moves 94 -> 101 with
no existing assertion lost.

The other suite that materializes these two hooks also stays green:

Command: `bash tests/test-install-modules.sh`
Exit: 0
Verdict: PASS

```
== 37 passed, 0 failed ==
```

## NEGATIVE CONTROL

The guard in `hooks/harvest.py` `_dispatch()` was replaced with `if False:` (keeping
the same control-flow shape, so only the predicate changed) and the suite re-run: the
new assertion goes RED, reproducing the bug. The guard was then restored from a
byte-identical copy and the suite goes back to 101 / 101.

Command: `bash tests/test-kit-foldin-hooks.sh` (guard predicate disabled)
Exit: 1
Verdict: RED, as required
Output:

```
  FAIL row 4-nc: neither leg wrote _meta/ into a non-adopted repo (unexpectedly found '_meta')
Passed: 100 / 101
```

Command: `bash tests/test-kit-foldin-hooks.sh` (guard restored)
Exit: 0
Output: `Passed: 101 / 101`

This is the load-bearing check: it proves the new assertions actually fail when the
guard is absent, rather than passing vacuously.

## Fixture correction (why 10 existing fixtures changed)

The 10 `hv-repo*` / `bs-repo*` fixtures created a repo with no
`docs/verification/README.md` — they modelled a NON-adopted repo, which is exactly
the condition the bug lives in, and is why the suite never caught it. Each now
creates the marker, so the existing rows still exercise the adopted-repo path they
were written for.

## Live miss that motivated this

The operator's `~/projects/anlapreel` (a Remotion video project, never adopted by the
kit) accumulated a 15 KB `_meta/.lab-log-draft.md` across 2026-08-04..08-07 from
plugin-mode SessionEnd fires, and the file was committed to that repo. The staged
content itself was legitimate session history — it was migrated into that repo's own
`docs/LAB_LOG.md` before the stray `_meta/` was removed — so the defect is the
namespace violation, not the drafting.

## Scope boundary (deliberately NOT guarded)

- `hooks/session-state-save.sh` (`.claude/session-state/`) and
  `hooks/pre-compact-backup.sh` (`.claude/backups/`) also write into every repo.
  `.claude/` is Claude Code's own namespace, so writing there is legitimate anywhere.
  `_meta/` is the kit's project-contract namespace — that is the line drawn here.
- `hooks/output-offload.sh` writes to `$XDG_CACHE_HOME/dwarves-kit/offload`, outside
  any repo. Nothing to fix.

## Reproducibility

`bash tests/test-kit-foldin-hooks.sh` was run four times over this change: 94 / 94
pre-patch, 101 / 101 post-patch, 100 / 101 with the guard predicate disabled, and
101 / 101 again after restoring it. Same result on each repeat of an identical tree.
