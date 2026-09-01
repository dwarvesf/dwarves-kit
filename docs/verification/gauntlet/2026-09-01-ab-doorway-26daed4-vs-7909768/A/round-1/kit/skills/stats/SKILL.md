---
name: stats
description: Query or render the state of the scattered kit/tide/tg-cleanup/learned ledgers (the dwarves-kit gate/proof/telemetry corpus, tide file-move state, tg-cleanup snapshots, the learning ledger), and detect + propose backlog rows off anomalies in that state. Use when the operator asks to SEE ledger state -- "show me the ledger state", "my debt", "understanding debt", "telemetry", "token cost" / "how much am I spending on tokens", "kit runs" / "kit lane telemetry", "ledger status", "render the ledger", "ledger dashboard", "share this as an artifact" (mid-ledger-conversation) -- or to check/propose off it -- "any ledger anomalies", "is my debt over threshold", "propose a backlog row from the ledger state". Drives the read-only `stats` CLI (dwarves-kit/lib/stats) and renders the result as EITHER an in-terminal reply (bot-reply-formatting , tables + bar-fills) or a shareable web Artifact, both from the same one query; `stats anomalies` is the feedback-loop path, PROPOSE-only (stages a cc-backlog candidate, never files a board row). READ-ONLY by hard contract over every source ledger , the CLI never writes back to a source ledger; the one exception is `stats anomalies --propose`, whose ONLY write is the gitignored cc-backlog staging buffer. NOT for editing/mutating any ledger. NOT for ad-hoc SQL exploration (drive `stats query`/`stats show` directly for that; this skill is the rendered-answer path). NOT a persistent TUI/app -- there is no daemon here, only an on-demand agent-driven query + render + propose.
---

# stats

Read-only, agent-callable observability over the ledgers dwarves-kit and its
neighbors (tide, tg-cleanup, learned-ledger) already write. The tool dir is
`~/workspace/<owner>/dwarves-kit/lib/stats` (run `uv run stats <cmd>`
there). **Everything is read-only: the CLI never writes back to a source ledger; there
is no path through this skill that mutates anything.**

## One data path: always query via the `stats` CLI

Never re-derive a ledger reading by grepping `~/.local/state/dwarves-kit/logs/` or
`tide`'s sqlite or `tg-cleanup`'s json yourself , that is a second, divergent data
source and breaks the whole point of the lens (SG-02 already reuses `lane-telemetry`
for the kit read; re-implementing it here would drift). Always go through `stats`.

## Which command answers which question

| The operator wants | Command |
|---|---|
| "show me the ledger state" / "kit runs" / "kit lane telemetry" | `stats render kit_runs --surface terminal` |
| "my debt" / "understanding debt" | `stats anomalies` (checks `SUM(kit_runs.gates_ovr)` against threshold; this is the current debt signal, superseding a raw grep over `\| DEBT \|` lines). For the raw numbers behind it, `stats query "SELECT rid, gates_ovr FROM kit_runs WHERE gates_ovr > 0" --surface terminal` |
| "any ledger anomalies" / "should I propose anything" | `stats anomalies` (report only) or `stats anomalies --propose` (stage a candidate row per fired anomaly into the cc-backlog staging buffer; never files a board row) |
| "telemetry" (tide moves) | `stats render tide_moves --surface terminal` |
| "token cost" / "how much am I spending on tokens" | `stats render tide_tier_b_calls --surface terminal` (per-call cost/token rows); for a spike check specifically, `stats anomalies` |
| "ledger status" / a quick glance at everything | `stats tables` first (row counts per table), then render the table the operator actually cares about |
| "render the ledger" / "ledger dashboard" / "share this as an artifact" | the same `render` command with `--surface artifact --out <tmp path>.html`, then call the **Artifact** tool on that file |
| an ad-hoc cross-ledger question ("which runs correspond to which tide moves") | `stats render --query "<read-only SQL JOIN>" --surface terminal` |

