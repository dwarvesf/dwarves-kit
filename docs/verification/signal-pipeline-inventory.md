# Signal-pipeline inventory (evidence for SPEC-200)

Swept 2026-07-14 over the whole repo; re-swept 2026-07-20. The pipelines below match
the shape collect -> analyze -> report -> propose. This is the evidence base for
SPEC-200's claim that the kit has one ETL class with five vocabularies.

The 2026-07-20 re-sweep added rows 20-21: the two hook-entry pipelines that feed the
same staging file the `learn` verbs do. Row 20 (`backlog-stage`) was a pre-existing
omission from the original sweep, found while registering row 21; the original sweep
enumerated CLI entries and missed the hook-entry ones.

| # | Pipeline | Entry | Source | Transform | Output | Proposal shape | Cadence | Chains? |
|---|---|---|---|---|---|---|---|---|
| 1 | lane-telemetry | `lib/telemetry/lane-telemetry.sh` | run ledger `runs/*.log` | bash/awk | stdout ASCII / mermaid | none (feeds retro) | on-demand | no |
| 2 | learn propose | `bin/learn propose` | stats lenses + debt + learned-ledger | aggregate + LLM interpret + adversarial refute | `## [staged]` blocks | **staging block** | weekly | yes (dedup vs staged/expired/rejected) |
| 3 | learn drain | `bin/learn drain` | the staging file | parse/group/age | stdout list; ages to `[expired]` | (review surface) | on-demand | yes (self-mutates) |
| 4 | learn debt | `bin/learn debt` | `\| DEBT \|` ledger lines | bash classify | stdout TSV / md digest | collectible items | on-demand | reads own writes |
| 5 | stats | `bin/stats <verb>` | ledger + transcripts (numeric only) + opt-in sources | DuckDB SQL, in-memory | stdout json/table; HTML | **staging block** (`--propose`) | on-demand | no (stateless) |
| 6 | mega report | `bin/mega report` | ROADMAP + ledger | python | `RUN_REPORT.md` | none | mega close | no |
| 7 | mega review | `bin/mega review` | roadmap + ledger + `gh pr view` | python join | `REVIEW.html` | none | mega close | no |
| 8 | skill-curator reviewer | hook -> `reviewer-run.sh` | session transcript | LLM (haiku) | `~/.claude/skill-proposals/<slug>/SKILL.md` | skill draft | hook (SessionEnd) | no |
| 9 | cc-improve curate | `bin/cc-improve curate` | `~/.claude/skills/*` | LLM | `curator-report-<ts>.md` | archive/cluster plan | on-demand | no |
| 10 | board mirror/writeback | `bin/board mirror` | every repo's BACKLOG + ROADMAP | keyed diff vs snapshot | Hermes cards; `chore/board-sync` PR | held PR | on-demand | yes (own snapshot) |
| 11 | session observe | `bin/session observe` | CC transcripts | python heuristics | stdout tables | none | on-demand | no |
| 12 | session report | `bin/session report` | observe output | POST | vps-mon heartbeat | none | weekly | no |
| 13 | session semantic | `session-semantic` | recent prompts | LLM (haiku) | stdout json | ephemeral | cron-able | no |
| 14 | session intel | `bin/session intel run` | observe + repo-sweep + ledger + transcripts | deterministic heuristics | `intel-YYYY-MM-DD.md` | **bullet prose in the digest** | weekly | no |
| 15 | session audit | `session audit run\|triage` | CC transcripts | agentic LLM | `audit-YYYY-MM-DD.md` | **staging block** (since this PR) | weekly / on-demand | yes ({PREV} diff) |
| 16 | proof-table-gen | `lib/gate/proof-table-gen.sh` | run ledger | python | `docs/verification/generated/<rid>.md` | none | on-demand | no |
| 17 | verif-counts | `lib/gate/verif-counts.sh` | test output | grep/sed | `COUNTS.md` block | none | on-demand | overwrite |
| 18 | /kit:retro | `commands/retro.md` | git + specs + completeness.log + lane-telemetry | LLM-facilitated Q&A | `RETRO-[date].md` | **checkbox action items** | on-demand | loose |
| 19 | /kit:kit-health | `commands/kit-health.md` | kit's own fs/hooks/logs | bash checklist | stdout report | advisory prose | on-demand | no |
| 20 | backlog-stage | `hooks/backlog-stage.sh` | CC session transcript | prefilter + LLM (haiku) extract | `## [staged]` blocks | **staging block** | hook (SessionEnd), 1h throttle | yes (dedup vs board + staging) |
| 21 | intake-sweep | `hooks/intake-sweep.py` (via `backlog-stage.sh --surface`) | consumer-declared sources (`_meta/intake-sources.json`: jsonl / command adapters) | filter + field-map, no LLM | `## [staged]` blocks | **staging block** | hook (SessionStart), daily throttle | yes (board + staging + durable swept-keys) |

## What the sweep proves

- **Three proposal shapes, one gate.** Staging blocks (2, 5, 15, 20, 21) are the currency
  `board promote` reads. Bullet prose (14) and checkbox items (18) never reach it:
  they are leads a human must retype, which is why nobody does. SPEC-200 I1.
- **One resource, three env families.** `_meta/BACKLOG.md` is addressed by
  `BACKLOG_FILE`, `BACKLOG_STAGE_BACKLOG`, and `CC_BACKLOG_BACKLOG`. The `CC_*`
  prefix is banned by the kit's own invariant and was renamed once already
  (`kit-foldin-hooks.md`); `lib/stats` entered later and reintroduced it.
  SPEC-200 I2, fixed + lint-enforced in this PR.
- **Two durable-root disciplines.** 16 pipelines route persistence through
  `kit-log-dir.sh` (SPEC-097); `queue.sh` does not and defaults into the exact
  reinstall blast zone SPEC-097 exists to escape. SPEC-200 I3.
- **Five verbs for "generate a dated document"** (`stats digest`, `session intel
  run`, `session audit run`, `lane-telemetry report`, `/kit:retro`), and one word
  (`report`) meaning two different things one level apart in the same CLI
  (`session report` = heartbeat POST; `session observe report` = terminal table).
  SPEC-200 I4.
