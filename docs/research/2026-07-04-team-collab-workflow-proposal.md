---
title: "dwarves-kit team collaboration workflow: proposal for Han's review (v3, diagrammed)"
date: 2026-07-04
purpose: >
  Elaborates the parked "attestation, not sync" design (frens-repos absorption doc section 5,
  dwarves-kit Parking lot) into a reviewable workflow proposal. v2 same day at Han's request:
  full detail with ASCII diagrams showing the collaboration scope and responsibility of each
  role (maintainer, orchestrator/conductor, contributor dev, casual contributor), git as the
  only shared medium. v3 (2026-07-05) folds in the Omnigent cross-check deltas
  (research/2026-07-05-omnigent-team-harness-absorption.md D1-D4): policy-as-code stacking,
  the billing + cost axis (per Han: billing mode stays optional per member), the TEAM.md
  content spec, and fail-closed evidence. PROPOSAL ONLY; the named-second-user tripwire
  still gates any build.
status: v3 proposal, awaiting Han's review
---

# dwarves-kit team collaboration workflow (proposal v3)

**The one principle everything hangs on:** git stays the only shared medium. Evidence
rides the branch; CI re-checks what hooks cannot guarantee; local ledgers never sync;
identity comes from git itself. ADR-0022's L5 fence (no cross-machine coordination
infrastructure) is amended at exactly that line, not crossed. No lock servers, no synced
state, no dashboards-as-service, no real-time presence, at any phase.

## 1. Topology: git as the hub

```
                            ┌───────────────────────────────────────────┐
                            │                GIT (the hub)              │
                            │                                           │
                            │  specs/ ADRs/ _meta/BACKLOG.md (+Owner)   │
                            │  docs/verification/proof-of-done.md       │
                            │  docs/verification/rejected-findings.md   │  <- team review memory
                            │  docs/runs/<rid>.md   (SHIP ATTESTATIONS) │  <- generated, never hand-edited
                            │  branches: spec stubs = reservations      │
                            └───────┬───────────────▲───────────┬───────┘
                          pull      │        push   │           │ PR events
                                    ▼               │           ▼
        ┌───────────────────────┐  ┌────────────────┴──────┐  ┌──────────────────────────┐
        │  MAINTAINER (Han)     │  │  CONTRIBUTOR (dev)    │  │  CI (kit consumer action) │
        │  branch protection    │  │  kit installed         │  │  re-checks IN-BRANCH      │
        │  gate approvals       │  │  local ledger = SOURCE │  │  evidence only:           │
        │  board triage         │  │  ~/.local/state (never │  │  proof diff-key, run      │
        │  TEAM.md / culture    │  │  synced, actor= rows)  │  │  table parses, spec       │
        │  retire/gate policy   │  │  hooks = UX guardrail  │  │  exists for full lanes    │
        └───────────────────────┘  └───────────────────────┘  └──────────────────────────┘

        The ledger stays on the builder's machine as the SOURCE.
        /kit:ship RENDERS it into docs/runs/<rid>.md on the branch = the attestation.
        CI never needs anyone's machine; it reads only what the branch carries.
```

## 2. Roles, scope, and responsibility

Four roles. "Orchestrator" is a HAT a contributor wears when conducting a mega, not a
separate person; any kit-installed dev can conduct.

```
┌───────────────────┬──────────────────────────────────┬─────────────────────────────────┐
│ ROLE              │ OWNS (scope)                     │ ACCOUNTABLE FOR                 │
├───────────────────┼──────────────────────────────────┼─────────────────────────────────┤
│ MAINTAINER (Han)  │ branch protection + merge rights │ gate decisions inside the       │
│                   │ on protected branches; gate      │ review window; deny feedback in │
│                   │ approvals; TEAM.md; board        │ the triage-first frame; retire/ │
│                   │ triage; per-actor telemetry      │ policy calls; culture rule      │
│                   │ policy; CI flip to blocking      │ (process health, never a        │
│                   │                                  │ person leaderboard)             │
├───────────────────┼──────────────────────────────────┼─────────────────────────────────┤
│ ORCHESTRATOR      │ ONE mega scaffold + its          │ advisor P5/P6 pre-launch pass;  │
│ (conductor hat,   │ worktrees/branches; wave         │ checkpoint discipline; the      │
│ any kit dev)      │ dispatch; convergence gate;      │ convergence gate actually       │
│                   │ RUN_REPORT; holding gate PRs     │ running (/kit:verify +          │
│                   │                                  │ review-team + advisor);         │
│                   │                                  │ recovery of dead workers        │
├───────────────────┼──────────────────────────────────┼─────────────────────────────────┤
│ CONTRIBUTOR (dev, │ rows they claimed (Owner col);   │ lane gates run locally; proof   │
│ kit installed)    │ their branches + spec stubs;     │ of done produced BEFORE push;   │
│                   │ their local ledger; their        │ attestation rides the branch;   │
│                   │ attestations (actor=them)        │ deny handled triage-first,      │
│                   │                                  │ never resubmit-unchanged        │
├───────────────────┼──────────────────────────────────┼─────────────────────────────────┤
│ CASUAL            │ their PR branch only             │ passing the same CI checks; OR  │
│ CONTRIBUTOR       │                                  │ asking the maintainer to        │
│ (no kit)          │                                  │ attest-for them (auditable      │
│                   │                                  │ vouch: actor=han                │
│                   │                                  │ attested-for=<author>)          │
└───────────────────┴──────────────────────────────────┴─────────────────────────────────┘

Consulted/informed, by artifact (the RACI tail):
- rejected-findings.md: appended by whoever's review rejected the finding; read by ALL
  review lenses on every future review (team memory for free, it is in git).
- boards: contributor flips own rows; maintainer triages; anyone reads (board-all).
- observatory: reads docs/runs/* from git; anyone can run it; per-actor slices are a
  maintainer-policy question (open question 3).
```

