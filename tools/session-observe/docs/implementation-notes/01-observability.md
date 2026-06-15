# Implementation notes: cc-observe (cc-elevation sub-goal 01)

Delta from `_meta/megagoals/cc-elevation/goals/01-observability.md`. Not a restatement.

## 2026-06-14 No hook-latency wrapper needed (spec deviation)
- Context: the sub-goal said to ship a "hook-latency timing wrapper" that hooks call, plus a runbook to wire it into the dotfiles hooks.
- Change: dropped the wrapper entirely. The transcript JSONL already records, per entry, `hookInfos: [{command, durationMs}]` and `hookErrors`. So hook latency is read straight from the transcript, same source as tool/skill usage.
- Why: zero instrumentation, no dotfiles change, no activation step, and the whole tool becomes pure JSONL parsing that is fully testable in-repo against a fixture.
- Impact: the "wrap the dotfiles hooks" runbook is gone. The only remaining deploy step (deferred, not in this PR) is scheduling `cc-observe report --days 7 --json` on a cadence and feeding it to vps-mon.

## 2026-06-14 Single stdlib script, no deps
- Decision: `bin/cc-observe` is one `python3` stdlib script (argparse/json/collections), no `uv`, no `pyproject`.
- Why: matches the repo's other bare-script tools (`migrate-op-refs`, `book-dedup`), and a dependency-free script can run from anywhere including a future hook context.

## 2026-06-14 Project slugs start with a dash (CLI gotcha)
- Constraint the spec missed: Claude Code names project dirs by the cwd path with `/` -> `-`, so a slug like `-Users-tieubao-...` begins with `-` and argparse reads it as a flag.
- Handling: use the equals form `--project=<slug>`. The default mode (`--root` + `--days`, the global digest) does not hit this. Documented in README.

## 2026-06-14 hook_label is imperfect for long-text inline hooks
- Tradeoff: script hooks label cleanly by basename (`slop-cleaner.sh`, `lane-classify.sh`). But some hookInfos commands are a long text blob, the `/goal` Stop-hook records the goal CONDITION as its command, so the label falls to the first token (`Mega-goal:`, `Outcome:`, `Execute`, `A`) and fragments per goal.
- Decision: accept for v1. The actionable latency lives in the script hooks, which label correctly. A future pass could special-case the goal/Stop condition hooks. Logged to the mega-goal NOTES proposed-additions.

## 2026-06-14 Real-run finding worth acting on
- `slop-cleaner.sh`: 1072 runs, p50 ~2967ms, max ~10303ms. That is a Stop hook adding multiple seconds to most turns. Surfaced to NOTES proposed-additions as a candidate backlog item (this is exactly the signal the tool was built to find).

## 2026-06-15 subagents view: count both `Agent` and `Task`; prompt-turn denominator
- Context: added the `subagents` view (ID-100) after a session investigating subagent-mix drift.
- Decision / Change: count `tool_use` named **both** `Agent` and `Task`. This harness names the spawn tool `Agent`; older Claude Code transcripts name it `Task`. Counting both keeps the view correct across the rename + any mixed-age transcript window. The SPEC states the sidechain-exclusion + per100 design; this note holds only the two implementation choices the spec leaves open.
- Why: a single-name match would silently undercount on whichever transcripts use the other name.
- Alternatives considered: (a) count only `Agent` , rejected, breaks on historical transcripts; (b) normalize per "task" , rejected, transcripts have no clean task boundary, so the denominator is **user-prompt turns** (a turn = a non-sidechain `user` entry with a text block, i.e. a real prompt, not a tool_result carrier). per100 = spawns / prompts * 100.
- Impact: `bin/cc-observe` `collect()` (turn + spawn tallies), `emit()` + `subagent_*_rows()`; fixture gained a text prompt, 2 main spawns, 1 sidechain spawn; smoke 9 -> 12 assertions.

