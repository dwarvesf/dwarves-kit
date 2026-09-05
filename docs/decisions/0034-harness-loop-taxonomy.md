# 0034. Harness-loop taxonomy: names, scopes, and surface consolidation

Date: 2026-07-12
Status: Accepted 2026-07-14 (Han). The GATE it carried is discharged: sub-goals 04/05/06/08/09/10 shipped, the `bin/` layout and `lib/config/module-registry.md` are live, and the five legs are the kit's working vocabulary. The Status field simply never got bumped after the merge (PR #236, 2026-07-12); a doc sweep on 2026-07-14 caught it.
Relates-to: `docs/briefs/DECISION-BRIEF-harness-loop.md` §4 (working positions attacked here), `docs/research/2026-07-05-harness-ops-loop-and-naming.md` (the naming convention this amends), ADR-0031 (no new learning engine), SPEC-126 (weekend-batch kit/skill split), SPEC-182/183/184 (stats plane, config resolver, stable bin entrypoints), SPEC-129 (OUTCOME emitter), ADR-0009 (plugin dual-ship), PHILOSOPHY §3 (no unbounded outer loops)

## Decision (one line)

One grammar for the operator surface (`bin/<subsystem> <verb>`, two named module-CLI exceptions), one home for the Learn leg (`lib/learn/` + `bin/learn`), one word per meaning (`retro` = per-run, `propose` = cross-run), legs as metadata (never module renames), and ONE weekly scheduler with a declarative jobs list instead of plist-per-job, locked here so a name that survives this ADR is never renamed in sub-goals 04–10.

## Census (2026-07-12, master `a6c5a9e`)

The taxonomy is a consolidation plan, so it opens with what exists. Four surfaces.

### bin/, 11 entries, three grammars

| Entry | Grammar class today | Target state |
|---|---|---|
| `board` | subsystem noun | keep; gains `promote` verb (absorbs `add-backlog`) |
| `classify` | subsystem noun | keep |
| `gate` | subsystem noun | keep |
| `add-backlog` | verb-first orphan (board family) | **retires** → `board promote`, no alias (decision 7) |
| `session-intel` | prefixed sibling (1 of 5) | collapses → `session intel` |
| `session-observe` | prefixed sibling | collapses → `session observe` |
| `session-recall` | prefixed sibling | collapses → `session recall` |
| `session-report` | prefixed sibling | collapses → `session report` |
| `session-semantic` | prefixed sibling | collapses → `session semantic` |
| `prose-rag` | module CLI | keep, module class (decision 7) |
| `worktree-provision` | module CLI | keep, module class (decision 7) |

### Subsystems with no bin entry today

| Subsystem | Engine today | Target |
|---|---|---|
| spec | `lib/spec/spec.sh` | `bin/spec` (SG-04) |
| goal | `lib/goal/goal.sh` | `bin/goal` (SG-04) |
| stats | `lib/stats/` (Python CLI, uv) | `bin/stats` (SG-04) |
| mega | `lib/mega.sh` | `bin/mega` (SG-04) |
| queue | `lib/queue/queue.sh` | `bin/queue` (SG-04) |
| config | `lib/config/kit-config.sh` (resolver, SPEC-183) | `bin/config` (SG-08) |
| learn | does not exist | `lib/learn/` + `bin/learn` (SG-04, decision 1) |

Deliberately bin-less (internal libs, command-invoked, not operator CLIs): `ledger`, `telemetry`, `plugin-check`, `skill-curator`, `adopt.sh`, `explain.sh`, `pitch.sh`, `precedent.sh`. Target bin/ after SG-04+08: 11 subsystem entries (`board classify config gate goal learn mega queue session spec stats`) + 2 module CLIs (`prose-rag`, `worktree-provision`) = 13, two grammar classes, both stated in decision 7.