## 3. Flow A: single-item contribution (the everyday path)

```
 CONTRIBUTOR                      GIT                              MAINTAINER              CI
 ───────────                      ───                              ──────────              ──
 1 claim row ───────────────────► BACKLOG row: claimed, Owner=me
   (or pick from board-all next)
 2 push spec stub ──────────────► branch feat/x + docs/specs/stub
                                  = the SPEC-NNN RESERVATION
                                  (spec-next scans remote branches)
 3 build in the lane
   hooks = UX guardrails
   gate rows actor=me (LOCAL)
 4 /kit:verify + proof-of-done
 5 /kit:ship ───────────────────► branch + docs/runs/<rid>.md
                                  (rendered attestation)
 6 open PR ─────────────────────► PR ─────────────────────────────────────────────────► 7 re-check:
                                                                                          proof diff-key ok?
                                                                                          run table parses?
                                                                                          spec exists (full lane)?
                                                                                          ── report-only in P1,
                                                                                          BLOCKING via branch
                                                                                          protection in P2
                                  PR + green checks ─────────────► 8 review window:
                                                                     explain digest first,
                                                                     kit lenses on the diff,
                                                                     rejected-findings memory
                                                                     consulted automatically
                                                     ┌─── APPROVE ─► merge (squash);
                                                     │               attestation rides history
                                                     └─── DENY ────► triage-first feedback
 9 on DENY: responding-to-review                                     (findings w/ file:line)
   verdicts EVERY finding
   (Confirmed / Partly /
   Not-a-bug / Intended),
   fixes, SAME branch+title ────► updated PR ────────────────────► re-review diffs
                                                                   against the denial
```

Responsibility cut: steps 1-6 and 9 are the contributor's; 7 is CI's alone (no human
re-derives evidence); 8 is the maintainer's alone. Nothing in 1-9 requires anyone to
read another machine's ledger.

## 4. Flow B: mega-goal in a team (orchestrator hat)

```
 ORCHESTRATOR (any kit dev)          WORKERS (in-harness subagents)      MAINTAINER (Han)
 ──────────────────────────          ──────────────────────────────      ────────────────
 scaffold mega (plan-for-mega-goal)
 advisor P5 critique + P6
 over-suggest PRE-LAUNCH; apply
 fixes; NOTES the ride-laters
 launch /goal (pointer <4000ch)
    │
    ├── dispatch wave ─────────────► build sub-goals in worktrees
    │                                lane gates, actor= rows local,
    │                                commit at phase boundaries
    ◄── terse reports; verify
        ROADMAP boxes on disk
    auto-merge `auto` sub-goals
    (CI green; bottom-up)
    │
    CONVERGENCE GATE on the
    assembled stack:
      /kit:verify (right arm)
      /kit:review-team (diff-keyed
        lenses + advisor P5)
      advisor P6 over-suggest
      recheck-verifier re-audits
      all rows recorded, actor=
    │
    hold `gate` PRs + final PR ───────────────────────────────────────► batched review window
    write RUN_REPORT.md (rides git)                                      (Flow A steps 8-9 apply
                                                                          per held PR)
```

Scope rule: ONE orchestrator per mega; one merge queue per repo (bookkeeping serializes
even when code is disjoint); cross-mega file overlap is handled the way this repo already
does it, a launch guard in the scaffold, not a lock. The maintainer never has to know a
mega is running until its gate PRs reach the window; the RUN_REPORT and attestations in
git are the audit trail.

## 5. Who may do what, by phase (rollout)

