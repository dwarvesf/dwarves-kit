# Proof of Done: cc-observe

**Feature:** report Claude Code skill/tool usage + per-hook latency + subagent mix + friction + session-shape + token-cost signals from session transcripts.
**Date:** 2026-06-14 (skills/tools/hooks); 2026-06-15 (subagents, friction, sessions, cost views) · **Lane:** full · **Host:** Hans-Air-M4 (macOS 26.5) · **Mega-goal:** cc-elevation SG-01; subagents per ID-100; friction/sessions/cost = cc-elevation-r3 SG-01/02/03 / `research/2026-06-15-claude-code-usage-metrics-and-tooling.md`

## Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| A1 | `skills` view: each Skill counted, with error rate | sub-goal Done |
| A2 | `tools` view: each tool counted, errors attributed via `tool_use_id` | sub-goal Done |
| A3 | `hooks` view: per-hook count + p50/p95/max latency from `hookInfos[].durationMs` | sub-goal Done |
| A4 | Latency discriminates: a known-slow hook surfaces, a known-fast one stays small (negative control) | sub-goal Done |
| A5 | Hook errors surfaced from `hookErrors` | sub-goal Done |
| A6 | `--json` machine-readable output (for vps-mon ingest) | sub-goal "report into vps-mon" |
| A7 | Read-only, no instrumentation, runs on real transcripts | sub-goal quality bar |
| A8 | `tests/smoke.sh` green | sub-goal close-the-loop |
| A9 | `subagents` view: Agent/Task spawns per day + by `subagent_type`, normalized `per100` prompts | ID-100 |
| A10 | Sidechain spawns excluded (each spawn counted once from the main session) | ID-100 negative control |
| A11 | `subagents` included in `report` + the `--json` object | ID-100 (cc-intel weekly digest picks it up) |
| A12 | `friction` thrash: a file edited `>= THRASH_MIN` (3) times in one session is flagged; a once-edited file is not (negative control) | r3 SG-01 |
| A13 | `friction` permission: a real permission marker in a `tool_result` is attributed to the tool (Bash by command) | r3 SG-01 |
| A14 | `friction` context-pressure: `isCompactSummary` entries counted per day | r3 SG-01 |
| A15 | `friction` skill-precision: errored skills ranked by inert-rate; a clean skill is absent (negative control); `friction` in `report` + `--json` | r3 SG-01 |
| A16 | `sessions` archetype: a session is bucketed quick/standard/deep/marathon/automation from wall-clock + tool/prompt volume | r3 SG-02 |
| A17 | `sessions` interruption: `[Request interrupted` turns counted; a clean turn is not (negative control) | r3 SG-02 |
| A18 | `sessions` circadian: prompt-turns + tool-uses bucketed by UTC hour | r3 SG-02 |
| A19 | Subagent transcripts (`isSidechain`) excluded from archetype (negative control: do not inflate `automation`); `sessions` in `report` + `--json` | r3 SG-02 |
| A20 | `cost` tokens-by-model: input/output/cache-read/cache-create summed per `message.model`, with a `$` estimate from the dated `PRICING` table | r3 SG-03 |
| A21 | `cost` unknown family (fable): tokens counted, `$` shown as `?` (negative control) | r3 SG-03 |
| A22 | `cost` cache economics: cache-read / (read + create) hit ratio | r3 SG-03 |
| A23 | `cost` in `report` + `--json`; cost-per-merged-PR documented as out-of-scope (cross-repo + squash-merge) | r3 SG-03 |

## Implementation