Full table list + schema: `lib/stats/README.md`. `stats tables` also
lists what's materialized right now.

## Surface-selection rule (pick ONE per ask)

- **Quick look, mid-conversation** (the operator just wants an answer now) ->
  `--surface terminal`. This prints a `bot-reply-formatting`-shaped fenced code-block
  table (right-aligned numerics, a bar-fill column for any `*_pct`/`*_rate`/`*ratio*`
  column) , paste that output directly into your reply, do not re-summarize it into
  prose first.
- **"Share this" / "send it to me" / "for review"** -> `--surface artifact --out
  <tmp-path>.html`, then call the **Artifact** tool on the written file (self-contained
  HTML, CSP-safe, no external requests , the file already satisfies the Artifact tool's
  contract as-is).
- Both surfaces render from the exact same query result (one `stats render`
  invocation, one row set); there is no divergent second read between them.
- A wide result (many columns) reads badly as a phone-width code block , prefer
  `--surface artifact` for those rather than fighting the terminal table's width.

## Examples

```bash
cd ~/workspace/<owner>/dwarves-kit/lib/stats

# Quick look: "show me the ledger state"
uv run stats render kit_runs --surface terminal --limit 10

# Share: "send me the token-cost breakdown as an artifact"
uv run stats render tide_tier_b_calls --surface artifact --title "Token cost" \
  --out /tmp/ledger-token-cost.html
# then: call the Artifact tool on /tmp/ledger-token-cost.html

# Ad-hoc cross-ledger question, terminal surface
uv run stats render --query \
  "SELECT k.repo, count(*) AS n FROM kit_runs k GROUP BY 1 ORDER BY n DESC" \
  --surface terminal --title "Runs per repo"

# Feedback loop: "any anomalies? propose a backlog row if so"
uv run stats anomalies --propose
```

If the db has never been built on this host, `stats render` (like `show`/`query`)
lazy-rebuilds from the source files first (SG-02 behavior, unchanged here); no extra
step needed.

## Install

This skill's canonical source is this file (`skills/stats/SKILL.md`; relocated
from `lib/stats/skill/` per ADR-0034 decision 8 -- at the old subsystem-internal
path it never installed, because `install.sh` globs `skills/*/SKILL.md` only).
It now installs automatically on both install paths (bash installer + plugin),
same as `get-api-docs` and `skill-review`. No symlink step needed; edit the
in-repo file.

## When NOT to use this skill

- Editing or mutating any ledger , there is no such path here, or anywhere in this
  tool (read-only by hard contract; `stats anomalies --propose`'s only write is the
  gitignored cc-backlog staging buffer, never a ledger, never a board).
- Ad-hoc SQL you're going to iterate on yourself , just run `stats query`/`ledger
  show` directly; this skill is the rendered-answer path, not a SQL console.
- Filing a board row directly , `stats anomalies --propose` only STAGES a candidate;
  promoting it to `_meta/BACKLOG.md` still goes through the existing `board promote`
  human gate (ex `add-backlog`, ADR-0034), same as any other cc-backlog candidate.
- A persistent dashboard or TUI , there isn't one; every render (or anomaly check) is
  one on-demand query, driven by the agent, per the ROADMAP's binding "consumer is the
  agent on-demand, not a human TUI" decision.

## Known tradeoffs (read before trusting an anomaly at face value)

- `stats anomalies`' `home` field is a static per-detector guess, not derived from
  data; debt/misfire sums are GLOBAL across every repo in `kit_runs`, and ~44% of
  `kit_runs` rows carry `repo = "?"` (unattributed) as of this writing. Treat a fired
  anomaly's "home" as a starting guess for the operator to confirm, not a fact.
- A missing source (e.g. no tide `state.sqlite` on this host) reads identically to a
  present-but-empty one; `stats tables`/`anomalies` cannot currently tell you which.
  Full list + the other two (schema double-definition, lane-telemetry coupling):
  `lib/stats/README.md` "Known tradeoffs".