```
              P0 (now)          P1 (named 2nd user)       P2 (pilot proven)       P3 (>2 devs)
              ────────          ───────────────────       ─────────────────       ────────────
 identity     actor= on new     actor= everywhere;        unchanged               unchanged
              emit grammars     Owner col + claim verb
 attestation  n/a               /kit:ship emits           unchanged               unchanged
                                docs/runs/<rid>.md
 enforcement  local hooks       CI action REPORT-ONLY     CI BLOCKING via         + CODEOWNERS
              only              on the pilot repo         branch protection         review routing
 reservation  machine-local     push-early spec stubs     unchanged               unchanged
 onboarding   n/a               TEAM.md via /kit:adopt    unchanged               + plannotator
                                                                                    Workspaces decision
 review       Han only          Han only (gates);         Han + attest-for        domain lenses route
              												peer review allowed      codified               by CODEOWNERS
```

Build list unchanged from v1 (six Tier-1 items, each one sub-goal; CI action is the only
new GATE and ships report-only first). Advisor's actor= adoption already front-ran item 1
on the three green-field grammars.

## 6. Failure modes this design accepts vs kills

| Scenario | Outcome under this design |
|---|---|
| Teammate ships a branch someone else built | CI checks the BRANCH's evidence; no false block (the old ledger-on-wrong-machine failure is gone) |
| Kit-less bare `git push` | branch protection + CI catch it (today even solo it bypasses everything) |
| Two devs mint the same SPEC number | impossible once reservation = pushed stub branch |
| Hand-edited attestation | run table is generated + CI-parsed; a doctored table that still parses is a deliberate forgery, caught by review not tooling (accepted residual risk, same trust level as code itself) |
| Ledger lost (machine wipe) | attestations + proofs survive in git; local ledger is rebuildable history, not the record of record |
| Gate pile-up on Han | batched review windows + explain digests (wired 2026-07-04); plannotator surface if ID-262 adopts |
| Policy hot-path outage (the Omnigent failure class: a fail-closed evaluate server on every tool call; upstream documents a 24h re-POST spin-loop pathology) | cannot happen here: hooks are advisory and local, the only blocking surfaces are branch protection + CI, both always-on infra someone else operates |

## 7. The board is an adapter seam (GitHub / Notion later)

Asked 2026-07-04: can an online tool (GitHub, Notion) become the kanban datasource later?
Yes, cleanly, because nothing else in this design touches the board. The attestation,
reservation, CI, and gate machinery all live in branches and evidence files; the board
only feeds CLAIM (who owns what) and TRIAGE (what is queued). So the board is a swappable
backend behind a stable contract:

```
   the CONTRACT (stays fixed)                the BACKENDS (pick per repo)
   ─────────────────────────                 ───────────────────────────
   kanban grammar:                           markdown _meta/BACKLOG.md   (today)
   states queued -> claimed -> speccing      GitHub Issues/Projects      (code repos;
     -> validated -> executing -> shipped      via gh CLI; assignee = Owner for free)
     (+ parked/dropped)                      Notion database             (Dwarves ops
   ID prefix per repo, Owner column,           repos; via the ntn CLI, the mandated
   one row per item                            Notion path)
```

Rules that make it safe: ONE source of truth per repo (never two-way sync; dual-write
drift is the known trap); the `board` wrapper keeps the same read/render interface so
`board-all` still aggregates mixed backends; `_meta/boards.txt` rows gain a backend
column. Side benefit: an external board removes status-flip bookkeeping from PRs
entirely (the "PR that is 100% bookkeeping" anti-pattern dies naturally). Timing: P3,
or P2 for a pilot repo already living in GitHub Issues; the markdown board remains the
default and the fallback.

## 8. Policy as code (v3, Omnigent D1)

The one artifact v2 lacked: a DECLARATIVE statement of what is allowed, readable in git.
Omnigent proves the demand (its flagship feature) but evaluates policies on a server in
the hot path of every tool call; we take the stacking idea, not the server.

```
   level (strictest wins; lower levels may only TIGHTEN, never loosen)
   ──────────────────────────────────────────────────────────────────
   1 repo policy      maintainer-owned, in git (TEAM.md section or      the admin plane
                      kit.toml [policy] table; shape decided at build)
   2 goal/mega scope  the scaffold's scope fence + Not: list            the orchestrator plane
   3 session          the operator's own local hooks                    the personal plane
```

Contents of the repo level: path fences ("contractors do not touch `infra/`",
"generated dirs are read-only"), guarded verbs (force-push, prod deploy, mass send,
dependency adds), ASK-class actions (anything irreversible). Enforcement split stays
the v2 doctrine: kit hooks READ the policy file as UX guardrails; CI re-checks the
mechanically checkable subset (diff touches a fenced path = fail); branch protection
remains the only hard block. Explicit non-goals: no evaluation server, no fail-closed
hot path, no per-tool-call round trip.