| Piece | What | Where |
|---|---|---|
| Parser | single stdlib pass: `tool_use`/`tool_result` -> usage + errors; `hookInfos`/`hookErrors` -> latency | `bin/cc-observe` `collect()` |
| Hook label | basename for script hooks; hash for inline-echo; first token otherwise | `bin/cc-observe` `hook_label()` |
| Views | `skills` / `tools` / `hooks` / `subagents` / `friction` / `sessions` / `report`, aligned tables or `--json` | `bin/cc-observe` `emit()` |
| Sessions | per-transcript first/last ts + tool/prompt counts -> `classify_session` archetype (skip sidechain); turns+tools by UTC hour; `INTERRUPT_MARK` turns | `bin/cc-observe` `collect()` + `classify_session`/`arch_rows`/`circ_rows` |
| Subagents | count `Agent`/`Task` spawns by day + `subagent_type`, skip `isSidechain`; per100 = spawns / user-prompt turns | `bin/cc-observe` `collect()` + `subagent_*_rows()` |
| Friction | per-session Edit/Write counts -> thrash; `PERM_MARKERS` in tool_result -> permission-friction; `isCompactSummary` -> context-pressure; errored skills -> skill-precision | `bin/cc-observe` `collect()` + `thrash_rows`/`perm_rows`/`compact_rows`/`skill_precision_rows` |
| Fixture | + a thrice-edited file, a once-edited file (control), a permission-denied Bash, an errored Skill, a compaction entry; + `session-sample.jsonl` (clean 10.5-min/2-turn session, 1 interrupted) | `tests/fixtures/sample.jsonl` + `session-sample.jsonl` |
| Cost | sum `message.usage` per `message.model`; `model_cost` applies dated `PRICING` (unknown -> `?`); cache-hit = read/(read+create) | `bin/cc-observe` `collect()` + `model_cost`/`cost_rows` |
| Tests | 26 assertions incl. latency + sidechain + thrash + skill-precision + interruption + archetype-sidechain + unknown-family-cost negative controls | `tests/smoke.sh` |

No wrapper, no daemon, no dotfiles change (the transcript already records hook timing). See `docs/implementation-notes/01-observability.md`.

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Smoke (all) | `bash tests/smoke.sh` | `smoke: all 26 passed` | PASS |
| Skills (A1) | `cc-observe skills --file fixture` | `prose-rag 1` | PASS |
| Tools + errors (A2) | `cc-observe tools --file fixture` | `Bash 3 2`, `Read 1 0` | PASS |
| Hook latency (A3) | `cc-observe hooks --file fixture` | `slow-hook.sh max 500` | PASS |
| Negative control (A4) | same | fast `inline-echo` max 12 (< 100) | PASS |
| Hook errors (A5) | same | `1 hook errors` | PASS |
| JSON (A6) | `cc-observe report --file fixture --json \| python3 -m json.tool` | valid JSON | PASS |
| Real data (A7) | `cc-observe subagents --days 6` | 853 transcripts, per-day + per-type table | PASS |
| Smoke green (A8) | `bash tests/smoke.sh` | exit 0 | PASS |
| Subagents (A9) | `cc-observe subagents --file fixture` | `2026-06-14 2 1 200.0` | PASS |
| Sidechain excl. (A10) | same | `2 spawns` (not 3), `Explore 1` (not 2) | PASS |
| In report+json (A11) | `cc-observe report --file fixture[ --json]` | `# subagents` section + `subagents` json key | PASS |
| Thrash + control (A12) | `cc-observe friction --file fixture` | `/x/thrash.py 1 3`; `/x/once.py` absent | PASS |
| Permission (A13) | same | `Bash:deploy 1` | PASS |
| Context-pressure (A14) | same | `2026-06-14 1` compaction | PASS |
| Skill-precision + control (A15) | same | `flaky-skill 1 1 100%`; `prose-rag` absent | PASS |
| Friction real data | `cc-observe friction --days 7` | thrash 28-34x files, perm Write/Agent/Bash, compactions/day | PASS |
| Archetype (A16) | `cc-observe sessions --file session-fixture` | `standard 1 100%` | PASS |
| Interruption + control (A17) | same | `1 interrupted, 1 interrupts` (clean turn not counted) | PASS |
| Circadian (A18) | same | hour `08 2 2` | PASS |
| Archetype sidechain-excl (A19) | `cc-observe sessions --file main-fixture` | archetype `(none)` | PASS |
| Sessions real data | `cc-observe sessions --days 7` | 946 sessions: quick 81% / automation 1% (after sidechain exclusion) | PASS |
| Cost by-model (A20) | `cc-observe cost --file fixture` | opus row `$93.22`, haiku `$0.80` | PASS |
| Cost unknown (A21) | same | fable: tokens counted, `?` (no $) | PASS |
| Cost cache (A22) | same | header `cache-hit 90%` | PASS |
| Cost real data | `cc-observe cost --days 7` | est ~$32k attribution, cache-hit 97%, opus-4-8 dominant, fable `?` | PASS |

## Run detail

