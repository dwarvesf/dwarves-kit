# Architecture: skill-curator

The skill half of a Claude Code self-improvement loop (originally adapted from a Hermes-side
design). cc-harvest is the
memory half (a separate, shipped tool); this tool drafts, gates, and curates SKILLs. Everything here
rests on one decision: **the model can write nothing.** Read `docs/decisions/0001-model-has-no-write.md`
for the why; this doc shows the shape.

## 1. The two halves (where this tool sits)

```
                         your interactive Claude Code session
                                       │ transcript JSONL
                  ┌────────────────────┴─────────────────────┐
                  ▼                                           ▼
        cc-harvest  (separate tool)              skill-curator  (this tool)
        MEMORY half                              SKILL half
        transcript -> Haiku -> learnings         transcript -> reviewer -> SKILL draft
        -> _meta/learned-ledger.md (queued)      -> ~/.claude/skill-proposals/<slug>/SKILL.md
        -> /learned flushes                      -> /skill-review promotes -> ~/.claude/skills/
                                                 -> cc-improve curate consolidates + archives
```

**Reader takeaway:** this tool never touches memory capture. It registers its OWN
PreCompact/SessionEnd hook (same events as cc-harvest, separate entry) and reads the same transcript.
The only cross-tool tie is read-only: the SessionStart line counts cc-harvest's queued rows.

## 2. The trust boundary (the keystone)

```
  ┌── UNTRUSTED: the model ───────────────┐        ┌── TRUSTED: bash wrappers ───────────────┐
  │ claude -p --bare --no-session-        │  JSON  │ reviewer-run.sh / promote.sh / curate.sh │
  │   persistence --allowedTools ""       │ ─────▶ │ have ALL the filesystem writes           │
  │   --model haiku --output-format json  │ stdout │                                          │
  │                                       │        │ write ONLY to fixed paths:               │
  │ reads transcript or skill inventory   │        │   ~/.claude/skill-proposals/<slug>/      │
  │ returns {draft|null} or a curate plan │        │   ~/.claude/skill-curator/ledger.jsonl │
  │ HAS NO FILESYSTEM TOOL AT ALL         │        │   ~/.claude/skills/_archive/  (git mv)   │
  └───────────────────────────────────────┘        │   (promote, human-run) ~/.claude/skills/ │
                                                    └──────────────────────────────────────────┘
   reviewer-run.sh:99   --allowedTools ""            common.sh / reviewer-run.sh / promote.sh /
   curate.sh:36         --allowedTools ""            curate.sh do every write
```

**Reader takeaway:** a prompt-injected transcript cannot make a skill appear in `~/.claude/skills/`,
because the model has no Write tool to abuse. Staging-by-path is a structural guarantee, not a prompt
instruction. `tests/test-staging-gate.sh` greps the source to keep `--allowedTools ""` pinned and
proves a path-traversal slug is contained by `safe_slug` (`common.sh`).

## 3. Data flow: a session becomes a staged draft

```
 PreCompact / SessionEnd ─▶ hooks/skill-review.sh (async)
   │  reentrancy gate (CLAUDE_REVIEWING set? exit 0)
   │  enabled gate (cfg enabled)
   │  payload (transcript_path, session_id) ─▶ temp file
   │  setsid (fallback nohup+disown) bash lib/reviewer-spawn.sh <payload>  &
   └─ exit 0   (returns in ~0.11s; the turn is never blocked)
                         │  DETACHED
                         ▼
        lib/reviewer-spawn.sh  ──runs──▶ lib/reviewer-run.sh <payload>  ──then──▶ rm <payload>
                                          │  (thin wrapper exists so reviewer-run stays a pure
                                          │   unit that never deletes its own input)
                                          ▼
        lib/reviewer-run.sh (TRUSTED):
          1. lib/transcript.sh: JSONL ─▶ last-K [role] text turns
          2. single-flight: si_acquire_lock (atomic mkdir lock; skip if a review is in flight)
          3. CLAUDE_REVIEWING=1 claude -p --allowedTools "" ... ─▶ ENVELOPE JSON
          4. two-layer parse:  envelope.total_cost_usd + envelope.result
                               envelope.result is itself the model's JSON {draft|null, reason}
          5. secret-drop: contains_secret(body)? log + ledger note, NO write
          6. WRITE draft  ─▶ ~/.claude/skill-proposals/<slug>/SKILL.md   (the ONLY draft target)
          7. WRITE cost   ─▶ ~/.claude/skill-curator/ledger.jsonl      (one row per run)
          (any failure at any step: log + exit 0; a reviewer must never break a session)
```

