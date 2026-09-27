# Proof of done: handoffs-archive-skip (SPEC-333)

`lib/session/handoffs.sh cmd_list`'s `find` filter now excludes `archive/` and a nested
`.claude/` subdirectory alongside the pre-existing `done/`/`_archive/`, and fixes a
pre-existing bug where a repo checked out under a `.claude/`, `archive/`, `done/`, or
`_archive/` ANCESTOR path (e.g. `<repo>/.claude/worktrees/<name>/`) lost every live handoff
under both scan roots. Does not change the two scan roots, `handoff_liveness`, or any other
function.

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | `archive/` under either scan root is excluded | case [16] | PASS |
| AC2 | `_archive/` under either scan root is excluded (pre-existing suite only covered `done/`) | case [16] | PASS |
| AC3 | a stray nested `.claude/session-state/` under `.claude/handoffs` is excluded | case [16] | PASS |
| AC4 | live files under both `.claude/handoffs` and `_meta/handoffs` still list, exact count 2 | case [17] | PASS |
| AC5 | a repo checked out under a `.claude/` ancestor path loses neither scan root | case [18] | PASS |
| AC6 | a repo with only excluded paths gets the honest "no handoffs" message | case [19] | PASS |
| AC7 | every pre-existing case ([1]-[15]) is unaffected | full suite | PASS |

## Implementation

- `lib/session/handoffs.sh` `cmd_list` -- the `find "$d" -type f -name '*.md' -not -path
  '*/done/*' -not -path '*/_archive/*'` filter is replaced with `find "$d" -mindepth 1 \(
  -name done -o -name _archive -o -name archive -o -name .claude \) -type d -prune -o -type f
  -name '*.md' -print`, pruning on each visited node's own basename instead of a substring
  match against the full printed path. The two header-doc passages (lines ~5-6, ~20-21) name
  all four exclusions.
- `lib/session/tests/test-handoffs.sh` -- 4 new cases ([16]-[19], 22 total assertions in the
  file), each in its own `mktemp` fixture repo so the pre-existing exact-count assertions in
  `[1]`/`[4]`/`[6]` are untouched.

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash lib/session/tests/test-handoffs.sh` | 0 | smoke: all 22 passed |

## Run detail

```
[16] archive/, _archive/, and nested .claude/ excluded
  ok: archived/nested paths excluded
[17] live files under both scan roots present, exact count 2
  ok: both live files listed
  ok: count: 2 open handoffs
[18] a .claude/ ancestor above the repo root blanks neither scan root
  ok: both scan roots survive a .claude/ ancestor
[19] only-excluded repo: honest 'no handoffs'
  ok: no handoffs for only-excluded repo
---
smoke: all 22 passed
```

## Negative control (negctl.sh mutate mode, two reversions)

**NC1: revert to the pre-fix two-clause `-not -path` filter.** Must turn the new suite RED
(cases 1-4's archived/nested paths reappear as listed), then restore GREEN.

```
$ bash lib/gate/negctl.sh . "bash lib/session/tests/test-handoffs.sh" "git show 194c89f0:lib/session/handoffs.sh > lib/session/handoffs.sh"
## Negative control (negctl)
Command: bash lib/session/tests/test-handoffs.sh
Exit: 0 (green before mutation)
Mutation: git show 194c89f0:lib/session/handoffs.sh > lib/session/handoffs.sh
Changed: lib/session/handoffs.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/session/handoffs.sh
Exit: 0 (green after restore)
Verdict: PASS
```

(`194c89f0` is the spec-fold commit on this branch, immediately before the implementation
commit; `lib/session/handoffs.sh` was untouched by any commit before the implementation, so
its content there is byte-identical to the pre-spec original.)

**NC2: apply the rejected naive fix (SPEC-333 Solution approach 2) instead of the chosen
one.** Must turn the suite RED specifically on case 8/[18]'s `_meta/handoffs/live.md`
assertion, since `_meta/handoffs` is not itself named `.claude` and its live file
disappearing can only be explained by the ancestor segment leaking into the path match (the
exact bug this spec fixes), not by the scan root's own name (already explained by approach 2
in `## Solution`).

The mutate-cmd rewrites the fixed `find` block back to the naive two-clause append, matching
by content rather than line number. Written to a script file first (avoids nested-quoting
hazards through negctl's own `bash -c` layer):

```sh
cat > /tmp/nc2-mutate.sh <<'EOF'
#!/usr/bin/env bash
# NC2 mutate-cmd for negctl.sh: rewrite the -prune fix back to the naive
# "append two more -not -path clauses" shape (SPEC-333 Solution, approach 2,
# rejected). Matches the block by content, not line number.
set -euo pipefail
f="lib/session/handoffs.sh"
awk '
  /done < <\(find "\$d" -mindepth 1 \\/ {
    print "    done < <(find \"$d\" -type f -name '\''*.md'\'' \\"
    print "      -not -path '\''*/done/*'\'' -not -path '\''*/_archive/*'\'' -not -path '\''*/archive/*'\'' -not -path '\''*/.claude/*'\'' 2>/dev/null)"
    skip=2
    next
  }
  skip>0 { skip--; next }
  { print }
' "$f" > "$f.nc2tmp"
mv -f "$f.nc2tmp" "$f"
EOF
bash lib/gate/negctl.sh . "bash lib/session/tests/test-handoffs.sh" "bash /tmp/nc2-mutate.sh"
```

Actual run (verbatim):

```
## Negative control (negctl)
Command: bash lib/session/tests/test-handoffs.sh
Exit: 0 (green before mutation)
Mutation: bash /private/tmp/claude-501/-Users-tieubao-workspace-tieubao-ops-toolkit/43bc5568-ab4c-4cbf-8147-f31fc9dad757/scratchpad/nc2-mutate.sh
Changed: lib/session/handoffs.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/session/handoffs.sh
Exit: 0 (green after restore)
Verdict: PASS
```

(The mutate script ran from this session's scratchpad path; the `cat > /tmp/nc2-mutate.sh`
form above is the same script content, relocated for reproducibility outside this session.)

Manual reproduction (mutation applied directly, inspected, then `git checkout HEAD --`
restored before negctl's own run) confirmed the specific failure signature negctl's exit-code
check alone does not distinguish:

```
[18] a .claude/ ancestor above the repo root blanks neither scan root
  FAIL: a .claude/ ancestor blanked a scan root: no handoffs
```

Both scan roots went empty under the naive mutation (not just `.claude/handoffs`), confirming
`_meta/handoffs/live.md` -- the decisive half -- went red.

Working tree confirmed clean (`git status --short` empty) after both restores.

## Reproduce

```
cd dwarves-kit  # this worktree
bash lib/session/tests/test-handoffs.sh                                            # 22/22, exit 0
bash lib/gate/negctl.sh . "bash lib/session/tests/test-handoffs.sh" \
  "git show 194c89f0:lib/session/handoffs.sh > lib/session/handoffs.sh"            # NC1
```

## Not proven
- The broader `tests/test-hooks.sh` suite was run once during this session and returned exit
  0, but is not re-asserted here: this spec's `## Verification` names only
  `tests/test-handoffs.sh` (an unrelated repo-wide test is not this change's proof).

Verdict: PASS