Amendment 2026-09-06: a third class, standalone operator executables that dispatch to no engine because they ARE the whole feature: `activate` (the free-to-pro client, ID-438), `release` (the semver tag + two-channel publish, ID-437), plus `plugin-check`, `skill-improve`, `skill-review` which had already landed in bin/ under the same shape. The census in `tests/test-bin-forwarders.sh` names every entry in all three classes and proves each standalone one answers with its own contract; a bin/ entry outside those lists is still the drift the census exists to catch.

### skills/, 2 visible, 1 hidden

| Skill | Location today | Target |
|---|---|---|
| get-api-docs | `skills/get-api-docs/` | keep |
| skill-review | `skills/skill-review/` | keep |
| stats | `lib/stats/skill/SKILL.md` (hidden) | relocate → `skills/stats/` (SG-04, decision 8) |

Census fact forcing decision 8: `install.sh` installs skills by globbing `skills/*/SKILL.md` only (install.sh:674); the stats skill ships in the repo but **never installs** on either path today.

### Scheduled-job templates, one per-job plist

| Template | Today | Target |
|---|---|---|
| `lib/session/intel/deploy/macos/session-intel-weekly.plist.tmpl` | one plist for one job | folds into the ONE weekly scheduler + jobs list (SG-10, decision 9) |

(`lib/skill-curator/deploy/` install/uninstall scripts are a deploy bundle, not a scheduler; unaffected.)

## The ten decisions

### 1. The `learn` subsystem: `lib/learn/` + `bin/learn`

The Learn leg's machinery is scattered (weekend-batch in `lib/queue/`, an Execute dir; harvest rides the session module; backlog-stage rides board). Decided:

- `lib/learn/` is the one home for the Learn leg's **read/propose side**; `bin/learn` is its stable entry (SPEC-184 shape) with exactly three verbs: `learn propose` (cross-run distiller), `learn drain` (staging review render), `learn debt <list|collect|mark-paid>` (weekend-batch, relocated).
- Physical move `lib/queue/weekend-batch.sh` → `lib/learn/weekend-batch.sh`, **no alias shims**; every call-site repoints to `bin/learn debt`, including the dotfiles `weekend-debt-paydown` skill whose deep `lib/queue/...` call is itself a SPEC-184 violation the repoint fixes (cross-repo companion PR in SG-04).
- Hooks stay where they fire: harvest and backlog-stage remain SessionEnd hooks in their owning modules (session, board). The subsystem owns reading and proposing, never capture.

Rejected: naming it `retro` (collides with decision 2); moving harvest/backlog-stage into `lib/learn/` (drags capture hooks out of their install units and breaks module gating); alias shims (kit-modularity precedent: repoint every call-site in one release, no back-compat layer).

### 2. One word, one meaning: `retro` = per-run, `propose` = cross-run

`/kit:retro` keeps its name and job (per-run, human Q&A). The cross-run distiller is never called retro: it is `learn propose` at the lib layer. The recurring queue goal keeps its drafted name `kit-retro-YYYY-WW`, the date-suffixed slug IS the whole recurrence mechanism (zero queue-engine changes, PHILOSOPHY §3), and this is the one recorded exception to the vocabulary rule: the goal name is a proper noun for the weekly ritual (which reads per-run retros and ENDS in a propose), predates this ADR in a drafted contract that journal dedup already keys on, and renaming it would churn that contract for symmetry alone.

Rejected: `kit-propose-YYYY-WW` (churns the drafted contract); calling the distiller `retro` anywhere (the collision Han flagged).

### 3. Legs are metadata; modules stay install units

No module renames (install records and `KIT_KNOWN_MODULES` compat). Each module/subsystem declares a **primary leg** (Specify / Execute / Observe / Govern / Learn) in the registry; the two honest spanners are documented as such: **board** (Specify input + Learn output) and **session** (Observe capture + Learn capture). The authoritative assignment:

| Leg | Modules / subsystems |
|---|---|
| Specify | spec, classify, goal, board (input side) |
| Execute | queue, mega, worktree, quiz_gate |
| Observe | stats, session (capture side), telemetry, bridge (board mirror to the cockpit; presentation side) |
| Govern | gate, money_gate, advisor |
| Learn | learn (new), weekend_batch, session (harvest), board (staging/promote), skill-curator |
| (no leg) | cosmetic (statusline; orthogonal to the loop) |

