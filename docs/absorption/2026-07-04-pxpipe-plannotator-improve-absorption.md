---
title: "Frens-repos absorption: plannotator, shadcn/improve, pxpipe + dwarves-kit team mode"
date: 2026-07-04
purpose: >
  Deep-read analysis of three friend-suggested repos (teamchong/pxpipe,
  backnotprop/plannotator, shadcn/improve) against our SDD/telemetry machinery, plus a
  single-user-coupling audit of dwarves-kit answering "can the kit open for team usage".
  Produces absorptions A1-A5 (rows ID-262..264, mega gate-review-absorptions), two parked
  candidates (pxpipe experiment ID-265, compounding lens ID-266), and the team-mode
  "attestation, not sync" design (dwarves-kit board ID-210, parked until a named teammate).
source_repos: [ops-toolkit, dwarves-kit]
refresh_cadence: none
next_review: null
status: active
---

# Frens-repos absorption: plannotator, improve, pxpipe (+ kit team mode)

Method: four parallel deep-read agents on 2026-07-04, three cloning + source-reading the
repos, one auditing dwarves-kit for single-operator assumptions. This doc is the distilled
record + the designs; the mega `_meta/megagoals/gate-review-absorptions/` executes them.

## 1. Verdicts

| Target | One-line | Verdict |
|---|---|---|
| plannotator (6.7k star, 6mo, daily commits, bus-factor 1) | browser annotation surface for agent plans/diffs, hooks ExitPlanMode, structured deny feedback | richest absorption; trial the gate surface (A1), steal the compound loop (A2) + deny contract (A2b) |
| shadcn/improve (6.8k star, dormant after a 5-day burst) | markdown-only advisor skill: audit, vet, plan-for-cheap-executor | parallel evolution of the kit; steal rejected-findings memory (A3) + stale-ADR inversion (A4), skip the pipeline |
| pxpipe (625 star, 6wk, single author) | proxy rendering bulky context to PNG glyph pages (pixel-price arbitrage, measured 59-70%) | do NOT adopt the tool now (P1 parked, two hard flags); steal the measurement methodology (A5) |
| dwarves-kit team mode | ADR-0022 deliberately fenced cross-machine out | viable via "attestation, not sync"; parked until a named second user (kit ID-210) |

## 2. plannotator (backnotprop/plannotator)

**What it is.** Local Bun binary + embedded React SPA. For Claude Code it is a
`PermissionRequest` hook on `ExitPlanMode`: the hook process hosts a web server on a random
localhost port, blocks (timeout 4 days) until the browser POSTs approve/deny, and its stdout
IS the hook decision. Deny feedback serializes as structured markdown (numbered, line-anchored,
quoted selections) wrapped in a deliberately harsh template ("YOUR PLAN WAS NOT APPROVED...
do not resubmit unchanged; do NOT change the plan title", tuned because agents ignore soft
phrasing). Plan title keys a version history so a resubmission renders a word-level diff
against the denied version. State under `~/.plannotator/`.

**Load-bearing mechanisms.**
- `plannotator annotate <file> --gate --json`: turns ANY markdown file into an approve/deny
  gate emitting `{"decision":"approved|dismissed|annotated","feedback":...}`. Scriptable; no
  plan mode required. This is the kit-relevant entry point.
- Compound loop: deny archive -> analysis skill -> corrective-instruction file ->
  auto-injected `additionalContext` on every future `EnterPlanMode`. Denial history becomes
  standing planning instructions (human in the middle, 50KB cap).
- External annotations API (+SSE): other agents/tools POST findings into the live review
  session; UI generates the how-to-post contract for an arbitrary agent. Reviewer agents and
  the human converge on one surface.
- Review-feedback suffix: agent must first TRIAGE each finding (Confirmed / Partly / Not a
  bug / Intended, with file:line evidence) before changing any code.
- Team story today: share-URL (deflate+base64url in the fragment; big plans via client-side
  AES-GCM paste service) + import-merge + pseudonymous "tater" identities. Live collab =
  future paid Workspaces (the commercial seam).

**Caveats.** Bus-factor 1 at high velocity; on Claude Code approve-with-notes does NOT reach
the agent (only deny carries feedback); install path is curl|bash (checksummed + SLSA
attestable, so download-verify-install instead); code-review decisions are NOT persisted
(only plan decisions archive), so the gate ledger stays ours.

