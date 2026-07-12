# session-observe

See my own Claude Code usage as data: which Skills and tools I actually use (with error rates), and which hooks are slow. Pure read-only parsing of the session transcripts under `~/.claude/projects/`, no instrumentation, no daemon.

Part of the `cc-elevation` self-observability axis. Full design: `SPEC.md`. Why no hook wrapper: `docs/implementation-notes/01-observability.md`.

## Install

Installed by the kit's `--with session` module: `install.sh` puts a single `session`
shim on `~/.local/bin` (ADR-0034 one-grammar entry); this tool is `session observe`
(and its siblings `session report` / `session semantic`). Direct deep path for dev:
`lib/session/observe/bin/session-observe`.

Needs only `python3` (stdlib).

## Use

```bash
session-observe report                   # all views, all projects, all time
session-observe report --days 7          # the weekly digest (recommended cadence)
session-observe skills --days 30         # which skills fired in the last 30 days
session-observe tools  --days 7          # tool usage + error rates
session-observe hooks  --days 7          # per-hook p50/p95/max latency + hook errors
session-observe subagents --days 7       # subagent spawns per day + by type, per100 prompts
session-observe friction --days 7        # thrash / permission-friction / context-pressure / skill mis-fires
session-observe sessions --days 7        # archetype mix / circadian (by hour) / interruption rate
session-observe cost --days 7            # tokens by model + cache economics + $ estimate
session-observe report --days 7 --json   # machine-readable, for vps-mon ingest
```

**`session-semantic`** (sibling script) , LLM-derived signals that a deterministic parser cannot produce, as **proposals only** (writes nothing durable):

```bash
session-semantic --days 7                 # topic-drift + self-correction over recent prompts (uses claude -p)
SESSION_SEMANTIC_CMD="cat resp.json" session-semantic ...   # inject a fixed model response (tests)
```

It feeds a windowed, capped sample of recent user prompts to Claude Haiku (`claude -p`, overridable via `SESSION_SEMANTIC_CMD`), which returns `{topics, self_corrections}`. Degrades to `_unavailable_` if the model is missing , it never fabricates. These are NLP estimates (noisier than the deterministic views); a human acts on them. NOT mini.ollama.

Scope to one project (note the **equals form**, slugs start with `-`):

```bash
session-observe hooks --project=<project-slug> --days 7
```

## What it reads

Each transcript entry already carries `hookInfos: [{command, durationMs}]`, `hookErrors`, and the `tool_use` / `tool_result` blocks. session-observe tallies them:

- **skills / tools**: count `tool_use` by name (Skill by `input.skill`); attribute `is_error` results back via `tool_use_id`.
- **hooks**: group `hookInfos[].durationMs` by a normalized hook label; count `hookErrors`.
- **subagents**: count `tool_use` named `Agent`/`Task` by day and by `input.subagent_type`, normalized by user-prompt turns (`per100` = spawns per 100 prompts). Sidechain entries (`isSidechain`) are the subagents' own runs, so they are excluded to avoid double-counting. Answers "is my subagent mix drifting?" (e.g. Explore -> general-purpose) which a raw tool count hides.
- **friction**: four deterministic working-pattern signals. **thrash** = a file edited `>= THRASH_MIN` (3) times in one session (rework/debug spiral). **permission-friction** = `tool_result` content matching a real permission marker (capital-P `"Permission to use "`, `"doesn't want to proceed"`, `"denied by your permission"`), attributed to the tool (Bash by command). **context-pressure** = `isCompactSummary` entries per day (the window collapsing). **skill-precision** = skills that mis-fired (errored), ranked by inert-rate, surfaced from the skill-error data the `skills` view buries.
- **sessions**: per-transcript shape. **archetype** = each session bucketed quick / standard / deep / marathon / automation from wall-clock (first->last `timestamp`) + tool-use volume + whether a human prompted; subagent transcripts (`isSidechain`) are excluded so they do not inflate `automation`. **circadian** = prompt-turns + tool-uses by UTC hour-of-day. **interruption rate** = user turns carrying `"[Request interrupted"`, as a count + per-100-turns.
- **cost**: from the assistant `message.usage` block (input / output / cache-read / cache-create tokens) + `message.model`. **tokens-by-model** + a **$ estimate** from an embedded dated `PRICING` table (Max plan is flat-rate, so this is *attribution*, not a bill; unknown model families like `fable` count tokens but show `?`). **cache economics** = cache-read / (read + create) hit ratio, the biggest cost lever. (cost-per-merged-PR is deferred, see proof/impl-notes: transcripts are cross-repo and this repo squash-merges, so there is no clean per-PR attribution.)

## Output (real run, abbreviated)

```
# tools  (225 transcripts)
  tool   count  errors  rate
  Bash    3697     219    6%
  Edit    1517     113    7%
  Read    1457     124    9%

# hooks
  hook              runs  p50ms  p95ms  maxms
  slop-cleaner.sh   1072   2967   6211  10303
```

## Limits

- Script hooks (`*.sh`/`*.py`) label cleanly by basename. Long-text inline/condition hooks (e.g. the `/goal` Stop-hook) fragment by first word. The actionable latency is in the script hooks.
- `--days` is a coarse file-mtime window.
- Read-only by contract: session-observe never writes anything.

## session-report: weekly bridge to vps-mon + `/status`

`bin/session-report` pings the `session-intel-weekly` heartbeat (the default action). The
heartbeat surfaces digest liveness on the public `/status` page: if no digest lands for
>8 days (interval 7d + grace 1d) the item flips to 🔴 and a `heartbeat-silent` alert
fires, so a stopped digest is never silently green.

It can ALSO distill `session-observe report --json` into a handful of headline metrics
(subagent per100 + top type, tool/skill/hook error counts, friction/cost when present),
HMAC-sign a schema-v1 snapshot the same way the vps-mon host agent does, and POST it to
the `mon-ingest` Worker's `/v1/snapshot`, but only behind the opt-in `--snapshot` flag
(default OFF). The snapshot registers a vps-mon `hosts` row subject to the prober's
hardcoded 600s `agent-silent` rule, which false-fires for a weekly pusher (incident
2026-06-15); the heartbeat is the correct weekly liveness signal and does not touch that
table. Only opt in to `--snapshot` once vps-mon exempts low-frequency hosts.

```bash
bash tests/test-vps-report.sh            # deterministic signer + distiller test (no network)
bin/session-report --days 7 --dry-run     # see the signed envelope, no POST
# default = heartbeat-only (the weekly path; no hosts-row, no agent-silent risk):
SESSION_REPORT_HB_TOKEN=$(op read op://Toolkit/session-report/hb_token) \
  bin/session-report                       # -> heartbeat: 204
# opt-in snapshot (only once vps-mon exempts low-frequency hosts):
SESSION_REPORT_HMAC_KEY=$(op read op://Toolkit/session-report/credential) \
SESSION_REPORT_HB_TOKEN=$(op read op://Toolkit/session-report/hb_token) \
  bin/session-report --snapshot --days 7  # -> snapshot: 202 / heartbeat: 204
```

Read-only producer: session-observe/session-report never store state; only vps-mon does. The
signing scheme is the secret string's UTF-8 bytes (not base64-decode) per
`vps-mon/worker/src/hmac.ts`; see `docs/implementation-notes/01-observability.md`. The
`session-intel-weekly` launcher calls this after writing the weekly digest (best-effort,
non-fatal).