```
$ bash tools/cc-observe/tests/smoke.sh | tail -1
smoke: all 26 passed

$ tools/cc-observe/bin/cc-observe cost --days 7 --top 3
# cost  (est $32,201.61, cache-hit 97%, 951 transcripts; Max-plan flat-rate, this is attribution not a bill)
  model              input    output     cache-rd   cache-wr      est$
  claude-opus-4-8  24862092  56965802  12968381497  350511351  $30670.03
  claude-fable-5    6947549   7548018   2200784188   45701673         ?
  claude-opus-4-7     48471   6149434    185220626   35414715   $1403.79

$ tools/cc-observe/bin/cc-observe sessions --days 7 --top 3
# sessions  (946 sessions, 23 interrupted, 36 interrupts = 1.4/100 turns)
  archetype mix:
  archetype   sessions  share
  quick            480    81%
  marathon          46     8%
  automation         8     1%
  circadian (UTC hour):
  hour  turns  tools
  17      170   2387
  18      177   2361
  09      177   1960

$ tools/cc-observe/bin/cc-observe friction --days 7 --top 3
# friction  (939 transcripts)
  thrash (file edited >= 3x in one session):
  file                                          sessions  max-edits
  hidden/Hidden Bar.xcodeproj/project.pbxproj          1         34
  Features/StatusBar/StatusBarController.swift         1         32
  permission-friction (prompts/denials by tool):
  tool/cmd     events
  Write             6
  Agent             5
  Bash:grep         4
  context-pressure (compactions per day):
  day         compactions
  2026-06-11            6
  skill-precision (skills that mis-fired):
  (none)

$ tools/cc-observe/bin/cc-observe subagents --days 6
# subagents  (232 spawns, 2302 prompts, 853 transcripts)
  day         spawns  prompts  per100
  ----------  ------  -------  ------
  2026-06-15      20      201    10.0
  2026-06-14      26      340     7.6
  2026-06-13      30      383     7.8
  2026-06-12      12      182     6.6
  2026-06-11      58      520    11.2
  2026-06-10      43      425    10.1

  subagent_type     count  share
  ----------------  -----  -----
  general-purpose      93    40%
  reviewer             54    23%
  Explore              36    16%

$ tools/cc-observe/bin/cc-observe report --days 2 --top 4
# skills  (225 transcripts)
  skill               count  errors  rate
  prompt-improver        14       0    0%
  plan-for-mega-goal      7       0    0%
# tools  (225 transcripts)
  tool   count  errors  rate
  Bash    3697     219    6%
  Edit    1517     113    7%
  Read    1457     124    9%
# hooks  (18 hook errors across 225 transcripts)
  hook              runs  p50ms  p95ms  maxms
  slop-cleaner.sh   1072   2967   6211  10303
```

The real run produced an actionable finding the tool was built to find: `slop-cleaner.sh` runs on ~every turn at p50 ~3s, max ~10s (logged to the mega-goal NOTES proposed-additions as a candidate fix). The `subagents` view answered the question that prompted it (`research/2026-06-15-...metrics`): raw counts looked flat-to-down (06-11 peak 58, 06-14 only 26), but the type table showed `general-purpose` now dominates (40%) over `Explore` (16%), the costlier-per-spawn shift that the raw count hid.

## Negative control

Two controls prove the numbers are real, not incidental:
- **Latency discrimination**: in the same fixture the slow hook reports max 500ms and the fast hook 12ms; smoke items 4 and 5 assert both. If `collect()` ignored `durationMs`, both would read 0 and items 4-5 fail.
- **Error attribution**: Bash has 1 error (the errored `tool_result` references `tu_2`), Read has 0. If `tool_use_id` mapping were broken, the error would land on the wrong tool or none, failing item 2/3.
- **Sidechain exclusion**: the fixture has 3 Agent spawns but one is `isSidechain` (a subagent's own run). `subagents` reports 2, with `Explore 1` not 2; smoke items 10-11 assert it. If `collect()` did not skip sidechain, every spawn would be double-counted (once in the main session, once in the subagent's transcript) and the count would read 3 / Explore 2.
- **Thrash threshold**: the fixture edits `/x/thrash.py` 3 times (flagged) and `/x/once.py` once (NOT flagged); smoke items 13-14 assert both. If the `>= THRASH_MIN` gate were broken, `once.py` would appear and the signal would be noise.
- **Skill-precision selectivity**: `flaky-skill` errored (shows 100% inert) while `prose-rag` succeeded (absent from the precision table); smoke items 17-18 assert both. If precision listed all skills, a clean skill would show 0% and bury the real mis-fires.
- **Interruption selectivity**: the session fixture has 2 turns, one carrying `[Request interrupted`; `sessions` reports 1 interrupt, not 2; smoke item 20 asserts it. If any turn counted, the rate would double.
- **Archetype sidechain exclusion**: the main fixture is one transcript containing a sidechain entry; `sessions` classifies NO archetype for it (smoke item 22). Without the skip, every subagent transcript would land in `automation` (it inflated the real run from 1% to 38% before the fix).
- **Cost unknown-family**: the fixture's `fable` entry has 1M tokens but no `PRICING` family, so `cost` shows `?` not a fabricated `$` (smoke item 25). A naive `dict.get(...) or 0` would silently report `$0.00` and hide untracked spend; `?` makes the gap visible. opus/haiku price to exact known values ($93.22 / $0.80), proving the table is applied, not guessed.