**Absorptions.**
- **A1 (mega SG-03): gate-surface trial.** Thin wrapper: kit/mega HUMAN gates (`gate`
  sub-goal files, held specs, ROADMAPs) open via `annotate --gate --json`; decision JSON is
  recorded to gate-ledger (finally: structured feedback + verdict per human gate, today the
  ledger records ran/skip but never what the human said). Reader ships with the emitter
  (kit_gates parses the line; RUN_REPORT gate matrix shows it). Trial checkpoint: phone
  access over Tailscale (remote mode binds a fixed port) would unlock review windows from
  the SPEC-002 mobile path. Keep the integration ONE wrapper deep (swappable; commercial
  trajectory + bus factor). Verdict adopt/park written into the experiment README.
- **A2 (ID-266, parked): gate-feedback compounding lens.** Our version of the compound loop:
  a ledger-observatory lens mining recurring deny/override reasons + review feedback ->
  STAGES prompt amendments via cc-backlog (propose-never-autofile; plannotator auto-injects,
  we do not). Parked until harness-observatory (ID-260) closes; it reads that mega's tables.
- **A2b (mega SG-05): gate-deny feedback contract in OPERATE.md.** When a human gate denies,
  the feedback handed to the worker follows the triage-first contract: verdict every finding
  with evidence before changing anything; never resubmit unchanged; keep branch/title stable
  so the re-review diffs.

## 3. shadcn/improve

**What it is.** One skill, zero code (~875 lines of markdown): recon -> parallel category
audit (9 categories, effort knob) -> vet pass (advisor re-reads every cited location;
subagents over-report) -> leverage-ordered findings table -> self-contained plans written
for "the weakest plausible executor" (per-step `Verify: <command> -> <expected>`, STOP
conditions, SHA-stamped drift check). 22 commits in 5 days, then silence; 10 open issues
incl. its own security gaps (Hard Rules not propagated to the execute subagent).

**Absorptions.**
- **A3 (mega SG-02 + SG-04): rejected-findings memory + review-yield lens.** improve
  persists "considered and rejected" findings so false positives never resurface. The kit's
  review lenses have no memory, and our telemetry measures catch-rate but not FP cost (the
  denominator of whether a lens deserves its attention budget). Design: reviewers append
  `date | lens | finding-key | verdict | reason` to per-repo
  `docs/verification/rejected-findings.md`, check it before re-flagging (a previously
  rejected finding is surfaced as "previously rejected <date>: <reason>", never silently
  re-raised as new); the review gate-ledger line gains `findings=N rejected=M` KVs (grammar
  parseable by the merged kit_gates reader); ledger-observatory gets a `review-yield` query
  (FP-rate per lens). Numbers to the lens, content stays in the repo file.
- **A4 (mega SG-01): stale-ADR inversion.** Intent docs suppress by-design findings, BUT
  code-vs-ADR drift is itself a finding; a doc can never blanket-mute observed behavior. One
  line into the kit's advisor + review prompts.

**Skips.** The 9-category audit pipeline (duplicates kit per-phase reviewers, structurally
generates work, zero measurement story: an unmeasured parallel review channel); the
quick/deep effort knob (lane classification already routes depth); capability arbitrage
(already practiced: Model: routing in mega). Candidate NOT taken now: `Planned-at:` SHA +
mechanical drift check on sub-goal files (remega re-decomposition covers the staleness
class; revisit if stale-sub-goal defects show up in deviation-rate data).

## 4. pxpipe (teamchong/pxpipe)

**What it is.** Transparent `ANTHROPIC_BASE_URL` proxy rewriting bulky request parts (system
prompt + tool docs, large tool_results, older history) into dense 5x8-glyph PNG pages; image
tokens are priced by pixel area (~w*h/750), so token-dense text packs ~3.1 chars/image-token
vs ~1.9 chars/text-token. Measured 59-70% end-to-end at Fable list prices. Cache-aligned
history collapse (quantized append-only boundary keeps old pages byte-stable for the prompt
cache); verbatim "factsheet" (exact identifiers ride as text beside the image).

**P1: parked, two hard flags.** (1) The failure mode is SILENT CONFABULATION of exact
strings (verbatim hex 13/15 on Fable, 0/15 on Opus; their guard "not built yet"), poison for
SDD work where SHAs/spec numbers matter. (2) We run Max-plan OAuth; a request-mutating proxy
between the claude CLI and the API is exactly the traffic shape our own notes flag as
ban-risk. If ever trialed: API-key session, low-stakes repo, `experiments/` frame; the win
would be rate-limit headroom, not dollars. Revisit when rate-limit pressure actually hurts.