## 2026-06-15 friction view: permission-marker false positive + skill-precision proxy
- Context: cc-elevation-r3 SG-01 added the `friction` view (thrash / permission / context-pressure / skill-precision).
- **Permission marker, a trap avoided:** the obvious substring `"permission to use"` is a FALSE positive , it appears in skill-DESCRIPTION text (e.g. update-config's "add bq permission to global settings"), not in real denials. Verified against live transcripts: the genuine markers are capital-P `"Permission to use "` (the prompt), `"doesn't want to proceed"` (denial), and `"denied by your permission"` (config fence). `PERM_MARKERS` uses those three. Grounding the signal in real transcript content before coding caught this; a naive lowercase match would have been pure noise.
- **skill-precision is a deviation from the sub-goal's wording.** The sub-goal said "skill fired but the very next action ignored its output". Transcripts have NO clean marker for "output ignored", and a positional "no follow-through" proxy is noisy (a skill at session-end is normal). So v1 defines skill-precision as **inert = errored** (skill fired, its tool_result is_error), ranked by inert-rate, surfacing the skill-error data the `skills` view buries by sorting on count. The richer "fired-but-output-ignored" proxy is logged to the mega-goal NOTES `## Proposed additions`, not built. See the sub-goal file's `## Notes`.
- **thrash counts sessions, not raw edits.** `thrash[file]` = number of sessions where that file crossed `THRASH_MIN` (3) edits in one transcript; `thrash_max` keeps the worst single-session count. Per-session, because 3 edits across 3 different sessions is normal iteration, 3 in ONE session is a spiral. The fold happens at end-of-transcript (one transcript = one session).
- Impact: `bin/cc-observe` `collect()` (per-file edit fold + perm + compaction) + 4 row helpers + `friction` view; fixture +5 entries (thrice-edited file, once-edited control, denied Bash, errored skill, compaction); smoke 12 -> 18; existing test [2] updated (fixture now has 3 Bash / 2 errors, not 2/1).

## 2026-06-15 sessions view: archetype excludes sidechain; UTC hours; second fixture
- Context: cc-elevation-r3 SG-02 added the `sessions` view (archetype / circadian / interruption).
- **Archetype skips sidechain transcripts.** A subagent's own transcript (`isSidechain`) has 0 prompt turns, so it would classify as `automation` , inflating that bucket from a true ~1% to 38% on real data (measured). Per-file `f_sidechain` flag skips classification for those, so archetype reflects sessions Han actually ran. (circadian/interruption already gate on `not side` per the per-turn counting.)
- **Second fixture required.** The main `sample.jsonl` contains a sidechain entry (for the subagents test), which makes the WHOLE file count as a subagent transcript , so archetype is skipped there and can't be tested on it. Added `tests/fixtures/session-sample.jsonl` (a clean 10.5-min/2-turn session, one interrupted, no sidechain) for the archetype/circadian/interruption assertions. The main fixture instead serves as the archetype sidechain-exclusion negative control (smoke 22).
- **Circadian is UTC.** Hours come straight from the transcript `timestamp` (`ts[11:13]`), no localization (noted in the header + SPEC). Da Nang is UTC+7; left to the reader to shift.
- **Archetype thresholds live in `ARCH`** (marathon 120min/300 tools, deep 30/80, quick 5/15), tunable in one place; order of tests is automation -> marathon -> deep -> quick -> standard.
- Impact: `bin/cc-observe` `collect()` (per-session ts/tool/turn tracking + classify) + `classify_session`/`parse_ts`/`arch_rows`/`circ_rows` + `sessions` view; new fixture; smoke 18 -> 22; `datetime` import added.

## 2026-06-15 cost view: cost-per-merged-PR deferred; pricing is dated + family-keyed
- Context: cc-elevation-r3 SG-03 added the `cost` view (tokens-by-model + cache economics + $ estimate).
- **cost-per-merged-PR deferred (deviation from the sub-goal outcome).** No clean data path: (a) transcripts span ALL repos but merges are per-repo, so total CC cost / one repo's PRs is meaningless; (b) ops-toolkit **squash-merges**, so `git log --merges` returns ~0 (a squash is not a merge commit) , the natural git signal is empty here; (c) real per-PR attribution needs PR data (gh), not transcript data. Shipped tokens-by-model + cache economics (the two clean, fully-deterministic signals) instead. Logged to NOTES `## Proposed additions` + sub-goal `## Notes`.
- **`$` is attribution, not billing.** Max plan is flat-rate; the `PRICING` table (dated 2026-06-15, $/M tokens by family substring) estimates relative spend. Unknown families (`fable`, a stray `<synthetic>`) count tokens but show `?` , NOT `$0.00` , so untracked spend stays visible rather than silently zeroed.
- **Cache-hit ratio = read / (read + create)** across all models; on real data it runs ~97%, confirming caching is doing its job (the biggest cost lever per the research note).
- Impact: `bin/cc-observe` `collect()` (per-model usage tally) + `model_cost`/`cost_rows` + `cost` view; `PRICING` constant; fixture +3 usage entries (opus/haiku/fable); smoke 22 -> 26. Non-goal #2 in SPEC.md rewritten (it previously said "no cost accounting", now superseded).

## 2026-06-15 cc-semantic (SG-04): separate script, injectable LLM, live run deferred
- Context: cc-elevation-r3 SG-04 added LLM-derived semantic signals (topic-drift + self-correction). Off main, independent of the SG-01/02/03 stack.
- **Separate script, not a cc-observe view.** cc-observe is stdlib-only + "runs anywhere including from a hook"; adding an LLM/subprocess call would break that contract. So SG-04 is a sibling `bin/cc-semantic` (still part of the cc-observe tool dir + proof). cc-observe stays pure.
- **LLM command is injectable** (`CC_SEMANTIC_CMD`, prompt piped to stdin) so tests run with a fixed response , no live model, deterministic. Default is `claude -p` (Haiku tier intent; binary at `~/.local/bin/claude`). `parse_json` requires both expected keys or returns None -> the tool degrades to `_unavailable_` rather than fabricating.
- **Live run deferred in-loop.** Exercising a real `claude -p` nests a live claude session inside this one (hang/recursion risk). The deterministic injected/degrade/empty paths are the proof (smoke 27-30); the live path is wired + documented for manual use. Honest gap, not a silent skip.
- **Propose-only is structural**, not just a label: the script has zero write calls; `git status` after a run shows no tool-created files. Bounded by `--cap` (200) + per-prompt truncation (300 chars) for cost.
- Impact: new `tools/cc-observe/bin/cc-semantic` + `tests/fixtures/semantic-llm-out.json`; smoke +4 (27-30); proof-of-done gained a `## cc-semantic` section.

## 2026-06-15 14:30 cc-vps-report: signing scheme is UTF-8 key bytes, NOT base64-decode
- Context: building the SG-05 bridge (`bin/cc-vps-report`) to POST a distilled digest to the live vps-mon and ping a heartbeat.
- Decision / Change: the HMAC key is the secret string's **UTF-8 bytes** (trimmed), not a base64-decode of it. `key_bytes(secret) = secret.strip().encode()`. Output is `"sha256=" + hex`.
- Why: `vps-mon/worker/src/hmac.ts::keyFromSecret` is literally `encoder.encode(secret.trim())`, and `vps_mon_agent.py::load_key` reads the key file's raw bytes rstrip'd. The wrangler.toml comment says "base64-decoded to raw bytes inside the Worker", that comment is **stale/wrong** for the live code. The SG-05 task brief inherited the same wrong assumption. Verified by reading hmac.ts + ingest.ts and cross-checking the signature two independent ways (python hmac == node crypto == cc-vps-report::sign_request) before any live POST. We still store a base64 string in the secret value (it is just opaque key material), but both sides UTF-8 it, so the base64-ness never enters the math.
- Alternatives considered: (a) base64-decode per the comment, rejected, would produce a signature the Worker rejects with a silent 401; (b) import vps_mon_agent.py, rejected, it is a root-owned host agent with a state dir + key file, wrong shape for a one-shot env-driven client.
- Impact: `bin/cc-vps-report`, `tests/test-vps-report.sh` (deterministic signer test gates the live call).

## 2026-06-15 14:35 personal mon-ingest had ZERO status_pages; created one
- Context: SG-05 says "pick the right status page slug by reading status_pages first". On the personal `mon-ingest` that table was empty (`/status` returned "no status pages configured"); the dwarves/icy/landing pages were seeded only on the OTHER (trading) instance via the UptimeRobot import.
- Decision / Change: created a new public status page `slug='ai-substrate'` (title "AI substrate") to host the cc-intel-weekly item, since `/status` renders nothing without a `status_pages` row + a `status_page_items` link. Slug matches the `channel='ai-substrate'` all the personal heartbeats already use.
- Why: it is the only way the digest liveness reaches the public `/status` page; the spec assumed a page existed.
- Alternatives considered: (a) reuse an existing slug, none existed; (b) only insert the heartbeat (no status page), rejected, the heartbeat would be swept + alertable but would NOT appear on `/status`, failing the SG-05 Done.
- Impact: live `vps-mon` D1 (additive: 1 status_pages row, 1 heartbeats row, 1 status_page_items row; all reversible by DELETE).

## 2026-06-15 14:40 bridge is best-effort in the launcher; needs a ~/.local/bin symlink
- Context: wiring `cc-intel-weekly` to call the bridge after the digest write.
- Decision / Change: the launcher dropped `exec` (it cannot append after exec), runs `cc-intel run` first, then a non-fatal `bridge_to_vps_mon`. The bridge no-ops (returns 0) if `op` is unavailable, if `~/.local/bin/cc-vps-report` is missing, or if either `op read` fails. A vps-mon outage must never fail the weekly digest (read-only producer).
- Why: the digest file is the must-not-regress behavior; delivery is best-effort.
- Impact: `tools/cc-intel/deploy/macos/cc-intel-weekly`. Deploy adds one symlink `ln -sf .../tools/cc-observe/bin/cc-vps-report ~/.local/bin/cc-vps-report` (documented in the cc-intel runbook). No launchd redeploy needed (the launcher path is unchanged; only its body changed), but a `launchctl kickstart -k gui/$(id -u)/cc-intel-weekly` proves it end to end.