Completeness rule: every `KIT_KNOWN_MODULES` key has a row here and in the registry file; the SG-08 drift lint asserts it, so an added module without a leg row fails CI (the same protection the env↔key rows get).

The machine home for this table is pinned: **`lib/config/module-registry.md`** (co-located with the resolver it feeds; a markdown table parsed the same way gate-ledger already parses the WORKFLOW lane×phase matrix, so no second TOML reader appears and the decision-4 fence holds). One checked-in module-metadata registry carrying **both** the leg column and the env↔key rows, rendered by README and `config list`. One file, because two hand-maintained module tables is the same drift class as the README's agents-11-of-25 bug.

Rejected: renaming modules to leg names (churn for narrative gain); a filesystem reorg by leg (legs are a view, not a directory tree); a second standalone leg-table file (drift).

### 4. Front-door verb fences

Four surfaces, four fenced jobs, locked:

| Surface | Job | Fence |
|---|---|---|
| `/kit:start` | state detector | never writes |
| `/kit:adopt` | mechanical contract injector | idempotent, never interactive |
| `/kit:onboard` | interactive first-run orchestrator (SG-09) | CALLS start + adopt + install/config; confirms before every write |
| `bin/config` | read/explain surface over the SPEC-183 resolver (SG-08) | `lib/config/kit-config.sh` stays the ONLY reader of TOML |

Rejected: interactive prompts in `install.sh` (batch scripts don't prompt; ADR-0009 paths unchanged); config verbs inside adopt; a second TOML reader (SPEC-183's lint exists precisely to prevent it).

### 5. The `-propose` role suffix