**Reader takeaway:** two indirections matter and the README's flat diagram omits them. (a) The hook
spawns `reviewer-spawn.sh`, not `reviewer-run.sh` directly, so the deletable temp payload is separate
from the testable reviewer unit. (b) The model's answer is wrapped twice: the `claude -p
--output-format json` envelope gives the cost, and its `.result` string is itself the draft JSON.

## 4. The propose-and-stage gate (how a draft enters the live library)

```
   ~/.claude/skill-proposals/<slug>/SKILL.md     ◄── reviewer stages here. Claude Code does NOT
            │                                          auto-load this path. The gate IS the path.
            │  /skill-review  (bin/skill-review, the ONLY writer of ~/.claude/skills/)
            │    list → you read + vet against superpowers:writing-skills → promote | reject
            ├── promote ──▶ ~/.claude/skills/<name>/      (mv; refuses overwrite w/o --force;
            │                                              --force backs the old up to _replaced/)
            └── reject  ──▶ ~/.claude/skill-proposals/_rejected/<slug>/   (move, never rm)

   (optional, default OFF) skill-review auto ─▶ writes references/<topic>.md INTO an existing
   umbrella under skills/ , ONLY for a draft tagged cc-si-kind: references-add. Never a new skill,
   never a SKILL.md-body edit. This is the one automated path that touches skills/.
