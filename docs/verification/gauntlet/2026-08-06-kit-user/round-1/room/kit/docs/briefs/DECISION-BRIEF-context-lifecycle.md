# Decision Brief: context lifecycle subsystem (audit + refresh; onboard deferred to v2)

Status: THINK-PASSED, verdict BUILD (feeds /kit:spec). Owner: Han. Drafted 2026-07-10; /kit:think run 2026-07-10.

## Problem

Every repo an agent works in needs a context stack: a CLAUDE.md map, git-tracked repo
memory (incl. a cloud/credential access map), a code-structure index (codebase-memory), a
recall index (prose-rag corpus membership), board registration, and optionally the kit
operate-contract. Today each layer has its own bootstrap (`/init`, memory-bootstrap,
`index_repository`, `/kit:adopt`, boards.txt row) and NOTHING owns the set: onboarding a
new repo is a by-hand checklist nobody runs completely, and no process maintains the
artifacts afterward, so they rot silently.

Evidence (all 2026-07-10, ops-toolkit audit + deep transcript sweep):

- ICY sessions repeatedly "forgot" AWS/GCP/GKE access existed: the access map was never
  written anywhere push-loaded, and each fresh session assumed no credentials. Clarifying
  questions about the agent's own prior work ranked 4th of the 4 intervention causes
  in the 24-session shape analysis (ops-toolkit
  research/2026-07-10-convention-as-spec-audit.md, Addendum).
- prose-rag's UserPromptSubmit hook was silently dead for 26 days (purged embedding-model
  cache) and its index 26 days stale; no audit surface existed to notice either.
- ops-toolkit's hand-maintained indices lagged reality by ~30% (INVENTORY.md missing 23
  live tools), skewed toward the newest work.
- Memory notes can reference files/flags that no longer exist; the global memory rules
  tell the agent to re-verify, but nothing detects rot proactively.

Onboard-only tooling would recreate the proof-ceremony failure in memory form: artifacts
created once, never refreshed, trusted anyway. The lifecycle (create + audit + refresh)
is the unit, not the bootstrap.

## Why the kit (and not an ops-toolkit skill)

Per the harness-machinery rule (ops-toolkit memory `harness-machinery-in-the-kit`):
generic engine goes in the kit, personal data stays consumer config read via
CONSUMER_ROOT (boards.txt precedent). Which layers exist and how to check their
freshness is generic across every adopted repo; which corpora, what the access map
contains, and which boards register are Han-taste consumer config.

## Proposed shape (for /kit:spec to harden)

A `context` subsystem (`lib/context/`, standalone `<subsystem> <verb>` per the
kit-modularity shape), three verbs:

- `context onboard [path]` (v2, documented for continuity; OUT of spec scope this pass): idempotent; detects each layer (CLAUDE.md, .claude/memory/
  + access-map note, code index, recall-corpus membership, board row, kit adopt),
  creates what is missing from consumer templates, prints a scorecard
  (`memory OK / access-map TODO(fill creds) / code-index OK 41k nodes / kit SKIPPED-by-choice`).
  Kit adopt and board registration are prompted options, never auto (gates only where a
  gate will fire).
- `context audit [path]`: read-only staleness report: memory notes citing dead
  paths/commands, access-map verify commands failing, index age vs repo activity
  (last index run vs last N commits), recall-index age. (CLAUDE.md drift detection is
  cut from v1, see Q4: fuzzy inference, high false-positive risk.)
  Output shaped like `mega status` drift flags.
- `context refresh [path]`: runs the mechanical refreshes the audit flagged
  (incremental code re-index, recall re-index, regenerate derived indices); never edits
  memory content itself (rot in prose needs a human or a gated fix, not a refresher).

Cadence wiring is a spec decision: candidates are repo-sweep integration (audit as a
sweep lens) vs a SessionStart nudge on Nth-session-since-audit. Prefer piggybacking the
existing sweep over a new daemon (minimum-infra).

## Think verdict (2026-07-10): BUILD

