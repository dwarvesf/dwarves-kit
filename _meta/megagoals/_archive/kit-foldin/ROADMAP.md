# Mega-goal: kit-foldin

**Destination:** The ~14 `cc-*` / cc-elevation tools stop living as an ops-toolkit snapshot-deployed suite and become first-class dwarves-kit artifacts, each named by FUNCTION (no host-agent prefix) and placed by the decided taxonomy: settings.json-fired guards land in `hooks/`, transcript/session tools land in `tools/session-*` over a shared `lib/session/` parser, the skill self-improvement loop becomes `tools/skill-curator`, the adversarial claim panel becomes a real kit subagent `agents/claim-verifier.md`, and `lib/`'s ~32 flat files regroup into subsystem subdirs with a sibling-call resolution strategy that keeps every cross-subsystem call working (the rehomed runner-fastpath SG-09; a naive root-only shim false-greens , see the design note). The kit's `install.sh` wires the new hooks at its fixed path so ops-toolkit's `redeploy.sh` snapshot dance drops out for them. Personal/tenant-bound tools (`cc-money-gate`) stay in ops-toolkit; nothing tenant-specific enters the kit.

**Quality bar:** The kit reads like it was always one suite, not a dumping ground. Every moved tool keeps its tests green through the move and gains no new coupling to ops-toolkit paths (adapter defaults go repo-relative for kit-internal sources, opt-in-explicit for tenant sources , same discipline as the ledger-observatory move). Naming is boring and self-evident: a reader never has to know which agent a tool was born for. The `lib/` regroup breaks zero call-sites (the resolver survives every existing `bash "$DIR/x.sh"`), the full kit suite is the gate, and the ops-toolkit side is a clean HARD-REMOVE (`git rm` the moved code down to a `MOVED.md` tombstone; git history preserved), not a stub left rotting in place.

**Terminus:** non-deployable (a code-move + refactor + one new subagent across two repos). Build + merge IS the terminus , there is no daemon/service/UAT gate. The convergence gate is an integration check: re-run the kit's own `install.sh` into a temp HOME and confirm the 4 new hooks wire; confirm every moved tool's suite is green on merged master; grep both repos for dangling `cc-*`/old-path live-pointers. Deliberately no deploy/UAT sub-goal , stated here so the missing terminus is intentional, not forgotten.

