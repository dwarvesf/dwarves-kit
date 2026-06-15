# cc-observe

See my own Claude Code usage as data: which Skills and tools I actually use (with error rates), and which hooks are slow. Pure read-only parsing of the session transcripts under `~/.claude/projects/`, no instrumentation, no daemon.

Part of the `cc-elevation` self-observability axis. Full design: `SPEC.md`. Why no hook wrapper: `docs/implementation-notes/01-observability.md`.

## Install

```bash
ln -s "$(pwd)/tools/cc-observe/bin/cc-observe" ~/.local/bin/cc-observe   # ~/.local/bin is on PATH
```

Needs only `python3` (stdlib).

## Use

```bash
cc-observe report                   # all views, all projects, all time
cc-observe report --days 7          # the weekly digest (recommended cadence)
cc-observe skills --days 30         # which skills fired in the last 30 days
cc-observe tools  --days 7          # tool usage + error rates
cc-observe hooks  --days 7          # per-hook p50/p95/max latency + hook errors
cc-observe subagents --days 7       # subagent spawns per day + by type, per100 prompts
cc-observe friction --days 7        # thrash / permission-friction / context-pressure / skill mis-fires
cc-observe sessions --days 7        # archetype mix / circadian (by hour) / interruption rate
cc-observe cost --days 7            # tokens by model + cache economics + $ estimate
cc-observe report --days 7 --json   # machine-readable, for vps-mon ingest
```

**`cc-semantic`** (sibling script) , LLM-derived signals that a deterministic parser cannot produce, as **proposals only** (writes nothing durable):

```bash
cc-semantic --days 7                 # topic-drift + self-correction over recent prompts (uses claude -p)
CC_SEMANTIC_CMD="cat resp.json" cc-semantic ...   # inject a fixed model response (tests)
```

It feeds a windowed, capped sample of recent user prompts to Claude Haiku (`claude -p`, overridable via `CC_SEMANTIC_CMD`), which returns `{topics, self_corrections}`. Degrades to `_unavailable_` if the model is missing , it never fabricates. These are NLP estimates (noisier than the deterministic views); a human acts on them. NOT mini.ollama.

Scope to one project (note the **equals form**, slugs start with `-`):

```bash
cc-observe hooks --project=-Users-tieubao-workspace-tieubao-ops-toolkit --days 7
```

## What it reads

Each transcript entry already carries `hookInfos: [{command, durationMs}]`, `hookErrors`, and the `tool_use` / `tool_result` blocks. cc-observe tallies them:

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
- Read-only by contract: cc-observe never writes anything.

## Next (not in this tool yet)

Schedule `cc-observe report --days 7 --json` on a cadence and feed it to vps-mon. That deploy step is deferred; the tool stands alone today.
