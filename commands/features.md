---
description: "Build or refresh a source-cited, agent-checkable feature inventory for ANY target project you point it at: per-module spec + a top-level checklist. Works standalone (what does this codebase do) or as a migration source of truth (what needs porting). Refresh mode is an audit-loop instance, sibling to the maintainer-only kit:feature-map (which audits this kit's own registry, not a target project)."
---

Formalizes a pattern already run by hand at least 4 times (dfoundation's
`projects/cloudflare-migration/specs/{icy,invoice,leave,payout}.md`, one shared
7-section template every time, plus `ENDGAME-CHECKLIST.md` as the rollup ledger).
Same dispatch idiom as `/kit:spec`'s Step 2 research fan-out. Generic: point it at
ANY project. A named port/migration target is one use case, not a requirement.

## Relationship to the audit-loop pattern

Step 6 (Refresh mode) below is an instance of `docs/patterns/audit-loop.md`:

| Slot | This instance |
|---|---|
| Item set | every module row in the checklist (Step 4's output), enumerated at Step 2 |
| Contract | the module's spec (`docs/specs/<module>.md`) still matches the live source across every given location |
| Evidence class | a fresh `research-features` re-read of the source, `file:line` cited, diffed against the existing spec |
| Apply mechanics | match = leave status untouched (OK); drift = `NEEDS REVIEW` on the checklist row (FIX proposed, never silent); the operator decides |

The FIRST run against a module isn't an audit (there's nothing to reconcile yet,
just a spec to construct) -- the audit-loop shape only applies from Step 6 onward.
Sibling instance: `skills/feature-map/SKILL.md` (maintainer-only, audits THIS repo's
own command/agent/skill/hook registry against its path-index doc, not a target
project). Different item set and contract, same four-slot shape; an improvement to
one loop's evidence/apply mechanics is worth checking against the other.

## Process

### Step 1: Gather intent

If not already clear from the conversation, ask:

- Which project? A project can be ONE repo or SEVERAL -- list every repo/clone-read
  location in scope, each with a short tag (`fortress-api: ~/repos/fortress-api`,
  `foundation-workers: ~/repos/foundation-workers`). A single-repo project is just
  the N=1 case, nothing special to configure.
- Any named surfaces with no readable source (a Discord server/channel, a Notion
  automation/database, a third-party webhook)? These get documented by reference
  (a doc, a URL, an automation ID), never a fabricated citation. Skip if none.
- Which modules/areas? (or: derive the module list from the given locations'
  routing/directory structure? A module may span more than one location, e.g. a
  Discord command in one repo triggering a handler in another -- see one module,
  multiple locations, not one module per repo.)
- Is there a named port/migration target (a system this is moving to), or is this a
  plain census (understand/document what the project does, no target)? This decides
  whether `research-features` writes a Parity contract (port) or a Behavior contract
  (census) -- see `agents/research-features.md` section 5.
- Output location for specs (default `docs/specs/`) and for the top-level checklist
  (default `docs/CENSUS.md`; a migration run may prefer a name like
  `docs/PORT-CHECKLIST.md`, caller's call).

### Step 2: Derive or confirm the module list

If not given, propose one from the given locations' structure (route groups,
top-level packages, cron registrations) -- across ALL locations, not just the first
one named. Show it, get confirmation -- don't guess silently on scope this
consequential, and don't silently assume a module lives in only one repo.

### Step 3: Dispatch `research-features` per module, in parallel

Each dispatch gets the FULL location set (every tagged repo + named surface from
Step 1), not just whichever one the module "mostly" lives in -- the agent decides
per-module relevance and traces cross-repo calls itself; under-scoping the input is
how a real cross-repo behavior gets silently cut in half.

#### Mode A (preferred)

If `.claude/agents/research-features.md` exists, dispatch it via the Task/Agent tool
once per module, in parallel, each with: module name, the full tagged-location list,
any named surfaces, output path, and whether a port target was named (and if so,
what).

#### Mode B (inline fallback)

If not installed, dispatch a general-purpose read-only subagent per module with the
`research-features` prompt embedded (same 8-item findings list, same `file:line`
citation rule -- see `agents/research-features.md` for the exact template if present,
otherwise use the shape below):

```
Produce a source-cited feature inventory for the <module> module of <project>.
Locations (read ALL of them; a behavior can start in one and finish in another):
<tag>: <path>, <tag>: <path>, ... Surfaces (no readable source, cite by reference
only): <name>: <what/how referenced>, ... [being ported to <target>, if one was
named]. Find every entry point (routes/crons/webhooks/CLI/exported functions) in
every location, cite file:line for each (tag-prefixed if more than one location),
note data touched, cross-repo calls (cited on both ends, not filed as "external"),
external calls, a <parity contract: golden-fixture input->output a port must
reproduce / behavior contract: what must always hold>, flag money/irreversible
actions as STOP-gates, a test plan, and open questions. No line cap; every claim
needs a citation, never a fabricated one for a surface. Write to <output path> using
the section order: Scope (with a MIGRATE table if porting else a plain live-path
table, a Location column if >1 location, a Surfaces subsection if any, and an
Out-of-scope list with real owners), Pipeline (cross-repo legs cited on both sides),
Data, External calls, <Parity/Behavior contract>, Test plan, Open questions.
```

### Step 4: Build/refresh the top-level checklist

Read every module spec's Scope + section-5 contract. Write/update the checklist file
from Step 1:

```markdown
# Feature census: <project>[ -> <target>, if porting]

Generated <date>. Source of truth for what this project does[ and what's ported];
re-run `/kit:features` to refresh.

| Module | Behavior | Status | Spec | STOP-gate |
|---|---|---|---|---|
| payout | commit (month/batch) | NOT STARTED | specs/payout.md#5 | yes |
```

`Status` only makes sense with a port target (NOT STARTED / IN PROGRESS / PORTED /
VERIFIED); for a plain census, drop that column and use the row purely as a feature
inventory (Module / Behavior / Spec / STOP-gate). On a refresh run, preserve existing
status values for rows unchanged since the last spec; flag any row whose behavior
text changed (source drifted) as `NEEDS REVIEW` rather than silently resetting it.

### Step 5: Present for review

Show module count, behavior count, STOP-gate count, and every module's open
questions rolled up. Ask: "Approve, or adjust scope?"

### Step 6: Refresh mode

Re-running against a module that already has a spec: dispatch `research-features`
again, diff the new Scope/section-5 output against the existing file. Match = leave
status untouched. Drift = flag it in the checklist (`NEEDS REVIEW`) and let the
operator decide whether the spec (or, if porting, the port itself) needs updating --
never silently overwrite a spec someone signed off on.

## Cadence

Run a module's refresh (Step 6) after its live source changes -- a merge into a
module you already have a spec for, or before trusting the checklist as a migration
gate. Default driver is one interactive pass (this command, run directly): fine for
the module counts a real project actually has (dfoundation's Cloudflare migration
ran 4). For a module list too large to refresh in one session, escalate per the
audit-loop driver ladder: `/loop` for a recurring cadence, or the loop-engineering
runtime for a large set that needs to resume across sessions -- see
`docs/patterns/audit-loop.md`'s "The loop bridge". No cadence is forced by default;
this is pull, not a scheduled push, unlike `feature-map`'s merge-triggered cadence
(which reacts to every kit-internal commit -- there's no equivalent "every commit to
the target project" trigger here, since the target project isn't this repo).
