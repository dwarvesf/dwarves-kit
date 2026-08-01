---
description: "Build or refresh the feature-inventory source of truth for a system migration: per-module spec + a top-level port checklist, source-cited and agent-checkable."
---

Formalizes a pattern already run by hand at least 4 times (dfoundation's
`projects/cloudflare-migration/specs/{icy,invoice,leave,payout}.md`, one shared
7-section template every time, plus `ENDGAME-CHECKLIST.md` as the rollup ledger).
Same dispatch idiom as `/kit:spec`'s Step 2 research fan-out.

## Process

### Step 1: Gather intent

If the module/source scope isn't already clear from the conversation, ask:

- What's being migrated (source system + target)?
- Which modules/areas? (or: derive the module list from the source's routing /
  directory structure?)
- Where does the source live (repo path, or clone-read location)?
- Output location for specs (default `docs/specs/`) and for the top-level checklist
  (default `docs/PORT-CHECKLIST.md`).

### Step 2: Derive or confirm the module list

If not given, propose one from the source's structure (route groups, top-level
packages, cron registrations). Show it, get confirmation -- don't guess silently on
scope this consequential.

### Step 3: Dispatch `research-migration` per module, in parallel

#### Mode A (preferred)

If `.claude/agents/research-migration.md` exists, dispatch it via the Task/Agent tool
once per module, in parallel, each with: module name, source location, output path.

#### Mode B (inline fallback)

If not installed, dispatch a general-purpose read-only subagent per module with the
`research-migration` prompt embedded (same 7-section template, same `file:line`
citation rule -- see `agents/research-migration.md` for the exact template if
present, otherwise use the shape below):

```
Produce a source-cited feature inventory for the <module> module, being ported from
<source location> to <target>. Find every entry point (routes/crons/webhooks/CLI),
cite file:line for each, note data touched, external calls, a parity contract
(golden-fixture input->output per behavior, flag money/irreversible actions as
STOP-gates), a test plan, and open questions. No line cap; every claim needs a
citation. Write to <output path> using the section order: Scope (with a MIGRATE
table and an Out-of-scope list with real owners), Pipeline, Data, External calls,
Parity contract, Test plan, Open questions.
```

### Step 4: Build/refresh the top-level checklist

Read every module spec's Scope + Parity contract sections. Write/update
`docs/PORT-CHECKLIST.md`:

```markdown
# Port checklist: <source> -> <target>

Generated <date>. Source of truth for what's ported; re-run `/kit:port-map` to
refresh.

| Module | Behavior | Status | Spec | STOP-gate |
|---|---|---|---|---|
| payout | commit (month/batch) | NOT STARTED | specs/payout.md#5 | yes |
```

Status starts `NOT STARTED` for every row on first generation. On a refresh run,
preserve existing status values for rows unchanged since the last spec; flag any row
whose behavior text changed (source drifted) as `NEEDS REVIEW` rather than silently
resetting it.

### Step 5: Present for review

Show module count, behavior count, STOP-gate count, and every module's open
questions rolled up. Ask: "Approve, or adjust scope?"

### Step 6: Refresh mode

Re-running against a module that already has a spec: dispatch `research-migration` again,
diff the new Scope/Parity-contract output against the existing file. Match = leave
status untouched. Drift = flag it in the checklist (`NEEDS REVIEW`) and let the
operator decide whether the port itself needs updating -- never silently overwrite a
spec someone signed off on.