Core thesis: context layers rot silently and fresh sessions pay for it; a periodic
read-only audit plus mechanical refresh makes the stack self-healing without a human
ritual.

Strongest argument for: three real incidents in one month (prose-rag hook dead 26 days,
ICY credential amnesia, indices 30% stale) each cost real session time and none had a
detection surface.

Strongest argument against: an audit that cries wolf dies the proof-ceremony death,
green ritual, zero trust; alert fatigue is the named kill risk, so severity tiers + a
suppress-list are v1 requirements, not polish.

Forcing-question record (operator answers, 2026-07-10):

- Q1 pain: all three (amnesia stalls, silent rot, onboarding tax). V1 ordering comes
  from Q3: rot + amnesia first; onboarding tax deferred.
- Q2 10x: "never think about it" + agent self-serve, sessions detect and repair their
  own context, the human only hears about human decisions.
- Q3 MVP: audit + refresh, no onboard.
- Q4 cuts (operator AFK; recommended set adopted, VETO WELCOME): onboard verb (v2),
  CLAUDE.md drift detection (fuzzy, high-FP), multi-harness (omp/pi) support,
  cross-machine reconciliation.
- Q5 first break at scale: alert fatigue (mitigations in-spec: severity tiers,
  suppress-list, audit never in a hot path). Secondary: refresh cost. Incremental
  indexing (ops-toolkit ID-306, status QUEUED as of 2026-07-10, not started) gates the
  recall-index leg of refresh: v1 refresh MAY ship with the documented interim cost
  (~35 min full-corpus CPU rebuild per pass) but must not schedule that on a cadence;
  cadence-driven reindex activates only after ID-306 lands. (Operator default, veto
  welcome.)
- Q6 exit criteria (operator AFK; scorecard adopted, VETO WELCOME): 30-day scorecard,
  ship verdict needs 2 of 3 green: (a) >=2 genuine rot catches with <=1 false positive
  per week; (b) access/prior-work amnesia turns -> 0 over the next 20 ICY/mochi
  sessions (transcript-measurable); (c) at day 30, no incident of the classes named in Problem
  (dead hook, stale index, failing access verify) has persisted past one 7-day audit
  cycle without being flagged by an audit run.

V1 scope for /kit:spec: `context audit` (read-only: index age vs repo activity,
dead-path memory references, failing access-map verify commands, hook end-to-end
health) + `context refresh` (mechanical fixes the audit flagged; never edits memory
content). Onboard is v2. Severity tiers + suppress-list ship in v1.

## Documentation contract (ship requirement, not optional)

The subsystem ships with the full doc suite or it is not done, per the kit's module
completeness bar (doc + firing point):

- **Design record**: the /kit:spec output plus ADRs for the decisions the spec leaves
  open (cadence wiring, consumer-template mechanism).
- **Architecture note**: how the three verbs share detection logic, where consumer
  config enters (CONSUMER_ROOT), what each layer's freshness signal is.
- **Operator manual**: per-verb usage (onboard a new repo end-to-end, read an audit
  scorecard, what refresh does and does NOT touch), calibrated to a first-time adopter.
- **Module usage doc** wired into the kit's per-module doc audit so drift is caught.

Calibration reference for depth and voice: ops-toolkit's per-tool doc suite
(`tools/tide/` shape: README front door, MANUAL, architecture, decisions). The kit's
own doc layout governs where each lands.

## Not in scope

- Rewriting memory notes automatically (audit flags, human fixes).
- A new always-on daemon or per-prompt hook; the lifecycle is periodic + on-demand.
- Consumer-specific content (access-map fields, corpus lists) beyond template slots.

## Unverified assumptions (spec must check)

- codebase-memory + prose-rag CLIs are invocable headless on every adopted machine
  (verified on the Air only).
- The consumer-template mechanism (CONSUMER_ROOT) has an existing read pattern the new
  subsystem can reuse without new plumbing.
- repo-sweep's lens architecture accepts a new lens without core changes.
