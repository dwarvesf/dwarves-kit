# Proof of done: cockpit board command (SPEC-146)

## Acceptance criteria -> run-table

| # | Criterion | Result | Evidence |
|---|---|---|---|
| AC1 | `pb_rows`/`pb_queue_rows` extract + allow-list a valid `#queue{repo=...,pointer=...}` token, resolving to a real canonical path | PASS (6/6) | `bash tests/test-board.sh` "AC1/AC2" section |
| AC2 | Malformed token (missing a key) skipped, not emitted, reason logged | PASS (2/2) | "AC3" section |
| AC3 | Token on a non-`queued` row silently ignored | PASS (1/1) | "AC4" section |
| AC4 | Single-repo `board\|next\|set\|states\|priority` + cross-repo `all board\|next\|states\|priority[overview\|matrix]` render correctly | PASS (10/10) | "AC5"/"AC6" sections |
| AC5 | **NEGATIVE CONTROL (NC-a):** zero tokens -> empty stdout, "0 rows" on stderr, exit 0 | PASS (3/3) | "NC-a" section |
| AC6 | **NEGATIVE CONTROL (NC-b):** repo not in `boards.txt` / cross-repo spoof -> skipped w/ reason | PASS (3/3) | "NC-b" section |
| AC7 | **NEGATIVE CONTROL (NC-c):** pointer outside allow-listed dirs incl. `../` traversal, plus a dangling pointer -> skipped w/ reason | PASS (6/6) | "NC-c" section |
| AC8 | **NEGATIVE CONTROL (NC-d):** shell-metachar field never reaches an exec boundary (dynamic canary + static source audit) | PASS (4/4) | "NC-d" section |
| AC9 | **NEGATIVE CONTROL (NC-e), LOAD-BEARING:** render byte-identical to the pre-migration ops-toolkit `_meta/board`/`_meta/board-all`, against the REAL 13-repo cockpit | PASS (9/9) | "NC-e" section (real ops-toolkit path present on this machine; SKIPS in CI, same precedent as `test-weekend-batch.sh`'s dotfiles-path check) |
| CD | Coverage delta | PASS | 0 -> 44 board-tool-specific assertions |

**Total: 45/45 PASS, 0 FAIL, 0 SKIP** (ops-toolkit happened to be present on this run, so NC-e ran
for real rather than skipping).

## Implementation

- `lib/board.sh` (new): `board\|next\|set\|states\|priority [mode]` (single-repo, `--backlog-file`),
  `all <cmd>` (cross-repo, `--repo-root`/`--registry`), `queue [--dry-run]` (new). Base kanban
  render delegates to the existing `lib/backlog.sh`, unmodified. The `priority` quadrant awk and
  the cross-repo `priority matrix` pivot are migrated verbatim from ops-toolkit's
  `_meta/board`/`_meta/board-all`.
- `lib/parse-board.sh` (new): `pb_rows` / `pb_queue_rows`, the reusable structured parser + the
  `#queue{}` allow-list (charset gate, repo self-consistency, `../` traversal hardening,
  existence check).
- `tests/test-board.sh` (new): the run-table above, 45 assertions.
- `tests/test-meta.sh`: one new structural pin (board.sh + parse-board.sh executable, delegates
  to backlog.sh, doc-impact map updated).
- `README.md` / `docs/architecture.md`: doc-impact map entries for the two new `lib/` files.
- `.github/workflows/test.yml`: one new CI step (`bash tests/test-board.sh`).
- `docs/specs/SPEC-146-cockpit-board-tool.md`, `docs/implementation-notes/SPEC-146-cockpit-board-tool.md`.

## Confirmation run (green)

```
$ bash tests/test-board.sh
...
=== NC-e: RENDER NON-REGRESSION against the REAL ops-toolkit cockpit ===
  PASS NC-e: single-board byte-identical
  PASS NC-e: single-next byte-identical
  PASS NC-e: single-priority-overview byte-identical
  PASS NC-e: single-states byte-identical
  PASS NC-e: all-board byte-identical
  PASS NC-e: all-next byte-identical
  PASS NC-e: all-priority-overview byte-identical
  PASS NC-e: all-priority-matrix byte-identical
  PASS NC-e: all-states byte-identical

=== Coverage delta ===
  PASS coverage delta: board.sh/parse-board.sh checks went from 0 to 44 in this suite

  ---------------------------------------------
  TOTAL: 45   PASS: 45   FAIL: 0   SKIP: 0
```

## Negative controls (load-bearing, each confirmed RED then reverted)

Two independent deliberate breakages were applied in-place, the suite re-run to confirm the
EXACT expected assertions flip red (and nothing else), then reverted and re-confirmed
byte-identical to the pre-breakage file.

### 1. Allow-list breakage (repo self-consistency check neutered)

`lib/parse-board.sh`'s repo-mismatch guard changed from
`if [ "$repo" != "$repo_name" ]; then ...` to `if false && [ "$repo" != "$repo_name" ]; then ...`
(unreachable condition, simulating the check silently disappearing):

```
$ bash tests/test-board.sh   # (repo self-consistency check neutered)
...
  FAIL NC-b: ID-006 (claims repo=fixB while living in fixA's board) is skipped
  FAIL NC-b: the skip reason names the mismatch
  FAIL NC-b: ID-006 never appears in the emitted rows
  ---------------------------------------------
  TOTAL: 45   PASS: 42   FAIL: 3   SKIP: 0
```

Exactly the three NC-b assertions flip red; every other assertion (AC1-AC4, NC-a, NC-c, NC-d,
NC-e, AC coverage) is unaffected, confirming they test independent behavior. File restored
(`cmp` confirmed byte-identical to the pre-breakage backup), suite re-confirmed GREEN (45/45).

### 2. Render breakage (priority quadrant logic changed)

`lib/board.sh`'s `_priority_render` DO-NOW classification changed from
`if(u=="hi"&&f=="hi") t1[++n1]=row` to `if(u=="hi") t1[++n1]=row` (merges the DO-NOW and
URGENT,HARDER quadrants -- the exact class of subtle regression the render-migration NC exists
to catch):

```
$ bash tests/test-board.sh   # (priority quadrant classification broken)
...
=== NC-e: RENDER NON-REGRESSION against the REAL ops-toolkit cockpit ===
  PASS NC-e: single-board byte-identical
  PASS NC-e: single-next byte-identical
  FAIL NC-e: single-priority-overview byte-identical
  PASS NC-e: single-states byte-identical
  PASS NC-e: all-board byte-identical
  PASS NC-e: all-next byte-identical
  FAIL NC-e: all-priority-overview byte-identical
  PASS NC-e: all-priority-matrix byte-identical
  PASS NC-e: all-states byte-identical
  ---------------------------------------------
  TOTAL: 45   PASS: 43   FAIL: 2   SKIP: 0
```

Exactly the two `priority overview` render checks (single-repo and cross-repo) flip red against
the REAL ops-toolkit cockpit -- the `priority matrix` pivot (a separate awk block, untouched by
this edit) stays green, confirming the checks are independently sensitive to the specific logic
they cover. File restored (`cmp` confirmed byte-identical), suite re-confirmed GREEN (45/45),
`shellcheck lib/board.sh lib/parse-board.sh` re-confirmed clean.

## Byte-identical render proof (before/after, zero diff)

Captured directly (not just via the test harness) against the real ops-toolkit cockpit, using
`/usr/bin/cmp` (NOT the shell's `diff`, which is fish-aliased and fails non-interactively on this
machine -- a known gotcha):

```
$ OPS=~/workspace/tieubao/ops-toolkit
$ KIT=<this worktree>
$ # BEFORE: the real, unmodified ops-toolkit scripts
$ $OPS/_meta/board                                    > before.board.out
$ $OPS/_meta/board next                               > before.next.out
$ $OPS/_meta/board priority overview                  > before.prio-overview.out
$ $OPS/_meta/board priority full                      > before.prio-full.out
$ $OPS/_meta/board priority brief                     > before.prio-brief.out
$ $OPS/_meta/board priority counts                    > before.prio-counts.out
$ $OPS/_meta/board states                              > before.states.out
$ $OPS/_meta/board-all                                 > before.all-board.out
$ $OPS/_meta/board-all next                            > before.all-next.out
$ $OPS/_meta/board-all priority overview               > before.all-prio-overview.out
$ $OPS/_meta/board-all priority matrix                 > before.all-prio-matrix.out
$ $OPS/_meta/board-all priority full                   > before.all-prio-full.out
$ $OPS/_meta/board-all states                          > before.all-states.out
$ # AFTER: the new kit tool, invoked exactly as the shim would invoke it
$ bash $KIT/lib/board.sh board --backlog-file $OPS/_meta/BACKLOG.md          > after.board.out
$ bash $KIT/lib/board.sh next --backlog-file $OPS/_meta/BACKLOG.md           > after.next.out
$ bash $KIT/lib/board.sh priority overview --backlog-file $OPS/_meta/BACKLOG.md > after.prio-overview.out
$ bash $KIT/lib/board.sh priority full --backlog-file $OPS/_meta/BACKLOG.md  > after.prio-full.out
$ bash $KIT/lib/board.sh priority brief --backlog-file $OPS/_meta/BACKLOG.md > after.prio-brief.out
$ bash $KIT/lib/board.sh priority counts --backlog-file $OPS/_meta/BACKLOG.md > after.prio-counts.out
$ bash $KIT/lib/board.sh states --backlog-file $OPS/_meta/BACKLOG.md         > after.states.out
$ bash $KIT/lib/board.sh all board --repo-root $OPS                         > after.all-board.out
$ bash $KIT/lib/board.sh all next --repo-root $OPS                         > after.all-next.out
$ bash $KIT/lib/board.sh all priority overview --repo-root $OPS            > after.all-prio-overview.out
$ bash $KIT/lib/board.sh all priority matrix --repo-root $OPS              > after.all-prio-matrix.out
$ bash $KIT/lib/board.sh all priority full --repo-root $OPS                > after.all-prio-full.out
$ bash $KIT/lib/board.sh all states --repo-root $OPS                       > after.all-states.out
$ for pair in board next prio-overview prio-full prio-brief prio-counts states \
              all-board all-next all-prio-overview all-prio-matrix all-prio-full all-states; do
    /usr/bin/cmp -s before.$pair.out after.$pair.out && echo "PASS $pair byte-identical" || echo "FAIL $pair"
  done
PASS board byte-identical
PASS next byte-identical
PASS prio-overview byte-identical
PASS prio-full byte-identical
PASS prio-brief byte-identical
PASS prio-counts byte-identical
PASS states byte-identical
PASS all-board byte-identical
PASS all-next byte-identical
PASS all-prio-overview byte-identical
PASS all-prio-matrix byte-identical
PASS all-prio-full byte-identical
PASS all-states byte-identical
```

13/13 byte-identical, exit codes matched (before==after) on every pair, including `next`'s
pre-existing SIGPIPE exit (141) on this real BACKLOG.md -- a pre-existing `backlog.sh` behavior,
unrelated to this change, reproduced identically before and after since `backlog.sh` itself was
never touched.

## Live run: `board queue --dry-run` against the real ops-toolkit cockpit (read-only)

```
$ bash lib/board.sh queue --dry-run --repo-root ~/workspace/tieubao/ops-toolkit
queue: --dry-run has no additional effect (queue never mutates any BACKLOG.md)
queue: 0 rows
$ echo "exit=$?"
exit=0

$ git -C ~/workspace/tieubao/ops-toolkit status --porcelain -- _meta/boards.txt _meta/BACKLOG.md
(empty -- confirms read-only, zero writes)

$ grep -c '#queue{' ~/workspace/tieubao/ops-toolkit/_meta/BACKLOG.md
0
```

Honest-empty: no row in the real cockpit carries a `#queue{}` marker yet (the marker is new, born
in this sub-goal), so "0 rows" is the CORRECT live answer, not a bug. `git status` on the two
consumer files ops-toolkit owns confirms the run wrote nothing.

## Also verified: no regression to sibling suites

```
$ bash tests/test-meta.sh
=== Results ===
Passed: 670 / 670
All meta tests passed.

$ bash tests/test-hooks.sh
=== Results ===
Passed: 452 / 452
All tests passed.
```

## `shellcheck` (clean)

```
$ shellcheck lib/board.sh lib/parse-board.sh tests/test-board.sh
$ echo $?
0
```

## Rung 4 (INJECTION SURFACE) -- self-adversarial pass

**Threat:** a free-text Notes cell in a `BACKLOG.md` feeds `board queue`'s output, which an
unattended overnight runner (sub-goal 03K) consumes via argv-exec. A malicious or malformed cell
must not (a) escape the allow-list to point the runner at an arbitrary file, (b) claim a repo it
does not belong to, or (c) inject a shell command via any field.

Attempts, and why each is blocked:

1. **Repo not in `boards.txt` / cross-repo spoof.** A row in repo A's board claims
   `repo=repoB` (a repo that IS registered, just not this one) or `repo=nonexistent` (not
   registered at all). Both are blocked by the SAME check: `pb_queue_rows` is called with the
   `<repo-name>` of the file actually being parsed (from the registry walk itself, never from row
   content), and the token's `repo=` field must equal that value exactly. A row cannot assert a
   different repo than the one whose board it lives in, regardless of whether that other repo
   exists in `boards.txt`. Verified: NC-b, `tests/test-board.sh`.
2. **Path traversal (`../../../etc/passwd`).** Two independent layers: (i) the pointer charset
   regex `^[A-Za-z0-9_./-]+$` permits `.` and `/`, so a raw `..` sequence is not rejected by
   charset alone; (ii) a dedicated wrapped-string check (`case "/$pointer/" in */../*)`) rejects
   any `..` PATH COMPONENT at any position (leading, interior, trailing) before the pointer is
   ever joined with `repo_root`. Verified: NC-c, `tests/test-board.sh`.
3. **Wrong-directory pointer (a real, existing file OUTSIDE the allow-listed dirs, e.g.
   `lib/board.sh` itself).** Caught by the containment check: `_canon_path(repo_root/pointer)`
   must have `repo_root/_meta/megagoals/` or `repo_root/.claude/goals/` as a literal STRING
   prefix (trailing slash in the prefix, so `_meta/megagoals-evil` cannot match). A real,
   readable, existing file is still rejected if it sits outside those two directories. Verified:
   NC-c, `tests/test-board.sh` (ID-005 case).
4. **Dangling pointer (references a file that was never created).** Rejected by the existence
   check as defense in depth: an allow-listed-but-nonexistent path is useless to the downstream
   runner and is treated identically to malformed input, never emitted as a false promise.
   Verified: NC-c, `tests/test-board.sh` (ID-009 case).
5. **Shell metachar / command-substitution / newline injection** (`; touch <canary>`,
   `$(whoever)`, backticks, embedded space) in either the `repo=` or `pointer=` field. Blocked at
   the charset gate (`^[A-Za-z0-9_-]+$` for repo, `^[A-Za-z0-9_./-]+$` for pointer) BEFORE any
   other logic runs -- none of `;`, `$`, `` ` ``, space, or newline are in either allowed
   character class, so a metachar-bearing field can never be accepted as a valid token in the
   first place. Verified DYNAMICALLY: a live test wrote a `touch <canary-file>` payload into a
   pointer value and confirmed the canary file was NEVER created after running `board queue`.
   Verified STATICALLY: `tests/test-board.sh`'s NC-d section greps both `lib/board.sh` and
   `lib/parse-board.sh` for `eval` or `sh/bash -c "$var"` patterns and asserts NEITHER file ever
   hands a parsed value to a shell for re-interpretation -- the structural guarantee behind
   "never executed" that holds regardless of the specific payload tried.
6. **Malformed token (missing a required key).** A `#queue{repo=X}` with no `pointer=` (or vice
   versa) is rejected before any path resolution is attempted. Verified: AC2/AC3,
   `tests/test-board.sh`.