## Reproduce

```bash
cd tools/cc-observe
bash tests/smoke.sh                              # -> smoke: all 26 passed
bin/cc-observe report --days 7 --top 10          # real digest, last 7 days
bin/cc-observe subagents --days 7                # spawn mix per day + per type, per100 prompts
bin/cc-observe friction --days 7                 # thrash / permission / context-pressure / skill mis-fires
bin/cc-observe sessions --days 7                 # archetype mix / circadian / interruption rate
bin/cc-observe cost --days 7                     # tokens by model + cache economics + $ estimate
bin/cc-observe hooks --days 7 | sort -t$'\t' -k5 # slowest hooks first
```

---

## cc-semantic (cc-elevation-r3 SG-04)

**Feature:** LLM-derived semantic signals over recent prompts , topic-drift + self-correction , as PROPOSALS ONLY (writes nothing durable). A sibling script to `cc-observe`; off main (independent of the SG-01/02/03 stack).
**Date:** 2026-06-15 · **Lane:** full · **Host:** Hans-Air-M4.

### Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| S1 | A cheap model (`claude -p`, overridable by `CC_SEMANTIC_CMD`) is fed a windowed/capped prompt sample and returns topics + self-correction count | r3 SG-04 |
| S2 | Output is propose-only: NOTHING durable is written (no ledger/GLOSSARY/board/file) | r3 SG-04 quality bar |
| S3 | Degrades to `_unavailable_` on missing/failed/unparseable model output (never fabricates) , negative control | r3 SG-04 |
| S4 | Empty window -> "no prompts", no proposal (clean-fixture negative control) | r3 SG-04 |
| S5 | Bounded: prompt window capped (`--cap`, default 200) + per-prompt truncation; Haiku not mini.ollama | r3 SG-04 |

### Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Injected output (S1) | `CC_SEMANTIC_CMD="cat fixture" cc-semantic --root fixtures --days 0` | topics + `self-corrections: 1` + `PROPOSAL ONLY` banner | PASS (smoke 27) |
| Unavailable (S3) | `CC_SEMANTIC_CMD=false cc-semantic ...` | `_unavailable_` | PASS (smoke 28) |
| Empty (S4) | `cc-semantic --root /tmp/none --days 0` | `no prompts` | PASS (smoke 29) |
| JSON | `... --json \| python3 -m json.tool` | valid JSON | PASS (smoke 30) |
| Propose-only (S2) | run, then `git status` | no new files created by the run | PASS (only my own edits + untracked new tool files) |
| Real collection | `cc-semantic --days 1 --cap 50` (fake LLM) | 50 prompts sampled from real transcripts | PASS |

### Negative control

- **Never fabricates**: a failing/garbage model command yields `_unavailable_`, not a made-up topic split (smoke 28). The `parse_json` requires both `topics` and `self_corrections` keys or returns None.
- **Propose-only**: the script has zero write calls; after a run `git status` shows no new files from the tool (only the source files I added). The signal is for a human to act on.

### Run detail

```
$ CC_SEMANTIC_CMD="cat tests/fixtures/semantic-llm-out.json" bin/cc-semantic --root tests/fixtures --days 0
# semantic  (1 prompts sampled; PROPOSAL ONLY , estimates, nothing written)
  topic drift:
       3  cc-observe tooling
       1  git ops
  self-corrections: 1 of 1 prompts
```

Live `claude -p` path is wired (binary at `~/.local/bin/claude`) but not exercised inside the loop to avoid nesting a live claude session; the deterministic injected/degrade/empty paths above are the proof. Run `cc-semantic --days 7` manually for a real topic split.

### Reproduce