**A5 (mega SG-05): measurement methodology.** Two principles for the observatory design +
one phrase: (a) **counterfactual-in-same-row**: every request logs billed usage AND a free
`count_tokens` counterfactual in ONE JSONL row, so savings claims carry no cross-run
confound; cache credit only when the real request PROVED a warm cache. (b)
**honest-negative**: a mechanism that net-lost reports negative, never filtered. (c) the
roadmap rule worth quoting into OPERATE.md: "hypotheses ship as numbers with an n or they
get cut". Bonus API fact worth remembering: Anthropic downscales images to long-edge <=1568px
and ~1.15MP BEFORE the vision encoder but bills pre-resample pixels; oversized pages pay for
pixels the model never sees.

## 5. dwarves-kit team mode: "attestation, not sync"

Audit findings (full state table in the audit run, 2026-07-04): the kit's team gap is
structural, and DOCUMENTED (ADR-0022 fences cross-machine coordination out as L5; PHILOSOPHY
draws the same line). Three walls:

1. **Gate ledger on the wrong side of the git boundary.** Everything ship-gate enforces
   lives in `~/.local/state/dwarves-kit/logs/runs/<rid>.log` on the builder's machine, rid =
   branch slug, NO actor field. A teammate shipping a branch someone else built gets falsely
   blocked (the builder's gate records are not on their machine) -> rational move is an
   anonymous override. The ONE portable gate is proof-of-done: its evidence is diff-keyed
   and rides the branch. That is the template.
2. **Enforcement is client-side and optional.** All gates are Claude Code PreToolUse hooks,
   per user, per install; a bare `git push` from a plain terminal bypasses everything, even
   solo, today. A kit-less teammate bypasses silently. The kit ships zero consumer CI.
3. **No identity/allocation primitives.** Nothing records WHO (no actor on gate rows or
   overrides, no Owner column on boards); spec-number reservation is a machine-local mutex
   (two humans can mint the same SPEC-NNN same-day); goal-registry claims are structurally
   single-machine (by ADR, "the location IS the boundary").

**Design (Tier 1, the principled minimum):**

```
today                                     team mode (attestation, not sync)
-----                                     ----------------------------------
spec / ADR / board / proof-of-done   -->  already in git (the team surface)
gate records (~/.local/state, no who)-->  stay local as SOURCE; ship emits the
                                          generated run table docs/runs/<rid>.md
                                          onto the BRANCH (proof-of-done pattern
                                          extended to lane gates)
enforcement = local CC hooks         -->  kit ships a consumer CI action that
                                          re-checks the IN-BRANCH evidence
                                          (proof-ledger check is already
                                          diff-keyed; branch protection does the
                                          blocking, hooks become UX)
identity: nobody recorded            -->  actor= on gate rows + Owner column on
                                          boards; git supplies the rest (commit,
                                          PR, blame)
spec numbers: machine-local mutex    -->  push-early: the pushed spec-stub branch
                                          IS the reservation (the scan already
                                          reads remote branches; add a fetch)
```

No synced ledgers, no lock servers: git stays the only shared medium and its merge semantics
are the conflict resolution, so this does NOT relax the real ADR-0022 boundary (frame the ADR
amendment exactly there). Compounding win: run tables in-repo mean ledger-observatory reads
the whole team's gate activity from git alone (sweep-over-instrument), multi-user telemetry
for free. Tier 2 (live review surfaces, PR-comment ledgers, team debt paydown) waits for a
real team.

**Status:** parked as dwarves-kit board ID-210; unpark trigger = a NAMED second user on a
real repo (a Dwarves engineer). The two identity hardcodes found by the audit
(`lib/mutation-smoke.sh` blesses "Han" by name; `agents/meta-agent.md` hardcodes a dotfiles
absolute path) are fixed independently of team mode (same-day PR).

## 6. Execution map

| Item | Where |
|---|---|
| A1 plannotator gate trial | mega SG-03, row ID-262 |
| A3 rejected-findings + review-yield | mega SG-02 + SG-04, row ID-263 |
| A2b + A4 + A5 one-liners | mega SG-01 + SG-05, row ID-264 |
| P1 pxpipe experiment | row ID-265, parked |
| A2 compounding lens | row ID-266, parked (post ID-260) |
| Mega umbrella | row ID-267, `_meta/megagoals/gate-review-absorptions/` |
| Team mode | dwarves-kit board ID-210, parked |

Launch guard: the mega HOLDS until both sibling megas (ID-260 harness-observatory, ID-261
kit-absorptions) close; its kit stack overlaps kit-absorptions' command edits and its lens
work overlaps harness-observatory's ledger-observatory changes.
