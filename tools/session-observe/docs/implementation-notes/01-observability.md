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
