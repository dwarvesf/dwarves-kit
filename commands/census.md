---
description: "Build or refresh a source-cited, agent-checkable feature inventory for a target project: per-module spec + a top-level checklist. Works standalone (what does this codebase do) or as a migration source of truth (what needs porting)."
---

Formalizes a pattern already run by hand at least 4 times (dfoundation's
`projects/cloudflare-migration/specs/{icy,invoice,leave,payout}.md`, one shared
7-section template every time, plus `ENDGAME-CHECKLIST.md` as the rollup ledger).
Same dispatch idiom as `/kit:spec`'s Step 2 research fan-out. Generic: point it at
ANY project. A named port/migration target is one use case, not a requirement.

## Process

### Step 1: Gather intent

If not already clear from the conversation, ask:

- Which project, and where does it live (repo path, or clone-read location)?
- Which modules/areas? (or: derive the module list from the project's routing /
  directory structure?)
- Is there a named port/migration target (a system this is moving to), or is this a
  plain census (understand/document what the project does, no target)? This decides
  whether `research-features` writes a Parity contract (port) or a Behavior contract
  (census) -- see `agents/research-features.md` section 5.
- Output location for specs (default `docs/specs/`) and for the top-level checklist
  (default `docs/CENSUS.md`; a migration run may prefer a name like
  `docs/PORT-CHECKLIST.md`, caller's call).

### Step 2: Derive or confirm the module list

If not given, propose one from the project's structure (route groups, top-level
packages, cron registrations). Show it, get confirmation -- don't guess silently on
scope this consequential.

### Step 3: Dispatch `research-features` per module, in parallel

#### Mode A (preferred)

If `.claude/agents/research-features.md` exists, dispatch it via the Task/Agent tool
once per module, in parallel, each with: module name, source location, output path,
and whether a port target was named (and if so, what).

#### Mode B (inline fallback)

If not installed, dispatch a general-purpose read-only subagent per module with the
`research-features` prompt embedded (same 7-section template, same `file:line`
citation rule -- see `agents/research-features.md` for the exact template if present,
otherwise use the shape below):

```
Produce a source-cited feature inventory for the <module> module of <project>,
located at <source location>[, being ported to <target>, if one was named]. Find
every entry point (routes/crons/webhooks/CLI/exported functions), cite file:line for
each, note data touched, external calls, a <parity contract: golden-fixture
input->output a port must reproduce / behavior contract: what must always hold>,
flag money/irreversible actions as STOP-gates, a test plan, and open questions. No
line cap; every claim needs a citation. Write to <output path> using the section
order: Scope (with a MIGRATE table if porting, else a plain live-path table, and an
Out-of-scope list with real owners), Pipeline, Data, External calls, <Parity/Behavior
contract>, Test plan, Open questions.
```

### Step 4: Build/refresh the top-level checklist

Read every module spec's Scope + section-5 contract. Write/update the checklist file
from Step 1:

```markdown
# Feature census: <project>[ -> <target>, if porting]

Generated <date>. Source of truth for what this project does[ and what's ported];
re-run `/kit:census` to refresh.

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