7. **A `#queue{}` marker on a non-`queued` row.** `pb_queue_rows` filters to `status == "queued"`
   BEFORE even looking for a marker, so a `claimed`/`shipped`/`parked` row's marker (if one
   happens to be present, e.g. left over from a prior state) is never considered. Verified: AC3,
   `tests/test-board.sh`.

**No attempt succeeded in escaping the allow-list, spoofing a repo, or reaching a shell with
untrusted content.**

**VERDICT: SECURE**

## Reproduce

```bash
cd dwarves-kit
bash tests/test-board.sh
bash tests/test-meta.sh
bash tests/test-hooks.sh
shellcheck lib/board.sh lib/parse-board.sh tests/test-board.sh

# live, read-only:
bash lib/board.sh queue --dry-run --repo-root ~/workspace/tieubao/ops-toolkit
```

For the negative controls: in `lib/parse-board.sh`, change
`if [ "$repo" != "$repo_name" ]; then` to `if false && [ "$repo" != "$repo_name" ]; then`, re-run
`tests/test-board.sh`, observe the 3 NC-b failures above, then revert. Separately, in
`lib/board.sh`, change `if(u=="hi"&&f=="hi") t1[++n1]=row` to `if(u=="hi") t1[++n1]=row` inside
`_priority_render`, re-run, observe the 2 NC-e failures above, then revert.
