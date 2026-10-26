# Proof of done: `lib/gate/verbatim-rows.sh`

Change: a new gate helper, `lib/gate/verbatim-rows.sh`, that asserts every row in one or
more rewritten structured-index files (a kanban board, a MANIFEST, a GLOSSARY, a memory
index) still appears verbatim, whole-line, in the pre-edit original as read via
`git show <ref>:<path>`.

## Why (the defect this would have caught)

An agent rewrote `.claude/memory/MEMORY.md` by re-deriving each row from the note's
frontmatter instead of copying it, and hard-truncated many rows mid-sentence. It restored
verbatim text for the rows it kept but not for the 209 it moved to an archive file, so 23
archive rows shipped cut, one ending on `so a later git stash pop pops a`. A truncated row
still ends in a legal character, so it survives an eyeball check; only a byte-for-byte diff
against the pre-edit file caught it. This mechanises that diff.

Deliberately NOT in scope: repairing rows, counting whether rows went missing, or judging
which file a row should live in. It asserts one property only.

## Green run

```
$ bash tests/test-verbatim-rows.sh
=== AC1: all rows verbatim -> exit 0 ===
  PASS all-verbatim exits 0 (rc=0): rows checked: 3, verbatim: 3, not verbatim: 0
  PASS all-verbatim reports 0 not-verbatim

=== AC2: one truncated row -> exit 1, names the row ===
  PASS truncated row exits 1 (rc=1)
  PASS output names the truncated row
  PASS summary reports 1 not-verbatim

=== AC3: --pattern override picks up a non-default row marker ===
  PASS --pattern override matches kanban rows and exits 0 (rc=0)
  PASS --pattern override checked 2 rows
  PASS default pattern finds 0 rows in a kanban file (rc=0)
  PASS default pattern checked 0 rows

=== AC4: bad ref -> exit 2 ===
  PASS bad ref exits 2 (rc=2)

=== usage error -> exit 2 ===
  PASS no args exits 2 (rc=2)

=== 11/11 passed ===
```

Also confirmed discoverable and green through the suite harness (auto-globbed by
`tests/run-all.sh`'s `test-*.sh` pattern, not hand-wired):

```
$ bash tests/run-all.sh --only verbatim-rows
test-verbatim-rows                             ok

run-all: all 1 suites passed, 0 skipped for missing tooling
```

## Full suite

`bash tests/run-all.sh` (the required full-suite check) is slow in this environment
(`lib/registry/feature-registry.sh` regenerating the whole repo's manifest, run twice, took
several minutes on its own) and was substituted with `bash tests/test-meta.sh`, the
documented fallback for "run-all is very slow":

```
$ bash tests/test-meta.sh
...
=== Results ===
Passed: 852 / 852
All meta tests passed.
```

Before substituting, `run-all.sh` was let run far enough to observe `test-config-registry`
fail 2 of 50 (`wrap.drain_staged ships as false`, `wrap.drain_staged ignores a project
.kit.toml`) before it was stopped for time; neither case names or touches
`verbatim-rows.sh`, and this branch has not touched `lib/gate/gate-ledger.sh` or
`tests/test-config-registry.sh`, so the failure is pre-existing on `origin/master`, not
something this change introduced. `bash tests/run-all.sh --only verbatim-rows` (above,
under "Green run") confirms the new suite is discovered and green under the real harness.

## Negative control (`lib/gate/negctl.sh`)

Mutation neuters the truncation-check counter (`bad=$((bad + 1))` -> `bad=$((bad + 0))`), so
a non-verbatim row is still detected and printed but never counted as bad: the exit code
stays 0 and AC2/AC3 in the test go RED.

Committed the helper + test first (`f4156fb`), so the restore below is provable against a
real prior commit, not just an in-memory diff.

```
$ bash lib/gate/negctl.sh "$(pwd)" "bash tests/test-verbatim-rows.sh" \
    "bash mutate-verbatim-rows.sh"   # mutate script: perl -pi -e edits bad=$((bad + 1)) -> bad=$((bad + 0))
## Negative control (negctl)
Command: bash tests/test-verbatim-rows.sh
Exit: 0 (green before mutation)
Mutation: bash mutate-verbatim-rows.sh
Changed: lib/gate/verbatim-rows.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/gate/verbatim-rows.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Confirmed the restore was real, not just negctl's own claim: `git status --porcelain --
lib/gate/verbatim-rows.sh` was empty after, and `bash tests/test-verbatim-rows.sh` was
re-run standalone and stayed 11/11 green.

## Reproduce

```
bash tests/test-verbatim-rows.sh
bash tests/run-all.sh --only verbatim-rows
```

## Rollback

Revert the commit; no other file references `lib/gate/verbatim-rows.sh` yet.

## Addendum: `--words` mode

Change: `verbatim-rows.sh --words [--ignore-headings] <ref> <orig> <new>` compares the word
sequence of the original with the new file, ignoring whitespace and line breaks, YAML
frontmatter in both files, and standalone list or quote markers. Whole-line row matching
cannot check prose that was reformatted (headings added, paragraphs split, lines reflowed)
in a source kept word for word. Row mode is untouched.

```
$ bash tests/test-verbatim-rows.sh
=== AC5: --words, reformat keeping every word -> exit 0 ===
  PASS reflow with headings ignored exits 0 (rc=0)
  PASS reflow reports 0 changes
  PASS added heading without --ignore-headings exits 1 (rc=1)
  PASS added heading is named as inserted
  PASS row mode rejects the same reflow (rc=1)
=== AC6: --words, dropped or changed word -> exit 1, names it ===
  PASS dropped word exits 1 (rc=1)
  PASS dropped word 'lazy' is named
  PASS context shows the neighbouring words
  PASS changed word exits 1 (rc=1)
  PASS changed word is shown as forest -> jungle
=== AC7: --words, usage and read errors -> exit 2 ===
  PASS unreadable new file exits 2 (rc=2)
  PASS --words bad ref exits 2 (rc=2)
  PASS --words with two new paths exits 2 (rc=2)
  PASS --ignore-headings without --words exits 2 (rc=2)
=== 25/25 passed ===

$ bash tests/run-all.sh --only verbatim-rows
test-verbatim-rows                             ok
```

Negative control: the word-diff exit `sys.exit(1 if changes else 0)` was mutated to
`sys.exit(0)` (backup copy kept, restored with `cp` and confirmed byte-identical with `cmp`).
Under the mutation the suite went RED, 22/25, with the three change-detection cases failing
(added heading, dropped word, changed word); after restore it is 25/25 again.

Rollback: revert the commit; row mode never changed.