The 2026-07-05 closed role-suffix vocabulary gains one entry: **`-propose`**, a propose-only writer whose ONLY legal sink is a staging file (never a board, a ledger rewrite, or a config). This formalizes the discipline the auto-improvement design states in prose. The research doc stays a dated snapshot; this ADR is the canonical amendment to its §3 vocabulary (rule 2's closed list now ends `… -deploy · -propose`).

Rejected: reusing `-observe` (a proposer writes; observe is read-only); leaving the discipline as prose (unenforceable at scaffold time).

### 6. Scope fences (kit-fold contract, restated)

Engine kit-side; consumer state consumer-side. Specifically: the weekly LaunchAgent **instance**, `boards.txt`, and Hermes cockpit legs live consumer-side; no tenant paths kit-side; `learn propose`'s consumer inputs (`learned-ledger.md`, the staging file) resolve via the same env/`--repo-root` channels the stats adapters already use. One engine, one truth: the drafted kit-retro goal contract moves INTO this mega's SG-05 verbatim and out of kit-wiring (ID-273 gets a pointer note).

Rejected: a `CONSUMER_ROOT` config key (board.sh:23 precedent stands); any kit-side scheduler or auto-flush (stance rules; PHILOSOPHY §3).

### 7. bin/ consolidation: one grammar, two classes, no aliases

- **One grammar:** `bin/<subsystem> <verb>`, one entry per subsystem (census target table above). The five `session-*` CLIs collapse into `bin/session <verb>`; the bin entry is a thin router, deep lib paths unchanged.
- **`add-backlog` folds as `board promote`**, deciding the 2026-07-05 doc's deliberately-deferred open question. **No alias survives**: the naming convention permits verb-first for human-typed action commands, but one canonical name beats a permitted alias, and the kit-modularity precedent is repoint-everything-in-one-release. Consumers repoint: vps-mon heartbeat, the session-observe skill, LaunchAgents, install.sh CLI shims, the dotfiles skill.
- **Two-class rule, stated:** subsystem entries follow the one grammar; **module CLIs keep their module names** (`prose-rag`, `worktree-provision`) because they are opt-in install units whose name IS the module key, not subsystems of the always-on engine.
- Missing subsystem entries are **created** (spec, goal, stats, mega, queue in SG-04; config in SG-08; learn in SG-04) so the surface is complete, not just tidy. Internal libs stay bin-less (census list).

Rejected: keeping `add-backlog` as an alias (two names, one action, the exact sprawl this ADR exists to stop); renaming module CLIs into the subsystem grammar (erases the module/subsystem distinction the installer relies on); alias shims of any kind.

### 8. What earns `skills/` (and the stats skill moves there)

The rule: a kit skill is a workflow an **agent should auto-fire** that **drives kit machinery** (loop machinery kit-side; personal reflex skills stay operator-side, per the PHILOSOPHY skill-routing rule and the SPEC-126 split). Thin is acceptable; undecided is not.

Applied: the stats skill relocates `lib/stats/skill/` → `skills/stats/` (SG-04). It is agent-facing loop machinery, and the census fact decides it: hidden at the subsystem path it **never installs**, a phantom surface. After the move the skill-copy glob picks it up on both install paths, and the README stops underselling the surface (3 skills, not 2).

Rejected: leaving it subsystem-internal with a doc pointer (doesn't fix the install gap); inventing a second skill-install glob for `lib/*/skill/` (two conventions where one suffices).

### 9. One scheduler, not plist-per-job

The kit ships **one** scheduler template: a single weekly LaunchAgent that runs a small dispatcher reading a **declarative jobs list** (session-intel digest, kit-retro staging, future entries = one line each). One plist, one runbook, one place to see what runs and when. The existing `session-intel-weekly.plist.tmpl` folds in and retires (SG-10). Adding a weekly job becomes a jobs-list line, not a new daemon. BTM rules apply to the one launcher (`ProgramArguments[0]` = the dispatcher's own absolute path; no `.sh` extension on the launcher). The consumer instantiates the template (SPEC-126 split unchanged); the kit owns template + dispatcher.

Rejected: plist-per-job (N daemons, N runbooks, the fragmentation Han flagged); a kit-side scheduling daemon (PHILOSOPHY §3); cron (launchd is the platform standard here and BTM-visible).

### 10. Ledger retention: append-only stands

The append-only discipline stands (SPEC-097/182: ledgers are never rewritten; stats persists nothing). Retention is revisited ONLY at a measured threshold, named here: **shared ledger root > 100 MB, or `stats digest` wall-time > 10 s on the live corpus**. Below those, no rotation work is justified; at them, the revisit is a new ADR proposing an explicit archive step (the harvest `--cleanup` archive-sibling pattern), never silent rotation or TTL deletion.

Rejected: rotation now (no measured pain, speculative work); TTL deletion (destroys the audit trail and the evidence `learn propose` cites).

Provenance: this area came from Han's 2026-07-12 scope-amendment-2 review (`_meta/megagoals/harness-loop/NOTES.md` event log), not brief §4, which stops at 4.9.

## Amendment (2026-07-18, operator): plain-words rename (leg -> stage; the five leg names)

No decision change: decision 3 stands (legs, now called stages, remain metadata, never module
renames; the authoritative module-to-leg assignment above is the as-decided historical record and
is not rewritten). Only the vocabulary renames, per CONTRIBUTING.md's Plain Words rule and the
ranked inventory (`docs/research/2026-07-16-plain-words-inventory.md`, "The five legs" section),
which found the blast radius here is docs + one table + one lint, not semantic-everywhere -- so a
same-release sweep is the correct size, not a phased migration.

**The rename map:**

| Current | Renamed | Note |
|---|---|---|
| Specify | **Shape** | not "Plan": collides with the planning loop-type + the writing-plans skill |
| Execute | **Build** | the plain PM word |
| Observe | **Watch** | |
| Govern | **Check** | the most corporate of the five; "Guard" is the documented fallback if Check reads too close to verify |
| Learn | **Learn** | kept, already plain, and more accurate than "Improve" (the leg distills, it does not itself improve the product) |
| leg (container word) | **stage** | the everyday word every PM already uses for one step of a workflow |

Per the Plain Words rule's renaming clause, the old names live as a parenthetical alias for one
release where a reader would otherwise be confused by a hard cutover: `lib/config/module-registry.md`'s
stage column, README's "The five stages" section, and the touched per-module READMEs
(`lib/sync`, `lib/learn`, `lib/gate`, `lib/cosmetic`, `lib/session/audit`). Everywhere else the
rename is a clean sweep with no old-name residue -- `docs/data-flow.md`, `docs/MANUAL.md`'s
command index, `docs/kit-contract.md`, `commands/onboard.md`'s welcome tour, and the
registry-lint assertions in `tests/test-meta.sh` -- all move straight to the new names in the
same change (`_meta/BACKLOG.md` ID-292).
`prose_rag`'s leg assignment (flagged as a documented deviation in `lib/config/module-registry.md`)
is unaffected by this amendment; it is a separate open question.

## Amendment (2026-08-27, Han): command-invoked internal libraries stay at lib/ root

Decision (ID-308): the deliberate orphans stay orphans; no folder move. `adopt.sh`, `explain.sh`,
`pitch.sh`, and `precedent.sh` were already named bin-less, command-invoked internal libraries in
the census above (decision area, "Deliberately bin-less" list); this amendment covers the same
class explicitly and adds `onboard-detect.sh`, which the census left off that list. All five sit at
`lib/` root by design, not by drift: none is an operator CLI, each is invoked by a command file
(`commands/*.md`) rather than typed at a shell, and folding any of them into a module folder would
suggest a subsystem boundary that does not exist. No taxonomy or module-registry change follows
from this amendment.

## Consequences

- SG-04 executes the census target state in one wave (moves, collapses, new bin entries, skill relocation, call-site repoints incl. the dotfiles companion PR); SG-05/06 build `learn propose`/`drain` in the decision-1 home; SG-08 builds `bin/config` (decision 4) + the one module-metadata registry at `lib/config/module-registry.md` (decision 3); SG-09 builds `/kit:onboard` inside the decision-4 fences; SG-10 retires the per-job plist per decision 9.
- A later sub-goal that wants to deviate from a name locked here amends this ADR first; it does not ignore it.
- The 2026-07-05 naming research doc remains a snapshot; its §3 vocabulary is amended by decision 5, and its deferred backlog-cluster question is closed by decision 7.

## Appendix: collision audit (2026-07-12, worktree at `a6c5a9e`)

Every name this ADR locks, grepped against live surfaces before locking. Zero collisions.

| Name locked | Audit command (scope: `lib bin commands hooks skills docs/specs docs/decisions tests`) | Result |
|---|---|---|
| `bin/learn`, `lib/learn`, `learn propose\|drain\|debt` | `rg -l 'bin/learn\|lib/learn\|learn propose\|learn drain\|learn debt' <scope>` | no hits |
| `-propose` as a filename role suffix | `find lib bin commands hooks skills -name '*-propose*'` | only `lib/skill-curator/docs/decisions/0002-propose-and-stage.md` (a doc title, not an executable), free |
| `learn` in the module/config surface | `rg -n 'learn' kit.toml install.sh` | only `learning_ledger` key + its comment, free |
| `board promote` | `rg -n 'board promote' lib bin commands hooks docs/specs` | no hits |
| `bin/session`, `bin/config`, `bin/spec`, `bin/goal`, `bin/stats`, `bin/mega`, `bin/queue` | `ls bin/<name>` | none exist, free |
| `/kit:onboard` | `ls commands/ \| grep -i onboard` | no command, free |
| ADR number 0034 | `ls docs/decisions/` | 0033 is the last, free |
| SPEC-193…199 (pre-reserved for SG-02/04–09) | `ls docs/specs/ \| grep -E 'SPEC-19[3-9]'` | none exist, free (the stale name-drops in archived harness-ops notes are prose, not files) |

Note: `--propose` as a CLI **flag** (`stats anomalies --propose`) is widespread and unaffected; decision 5 governs the filename role-suffix vocabulary, not flag names.