```bash
cd tools/cc-observe
bash tests/smoke.sh                                  # -> includes cc-semantic 27-30
CC_SEMANTIC_CMD="cat tests/fixtures/semantic-llm-out.json" bin/cc-semantic --root tests/fixtures --days 0
bin/cc-semantic --days 7                             # real run (uses claude -p)
```

## cc-vps-report (SG-05)

**Feature:** bridge the weekly cc-observe digest into the LIVE vps-mon: HMAC-signed snapshot of headline metrics + a heartbeat ping that surfaces digest liveness on the public `/status` page.
**Date:** 2026-06-15 · **Lane:** full · **Host:** Hans-Air-M4 · **Mega-goal:** cc-elevation-r3 sub-goal 05 (supersedes r2 SG-01 cc-notify). **Target:** personal `mon-ingest` (`https://mon-ingest.han-ws.workers.dev`, CF account Han Ngo).

### Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| B1 | `cc-vps-report` distills `cc-observe report --json` to headline metrics + builds a schema-v1 snapshot envelope | SG-05 "decide the payload" |
| B2 | HMAC signature is byte-identical to `vps-mon/worker/src/hmac.ts` (UTF-8 key bytes, msg `ts\nhost\nsha256hex(body)`, `sha256=`+hex) | SG-05 contract |
| B3 | Signer unit-tested deterministically BEFORE any live POST (a wrong sig is a silent 401) | hard rule |
| B4 | Live `/v1/snapshot` returns 202 with the real key | SG-05 verify |
| B5 | Live `/v1/heartbeat/<token>` returns 204 with the real token | SG-05 verify |
| B6 | The cc-intel-weekly item renders on the public `/status` page | SG-05 Done |
| B7 | Ingest path is itself monitored: a stale digest shows a gap, not silently green | SG-05 monitoring-onboarding |
| B8 | cc-intel weekly launcher calls the bridge after writing the digest (file write preserved) | SG-05 wire |
| B9 | Secrets via `op://` / wrangler secret; never hardcoded; read-only producer | SG-05 quality bar |

### Implementation

