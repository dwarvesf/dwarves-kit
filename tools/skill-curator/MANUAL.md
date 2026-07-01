# cc-self-improve MANUAL

Daily-use guide. What it is + the design: [README.md](./README.md) and
[docs/architecture.md](./docs/architecture.md). When something breaks: [RUNBOOK.md](./RUNBOOK.md).

| Task | Section |
|---|---|
| Install + verify | [1](#1-install-and-verify) |
| See what the loop staged | [2](#2-see-what-the-loop-staged) |
| Promote or reject a draft | [3](#3-promote-or-reject-a-draft) |
| Curate the skill library | [4](#4-curate-the-skill-library) |
| Tune cost + cadence | [5](#5-tune-cost-and-cadence) |
| Turn it off | [6](#6-turn-it-off) |

## 1. Install and verify

**What this does:** wires three hooks (async) into `~/.claude/settings.json` (skill-review on
PreCompact + SessionEnd, surfacing on SessionStart), backs the file up first, seeds the config.

```bash
cd ~/workspace/tieubao/ops-toolkit/tools/cc-self-improve
bash deploy/install.sh
cc-improve status        # should print state dir, 0 drafts, 0 spend
```

**Gotcha:** install is idempotent (re-run adds no duplicate entries) and aborts if `settings.json`
is not valid JSON, after backing it up to `settings.json.bak-<ts>`. The reviewer only fires on a
real session end / compaction, so `status` stays empty until you have finished a substantial session.

## 2. See what the loop staged

**What this does:** shows the staged drafts and the 7-day reviewer spend.

```bash
cc-improve status        # staged-draft count + reviewer runs + loop spend (7d)
skill-review list        # one line per draft: <slug>\t<description>
```

`cc-improve status` reads `~/.claude/cc-self-improve/ledger.jsonl`; `skill-review list` reads
`~/.claude/skill-proposals/`. SessionStart also surfaces a one-line summary at the top of each new
session.

**Gotcha:** the "staged memory" count in the SessionStart line comes from cc-harvest's ledger, not
this tool. If it reads 0 unexpectedly, see RUNBOOK incident 9 (the cc-harvest path coupling).

## 3. Promote or reject a draft

**What this does:** `skill-review` is the only writer of `~/.claude/skills/`. Promote moves a vetted
draft into the live library; reject sets it aside (recoverable).

```bash
skill-review list                 # pick a slug
# read ~/.claude/skill-proposals/<slug>/SKILL.md and vet it against superpowers:writing-skills
skill-review promote <slug>       # mv into ~/.claude/skills/<slug>/
skill-review promote <slug> --force   # only if a live skill of that name already exists
skill-review reject <slug>        # mv to skill-proposals/_rejected/<slug>/ (recoverable, not deleted)
```

Or run the `/skill-review` skill for the guided, vet-each-draft flow (it runs the writing-skills
checklist for you, then calls these commands).

**Gotcha:** exit codes tell you why a promote refused: `2` no such draft, `3` the draft still
contains a secret-shaped string (scrub it), `4` a live skill exists (re-run with `--force`, which
backs the old one up to `_replaced/` first), `5` a move/mkdir failure. Never `--force` without
reading the live skill you are about to replace.

## 4. Curate the skill library

**What this does:** consolidates narrow skills into umbrellas and archives stale/superseded ones.
Propose-only by default; nothing changes without `--apply`. Never deletes.

```bash
cc-improve curate                 # writes a report; changes NOTHING. Read the report it prints the path to.
cc-improve curate --apply         # execute the proposed archives: git mv to skills/_archive/
cc-improve restore <name>         # bring an archived skill back
```

A weekly `mini.cc-curator` launchd runs `cc-improve curate` report-only; you read its report and run
`--apply` by hand. Install/verify it per [deploy/macos/cc-curator-runbook.md](./deploy/macos/cc-curator-runbook.md).

**Gotcha:** the curator NEVER archives a skill whose frontmatter has `pinned: true` (or
`cc-si-protected: true`), even if its plan names it. Pin anything you never want consolidated. Unlike
the reviewer, `curate` does not log a cost row to the ledger, so its spend is not in the 7-day line.

## 5. Tune cost and cadence

**What this does:** config lives at `~/.claude/cc-self-improve/config.toml` (copy of
`config/config.example.toml`). Every key is also overridable by a `CC_SI_<KEY>` env var, and **env
wins** over the file. Tests use the env path; you will normally edit the file.

| Key / env | Default | Effect |
|---|---|---|
| `enabled` / `CC_SI_ENABLED` | `true` | master switch for the skill-review hook + surfacing |
| `model` / `CC_SI_MODEL` | `haiku` | reviewer model (`claude -p --model`) |
| `curator_model` / `CC_SI_CURATOR_MODEL` | (= `model`) | curator model |
| `max_turns` / `CC_SI_MAX_TURNS` | `2` | `claude -p --max-turns` for both calls |
| `transcript_k` / `CC_SI_TRANSCRIPT_K` | `40` | last-K turns fed to the reviewer (smaller = cheaper) |
| `auto_promote` / `CC_SI_AUTO_PROMOTE` | `false` | enable `skill-review auto` (references-add to an existing umbrella only) |
| `signal_gate` / `CC_SI_SIGNAL_GATE` | `false` | skip the model call for a summary with zero signal markers (opt-in cost gate; ADR-0010) |
| `signal_markers` / `CC_SI_SIGNAL_MARKERS` | (built-in regex) | override the marker pattern the gate matches on |
| `CC_SI_STATE_DIR` | `~/.claude/cc-self-improve` | ledger + lock + config + reports |
| `CC_SI_PROPOSALS_DIR` | `~/.claude/skill-proposals` | the staging gate |
| `CC_SI_SKILLS_DIR` | `~/.claude/skills` | the live library + `_archive/` |
| `CC_SI_MEMORY_LEDGER` | ops-toolkit `_meta/learned-ledger.md` | cc-harvest ledger the surface line counts |
| `CC_SI_SETTINGS` | `~/.claude/settings.json` | install/uninstall target (point elsewhere for a dry run) |
| `CC_SI_REVIEWER_CMD` / `CC_SI_CURATOR_CMD` | (unset) | test seam: replace the `claude -p` call with a mock |

To spend less: raise `transcript_k` only if drafts are missing context (smaller is cheaper), keep
`model = haiku`, or set `enabled = false`. The per-session trigger + single-flight lock already bound
cost to roughly one Haiku call per substantial session. For a sharper cut, set `signal_gate = true`
to skip the model entirely on sessions with no signal markers (opt-in; skips are ledgered as
`skip-no-signal` so you can audit what it dropped before trusting it , see ADR-0010).

**Gotcha:** the reviewer always runs `--allowedTools ""` (the model can write nothing); that is not
configurable by design (SPEC-103 DEC-008 / ADR-0001).

## 6. Turn it off

```bash
bash deploy/uninstall.sh          # removes ONLY this tool's hook entries from settings.json
# or, leave it installed but inert:
# set enabled = false in ~/.claude/cc-self-improve/config.toml
```

`uninstall.sh` backs up `settings.json` first and removes only entries whose command path matches
`cc-self-improve` (your other hooks survive). It leaves the ledger and any staged drafts in place,
those are yours, not the installer's, to delete.

**Gotcha:** uninstall does not remove the weekly `mini.cc-curator` launchd (that is a separate
LaunchAgent). Bootout that per the curator runbook if you installed it.
