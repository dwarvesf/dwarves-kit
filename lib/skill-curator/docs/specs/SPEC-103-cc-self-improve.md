# Spec: skill-curator (skill half of the Hermes self-improvement loop)
Generated: 2026-06-19
Status: VALIDATED

## Problem

Hermes (Han's personal agent) silently self-improves on two cadences: a memory nudge
(every ~10 turns) that saves persona/preferences, and a skill nudge (every ~10
tool-iterations of real work) that authors/patches skills. Han's Claude Code cockpit
already has the **memory half** shipped (`cc-harvest`: PreCompact/SessionEnd -> Haiku ->
`_meta/learned-ledger.md` queued rows, manual flush). What is missing is the **skill
half** and the **curator**:

- No tool drafts a skill from a session (cc-intel only *suggests* `extract-workflow`).
- No tool consolidates the skill library into umbrellas or archives stale skills
  (the "one genuinely missing piece" in `research/2026-06-19-hermes-self-improvement-loop.md`).
- No unified surfacing of "what the loop staged this week" or its cost.

skill-curator is the skill half. **Suite goal: cc-harvest (memory) + skill-curator
(skill + curator) + unified surfacing = Hermes self-improvement-loop parity.**

## Relationship to the cc-elevation suite (read first)

| Concern | Owner | Status |
|---|---|---|
| Memory capture (transcript -> learnings -> ledger) | **cc-harvest** | shipped |
| Memory cadence parity (per-turn, like Hermes memory nudge) | **cc-harvest enhancement** (optional Stop-counter trigger) | sibling goal in the mega-goal, NOT this spec |
| Sequence/digest proposals | cc-intel | shipped |
| Hook latency / tool-usage metering | cc-observe | shipped |
| **Skill drafting + promote gate** | **skill-curator** (this spec) | new |
| **Skill-library curator** | **skill-curator** (this spec) | new |
| **Suite-wide cost ledger + SessionStart surfacing** | **skill-curator** (this spec) | new |

skill-curator does NOT re-implement memory capture. It registers its own PreCompact/SessionEnd
hook entries (same events as cc-harvest, separate entry) and reads the same transcript.

## Solution

### Approaches considered
1. **Skill-half tool, model-as-pure-function, reusing cc-harvest's trigger events (chosen).**
   Smallest non-duplicative surface; completes Hermes parity at the suite level. Tradeoff: two
   tools to keep coordinated (mitigated by one surfacing hook + a shared ledger schema).
2. **Full rebuild incl. a per-turn memory reviewer.** Rejected: duplicates shipped cc-harvest
   and is the most expensive piece; the per-turn *memory* cadence is better added to cc-harvest.
3. **Fold everything into cc-harvest.** Rejected: cc-harvest is memory-scoped, stable, and
   merged; skill authoring + curation is a different concern and would risk regressing it.

### Chosen approach + why
skill-curator = skill-draft reviewer + promote gate + skill-library curator + suite-wide
cost/surfacing. Trigger = PreCompact/SessionEnd (per-session), which maps faithfully to Hermes's
skill nudge (per substantial-work, not per literal turn). Autonomy = **propose-and-stage**.

**The gate is enforced structurally, not by prompt.** The `claude -p` reviewer and curator run
as **pure functions with no filesystem tools** (`--allowedTools ""`): transcript/skill-list in via
stdin, JSON draft/plan out via stdout. The **trusted bash wrapper** performs every write, to fixed
paths only (`skill-proposals/`, `ledger.jsonl`, `skills/_archive/`). So even a prompt-injected
transcript cannot make the model write a skill into `~/.claude/skills/`: the model has no Write at
all. This is the deliberate divergence from Hermes `guard_agent_created:false`, hardened.

### Extensibility & boundaries
- **Load-bearing dimension = skill-library size.** The curator's clustering cost grows with the
  number of agent-created skills; it reads SKILL.md frontmatter + first-paragraph only, not bodies.
- **Units (independently testable):** (1) transcript->session-summary parser, (2) reviewer
  pure-function (prompt + claude wrapper, no tools), (3) staging writer (trusted bash), (4) promote
  gate (`/skill-review`), (5) curator (pure-function plan + trusted git-mv executor), (6) cost
  ledger + SessionStart surfacing.

### Architecture
```
 PreCompact / SessionEnd  ──▶  skill-curator skill-review hook (async)
   (own hook entry, same events as cc-harvest)  │ setsid/nohup bash lib/reviewer-spawn.sh <payload> & ; hook returns now
                                                ▼
   reviewer-run.sh (TRUSTED bash):
     transcript last-K turns ──stdin──▶ CLAUDE_REVIEWING=1 claude -p --bare
       --no-session-persistence --allowedTools "" --model haiku --max-turns 2 --output-format json
                                                │ returns JSON {draft?, cost} on stdout
                                                │ (model has NO filesystem write at all)
                              ┌─────────────────┴─────────────────┐
                              ▼                                   ▼
        wrapper writes draft → ~/.claude/              wrapper appends cost →
        skill-proposals/<slug>/SKILL.md                ledger.jsonl
        (only the trusted wrapper writes; fixed path = hard gate; NOT under skills/)

 /skill-review  ──▶  list proposals → writing-skills checklist → mv proposal → ~/.claude/skills/<name>/

 new session ──▶ SessionStart hook → additionalContext:
   "staged: N memory (cc-harvest) · M skill drafts · loop spend $X/wk · /learned · /skill-review"

 weekly / on-demand ──▶ cc-improve curate (claude -p pure-function returns a JSON plan)
                          → wrapper applies: git mv to skills/_archive/ (never delete)
                          → launchd runs PROPOSE-ONLY (report); --apply is never automated
```

## Technical Design

### Interfaces (I/O contract)
- **Consumes:** PreCompact/SessionEnd + SessionStart hook stdin JSON (`session_id`,
  `transcript_path`, `cwd`, `hook_event_name`); the transcript JSONL (schema undocumented, see
  TASK-002); `config.toml`; `~/.claude/skills/` (curator input, read-only except wrapper archive).
- **Produces:** skill drafts `~/.claude/skill-proposals/<slug>/SKILL.md` (valid frontmatter,
  `disable-model-invocation: true` defensively); cost ledger `$STATE/ledger.jsonl` (`ts`,
  `session_id`, `kind`, `total_cost_usd`, tokens; accepts cc-harvest-tagged rows); SessionStart
  `additionalContext` string; curator report.
- **Invariants:** hooks return < 200 ms (async); **the `claude -p` reviewer/curator process has no
  filesystem write capability (`--allowedTools ""`)**; every write is done by the trusted bash
  wrapper to a fixed path; the wrapper never writes under `~/.claude/skills/` (only `/skill-review`
  promote does); curator never deletes (git mv only); a reviewer never spawns a reviewer (`--bare`
  + `CLAUDE_REVIEWING`).

### Data model (runtime state, NOT in repo)
```
~/.claude/skill-curator/
  config.toml                  # rendered on install
  state/reviewer.lock.d/       # single-flight (atomic mkdir lock; macOS has no flock(1), see ADR-0004)
  ledger.jsonl                 # suite cost ledger
~/.claude/skill-proposals/<slug>/SKILL.md   # the staging gate (gitignored / unsynced)
~/.claude/skills/_archive/<name>/           # curator archive (git-tracked if skills is a repo)
```

### Infrastructure changes
- `install.sh`: idempotent JSON-merge of the skill-review hook (PreCompact + SessionEnd) and the
  SessionStart surfacing hook into `~/.claude/settings.json`, read-merge-write, backup first.
  Both spawned hooks carry `"async": true`. `uninstall.sh` reverses it.
- Optional Phase C: `mini.cc-curator` LaunchAgent (weekly, propose-only), BTM-friendly
  (ProgramArguments[0] = `bin/cc-improve`, no `.sh`). Wired into vps-mon before "done".

## Task Breakdown

### Phase A: Skill-draft reviewer (the new core)
- [ ] TASK-001: Tool scaffold (`ops-tool-shape`): layout, `tool.toml`, README stub, `.gitignore`
      (ignore runtime state; ensure skill-proposals never tracked), `config.example.toml`.
      AC: `ops-tool-shape` audit passes.
- [ ] TASK-002: Transcript parser `lib/transcript.sh` (bash + jq). Dump a real transcript, lock the
      per-line schema, emit last-K user+assistant turns as compact text. References cc-harvest's
      schema findings; does NOT import cc-harvest's Python (cross-language). AC: fixture test green
      against a committed sample transcript.
- [ ] TASK-003: Skill-review hook + detached spawn. Own PreCompact/SessionEnd hook entry;
      `setsid/nohup bash lib/reviewer-spawn.sh <payload> &` (the thin wrapper runs `reviewer-run.sh` then removes the temp payload) with `--bare` + `CLAUDE_REVIEWING` + single-flight via an atomic mkdir lock (ADR-0004; macOS has no `flock(1)`).
      AC: hook returns < 200 ms (measured); reviewer runs out-of-band; lock skips a concurrent fire.
- [ ] TASK-004: Reviewer pure-function. `claude -p --allowedTools "" --model haiku --output-format
      json` reads the session summary on stdin and returns JSON `{draft|null, cost}`; the draft, when
      present, is a valid SKILL.md body + frontmatter for a reusable pattern. Prompt forbids copying
      secrets/tokens/credentials into a draft. AC: a seeded "repeated manual workflow" transcript
      returns a draft; a no-signal transcript returns `null`; no draft contains a seeded secret.
- [ ] TASK-005: Staging writer + cost ledger (trusted bash). The wrapper writes the returned draft
      to `~/.claude/skill-proposals/<slug>/SKILL.md` (only path it ever writes a draft to) and
      appends `total_cost_usd` + tokens to `ledger.jsonl`. AC: draft lands only under
      skill-proposals/; ledger line per run; malformed/empty JSON logged, not fatal; `claude`
      missing/non-zero exits 0 with a log line.

### Phase B: Promote gate
- [ ] TASK-006: Staging-gate test `tests/test-staging-gate.sh`: a proposal under `skill-proposals/`
      is NOT discovered/auto-invocable by Claude Code (only `skills/` is); AND the reviewer (no
      Write tool) cannot write under `skills/` even given an adversarial transcript.
- [ ] TASK-007: `/skill-review` promote skill: list proposals, run the `writing-skills` checklist
      (incl. a secret scan), on approval `mv` proposal -> `~/.claude/skills/<name>/`; reject
      discards; refuse to overwrite a live skill without `--force`. AC: promote moves the dir,
      reject discards, neither touches unrelated skills.
- [ ] TASK-008: SessionStart surfacing hook: `additionalContext` with cc-harvest staged-memory
      count + skill-draft count + 7-day loop spend from the ledger. AC: new session shows the line.
- [ ] TASK-009: Async + reentrancy tests. `tests/test-async.sh` (negative control: a `sleep 30`
      reviewer must not delay the hook return or the next prompt); `tests/test-reentrancy.sh`
      (a reviewer cannot trigger a reviewer). AC: both green.
- [ ] TASK-010: `install.sh` / `uninstall.sh` (idempotent settings.json merge + dirs + config,
      backup first). AC: install twice = no dup hook entries; uninstall removes only this tool's.

### Phase C: Skill-library curator
- [ ] TASK-011: `cc-improve curate` pure-function. `claude -p --allowedTools "" ` over skill
      frontmatter + first-paragraph returns a JSON plan (umbrella clusters + stale-by-mtime
      candidates). The wrapper writes a human-readable report; no changes without `--apply`.
      AC: report lists clusters + stale candidates; propose-only by default.
- [ ] TASK-012: Archive + restore (trusted bash). `--apply` archives via `git mv` to
      `skills/_archive/` (never delete); `cc-improve restore <name>`. AC: archived skill
      recoverable; no `rm` anywhere; non-git host falls back to `mv` + manifest with a warning.
- [ ] TASK-013: Optional weekly `mini.cc-curator` LaunchAgent (BTM-friendly), **propose-only**
      (writes a report, never `--apply`; the human runs `--apply` after reading) + vps-mon wiring.
      AC: `launchctl print` shows `bin/cc-improve`; job shows `monitored`; the plist has no `--apply`.
- [ ] TASK-014: Docs close-out: `docs/proof-of-done.md` (multi-feature index per SPEC-016), README,
      tool.toml, MANIFEST + INVENTORY rows; note the memory/skill split in the cc-elevation docs.

## After state
- [ ] After a session with a repeated manual workflow, a SKILL.md draft appears under
      `~/.claude/skill-proposals/` with no manual invocation. (Today: skill capture is manual.)
- [ ] The draft is provably NOT auto-loaded, AND the reviewer cannot write under `skills/`
      (`tests/test-staging-gate.sh`). (Today: no auto path, no gate.)
- [ ] `/skill-review` promotes a draft into `~/.claude/skills/` only after the writing-skills
      checklist. (Today: no promote gate.)
- [ ] `cc-improve curate` prints a consolidation report and changes nothing without `--apply`.
      (Today: no curator exists.)
- [ ] SessionStart shows "N memory, M skill drafts, $X/wk". (Today: nothing surfaced.)
- [ ] `cat ~/.claude/skill-curator/ledger.jsonl` shows a `total_cost_usd` line per run.
- [ ] The skill-review hook returns < 200 ms with a `sleep 30` reviewer (negative control green).

## Acceptance Criteria (global)
- [ ] **Skill-loop delivered (this spec, self-checkable)**: skill auto-draft + promote gate +
      curator + surfacing run automatically, background, non-blocking, propose-and-stage.
      (Suite-level Hermes parity = this + cc-harvest + the cc-harvest per-turn sibling goal; that
      parity is asserted at the mega-goal, not checked here.)
- [ ] **Cost observable** (first-class #1): every **reviewer** run logs `total_cost_usd` to the
      ledger (the curator writes a report + heartbeat, not a ledger row, so 7-day spend is
      reviewer-only); SessionStart surfaces 7-day loop spend; dial-back levers documented.
- [ ] **Fully async** (first-class #2): the skill-review hook spawns detached and returns
      immediately (`tests/test-async.sh`).
- [ ] **Zero interface blocking** (first-class #3): negative control proves a slow reviewer never
      delays the next prompt.
- [ ] **Model has no write**: reviewer/curator run `--allowedTools ""`; only the trusted wrapper +
      promote write files (verified by `tests/test-staging-gate.sh`).
- [ ] Curator never deletes; reentrancy guarded; no duplication of cc-harvest memory capture.

## Verification
```
bash tools/skill-curator/tests/test-transcript-parse.sh \
  && bash tools/skill-curator/tests/test-async.sh \
  && bash tools/skill-curator/tests/test-reentrancy.sh \
  && bash tools/skill-curator/tests/test-staging-gate.sh
```
Plus a recorded live run in `docs/proof-of-done.md`: a real session producing a skill draft +
a ledger line, and `cc-improve curate` producing a report.

## Edge Cases
1. **Reviewer pile-up.** Single-flight via an atomic mkdir lock (ADR-0004): a second trigger while one is in flight is skipped
   (logged), bounding cost.
2. **Malformed/empty `claude -p` JSON.** Wrapper logs and continues; no partial draft written.
3. **`claude` not on PATH / auth expired / non-zero exit.** Wrapper exits 0 with a log line; no
   draft, no ledger corruption (a harvest must never block or break a session).
4. **Transcript schema drift.** Parser fixture fails loudly; reviewer no-ops rather than drafting garbage.
5. **`~/.claude/skills/` is not a git repo.** Curator archive falls back to `mv` into `skills/_archive/`
   + a manifest line (still recoverable); warns git-restore is unavailable.
6. **Draft slug collides with an existing skill name.** Reviewer suffixes `-draft`; promote refuses
   to overwrite a live skill without `--force`.
7. **No reusable pattern in the session.** Reviewer returns `null` (a no-op pass is valid, unlike
   Hermes's "always do something" prompt).
8. **Secret printed in the transcript.** Reviewer prompt forbids copying secrets into a draft; the
   promote checklist scans; skill-proposals/ is gitignored/unsynced so a slip is local + transient.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Reviewer cost runs hot | ledger 7-day spend spike in SessionStart line | per-session trigger already; raise K cap or disable skill-review via config |
| Reentrant reviewer loop | runaway `claude` processes | `--bare` + `CLAUDE_REVIEWING` + lock; `uninstall.sh` kill-switch |
| Prompt-injected transcript tries to write a live skill | a write under `skills/` from a reviewer | model runs `--allowedTools ""` (no write at all); only the wrapper writes, to fixed paths |
| Secret in transcript copied into a draft | a token-shaped string in a proposal file | reviewer prompt ban + promote secret-scan; proposals gitignored/unsynced |
| settings.json corrupted by install | Claude Code fails to start | install backs up first; uninstall/restore from backup |
| Curator data loss | a skill file missing after curate | `git mv` only, never `rm`; `cc-improve restore`; `_archive/` |
| Duplicate memory staging vs cc-harvest | two ledger/buffer entries for one learning | skill-curator does NOT stage memory; review-time check + AC |

## Out of Scope
- **Memory capture** (owned by cc-harvest). A per-turn *memory* cadence is a cc-harvest enhancement,
  tracked as a sibling mega-goal, not here.
- Auto-activating skills (Hermes `guard_agent_created:false` parity), explicitly rejected.
- Routing staged memory to its durable home, `learning-ledger` `/learned` owns it.
- Reimplementing `writing-skills`, promote delegates to it.

## Touches
- tools/skill-curator/**

## Decision Log
- DEC-001: **Bash for everything**, not Go (hooks are shell; reviewer/curator are thin `claude -p`
  + `git` orchestration; no daemon/perf path). *Flagged for override at review.*
- DEC-002: **Reviewer model = haiku** (configurable).
- DEC-003: **Staging-by-path is the gate** (drafts outside `~/.claude/skills/`).
- DEC-004: **Repo-wide spec numbering (SPEC-103)** via dwarves-kit `spec-next.sh`.
- DEC-005: **Single-flight lock** bounds cost + rate-limit exposure.
- DEC-006: **Reframed 2026-06-19 after discovering cc-harvest.** Dropped the per-turn memory
  reviewer (duplicate of shipped cc-harvest); skill-curator is now the SKILL half + curator.
  Trigger reuses cc-harvest's PreCompact/SessionEnd. Maps Hermes's dual cadence faithfully and is
  *more* faithful than the original "per-turn for everything."
- DEC-007: **Hermes parity is a suite property** (mega-goal-level AC), satisfied by cc-harvest +
  skill-curator + the cc-harvest per-turn sibling goal together; this spec's own AC is the
  self-checkable skill-loop.
- DEC-008: **Model runs `--allowedTools ""` (no filesystem write); the trusted bash wrapper does all
  writes** (spec-validate CRITICAL). Closes prompt-injection-to-arbitrary-write and makes the
  staging-by-path gate a hard guarantee rather than a prompt instruction. Curator likewise returns a
  plan; the wrapper executes `git mv`.

## Amendments
- AMEND-001: 2026-06-19 | reframed scope from "full memory+skill clone, per-turn" to "skill half +
  curator, per-session trigger" | why: cc-harvest already ships the memory half | pre-implementation
  | re-validated: full lane (this `/kit:spec-validate`).
- AMEND-002: 2026-06-19 | model-as-pure-function (no Write); trusted-wrapper writes; suite-parity AC
  rescoped to mega-goal; secrets-in-transcript + claude-unavailable handling; launchd propose-only |
  why: `/kit:spec-validate` CRITICAL (security/gate) + warnings | pre-implementation | re-validated.

## Open questions
(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
