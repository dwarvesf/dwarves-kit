# Spec: context-readiness reads specs in one awk pass

Generated: 2026-09-29
Status: VALIDATED (fresh-context validation: 0 critical, 7 warnings folded)
Lane: full (kit-machinery hard gate on hooks/; think, design, design-critique and test-plan carry audited operator overrides)
Type: refactor
File: `docs/specs/SPEC-354-context-readiness-one-pass.md`
References: `hooks/context-readiness.sh` (the live-spec filter and the branch-match loop), `tests/test-hooks.sh` (the context-readiness section)

## Problem

Claude Code blocks session start on SessionStart hooks. `hooks/context-readiness.sh` is the slowest of them once the repo-memory hook was fixed. `session observe hooks` over 7 days of real sessions shows it at a 707ms median, a 2.4s p95 and a 5.1s max.

Almost all of that time is the live-spec filter. It runs two `grep` processes per spec file:

```bash
for F in $(ls docs/specs/SPEC-*.md 2>/dev/null | sort || true); do
  grep -qiE '^Status:[[:space:]]*(SHIPPED|PARKED)' "$F" && continue
  grep -qiE '^Status:' "$F" || continue
  printf '%s\n' "$F"
done
```

Measured on a Mac Mini, best of three:

| Repo | Specs | Filter alone | Whole hook |
|---|---|---|---|
| dwarves-kit | 267 | 2.29s | 2.15s |
| ops-toolkit | 33 | 0.26s | 0.38s |
| dotfiles | 0 | 0.01s | 0.09s |

When more than one spec is live, the branch-match loop adds a `basename`, a `sed` and a `printf | tr` pipeline per candidate.

## Change

1. Replace the filter loop with one `awk` pass over the same sorted file list. A file is live when some line matches `^status:` case-insensitively and no line matches `^status:` followed by blanks and then `shipped` or `parked`, case-insensitively. The blanks are spelled `[ \t\r\f\v]`, not `[[:space:]]`, because mawk 1.3.3 lacks POSIX classes. That is the old two-grep rule. The file list is still `ls docs/specs/SPEC-*.md | sort`, so the order of CANDIDATES is unchanged. An empty list skips awk, so awk never reads stdin.
1a. Before awk runs, keep only regular, readable files (`[ -f ] && [ -r ]`, both builtins). BSD awk aborts the whole pass on a path it cannot open, so one dangling link or unreadable spec would drop every live spec. The old per-file greps failed on such a path and skipped only that file, and the filter keeps that behavior.
2. In the branch-match loop, compute SLUG with parameter expansion and `BASH_REMATCH`, and BTOK with `${BRANCH_NAME//[\/_.-]/ }`. Both are bash 3.2 compatible and give the same strings as the old pipelines.

Nothing else in the hook changes. `git status` and the source-file `find` remain. They cost about 90ms and 70ms, and changing them would change what the hook reports.

## Picture

```
ls docs/specs/SPEC-*.md | sort
        |
        v
[ -f ] && [ -r ] filter  (drops dangling links, dirs, unreadable files)
        |
        v
one awk pass  --->  CANDIDATES (live specs, sorted)
                         |
            1 -> SPEC_FILE        >1 -> branch token match (bash expansions)
                                         |
                              1 match -> SPEC_FILE, else spec:ambiguous(...)
```

## Design

obvious: a mechanical cut in process spawns. The live rule, the branch-match rule and every output string stay the same.

### Approaches considered

1. One awk pass over the readable files (chosen). One spawn, and the whole rule lives in one place.
2. `grep -liE` and `grep -LiE` over the whole list, joined with `comm`. That is 2 to 3 spawns, and grep skips a file it cannot open on its own. It was rejected because `comm` needs both lists in the same collation as `sort`, and a third tool makes the rule harder to read. The readable-file filter gives awk the same skip behavior.

## Acceptance criteria

- AC1: stdout is byte-identical to the pre-change hook on: ops-toolkit, dotfiles, dwarves-kit, an empty non-git dir, and a fixture repo on branches `main`, `feat/gateway`, `fix/db-migrate`, `feat/api-auth`, `feat/gate-check`, `chore/a`, plus a single-live-spec case. That makes 11 cases.
- AC2: the fixture covers a lowercase `status:` line, a late `Status: parked` line after a live Status, a spec with no Status line, an empty spec file, a dangling symlink, and a mode-000 spec (the last only when not running as root).
- AC3: `bash tests/test-hooks.sh` passes, including the new assertions over the AC2 edge fixture.
- AC4: the new assertion goes red when the awk pass stops case-folding. Proven with `lib/gate/negctl.sh`.
- AC5: the hook takes under 0.5s on dwarves-kit, best of three on a lightly loaded machine, down from 2.15s. Under load (load average 25) it measured 0.87s against 4.8s for the old hook.

## Out of scope

- `git status --porcelain` and the `find` source count.
- Running `tests/test-hooks.sh` inside a git worktree of this repo was seen to append rows to that worktree's `_meta/BACKLOG.md`. A `git archive` copy did not reproduce it. This predates the change and is not chased here.

## Verification

Record: `docs/verification/context-readiness-one-pass.md`. To re-run the equivalence check, run the pre-change hook (`git show <base>:hooks/context-readiness.sh`) and the new hook in each AC1 case, then `diff` the two stdouts. The fixture branches and spec files are listed in AC1 and AC2.

## Tasks

- [x] T1: one-pass filter and builtin slug/branch tokens in `hooks/context-readiness.sh`, plus the edge assertion in `tests/test-hooks.sh`.
