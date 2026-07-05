# Mega-goal: runner-fastpath

**Destination:** Simple tasks stop paying mega ceremony (a triage ladder at intake routes DIRECT-lane / single-goal / mega, mirrored skill<->kit), queued mega-goals drain unattended (`orchestrate.sh queue`, bash IN dwarves-kit: a LAUNCHER that drives the REAL Claude Code UI via tmux/cmux send-keys `/goal <pointer>` , NOT headless `claude -p` , with a line-anchored RUNNER_DONE/RUNNER_GATED completion contract, queue sourced from the cockpit boards, run on the Air via caffeinate+tmux + a runbook), and the whole cockpit becomes visible-and-steerable from the personal Hermes agent (the kit `board` command, `queue`/`mirror`/`writeback` in bash: opt-in boards + mega cards mirrored onto Hermes' native kanban, Hermes-side status moves flowing back as staged, reviewable git commits). The runner is a launcher, not a Go scheduler; board parsing lives once in bash (the kit `board` tool); DuckDB stays only in `ledger-observatory`, which ALSO moves into the kit (it reads gate-ledger data that already lives there; splitting the query engine from its data source across a repo boundary was the same anti-pattern just fixed for board/runner) and gains the `mega-durations` query. The whole harness suite (SDD + orchestrate + queue + board + ledger-observatory) ships as ONE kit; personal data stays ops-toolkit config the kit reads at runtime.
**Quality bar:** The runner is dumb on purpose: it never parses roadmaps, never merges, never touches git beyond status/pull/for-each-ref; all intelligence stays in the pointer contracts. The bridge is native-first absolutely (every Hermes access, reads AND writes, via `hermes kanban` CLI; SQLite ATTACH dropped per ADR-0001's own rationale) and one-writer-per-direction (SoT stays git; row-hash conflict rule, git wins; a missing snapshot means REFUSE ALL, never apply-everything). Behavioral sub-goals (03K, 04, 05, 07, 08) are OVER-TESTED with load-bearing negative controls; no real API/Hermes calls in test suites (stub-injected binaries); markers are line-anchored so quoted contract text can never false-trigger. Never-diverge holds for the triage ladder (skill <-> /kit:mega synced in the same run).
**Terminus:** deployable tools: build + merge closed by the convergence-gate demo (a live smoke queue run ON the Air in the prescribed caffeinate+tmux invocation producing a real journal, plus the FIRST live Hermes mirror, run twice so the second plan is empty, listing rendered in RUN_REPORT; per the advisor pass, no sub-goal touches the live Mini earlier). First real overnight run is Han's action, not this mega's.
**Stacking tool:** gh (stacked PRs, per-repo stacks)
**Merge mode:** auto-bottom-up
**Merge autonomy:** gated-final
**Started:** 2026-07-04 (drafted; Han launches tonight)

## Sub-goals

- [x] 01-triage-ladder, intake routing rule (DIRECT kit lane / single goal / mega) in goal-craft + plan-for-goal with a worked example per rung, `auto`, PR #202 merged b89f479
- [x] 02-mega-mirror-triage, /kit:mega mirror paragraph + never-diverge checklist row, wording identical to 01, `auto`, PR #175 merged fafad09
- [x] 03-runner-core, `tools/mega-runner` Go binary ... `auto`, PR #705 merged c43bcab **[SUPERSEDED 2026-07-05: duplicated dwarves-kit `lib/orchestrate.sh`; retired by 03R, replaced by 03K]**
- [x] 03R-retire-runner (ops-toolkit), mark `tools/mega-runner` `status=abandoned` in tool.toml + MANIFEST row + README pointer to the kit queue layer (repo retire convention, NOT a delete; preserves `git log --follow`), `auto`, PR #709 merged f3714a61
- [x] 03K-kit-queue (dwarves-kit), `orchestrate.sh queue` (bash) LAUNCHER: drain queued+tokened backlog megas overnight by driving the REAL Claude Code interface (tmux/cmux send-keys `/goal <pointer>` into a live session; Computer Use fallback) , NOT headless `claude -p` , + completion-marker monitor + journal + error-stops-night, `auto`, PR #178 merged 358373c
- [x] 04-board-tool (dwarves-kit), the `board` command (generic, config-driven): render/next/priority MIGRATED out of ops-toolkit `_meta/board`+`board-all` (now shims -> kit `board`, byte-identical) + `queue` emit (allow-listed, feeds 03K) + `lib/parse-board.sh`; reads `boards.txt` as CONSUMER config, `auto`, PR #176 merged 2694457 (+ paired ops-toolkit shim PR #711 merged 2622749)
- [ ] 05-mega-durations (ops-toolkit), observatory `mega-durations` query (per-rid wall time + phase split from kit_gates, honest-zero), `auto`, PR # **[SUPERSEDED 2026-07-05: ledger-observatory itself moves into the kit; retired by 05R, query built by 05K]**
- [x] 05R-retire-observatory (ops-toolkit), mark `tools/ledger-observatory` `status=moved` in tool.toml + MANIFEST row + README pointer banner to the kit path (retire convention, NOT a delete), `auto`, PR #710 merged bfa4d0a
- [x] 05K-observatory-to-kit (dwarves-kit), migrate the WHOLE `ledger-observatory` tool verbatim (src/tests/docs/skill/pyproject) into `tools/ledger-observatory/` + fix adapter defaults (kit-internal sources go repo-relative, ops-toolkit-specific sources go opt-in) + fold in the `harness-observatory` mega's doc tree + ADD the `mega-durations` query, `auto`, PR #177 merged 662a1fab
- [x] 06-deploy-runbook (ops-toolkit), Air runbook: run `orchestrate.sh queue` (kit) via caffeinate+tmux Phase 1 (launchd + Mini migration PARKED, triggers named) + live local smoke, `gate`, PR #712 merged 526a2bf (Han-authorised 2026-07-05, gate lifted)
- [x] 07-bridge-mirror (dwarves-kit), `board mirror` + `status` (bash, kit board tool): opt-in boards + one card per active mega -> Hermes kanban (target from config), `hermes kanban` CLI only, idempotent, incremental snapshot, `auto`, PR #179 merged c64ef47
- [x] 08-bridge-writeback (dwarves-kit), `board writeback` (bash): Hermes status moves -> staged BACKLOG.md commits via chore/board-sync PRs (v1 ops-toolkit board), row-hash git-wins, refuse-all-on-missing-snapshot, `gate`, PR #181 merged ba5e1dd (Han-authorised 2026-07-05, gate lifted)
- [~] 09-kit-layout (dwarves-kit), group `lib/` (32 flat files) into subsystem subdirs + `lib/README.md` nav map via a symlink shim (~0 runtime breakage; full test suite is the gate) **[REHOMED 2026-07-05 -> kit-foldin SG-01. NOT dropped: the lib/ regroup and the cc-* fold-in both rewrite lib/, so the taxonomy is decided once (research/2026-07-05-cc-elevation-kit-foldin-design.md) and executed once, in the kit-foldin mega. runner-fastpath therefore CLOSES at 12/13; this box stays `[~]` (rehomed), never `[x]` here.]**

## Dependencies (only if non-trivial)

- **Homes:** dwarves-kit = 03K, 04, 05K, 07, 08, 09 (kit-adopted; hand-made worktrees from `master`; gated). ops-toolkit = 03R, 05R, 06. Mega scaffold stays in ops-toolkit `_meta/megagoals/`.
- **03 (Go runner) SUPERSEDED:** 03R retires it (ops-toolkit); the runner role moves to 03K (kit, bash), which reuses the existing 1783-line `lib/orchestrate.sh` + `assign` + `backlog.sh`.
- **05 (mega-durations) SUPERSEDED:** `ledger-observatory` itself moves into the kit (05K, dwarves-kit), verbatim migration + adapter-default fix + the `harness-observatory` mega's doc tree, THEN gains the `mega-durations` query (the original ask). 05R retires the ops-toolkit copy (dep: 05K MERGED, needs its exact path + PR#). 05K has no dependency on 03K/04/07/08/09 (new `tools/` top-level, disjoint from `lib/`) and may run in wave 1 alongside them.
- **04 and 03K are largely parallel:** 04 EMITS the queue (`board queue`), 03K CONSUMES it; agree the queue-row format (`slug<TAB>repo<TAB>pointer`) up front so they compose. 03K also accepts a plain tsv.
- **07 depends on 04 MERGED** (reuses the kit `board` tool + `lib/parse-board.sh` + the `boards.txt` bridge opt-in column). 07 bases on `master`. **08 stacks on 07.**
- **06 depends on 03K MERGED** (the runbook runs `orchestrate.sh queue`).
- **09 (kit-layout) runs LAST**, after 03K/04/07/08 have MERGED their `lib/` additions, so the grouping+symlink-shim covers the final file set (else it collides on `lib/` paths). Its gate is the kit's full test suite green before+after.
- **CONSUMER-config seam (load-bearing):** the kit `board`/`queue`/`mirror` tools read the personal registry (`boards.txt`), bridge opt-ins, and Hermes target from ops-toolkit config via `CONSUMER_ROOT`/env; NO personal data (repo lists, Hermes host) is committed to dwarves-kit.
- **05's original unpark history (moot, superseded):** its blocker (gate-review-absorptions'
  04-review-yield-lens, ops PR #701) MERGED on origin (3b2221ed) and that mega closed out
  (#704), so 05 WAS clear to build on ops-toolkit main , kept here for the record. Superseded
  2026-07-05 before it ever dispatched real work: see the 05R/05K split above.
- **Cross-mega guard (launch):** gate-review-absorptions' auto lanes (01/02/05/06) all
  merged (`[x]` on its ROADMAP) AND that mega's RUN_REPORT.md exists OR its remaining
  03/04 PRs sit held awaiting Han (check `gh pr view`). Do NOT grep for the word "STOP";
  the terminal signal is the flipped boxes + RUN_REPORT/held-PR state. Its HELD 03/04
  PRs do NOT block this mega; only 05 above waits on one of them.

## Assumptions (front-loaded answers, baked at draft time)

1. **BASH runner in the kit, NOT a Go tool (Han-directed 2026-07-05, supersedes the original Go call):** the runner duplicated `dwarves-kit/lib/orchestrate.sh`, which already drives megas via unattended `claude -p` from bash (SPEC-087/ADR-0027). So the runner is a `queue` extension of `orchestrate.sh` (bash, kit), composing `backlog.sh` + `assign` + `orchestrate.sh run`. The Go `tools/mega-runner` (#705) is retired (03R). "Background tools = Go/Rust" yields to "the kit's non-LLM driver is bash, and this IS that driver." Full rationale: DECISIONS.md 2026-07-05 spine-change entry.
2. **The runner contract is output markers, not file sniffing:** `RUNNER_DONE` /
   `RUNNER_GATED: <reason>` as line-anchored final-message lines. Works for megas AND
   single goals; composes with launch guards (a guarded mega gates on turn 1, costing one
   iteration). RUN_REPORT sniffing rejected (mega-only, written before held merges anyway).
3. **Overnight permission posture is `--dangerously-skip-permissions`:** PreToolUse hooks
   (secret-guard, destructive-delete, commit-format) still fire headless; human gates are
   pointer contract, not permission prompts. Ratified by Han 2026-07-04
   (skip-permissions + hooks; runs on the AIR per his explicit call, Mini parked
   as the later always-on option).
4. **Runner never self-modifies mid-run:** the kit queue-launcher files are in no OTHER
   mega's Touches; a queue row whose pointer touches the runner is future Han's problem,
   noted in the runbook.
5. **Error-twice stops the WHOLE night** (assume account-level rate limit), sleep 30min
   between the two tries. Cheaper to under-run than to burn retries at 3am.
6. **launchd nightly stays PARKED** (minimum-infra): Phase 1 is a manual `tmux new -d`
   start per night; the journal's cost/duration columns are the data that justifies
   Phase 2, and 06's runbook names that trigger explicitly.
7. **Design sources are binding:** `research/2026-07-04-mega-runner-fastpath-design.md`
   (01-06) and `research/2026-07-04-board-hermes-bridge-design.md` (07-08), this repo.
   Workers read theirs before the sub-goal; do not re-litigate the contracts.
8. **Board + bridge are ONE bash `board` command IN THE KIT (Han-directed 2026-07-05):**
   `dwarves-kit` gains the `board` command (`queue`/`mirror`/`writeback` + migrated
   render), generic + config-driven; the kanban table is parsed once, in bash
   (`lib/parse-board.sh`). Personal data (`boards.txt`, Hermes target, opt-ins) stays in
   ops-toolkit config the kit reads at runtime. The bridge diff is a keyed comparison over
   dozens of rows (bash + `jq`), NOT analytics, so DuckDB is not needed and stays ONLY in
   `ledger-observatory`. Net: the whole harness suite (SDD + orchestrate + queue + board)
   ships as ONE kit; Python+DuckDB only for ledger analytics. Rationale: DECISIONS.md
   2026-07-05 entries (spine-change + board-to-kit).
9. **Notion (P2) and Hermes-as-runner-queue (P3) are NOT in this mega:** 07 keeps the
   adapter seam open; both ride NOTES Proposed additions. Writeback v1 is status moves
   on the ops-toolkit board only; extensions queue behind Han's 08 gate review.
10. **ledger-observatory moves into the kit too (Han-directed 2026-07-05, supersedes 05):**
    it reads `gate-ledger` data that already lives in the kit, so keeping the query engine
    ops-toolkit-side was the same engine/kit vs. data/ops-toolkit split this mega already
    fixed for board+runner. 05R (ops-toolkit) retires the old copy; 05K (dwarves-kit)
    migrates it verbatim (src/tests/docs/skill), fixes its adapter defaults (kit-internal
    sources go repo-relative now that they're co-located; ops-toolkit-specific sources
    tide/tg-cleanup/learned-ledger go opt-in via env var, no silent-wrong relative default),
    folds in the `harness-observatory` mega's doc tree (5 shipped lenses built on this tool),
    and adds the `mega-durations` query (the original SG-05 ask). Python+DuckDB stays the
    deliberate exception inside the kit (Assumption 8 unchanged); this does not reopen the
    bash-first call for board/runner. 05K has no dependency on 03K/04/07/08/09 (new `tools/`
    top-level, disjoint from `lib/`) and runs in wave 1.

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read pr; do
      gh pr view "${pr#PR #}" --json state,reviewDecision,statusCheckRollup
    done
