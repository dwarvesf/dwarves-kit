# Rejected findings ledger

Per-repo memory of review findings the operator has explicitly REJECTED at review close.
Consulted (never auto-applied) by `/kit:review`, `/kit:review-team`, and `agents/advisor.md`
critique mode, per SPEC-144: before reporting, each surface `grep`s a candidate finding's
finding-key against this file. A match is SURFACED in a separate "previously rejected"
section (with the date and the operator's stated reason); it is NEVER silently dropped and
NEVER re-raised as if it were a fresh finding. Judgment stays with the human: if the evidence
behind a previously-rejected finding has materially changed since the rejection, the reviewer
re-raises it as a fresh finding and names the delta, rather than staying silent.

**Fail-open.** A missing or unreadable ledger file means "no memory" for every finding this
run, never an error and never a blocked review. A malformed row (missing columns, broken
table syntax) is inert for that one row; it does not stop the consult step from matching
every well-formed row correctly.

**No auto-rejection, no severity scoring.** Only a HUMAN rejection at review close appends a
row here (see "Append path" below). This file never decides what counts as a defect; it only
remembers what a human already decided about one.

## Format

| date | lens | finding-key | verdict | reason |
|---|---|---|---|---|
| YYYY-MM-DD | \<lens that raised it: security / architecture / test-coverage / advisor / ...\> | `<defect-slug>:<file-path>` | rejected | \<the operator's stated reason, one clause\> |

**finding-key** = `<defect-slug>:<file-path>`, colon-joined. `<defect-slug>` is a short
kebab-case name for the DEFECT SHAPE (e.g. `bare-except`, `sql-injection`, `stale-adr` -- the
last one is SPEC-143's existing prefix convention, which this scheme generalizes from one
named lens type to any lens), not the per-instance wording of the finding. `<file-path>` is
the path the finding was raised against, repo-relative.

**Match is on the WHOLE finding-key, pipe-anchored.** A previously-rejected
`bare-except:tools/notify.py` row matches ONLY a fresh finding whose OWN finding-key is also
`bare-except:tools/notify.py`. A different defect at the same file (say,
`sql-injection:tools/notify.py`) has a different finding-key and is NOT a match: it always
fires as a fresh finding. Matching on the file path alone (ignoring the slug) is one failure
mode SPEC-144's load-bearing negative control proves against; see
`docs/verification/spec-144-review-findings-memory.md`.

**Consult with a pipe-anchored search, never a bare substring search.** Every row's
finding-key cell is delimited by ` | ` on both sides (standard table formatting, one leading
and one trailing space); consult it with `grep -F "| <finding-key> |" <this file>`, matching
the whole cell. A bare `grep -F "<finding-key>"` substring-matches, so a shorter, unrelated
slug that happens to be a suffix of a longer rejected one (e.g. `except:notify.py` against the
`bare-except:notify.py` row above) would WRONGLY match -- kebab-case defect-slugs collide this
way routinely (`auth` in `no-auth-check`, `leak` in `secret-leak`), not as a rare edge case.
This was a real bug caught by a live architecture review of this file's own consult-step
prose (SPEC-144 verification doc, "Run 3: pipe-anchoring").

## Append path

When the operator rejects a finding at review close (tells the reviewer it is by-design, a
false positive, or a deliberate won't-fix), the reviewer appends ONE new row per rejected
finding to the table below: today's date, the lens that raised it, the finding's finding-key,
`rejected`, and the operator's stated reason distilled to one clause. Existing rows are never
edited or removed by this path (append-only); a later re-litigation of an already-rejected row
is a manual edit by a human, not something a review session does automatically.

## Rows

| date | lens | finding-key | verdict | reason |
|---|---|---|---|---|
| 2026-07-04 | architecture | single-file-ledger:lib/gate/gate-ledger.sh | rejected | intentional single-file design (ADR-0024's one append-only audit trail per run); splitting it across files would fragment the trail the ledger exists to keep whole |