**Stacking tool:** gh-sequential (cross-repo: dwarves-kit + ops-toolkit; each sub-goal its own branch off its repo's default, merged one at a time; paired-retire batched into ONE ops sweep to avoid a PR-per-tool explosion)
**Merge mode:** auto-bottom-up
**Merge autonomy:** gated-final
**Started:** 2026-07-05 (drafted; Han launches when runner-fastpath's SG-09 is confirmed rehomed)

## Sub-goals

- [x] 01-lib-regroup (dwarves-kit), regroup ~32 flat `lib/` files into subsystem subdirs (board/queue/gate/classify/spec/goal/telemetry/session) with a sibling-call resolution strategy (lib-root resolver OR per-subsystem shims, NOT root-only, which false-greens) + create empty `lib/session/` + `lib/README.md` nav; full kit suite green before AND after + `orchestrate.sh`/`mega-merge.sh` run post-move, `auto` (Design:bearing, opus), PR #187 merged d319f1c [strategy (b): per-subsystem + root compat shims]
- [x] 02-hooks-batch (dwarves-kit), land 4 cc-* guards into `hooks/{backlog-stage,citation-guard,context-hints,harvest}.sh` + wire each into `install.sh` + `hooks/hooks.json`; each fires correctly on fixture input, install-into-temp-HOME shows all 4 paths, `auto`, PR #186 merged 29e3127
- [x] 03-session-tools (dwarves-kit), `tools/session-observe` (3 bins) + `tools/session-recall` + `tools/session-intel` + extract the shared JSONL turn-parser to `lib/session/parse-transcript.sh` both CLIs call; run-table over fixture transcripts, honest-zero on empty, `auto`, PR #188 merged 0601249
- [x] 04-skill-curator (dwarves-kit), move cc-self-improve to `tools/skill-curator` (subtree minus `deploy/` which stays ops; rewrite RUNBOOK/MANUAL personal paths) + flip the one hardcoded `CC_SI_MEMORY_LEDGER` default (surface.sh) to opt-in + promote its embedded `skills/skill-review/` to top-level `skills/` (loader-mandated); existing 11 tests green post-move + missing-config = clean error NC, `auto`, PR #185 merged eb41df9
- [x] 05-plugin-check (dwarves-kit), move cc-plugin-check to `tools/plugin-check`; runs against a fixture plugin dir with a correct freshness verdict + stale-plugin NC, `auto`, PR #183 merged 44232b7
- [x] 06-claim-verifier (dwarves-kit), NEW `agents/claim-verifier.md` subagent redesigning verify-claim's N-parallel-`claude -p` skeptic panel as an in-harness fan-out (majority-vote, default-refute); frontmatter valid + smoke dispatch returns a structured verdict on a fixture claim, `auto`, PR #184 merged 3a00c80
- [x] 07-retire-sweep (ops-toolkit), paired HARD-REMOVE for ALL moved tools: `git rm` each moved cc-* code dir -> `MOVED.md` tombstone + `moved` MANIFEST row; same for `tools/meta-agent` (dup) + `cc-workflows` (dropped) + the already-moved `ledger-observatory` + `mega-runner` stubs (Han wants them gone); strip `redeploy.sh` of the now-kit-wired hooks; grep sweep for dangling live-pointers; git history preserved, `auto` (HELD as final PR), PR #720 merged 77bad048

## Dependencies

- 03 depends on 01 (needs `lib/session/` to exist before dropping `parse-transcript.sh` into it).
- 02, 04, 05, 06 depend on NOTHING (disjoint dirs: `hooks/`, `tools/skill-curator`, `tools/plugin-check`, `agents/` , they do not touch `lib/`, so they run parallel with 01).
- 07 depends on 01-06 ALL merged (it hard-removes the ops-toolkit copies only once every kit copy exists; fan-in, runs LAST, held for Han under gated-final).
- Only 02 touches `install.sh` (hook wiring + the `skills/*` copy-loop generalization); no two dwarves-kit sub-goals write the same file (checked: lib/ vs hooks/+install.sh vs tools/session-* vs tools/skill-curator+skills/skill-review vs tools/plugin-check vs agents/). 04 places `skills/skill-review/` but does NOT touch `install.sh` , 02's glob loop picks it up regardless of merge order, so they stay parallel (no hard dep).

## Assumptions (baked from the design note + Han's directives, 2026-07-05)

1. **Naming = by function, drop `cc-`; `session-` for transcript/session tools.** Decided in `research/2026-07-05-cc-elevation-kit-foldin-design.md` (Decision 1). Scope = kit only; ops-toolkit-resident personal cc- config (`cc-money-gate`) keeps its name.
2. **Structure = type-first (loader-mandated), subsystem-second only in `lib/` + `tools/`.** `agents/`, `commands/`, `hooks/` stay FLAT (loader/settings.json addresses them by path/namespace). Decision 2 of the design note. The `lib/` subsystem map is fixed there.
3. **`redeploy.sh` snapshot dance drops out for hooks-landing tools , BUT install.sh does not auto-register events** (advisor P5 correction). `install.sh` COPIES hook scripts to `~/.claude/dwarves-kit/hooks/<name>.sh` and MERGES the root `dwarves-kit/settings.json` into the consumer; it does NOT generate registrations. SG-02 must add the 4 event->command entries to root `settings.json` (kept in parity with `hooks/hooks.json`, per `tests/test-meta.sh`) BY HAND. Once registered there, re-running the installer wires them , THEN the ops snapshot is unnecessary for those four.
4. **Consumer seam = `--repo-root`/`REPO_ROOT` + `_repo_root()`, NOT `CONSUMER_ROOT`** (that phrase was a wrong earlier assumption; confirmed three times across runner-fastpath). Any moved tool that reads tenant config uses this seam.
5. **Adapter-default two-class split** (from SG-05K): kit-internal sources go repo-relative via the kit's own root; tenant-specific sources are required-explicit (missing config = clean error, never a silent wrong write).
6. **HARD-REMOVE + tombstone** (Han directive 2026-07-05, reverses the retire-stub convention for confirmed-moved tools). `git rm` the code dir, leave a 3-line `MOVED.md` (what+kit-path+SHA) + a `moved`/`abandoned` MANIFEST row. Safe because `git log --follow` never spans repos anyway (cross-repo move = delete+add, not a rename), so ops-toolkit git history preserves the past regardless; the stub bought nothing but a pointer, which `MOVED.md` keeps. Applies to the cc-* set AND the already-moved ledger-observatory + mega-runner (whose runner-fastpath 03R/05R stubs Han wants gone). Only remove a tool whose kit copy is confirmed-merged.
7. **cc-self-improve is clean**, one hardcoded default (`lib/surface.sh:9 CC_SI_MEMORY_LEDGER`), no hardcoded Hermes host; the personal deploy runbook stays ops-toolkit-side (deploy-follows-source).
8. **verify-claim has NO kit duplicate** (checked 5 verify-shaped agents by source); porting is a real fan-out REDESIGN (in-harness N-skeptic dispatch), not a file move. `tools/meta-agent` CLI IS a duplicate of `kit:meta-agent`, retire it.
9. **cc-worktree-provision + review-findings-memory DEFERRED** (off critical path / not built yet); logged in NOTES ## Proposed additions, not sub-goals here.
10. **runner-fastpath SG-09 rehomes here as SG-01.** runner-fastpath closes at 12/13 with SG-09 marked rehomed (not dropped); doing the `lib/` regroup once here avoids two passes over the same tree.

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read _ pr; do
      gh pr view "${pr#\#}" --json state,reviewDecision,statusCheckRollup
    done

(dwarves-kit PRs audit against the kit repo; SG-07 against ops-toolkit , run the loop from each sub-goal's own repo or pass `--repo`.)
