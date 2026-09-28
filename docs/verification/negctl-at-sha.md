# Verification -- negctl-at-sha

`lib/gate/negctl.sh --at <sha> [--path <subdir>] [--setup <cmd>]` runs the full mutate negative control against an exported commit under `$TMPDIR`, never the live worktree. Default mode is unchanged.

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | `--at` runs against the commit even when the live tree holds an uncommitted change that fails the test | `tests/test-proof-negctl.sh` case 33 | PASS |
| AC2 | the live tree is byte-identical afterwards (status, diff, file checksum) | case 34 | PASS |
| AC3 | `--path` limits the export, `--setup` runs in the export before the green run | case 35 | PASS |
| AC4 | bad sha, `--path` without `--at`, `--at` with `--base-ref` exit 64 | case 36 | PASS |
| AC5 | default mode unchanged: no `At:`/`Export:` lines, dirty tree still REFUSED (exit 2) | case 37 plus cases 1 to 32 | PASS |

## Green run
```
Command: bash tests/test-proof-negctl.sh
Exit: 0
[33] --at: runs against the commit, not a live uncommitted change that fails the test
  ok: PASS against the exported commit, export under TMPDIR at <TMPDIR>/negctl-at.XXXXXX
[34] --at: the live tree is byte-identical afterwards (status, diff, content)
  ok: live WIP untouched
[35] --at --path --setup: export limited to the subdir, setup runs in the export first
  ok: subdir-only export with setup: PASS, live tree clean
[36] --at usage: bad sha, --path without --at, --at with --base-ref all exit 64
  ok: all three exit 64
[37] default mode unchanged: no At/Export lines, still REFUSES a dirty live tree
  ok: default output has no --at lines; dirty tree still REFUSED
test-proof-negctl: all 38 passed
```

Also: `bash tests/test-meta.sh` 878/879 before the registry regen (the one failure was the pre-existing stale `docs/FEATURES.md`, also stale at the base commit); `lib/registry/feature-registry.sh check docs/FEATURES.md` exit 0 after it. `tests/test-lint-scattered-ids.sh` and `tests/test-boundary-lint.sh` exit 0.

## Negative control
Manual, after committing: `root="$export_dir"` replaced by `:` so `--at` runs in the live tree.
```
Command: bash tests/test-proof-negctl.sh
Exit: 1
[33] --at: runs against the commit, not a live uncommitted change that fails the test
  FAIL: rc=2 out=negctl: REFUSED -- tracked files are modified or staged in .../atrepo
[35] --at --path --setup: export limited to the subdir, setup runs in the export first
  FAIL: rc=1 out=## Negative control (negctl)
Verdict: FAIL: test was not green before the mutation
test-proof-negctl: 36 passed, 2 FAILED
```
Result: RED as expected. Restored with `git checkout -- lib/gate/negctl.sh`; `git status --short` empty; the green run above was re-run after the restore.

Dogfood, the same control mechanised by the new mode against this repo at the feature commit (live worktree untouched, `git status --short` empty afterwards):
```
## Negative control (negctl)
At: 2ea8f141
Export: <TMPDIR>/negctl-at.H3nvv2
Command: bash tests/test-proof-negctl.sh
Exit: 0 (green before mutation)
Mutation: sed -i.bak 's/^  root="\$export_dir"$/  :/' lib/gate/negctl.sh && rm -f lib/gate/negctl.sh.bak
Changed: lib/gate/negctl.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/gate/negctl.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Not proven
- A real `pnpm install --frozen-lockfile` setup: the tests use `touch` as the setup command. The setup path is the same `bash -c` either way.
- Linux: run on macOS only (the suite passes under both /bin/bash 3.2.57 and Homebrew bash 5.3).
- The export dir is kept on purpose (printed as `Export:`); nothing prunes old exports under `$TMPDIR`.

Verdict: PASS