```

**Reader takeaway:** the reviewer never writes `skills/`. The manual `/skill-review` promote is the
normal path in. The `auto_promote` knob is a deliberate, default-off, references-only exception
(`docs/decisions/0002-propose-and-stage.md` scopes it). Nothing here ever deletes: reject moves to
`_rejected/`, force-replace moves the old skill to `_replaced/`.

## 5. The curator (keeping the shelf from overflowing)

```
   cc-improve curate            ─▶ lib/curate.sh
     inventory: skills/*/SKILL.md → {name, description, first-para, mtime, pinned}  (NOT bodies)
        │  CLAUDE_REVIEWING=1 claude -p --allowedTools ""  ─▶ JSON plan {clusters, archive, report}
        ▼
     report (always)  ─▶ ~/.claude/skill-curator/curator-report-<ts>.md  +  curator.heartbeat
        │
        ├── default        propose-only. Nothing in skills/ changes.
        └── --apply        for each archive item: git mv skills/<name> → skills/_archive/<name>
                           (non-git host: mv + _archive/manifest.tsv + WARN); record absorbed_into
   cc-improve restore <name>  ─▶ git mv (or mv) _archive/<name> back

   weekly launchd mini.cc-curator ─▶ runs `cc-improve curate` (NO --apply). Report only.
```

**Reader takeaway:** the maximum destructive action is `git mv` to `_archive/`, reversible by
`restore`. A wrapper guard refuses to archive a skill whose frontmatter says `pinned: true`,
independent of the prompt. The weekly job is report-only; you run `--apply` by hand after reading.
Note: **curate does NOT write a cost row to the ledger** (only the reviewer does), so the 7-day spend
line reflects reviewer cost only.

## 6. Cost + surfacing

```
   every reviewer run ─▶ ledger.jsonl  {ts, session_id, kind:"skill-review", staged, slug,
                                         note, total_cost_usd, input_tokens, output_tokens}
   SessionStart ─▶ hooks/sessionstart-surface.sh ─▶ additionalContext:
     "skill-curator loop: N staged memory (cc-harvest) · M skill drafts · $X spend (7d).
      /learned to flush · /skill-review to promote."
```

**Reader takeaway:** cost is observable per run and surfaced weekly. The memory count comes from
parsing a consumer's own memory-capture ledger (e.g. cc-harvest's queued-row table) by regex.
`SKILL_CURATOR_MEMORY_LEDGER` is tenant config with NO default: unset means the count is skipped with a
clear logged reason (never a silently-wrong path); if it IS set but the ledger's table format
changed, the count can still silently read 0. This is the one brittle cross-tool coupling, called
out in the RUNBOOK.

## 7. Component map

| Module | Single responsibility |
|---|---|
| `hooks/skill-review.sh` | PreCompact/SessionEnd entry: reentrancy + enabled gate, payload to tempfile, detached spawn, return fast |
| `hooks/sessionstart-surface.sh` | SessionStart entry: emit the one-line loop status as `additionalContext` |
| `lib/common.sh` | Paths, `cfg()` (env > config.toml > default), logging, `ledger_append`, `safe_slug`, `contains_secret`, the mkdir lock, the reentrancy sentinel |
| `lib/transcript.sh` | Parse transcript JSONL into last-K `[role] text` turns (jq; skips thinking/tool/summary) |
| `lib/reviewer-run.sh` | TRUSTED reviewer: transcript to `claude -p` (no write), two-layer parse, secret-drop, stage draft, ledger row |
| `lib/reviewer-spawn.sh` | Thin detached wrapper: run reviewer-run, then `rm` the temp payload |
| `lib/promote.sh` | TRUSTED promote core: list / promote / reject / auto; the only `skills/` writer; secret-refuse, force-backup |
| `lib/surface.sh` | Build the SessionStart status line (read-only counts) |
| `lib/curate.sh` | Curator: inventory to `claude -p` plan (no write), report; `--apply` git-mv archive; restore; pinned guard |
| `bin/cc-improve` | CLI: `status` / `curate [--apply]` / `restore` (BTM-friendly entry point) |
| `bin/skill-review` | CLI: `list` / `promote` / `reject` / `auto` (the human gate) |
| `prompts/review-skill.md` | No-write reviewer prompt (signals, preference order, naming, do-not-capture, secret ban, JSON contract) |
| `prompts/curator.md` | No-write curator prompt (umbrella-building, never-delete, propose-only banner, JSON plan contract) |
| `deploy/install.sh` / `uninstall.sh` | Idempotent jq read-merge-write of 3 hook entries into settings.json, backup-first, atomic |
| `deploy/macos/mini.cc-curator.plist` | Weekly propose-only launchd (no `--apply`) |

## 8. Runtime state (NOT in the repo; `.gitignore` enforces)

```
~/.claude/skill-curator/            (SKILL_CURATOR_STATE_DIR)
   config.toml                        rendered on install (copy of config/config.example.toml)
   ledger.jsonl                       suite cost ledger (reviewer rows; cc-harvest-tagged rows accepted)
   state/reviewer.lock.d/             the atomic-mkdir single-flight lock (a DIRECTORY, with a pid file)
   skill-curator.log                tool log
   curator.heartbeat                  mtime = last curate run (vps-mon liveness signal)
   curator-report-<ts>.md             the propose-only curate reports

~/.claude/skill-proposals/            (SKILL_CURATOR_PROPOSALS_DIR) , the staging gate, never auto-loaded
   <slug>/SKILL.md                    a staged draft
   _rejected/  _replaced/             reject + force-replace land here (recoverable, never rm)

~/.claude/skills/                     (SKILL_CURATOR_SKILLS_DIR) , the LIVE library (Claude Code auto-loads)
   _archive/<name>/  _archive/manifest.tsv     curator archive (git mv; absorbed_into recorded)
```

**Reader takeaway:** every path is env-overridable (`SKILL_CURATOR_*`), which is how the tests redirect all
writes into a temp dir and run with no live model (`SKILL_CURATOR_REVIEWER_CMD` / `SKILL_CURATOR_CURATOR_CMD` seams).
One naming wart: the config key is `reviewer.lock` but the lock is the directory `reviewer.lock.d`;
the bare file never exists.

## 9. What is deliberately NOT here

- **Memory capture** , owned by cc-harvest (`tools/cc-harvest/`). A per-turn memory cadence is
  cc-harvest's `--stop-trigger`, not this tool.
- **The skill quality bar** , delegated to `superpowers:writing-skills` at promote time; this tool
  does not reimplement it.
- **Auto-activation of skills** (Hermes `guard_agent_created:false`) , explicitly rejected; see
  `docs/decisions/0002-propose-and-stage.md`.
- **A daemon** , the reviewer is hook-triggered and detached; only the optional weekly curator is a
  launchd job, and it is propose-only.
