# Implementation notes: SPEC-194 surface consolidation (delta from spec only)

## 2026-07-12 14:05 Guidance strings repointed despite byte-level-unchanged bar

Context: the quality bar says outputs byte-level unchanged; several tools carry
user-facing strings NAMING the retired `add-backlog` surface (the engine's own usage
text + "promote with:" hint, stats' `--help` epilogs, the `_STAGING_HEADER` line
anomalies.py writes into the staging buffer).
Decision: repoint those strings to `board promote`; everything else moves verbatim.
Why: leaving them directs the operator at a command that exits non-zero after this PR
(the NC proves it dead); a stale self-reference is exactly the audit's target class.
Alternatives: leave verbatim (misleads), keep an alias (forbidden by ADR-0034 d7).
Impact: staged-buffer header text changes on future writes; no test asserts on it
(verified by grep before the edit).

## 2026-07-12 14:10 stats tests' cc-backlog cross-check left as dormant SKIP

Context: `lib/stats/tests/{test-feedback,test-anomalies-advisor,test-sessions-digest}.sh`
set `ADDBL="$ROOT/../cc-backlog/bin/add-backlog"` (the retired ops-toolkit sibling) and
SKIP when absent.
Decision: not repointed to `lib/board/bin/add-backlog`.
Why: the kit engine reads `BACKLOG_STAGE_*` env vars while those tests export
`CC_BACKLOG_*` for the stats CLI; repointing would make the check run against the wrong
files and fail, i.e. a behavior change, not a path move.
Alternatives: repoint + rewire env (out of scope: touches test semantics).
Impact: cross-check stays SKIP, as it already was on every machine since the cc-backlog
retirement.

## 2026-07-12 14:20 install.sh board module CLI = `board` (not nothing)

Context: the spec/goal fold retires the `add-backlog` PATH shim; the ADR does not say
what PATH surface the board module exposes afterwards.
Decision: `kit_module_clis board` -> `board` (one shim; `board promote` reaches the gate).
Why: the human gate must stay reachable from PATH for its consumers (the skills that
say "promote via board promote"); exposing `board` follows the one-grammar rule.
Alternatives: no shim (gate reachable only via $DWARVES_KIT path -- regresses operators),
a `board-promote` shim (a third grammar, forbidden).
Impact: `~/.local/bin/board` appears for `--with board` installs.

## 2026-07-12 14:25 module READMEs: Install sections repointed, usage examples kept

Context: lib/session/*/README.md show usage as `session-observe report` etc. (the tools'
own names, which do not change; deep paths stay).
Decision: repointed only the observe README's Install section (it instructed a symlink
creating the retired PATH name from the pre-foldin `tools/` path); left verb usage
examples as tool-level docs.
Why: the tool identity (prog name, argparse usage strings) is unchanged by design; only
the operator entry grammar moved.
Impact: none at runtime.

## 2026-07-12 14:30 board.sh usage() line-range bumped

Context: adding `promote` to board.sh's header usage block shifted the header length.
Decision: `usage()` sed range 2,159 -> 2,166 to keep `--help` printing the whole header.
Impact: cosmetic; `--help` output gains the promote lines.
