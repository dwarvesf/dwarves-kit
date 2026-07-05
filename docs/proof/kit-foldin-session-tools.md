# kit-foldin SG-03: session-tools -- narrative

Canonical gate-satisfying proof (run-table, NCs, COVERAGE-DELTA, reproduce):
`docs/verification/kit-foldin-session-tools.md`.

## What moved

`ops-toolkit/tools/cc-observe` -> `tools/session-observe/` (3 bins: `cc-observe`,
`cc-semantic`, `cc-vps-report`, unchanged names). `ops-toolkit/tools/cc-recall`
-> `tools/session-recall/` (`bin/cc-recall`, `cc_recall.py`, unchanged names).
`ops-toolkit/tools/cc-intel` -> `tools/session-intel/` (`bin/cc-intel`, unchanged
name) MINUS its `deploy/` (a personal launchd cron with a hardcoded
`/Users/tieubao/...` plist path and an ops-toolkit-assuming runbook -- it is not
a generic install script the way skill-curator's was, so deploy-follows-source
does not pull it into the kit; it stays in ops-toolkit for SG-07 to preserve).

History carried over per-commit via `git format-patch --relative` +
`git am --directory` (18 commits total: 12 for observe, 1 for recall, 5 for
intel), the same technique SG-04 used for skill-curator -- `git log --follow`
on the new kit path still walks back through the ops-toolkit-era commits.

## The design decision (open-Q 1, "extract the parser, not the capability")

The design note left the shared-parser's exact interface as an open design
task. The resolution: expose the RAW parsed JSON dict, not a wrapper type.
`iter_entries(path)` streams, `load(path)` materializes; both share one inner
loop. Full reasoning (why not a `Turn(role=, ts=, text=)` dataclass) is in the
verification doc's `## Design` section -- short version: role/ts/text
extraction is NOT duplicated between the two tools (only the file-parsing loop
is), so wrapping the dict would force an abstraction neither caller's real
logic needs, without resolving any duplication the plain-dict version doesn't
already resolve.

A third and fourth copy of the identical loop turned up mid-work: session-
observe's own `cc-semantic` bin, and session-intel's `repeat_detect`. Both
were folded into the same extraction so the "no duplicate turn-parser remains"
grep is actually true, not true-for-the-two-tools-the-design-note-named.

## Gate ledger

`bash lib/gate/gate-ledger.sh show kit-foldin-03-session` records: START (lane
normal), GATE design (ran -- Design: bearing, the interface decision above),
GATE build (ran -- move + extraction + rewire, 40+6+7+8 = 61 pre-existing
tests green unmodified + 7 new parser-unit tests), GATE review (dispatched
`kit:code-reviewer`, security lens, over untrusted-input parsing), GATE
recheck (dispatched `kit:recheck-verifier`, fresh-context re-run of the
run-table + NCs), GATE ship (this PR).
