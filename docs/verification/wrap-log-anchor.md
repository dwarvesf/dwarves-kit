# Proof of done: wrap log lands entries below the header, not above it

2026-09-10. `cmd_log` always prepended the new line at position 0, so every `wrap log`
call landed the entry above the target file's title, description and `---` separator
instead of among the entries. Confirmed live: `tieubao/ops-toolkit`'s `_meta/LAB_LOG.md`
had two entry lines sitting above its `# LAB_LOG` heading, written by two sessions today.

## Fix

`_log_anchor_head_lines <file>` (lib/wrap/wrap.sh) finds the first line that is exactly
`---` and returns how many lines of the file stay above the new entry: the anchor line
plus any blank lines immediately following it. If line 1 is itself `---` (a YAML
frontmatter opening delimiter), the SECOND `---` becomes the anchor instead, so the
entry never lands inside frontmatter. A file with no `---` anchor at all returns 0,
and `cmd_log` falls back to the old prepend-at-line-0 behavior rather than failing.

## Green run

Command: `bash tests/test-wrap.sh`
Exit: 0
Output: `test-wrap: all 278 passed` (269 pre-existing + 9 new anchor/frontmatter/
fallback/header-only/empty-file cases, all PASS).
Verdict: PASS

## NEGATIVE CONTROL (break the anchor search, watch the new cases go red, restore)

Command: hardcode `head_n="0"` in `cmd_log`, re-run `bash tests/test-wrap.sh`
Exit: 0 (test runner itself), but the suite reports failures
Output: `test-wrap: 272 passed, 6 FAILED of 278` -- exactly the 6 anchor/frontmatter/
header-only cases that assert the entry lands below the header went red; the
no-anchor-fallback, empty-file, and previously-newest-is-now-second cases stayed
green because they assert the same prepend-at-0 shape the broken code also produces.
Verdict: PASS (negative control proves the new tests exercise the anchor logic)

Restore: copied the committed `lib/wrap/wrap.sh` back over the hand-edited copy,
verified byte-identical with `cmp`, re-ran the suite.
Command: `bash tests/test-wrap.sh` after restore
Exit: 0
Output: `test-wrap: all 278 passed`
Verdict: PASS

## Not covered here

`test-config-seams.sh` only exercises `wrap.activity_log` key resolution, not the
write itself; no anchor-shaped case belongs there. The existing prepend-fallback
tests in `test-wrap.sh` (files with no `---` header at all) are unchanged and keep
covering that path.