## 9. Billing + cost axis (v3, Omnigent D2; Han's stance 2026-07-05)

Billing mode is **per member and optional**, declared in TEAM.md, all three first-class
(Han: members keep their own key or their own subscription; company key is an offer,
never a mandate):

```
   mode (per member)         cost visibility to org        enforceable lever
   ─────────────────         ──────────────────────        ─────────────────
   own subscription          none (flat, per-token          model-tier policy only
   (Max/Pro OAuth)           spend invisible by design)
   own API key (BYO)         none (member sees own bill)    model-tier policy only
   company-issued key        per-key usage + spend limit    Console workspace limits
   (optional offer)          free in Anthropic Console      (zero infra built by us)
```

- **The universal lever, works across all three modes:** model-tier policy. SPEC-116
  routing elevated from efficiency default to team policy: which lanes may burn
  opus/xhigh, expressed in the repo policy (section 8), enforced client-side
  (billing-agnostic), spot-checkable from attestation metadata in review.
- **The shape when a budget DOES exist** (company key, or a member self-imposing one):
  Omnigent's downgrade-gate, not hard stop, deny only while on an expensive model,
  allow again after `/model` down; ASK thresholds before the cap.
- **Governance lines regardless of mode:** a personal subscription OAuth token never
  fans out to shared or cloud machines (Omnigent documents that pattern as supported;
  here it is a named anti-pattern, ToS + ban risk); issued keys travel only as
  1Password `op://` references, never raw values in chat, email, or repo.
- **The decoupling that matters:** cost visibility is mode-dependent and optional;
  PROCESS visibility is not. Attestations, `actor=` rows, Owner columns, and
  rejected-findings record every member's work in git identically, whatever they bill.

## 10. TEAM.md content spec (v3, Omnigent D3)

v2 named TEAM.md once ("via /kit:adopt", P1) without contents. The spec, one file,
maintainer-owned, read on day one:

1. **Identity**: git email = `actor`; the mapping table if anyone commits under
   multiple emails.
2. **Roles**: who is maintainer; who may wear the orchestrator hat (default: any
   kit-installed dev); named casual contributors and their attest-for arrangement.
3. **Policy pointer**: where the repo policy lives (section 8) and the one-line
   summary of its fences.
4. **Billing declaration**: each member's mode from section 9 (mode only; never key
   material, `op://` refs where relevant).
5. **Machine bootstrap checklist**: install kit -> `/kit:adopt` -> install-verify
   (hooks fire on a fixture) -> first claimed row. Verifiable, not aspirational: the
   PHILOSOPHY assumption "contractor has the kit installed" becomes a checked box.
6. **Review-window expectations**: cadence, batching, the triage-first deny contract
   (Flow A step 9).

## 11. Open questions for Han (answers = the review)

1. **Pilot repo**: dwarves-kit itself (dogfood) or a real work repo? Recommendation:
   dwarves-kit, one engineer.
2. **Attest-for**: acceptable, or must every contributor install the kit? Recommendation:
   allow; the vouch is explicit and auditable.
3. **Per-actor telemetry**: acceptable under the process-health framing, or aggregate-only?
4. **CI runtime**: GitHub Actions only for P1? Recommendation: yes.
5. **absorb-ideas -> kit**: generalize the absorption pipeline into the kit at P3 only?
   Recommendation: yes, P3.
6. **Board backend per repo class** (section 7): markdown stays default; GitHub Issues
   for code repos at P2/P3, Notion via ntn for Dwarves ops repos? Recommendation: decide
   per pilot repo, one source of truth each, never two-way sync.

Answered 2026-07-05 (folded into v3 / the team-mode mega scaffold, no longer open):

7. ~~Billing mode for members~~: optional per member, own subscription / own key /
   company-issued key all first-class, declared in TEAM.md; encoded as section 9.
   Cost visibility follows the mode; process visibility (attestations, actor=, boards)
   is mandatory and billing-agnostic.
8. ~~Q1 pilot repo~~: dwarves-kit + 1 named Dwarves engineer (Han, at the team-mode
   mega decompose checkpoint; `_meta/megagoals/team-mode/DECISIONS.md` item 1).
9. ~~Q2 attest-for~~: allowed, auditable vouch grammar (DECISIONS item 3).
10. ~~Q3 per-actor telemetry~~: ON by default; the culture guard ("process health,
    never a person leaderboard") moves into TEAM.md prose, not the tooling
    (DECISIONS item 2). Q4 (CI runtime) resolved as GitHub Actions report-only by
    the mega's assumption 5. Q5/Q6 remain genuinely open (P3 decisions).
