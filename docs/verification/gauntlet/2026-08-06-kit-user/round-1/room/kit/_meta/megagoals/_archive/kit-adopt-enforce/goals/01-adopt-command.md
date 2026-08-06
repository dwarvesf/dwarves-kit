# Sub-goal 01: /kit:adopt command + classifier wiring

**Time budget:** 2-5 hours of loop work (full-lane dogfood adds ceremony on purpose)
**Depends on:** none
**Branch:** `feat/kit-adopt-01-cmd` (in `~/workspace/tieubao/dwarves-kit`)

## Outcome

Running one command from any target repo installs the dwarves-kit operate-contract into it and wires the classification machinery, so that repo's next agent reads "classify the work, pick a lane" before touching code, and a task in it resolves to the right test-design / proof-of-done / test-report shape by its loop type. The kit can seed a fresh repo in one step instead of the manual `cp AGENTS.md` tip.

## Quality bar

Idempotent and honest. Re-running is a no-op, not a duplicate-append mess. The command WIRES the classifiers that already exist (`lib/lane-classify.sh`, `lib/task-type-classify.sh`, `lib/proof-gate.sh`) into the adopted repo's flow; it does not reimplement classification or invent a new taxonomy. An adopted repo with no Claude Code is still left with a readable AGENTS.md (advisory under other runtimes, per the kit's honesty rule).

## How to close the loop

Built through the kit's OWN full lane (this is the dogfood). The gate-ledger must show the full sequence for this work:

    bash lib/gate-ledger.sh status <spec-slug>   # think, spec, spec-validate, execute, review, docs, ship all recorded ran

Functional verification, on a throwaway temp repo (never the real ones):

    TMP=$(mktemp -d); git -C "$TMP" init -q
    bash commands/adopt-driver-or-CLI "$TMP"          # whatever the command shells out to
    test -f "$TMP/AGENTS.md" && test -f "$TMP/WORKFLOW.md"        # contract landed
    grep -q -i 'AGENTS.md' "$TMP/CLAUDE.md"                       # loader pointer in CLAUDE.md
    bash commands/adopt-driver-or-CLI "$TMP"          # RE-RUN
    git -C "$TMP" diff --quiet && echo "idempotent: clean re-run"  # no second-run churn
    # loop-type wiring reachable from the adopted repo:
    (cd "$TMP" && bash "$OLDPWD/lib/proof-gate.sh" contract "benchmark tool X vs Y")  # -> names TEST-REPORT
    (cd "$TMP" && bash "$OLDPWD/lib/proof-gate.sh" contract "add a data-pull CLI command") # -> names a recorded live run

Plus the kit's existing suite stays green: `bash tests/test-meta.sh` (or the repo's `just test` / `make test`).

**Done =** `/kit:adopt <repo>` lands AGENTS.md + WORKFLOW.md (or a pointer) + a CLAUDE.md loader line in a fresh temp repo, a second run is a clean no-op, `proof-gate.sh contract` resolves two different task descriptions to two different artifacts from inside the adopted repo, the kit's own test suite passes, AND the gate-ledger records the full-lane gates for this sub-goal. PR open + CI green.

## Scope edges

**In:** a new `commands/adopt.md` (+ any thin driver under `lib/` it needs), the injection of AGENTS.md/WORKFLOW.md/CLAUDE.md-pointer, the wiring that makes lane/task-type/proof classification reachable from an adopted repo.
**Out:** install.sh changes (that is sub-goal 02), the fail-closed gate (02), adopting any real repo (03).
**Not:** rebuilding `lane-classify.sh` / `task-type-classify.sh` / `proof-gate.sh`; changing the lane set (tiny/normal/full/bug/backfill) or the proof-class taxonomy (inert/behavioral/stateful); a `--override` destructive mode beyond what `--merge` needs; multi-runtime portable enforcement (v3.x); a config DSL. Keep the command's surface small.

## Where to look

The kit's `commands/` (adopt joins `start.md` / `assign.md`; copy their front-matter + shape), `lib/` (the three classifiers + `gate-ledger.sh`), the root `AGENTS.md` + `WORKFLOW.md` (the contract being injected; read how they cross-reference), `docs/verification/{README,test-design-standard,task-types}.md` (the per-type shapes the wiring must expose). Branch into a worktree (kit is shared; never an in-place branch).

## PR body

Adds `/kit:adopt`: one command to install the operate-contract (AGENTS.md + WORKFLOW.md + a CLAUDE.md loader line) into a target repo and wire the existing lane/loop-type/proof classifiers so an adopted repo's task resolves to the right test-design/proof-of-done/test-report shape. Idempotent (--merge). Reuses lib/{lane-classify,task-type-classify,proof-gate}.sh; no new taxonomy.

Verify: see the close-the-loop block (temp-repo install + clean re-run + `proof-gate.sh contract` resolving two task types + `tests/test-meta.sh`). Built through the full lane; gate-ledger recorded.

Part of mega-goal kit-adopt-enforce (`ops-toolkit/_meta/megagoals/kit-adopt-enforce/ROADMAP.md`). First of three; 02 + 03 build on it.

## Notes

(empty)