| Piece | What | Where |
|---|---|---|
| Client | distill + envelope + sign + POST snapshot + GET heartbeat; stdlib only | `bin/cc-vps-report` |
| Distiller | subagent per100 + top type, tool/skill/hook error counts, friction/cost via `.get()` (defensive for PRs #333/#337) | `cc-vps-report::distill` |
| Signer | mirrors `hmac.ts`/`vps_mon_agent.py::sign_request` exactly | `cc-vps-report::sign_request` + `key_bytes` |
| Test | 6 assertions incl. signer-vs-independent-reference + wrong-key negative control + distiller | `tests/test-vps-report.sh` |
| Live D1 | `status_pages('ai-substrate')` + `heartbeats('cc-intel-weekly', 604800/86400, ai-substrate)` + `status_page_items` link | remote `vps-mon` D1 |
| Live secret | `HMAC_KEY_CC_AIR` on `mon-ingest`; key + token in 1P `op://Toolkit/cc-vps-report/{credential,hb_token}` | wrangler secret + 1P |
| Launcher wiring | `cc-intel-weekly` runs the digest, then best-effort `cc-vps-report --days 7` (non-fatal) | `tools/cc-intel/deploy/macos/cc-intel-weekly` |

### Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Signer (B2/B3) | `bash tests/test-vps-report.sh` | `vps-report: all 6 passed` | PASS |
| Distill real data (B1) | `cc-vps-report --days 30 --dry-run` | metrics object from 2211 transcripts | PASS |
| Live snapshot (B4) | `cc-vps-report --days 30` | `snapshot: 202` | PASS |
| Live heartbeat (B5) | same | `heartbeat: 204` | PASS |
| /status renders (B6) | `curl /status/ai-substrate` | `Claude Code weekly intel digest ... Operational` 🟢 | PASS |
| /status.json (B6) | `curl /status.json?page=ai-substrate` | `"state":"operational"` | PASS |
| Heartbeat recorded (B7) | D1 `SELECT ... WHERE hb_id='cc-intel-weekly'` | `last_status=up, ping_count>=1` | PASS |
| Launcher wiring (B8) | `bash -n cc-intel-weekly` + run bridge body live | syntax-ok + 202/204 | PASS |

### Run detail

```
$ bash tools/cc-observe/tests/test-vps-report.sh | tail -1
vps-report: all 6 passed

$ tools/cc-observe/bin/cc-vps-report --days 30 --dry-run   # metrics distilled from real transcripts
  "transcripts": 2211, "subagent_per100": 7.9, "subagent_top_type": "general-purpose",
  "tool_total": 69779, "tool_errors": 3944, "skill_total": 537, "hook_errors": 77, "friction_count": 0
  gzip_bytes: 241

$ CC_VPS_HMAC_KEY=$(op read op://Toolkit/cc-vps-report/credential) \
  CC_VPS_HB_TOKEN=$(op read op://Toolkit/cc-vps-report/hb_token) \
  tools/cc-observe/bin/cc-vps-report --days 30
snapshot: 202
heartbeat: 204

$ curl -s https://mon-ingest.han-ws.workers.dev/status/ai-substrate | grep intel
  <li class="row"><span class="dot">🟢</span><span class="name">Claude Code weekly intel digest</span>
  <span class="state operational">Operational</span></li>

$ curl -s 'https://mon-ingest.han-ws.workers.dev/status.json?page=ai-substrate'
{"slug":"ai-substrate","title":"AI substrate","overall":"operational","generated_at":...,
 "items":[{"name":"Claude Code weekly intel digest","state":"operational","since":null}]}
```

### Negative control

The ingest path is monitored, not silently green; three controls prove it:

- **Bogus heartbeat token → 404** (the credential is the token): `curl /v1/heartbeat/this-is-not-a-real-token-xyz` returns `404`. A run that fails to ping (because cc-intel did not run, or the token is wrong) does NOT advance `last_ping_at`.
- **Wrong signature → 401**: `POST /v1/snapshot` with `X-Signature: sha256=deadbeef` returns `401`. A forged or mis-signed metric never persists. This is why the signer is unit-tested offline first.
- **Stale-digest path**: the heartbeat is `interval_sec=604800` (7d) + `grace_sec=86400` (1d). The `*/5` prober's `runHeartbeatSweep` flips `last_status` to `silent` once `now - last_ping_at > 691200s`, and `status-queries.ts::mapHbState('silent')` renders the `/status` item as `down`/🔴. So a digest that stops running for >8 days shows red on `/status` and fires a `heartbeat-silent` alert, rather than staying green. (Time-based; verified by the `isOverdue` logic + the bogus-token 404 above, not by waiting 8 days.)

### Live writes + rollback (stateful)

All live changes are additive and reversible. To roll back completely:

```
# 1) Remove the public /status item + the heartbeat + the status page:
Command: cd tools/vps-mon/worker && CLOUDFLARE_ACCOUNT_ID=<Han-Ngo> pnpm wrangler d1 execute vps-mon --remote --command "DELETE FROM status_page_items WHERE ref_id='cc-intel-weekly'; DELETE FROM heartbeats WHERE hb_id='cc-intel-weekly'; DELETE FROM status_pages WHERE slug='ai-substrate'"
Exit: 0 (verified the INSERTs with the inverse SELECTs; DELETE is the exact inverse)

# 2) Remove the worker HMAC secret:
Command: cd tools/vps-mon/worker && CLOUDFLARE_ACCOUNT_ID=<Han-Ngo> pnpm wrangler secret delete HMAC_KEY_CC_AIR
Exit: 0 (secret is the only state added on the worker side)

# 3) Remove the 1Password item:
Command: op item delete "cc-vps-report" --vault Toolkit
Exit: 0
```

Reverting the branch (the code) leaves these live rows orphaned but harmless (the
heartbeat would eventually flip silent and alert on the ai-substrate Discord channel);
the DELETEs above are the clean teardown. No data migration, no schema change: the rows
reuse the existing SPEC-066/067 tables. Rollback is fully scripted, hence not
`[UNAVAILABLE]`.

### Reproduce

```bash
cd tools/cc-observe
bash tests/test-vps-report.sh                          # -> vps-report: all 6 passed
bin/cc-vps-report --days 7 --dry-run                   # see the signed envelope, no network
# live (needs the 1P item + HMAC_KEY_CC_AIR on the worker):
CC_VPS_HMAC_KEY=$(op read op://Toolkit/cc-vps-report/credential) \
CC_VPS_HB_TOKEN=$(op read op://Toolkit/cc-vps-report/hb_token) \
  bin/cc-vps-report --days 7                            # -> snapshot: 202 / heartbeat: 204
curl -s https://mon-ingest.han-ws.workers.dev/status/ai-substrate   # the item renders
```

