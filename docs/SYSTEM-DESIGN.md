---
rev: D
decided:
  - "Hermes stays reached by two bridges, kept as separate jobs: the cockpit mirror is the estate read-mirror over bridge=on boards, and the per-board sync spoke is the two-way sync for one board."
  - "Hooks of an off module are skipped in anchor-root.sh, so a plugin install honors [modules]."
  - "Adopted repos seed lane_gates and proof_of_done on; raw installs stay lenient."
  - "Lowering a run's lane needs --lower --reason; the verdict in the spec must match the run ledger."
---

# dwarves-kit

The kit is six clusters of bash, Python and prose commands that meet at a few shared stores. The spine (lane commands and their agents) moves one unit of work from intake to land. Gates and ledgers record and enforce what the spine did. Execution planes run many sessions at once. The board and signal path carries work items and proposals. Session and knowledge reads transcripts and distills them. Hooks wire all of it to Claude Code events and run the audit loops.

This model is a backfill. It maps the kit as the code stands on master, from a read-only pass with `path:line` evidence, spot-checked against the code. The planned workset module is the only amber element. Cluster colors hold on every sheet: spine blue, gates rose, planes violet, board green, hooks gray, session plain. Boxes marked «external» belong to another cluster or sit outside the kit.

## Use cases

Four actors drive the kit. The operator starts and lands work, the agent session runs the lane commands, a scheduler (launchd or cron) runs the unattended passes, and the Claude Code runtime fires hooks on its own events.

```uml
id: use-cases
type: usecase
title: Who drives the kit
level: L1
system: dwarves-kit
review:
  - The scheduler drives three passes (sweep, queue drain, reflect) with no operator in the loop. Is that the intended boundary, or should a sweep or a queue drain need an operator start?
  - Spec approval is the only operator step inside the plan band. Should Done (grill and phase 0) also need an explicit operator yes?
actors:
  - {id: operator, name: operator, kind: human, side: left, tone: blue}
  - {id: agent, name: agent session, kind: system, side: right, tone: violet}
  - {id: runtime, name: Claude Code runtime, kind: external, side: right, tone: green}
  - {id: scheduler, name: "scheduler (launchd, cron)", kind: system, side: right, tone: gray}
cases:
  - {id: start, name: Orient and pick next work, actor: operator, at: [0, 0]}
  - {id: think, name: Challenge and design an idea, actor: operator, at: [0, 1]}
  - {id: approve, name: Approve the spec, actor: operator, at: [0, 2]}
  - {id: assign, name: Assign a row to a goal, actor: agent, include: [grill], at: [1, 0]}
  - {id: grill, name: Grill and define Done, actor: agent, at: [1, 1]}
  - {id: spec, name: Write and validate a spec, actor: agent, at: [1, 2]}
  - {id: mega, name: Run a mega-goal roadmap, actor: operator, at: [0, 3]}
  - {id: hold, name: Release a held wave merge, actor: operator, at: [0, 4]}
  - {id: execute, name: Build a spec with verifiers, actor: agent, at: [1, 3]}
  - {id: dispatch, name: Fan out disjoint specs, actor: agent, at: [1, 4]}
  - {id: debug, name: Debug to root cause, actor: agent, at: [1, 5]}
  - {id: reverify, name: Re-verify a branch, actor: operator, at: [0, 6]}
  - {id: gauntlet, name: Probe an artifact clean-room, actor: operator, at: [0, 7]}
  - {id: review, name: Review a branch with lenses, actor: agent, at: [1, 6]}
  - {id: proof, name: Write the proof of done, actor: agent, at: [1, 7]}
  - {id: wrap, name: Land and wrap the session, actor: operator, at: [0, 8]}
  - {id: ship, name: Ship a PR, actor: agent, include: [gate], at: [1, 8]}
  - {id: gate, name: Gate a push or PR, actor: runtime, at: [1, 9]}
  - {id: promote, name: Promote staged rows, actor: operator, at: [0, 10]}
  - {id: adopt, name: Adopt a consumer repo, actor: operator, at: [0, 11]}
  - {id: guard, name: Guard every tool call, actor: runtime, at: [1, 10]}
  - {id: audit, name: Run an audit loop, actor: agent, at: [1, 11]}
  - {id: sweep, name: Sweep and mirror boards, actor: scheduler, at: [1, 12]}
  - {id: queue, name: Drain the overnight queue, actor: scheduler, at: [1, 13]}
  - {id: quiz, name: Answer the quiz tap, actor: operator, at: [0, 14]}
  - {id: harvest, name: Harvest learnings, actor: runtime, at: [1, 14]}
  - {id: reflect, name: Propose rows from ledgers, actor: scheduler, at: [1, 15]}
  - {id: recall, name: Recall a past session, actor: agent, at: [1, 16]}
bands:
  - {name: plan, rows: [0, 2]}
  - {name: build, rows: [3, 5]}
  - {name: verify, rows: [6, 7]}
  - {name: ship and land, rows: [8, 9]}
  - {name: operate, rows: [10, 13]}
  - {name: learn, rows: [14, 16]}
```

## V-model

Every artifact is checked twice: a static review when it is built (left arm, rose gates) and a dynamic test when it runs (right arm, green), paired level by level. Test design (`/kit:test-plan`) sits on the right arm in the command inventory, though it runs before the build.

```uml
id: v-model
type: component
title: The V-model, build and test
level: L1
caption: Blue is the left arm (build), green the right arm (test), rose the static quality gates (review, not test execution). Dashed green edges pair each right-arm verifier with the left-arm level it tests; rose edges show the static gate that reviews that level.
review:
  - "Lanes skip whole levels: tiny runs only build and review, bug starts at test-plan, backfill never builds. Is that the right floor, or should the bug lane also run design critique for a risky fix?"
  - "`/kit:execute` dispatches task, integration and acceptance verifiers, but system-verifier runs only from `/kit:verify`. Should execute run the system level on the full lane, so it is not on-demand only?"
lanes:
  - {id: gates, name: static quality gates, tone: rose}
nodes:
  - {id: bgate, name: brief-reviewer, note: "agent, clarity and testability", tone: rose, lane: gates, at: [0, 0]}
  - {id: dgate, name: /kit:devs-team, note: 5 lenses on the design, tone: rose, lane: gates, at: [0, 1]}
  - {id: sgate, name: /kit:spec-validate, note: "7 lenses, sets VALIDATED", tone: rose, lane: gates, at: [0, 2]}
  - {id: cgate, name: "/kit:review, review-team", note: "code, security and domain lenses", tone: rose, lane: gates, at: [0, 3]}
  - {id: battery, name: /kit:battery, note: "re-run, lenses, advisor", tone: rose, lane: gates, at: [0, 4]}
  - {id: brief, name: Brief, note: "/kit:think, assign, grill", tone: blue, at: [1, 0]}
  - {id: design, name: Design, note: "/kit:design, prototype", tone: blue, at: [2, 1]}
  - {id: spec, name: Spec, note: "/kit:spec", tone: blue, at: [3, 2]}
  - {id: execute, name: Execute, note: "/kit:execute, /kit:next", tone: blue, at: [4, 3]}
  - {id: builder, name: "builder, fix-agent", note: write-capable agents, tone: blue, at: [4, 4]}
  - {id: testplan, name: /kit:test-plan, note: "coverage matrix, test-write", tone: green, at: [3, 4]}
  - {id: task, name: task-verifier, note: "each task's criteria", tone: green, at: [5, 3]}
  - {id: recheck, name: recheck-verifier, note: re-audit of a sampled PASS, tone: green, at: [5, 4]}
  - {id: integ, name: integration-verifier, note: cross-task wiring, tone: green, at: [6, 2]}
  - {id: system, name: system-verifier, note: whole project suite, tone: green, at: [7, 1]}
  - {id: accept, name: acceptance-verifier, note: "spec Verification section", tone: green, at: [8, 0]}
edges:
  - {from: bgate, to: brief, label: reviews, tone: rose}
  - {from: dgate, to: design, label: reviews, tone: rose}
  - {from: sgate, to: spec, label: reviews, tone: rose}
  - {from: cgate, to: execute, label: reviews, tone: rose}
  - {from: battery, to: cgate, label: runs lenses, tone: rose}
  - {from: brief, to: design, tone: blue}
  - {from: design, to: spec, tone: blue}
  - {from: spec, to: execute, tone: blue}
  - {from: execute, to: builder, label: dispatches, tone: blue}
  - {from: testplan, to: builder, label: target matrix, tone: green}
  - {from: execute, to: task, tone: green}
  - {from: task, to: integ, tone: green}
  - {from: integ, to: system, tone: green}
  - {from: system, to: accept, tone: green}
  - {from: recheck, to: task, label: re-audits, tone: green}
  - {from: accept, to: brief, label: verifies, dashed: true, tone: green}
  - {from: system, to: design, label: verifies, dashed: true, tone: green}
  - {from: integ, to: spec, label: verifies, dashed: true, tone: green}
  - {from: task, to: execute, label: verifies, dashed: true, tone: green}
```

Which lanes run which levels, from the lane x phase depth matrix in `docs/WORKFLOW.md` (the human view of `[lane.*]` in `kit.toml`). Design covers the design critique too; spec covers validate.

| Lane | Brief | Design | Spec | Test plan | Build | Review | Ship |
|---|---|---|---|---|---|---|---|
| tiny | skip | skip | skip | skip | run-lite | run-lite | skip |
| normal | run-lite | skip | measure-twice | run-lite | measure-twice | measure-twice | measure-twice |
| full | measure-twice | measure-twice | measure-twice | measure-twice | measure-twice | measure-twice | measure-twice |
| bug | skip | skip | skip | run-lite | measure-twice | measure-twice | run-lite |
| backfill | run-lite | skip | run-lite | skip | skip | run-lite | skip |

The right arm has no lane columns of its own. `/kit:execute` dispatches the task, integration and acceptance verifiers inside every build, `/kit:verify` re-runs all four levels on demand, and the ship-gate enforces the lane's required phases only at push.

## How the clusters connect

The one-page answer: six clusters, five shared stores, and the outside systems they call. Only cluster-to-cluster and cluster-to-store edges are drawn, each labelled with its dominant verb; the component sheets that follow open each cluster.

```uml
id: context
type: component
title: How the clusters connect
level: L2
caption: Toned boxes are the six clusters (session is plain); boxes with a top band are shared stores; shaded «external» boxes sit outside the kit. Each edge carries its dominant verb only.
review:
  - Gates is the only cluster every other cluster writes into (through gate-ledger). Is one append-only ledger root the right single point of truth, or should planes keep their own journal outside it as the queue does today?
  - Board is the only core module beyond the spine; session, advisor and cosmetic are opt-in. Is that the right default for a fresh install?
nodes:
  - {id: runtime, name: Claude Code runtime, note: hook events, kind: ext, at: [1, 0]}
  - {id: transcripts, name: Claude Code transcripts, note: "~/.claude/projects/*.jsonl", kind: store, at: [3, 0]}
  - {id: kittoml, name: kit.toml layers, note: "project > operator > root", kind: store, at: [0, 1]}
  - {id: hooks, name: hooks and audit loops, note: "anchor-root, module table, config, adopt, audits", tone: gray, at: [1, 1]}
  - {id: session, name: session and knowledge, note: "recall, reflect, harvest, precedent", at: [3, 1]}
  - {id: claude, name: claude -p, note: "haiku, sonnet passes", kind: ext, at: [4, 1]}
  - {id: ledger, name: ledger root, note: "runs/<rid>.log, sibling logs", kind: store, at: [0, 3]}
  - {id: gates, name: gates and ledgers, note: "ship-gate, gate-ledger, proof, stats", tone: rose, at: [1, 3]}
  - {id: spine, name: spine and lanes, note: "assign, spec, execute, ship, wrap", tone: blue, at: [2, 3]}
  - {id: board, name: board and signal path, note: "backlog.sh, promote, sync, sweep", tone: green, at: [3, 3]}
  - {id: backlog, name: BACKLOG and staging, note: "BACKLOG.md, backlog-staging.md", kind: store, at: [4, 3]}
  - {id: docs, name: repo docs, note: "specs, briefs, proof, memory", kind: store, at: [0, 4]}
  - {id: hermes, name: Hermes kanban, kind: ext, at: [4, 4]}
  - {id: planes, name: execution planes, note: "orchestrate, queue, dispatch, gauntlet", tone: violet, at: [2, 5]}
  - {id: flickapi, name: Jev or Clef API, note: flick shadow pick, kind: ext, at: [4, 5]}
  - {id: gh, name: gh, note: "PRs, issues, merges", kind: ext, at: [1, 6]}
  - {id: workers, name: claude -p workers, note: "tmux session or headless", kind: ext, at: [2, 6]}
edges:
  - {from: runtime, to: hooks, label: fires events}
  - {from: hooks, to: kittoml, label: "seeds, reads"}
  - {from: hooks, to: gates, label: runs gate hooks}
  - {from: hooks, to: session, label: runs capture hooks}
  - {from: session, to: transcripts, label: reads}
  - {from: session, to: claude, label: LLM passes}
  - {from: session, to: backlog, label: stages proposals}
  - {from: spine, to: gates, label: records gates}
  - {from: spine, to: board, label: flips row status}
  - {from: spine, to: planes, label: "claims, fans out"}
  - {from: spine, to: session, label: "precedent, handoffs"}
  - {from: spine, to: docs, label: "writes spec, proof"}
  - {from: gates, to: ledger, label: appends}
  - {from: gates, to: kittoml, label: "reads [gate], [lane]"}
  - {from: planes, to: gates, label: "START, merge check"}
  - {from: planes, to: workers, label: spawns}
  - {from: planes, to: gh, label: merges PRs}
  - {from: board, to: planes, label: "queues #auto rows"}
  - {from: board, to: backlog, label: writes rows}
  - {from: board, to: hermes, label: mirrors cards}
  - {from: board, to: flickapi, label: shadow pick}
```

## Spine and lanes

The spine is prose commands plus a few classifiers. `/kit:assign` is the one mutator at intake; every other lane command records its own gate through gate-ledger (only the heaviest writers are drawn). The write agents (builder, fix-agent) are separate from the read-only verifiers on purpose.

```uml
id: c-spine
type: component
title: Spine and lanes
level: L2
review:
  - ship-gate compares the spec's `## Review` verdict with the one recorded in the run ledger, but the ledger is append-only, not tamper-proof: any writer can append a line. Should ledger writes be signed or fenced?
  - Seven commands write one spec file (replace-not-stack sections). Keep the single file, or split Review and Test plan into sibling files?
lanes:
  - {id: up, name: board and planes, tone: gray}
  - {id: plan, name: plan, tone: blue}
  - {id: build, name: build and verify, tone: blue}
  - {id: down, name: gates and docs, tone: gray}
  - {id: land, name: ship and land, tone: blue}
nodes:
  - {id: board, name: backlog.sh, note: board cluster, kind: ext, lane: up, at: [1, 0]}
  - {id: registry, name: goal-registry, note: planes cluster, kind: ext, lane: up, at: [2, 0]}
  - {id: start, name: /kit:start, note: read-only next-step detector, lane: plan, at: [0, 2]}
  - {id: assign, name: /kit:assign, note: "row to goal draft, START, claim", lane: plan, at: [1, 2]}
  - {id: think, name: "think, design, prototype", note: Decision Brief, lane: plan, at: [2, 2]}
  - {id: classify, name: classify libs, note: "lane, type, role, significance", lane: plan, at: [0, 3]}
  - {id: grill, name: /kit:grill, note: type-shaped interview, lane: plan, at: [1, 3]}
  - {id: spec, name: "spec, validate, test-plan", note: "SPEC-NNN, 7 reviewers", lane: plan, at: [2, 3]}
  - {id: execute, name: /kit:execute, note: "lane re-check, fix loop max 2", lane: build, at: [1, 5]}
  - {id: writers, name: builder and fix-agent, note: write-capable agents, lane: build, at: [2, 5]}
  - {id: verifiers, name: right-arm verifiers, note: "task, integration, acceptance, recheck", lane: build, at: [1, 6]}
  - {id: ledger, name: gate-ledger, note: gates cluster, kind: ext, lane: down, at: [3, 5]}
  - {id: docs, name: "spec, brief, verification log", note: repo docs, kind: store, lane: down, at: [3, 6]}
  - {id: ship, name: /kit:ship, note: "tests, version, PR", lane: land, at: [0, 8]}
  - {id: review, name: "review-team, battery", note: "## Review verdict", lane: land, at: [1, 8]}
  - {id: lenses, name: lenses and advisor, note: "security, code, domain, break-it", lane: land, at: [2, 8]}
  - {id: wrap, name: /kit:wrap and bin/wrap, note: "land, merge, tidy, distill", lane: land, at: [0, 9]}
edges:
  - {from: start, to: assign, label: suggests}
  - {from: assign, to: board, label: "next, set claimed"}
  - {from: assign, to: registry, label: claim}
  - {from: assign, to: grill, label: Q&A digest}
  - {from: assign, to: think, label: freeform intent}
  - {from: assign, to: classify, label: "type, lane"}
  - {from: think, to: spec, label: brief}
  - {from: spec, to: execute, label: VALIDATED spec}
  - {from: spec, to: ledger, label: validate round}
  - {from: execute, to: writers, label: dispatches}
  - {from: execute, to: verifiers, label: dispatches}
  - {from: verifiers, to: writers, label: "FAIL:fixable"}
  - {from: execute, to: classify, label: "escalate, agent-for"}
  - {from: execute, to: ledger, label: record build}
  - {from: verifiers, to: docs, label: verification log}
  - {from: verifiers, to: review, label: suggests review}
  - {from: review, to: lenses, label: dispatches}
  - {from: review, to: docs, label: writes Review}
  - {from: ship, to: review, label: reads verdict}
  - {from: ship, to: wrap, label: wrap land}
  - {from: ship, to: ledger, label: record Ship}
```

## Gates and ledgers

Two hooks do most of the stopping: safety-gate (always on) and ship-gate (per `[gate]` key). Other policy hooks block too; `docs/hard-rules.tsv` lists every rule code blocks on. Ship-gate composes push-refs, ship-rules, the config readers and two ledgers. Every writer appends through one substrate, `lib/ledger/ledger.sh`, which resolves the ledger root; the read plane recomputes from those files and persists nothing.

```uml
id: c-gates
type: component
title: Gates and ledgers
level: L2
review:
  - Spec-drift and descent only warn, even in an adopted repo where `lane_gates` and `proof_of_done` are on. Should either block once a repo is adopted?
  - ship-gate closes on an unloadable ship-rules, an unaccounted push or a missing Lane in an adopted repo, and opens when no kit lib exists. Should the no-lib case also close once the kit is installed?
nodes:
  - {id: safety, name: safety-gate, note: "always on: deletes, main push", tone: rose, at: [0, 0]}
  - {id: shipgate, name: ship-gate, note: "PreToolUse Bash, exit 2 blocks", tone: rose, at: [1, 0]}
  - {id: rules, name: "push-refs, ship-rules", note: "refs, base, floor, identities", tone: rose, at: [2, 0]}
  - {id: classify, name: lane-classify, note: spine cluster, kind: ext, at: [3, 0]}
  - {id: hooklogs, name: hook logs, note: "<ledger root>/hooks/", kind: store, at: [0, 1]}
  - {id: gateledger, name: gate-ledger, note: "start, record, check, outcome, debt", tone: rose, at: [1, 1]}
  - {id: proof, name: "proof-ledger, proof-gate, negctl", note: "proof class, check, override", tone: rose, at: [2, 1]}
  - {id: verif, name: docs/verification, note: proof files and marker, kind: store, at: [3, 1]}
  - {id: policyhooks, name: policy hooks, note: "anti-rationalization, commit, board-row, money", tone: rose, at: [0, 2]}
  - {id: substrate, name: ledger substrate, note: "ledger.sh, kit-log-dir.sh, hook-log-dir.sh", tone: rose, at: [1, 2]}
  - {id: advisory, name: advisory gates, note: "quiz-gate, coverage-delta, mutation-smoke, redteam", tone: rose, at: [2, 2]}
  - {id: megamerge, name: mega-merge, note: planes cluster, kind: ext, at: [3, 2]}
  - {id: config, name: "gate-policy, lane-data", note: the two kit.toml readers, tone: rose, at: [0, 3]}
  - {id: ledgerroot, name: ledger root, note: "runs/, proof-overrides, completeness", kind: store, at: [1, 3]}
  - {id: readplane, name: "lane-telemetry, stats", note: "in-memory DuckDB, persists nothing", tone: rose, at: [2, 3]}
  - {id: staging, name: backlog staging, note: board cluster, kind: store, at: [3, 3]}
  - {id: kittoml, name: kit.toml layers, kind: store, at: [0, 4]}
  - {id: spine, name: spine commands, note: spine cluster, kind: ext, at: [1, 4]}
edges:
  - {from: shipgate, to: rules, label: parse refs}
  - {from: rules, to: classify, label: hard-path floor}
  - {from: shipgate, to: gateledger, label: "check lane, outcome"}
  - {from: shipgate, to: proof, label: check proof}
  - {from: shipgate, to: hooklogs, label: "BLOCKED, ALLOWED"}
  - {from: shipgate, to: config, label: enabled key --at base}
  - {from: safety, to: hooklogs, label: BLOCKED}
  - {from: substrate, to: hooklogs, label: resolves dir}
  - {from: policyhooks, to: config, label: enabled key}
  - {from: config, to: kittoml, label: "[gate], [lane.*]"}
  - {from: gateledger, to: config, label: required gates}
  - {from: gateledger, to: substrate, label: ledger_append}
  - {from: proof, to: substrate, label: overrides}
  - {from: proof, to: verif, label: reads fresh proof}
  - {from: substrate, to: ledgerroot, label: appends}
  - {from: spine, to: gateledger, label: "START, GATE, OUTCOME"}
  - {from: megamerge, to: gateledger, label: check}
  - {from: advisory, to: gateledger, label: "DEBT, GATE, MUTATION"}
  - {from: readplane, to: ledgerroot, label: reads runs}
  - {from: readplane, to: staging, label: anomalies --propose}
```

## Execution planes

Four engines run agents: the orchestrator (one fresh `claude -p` per sub-goal, serial or in waves), the overnight queue (an interactive session in a tmux window), `/kit:dispatch` (Agent-tool workers in worktrees) and the gauntlet (a clean-room probe in docker). They share the dispatch-gate disjointness check and the goal registry, not code.

```uml
id: c-planes
type: component
title: Execution planes
level: L2
review:
  - No code caps `/kit:dispatch` workers; `WAVE_CAP` of 2 limits waves only. Should `dispatch-gate plan` enforce a cap?
  - The queue works in the real checkout with `--dangerously-skip-permissions` and detects protected-path writes only after the run. Move it to a worktree like the wave sessions?
nodes:
  - {id: mega, name: /kit:mega, note: "ROADMAP, goals/NN-*.md", tone: violet, at: [0, 0]}
  - {id: orchestrate, name: orchestrate.sh, note: "waves, converge, tier-4 close", tone: violet, at: [1, 0]}
  - {id: megamerge, name: mega-merge, note: "gate, merge, mark", tone: violet, at: [2, 0]}
  - {id: gh, name: gh, note: "PR view, squash merge", kind: ext, at: [3, 0]}
  - {id: dispatchgate, name: dispatch-gate, note: "Touches disjointness, drift", tone: violet, at: [1, 1]}
  - {id: handoffgen, name: handoff-gen, note: transcript to HANDOFF.md, tone: violet, at: [2, 1]}
  - {id: claude, name: "claude -p, vendor CLIs", note: headless workers, kind: ext, at: [3, 1]}
  - {id: dispatch, name: /kit:dispatch, note: one worker per spec, tone: violet, at: [0, 2]}
  - {id: registry, name: "goal-registry, wt", note: "claim, log, release", tone: violet, at: [1, 2]}
  - {id: ledger, name: gate-ledger, note: gates cluster, kind: ext, at: [2, 2]}
  - {id: gauntlet, name: "/kit:gauntlet, clean-room", note: docker probe per round, tone: violet, at: [3, 2]}
  - {id: attempts, name: attempt-state, note: task and attempt machine, tone: violet, at: [0, 3]}
  - {id: agenttool, name: Agent tool, note: "background, worktree", kind: ext, at: [1, 3]}
  - {id: watch, name: watch-board, note: "#auto rows, reaper", tone: violet, at: [0, 4]}
  - {id: queue, name: queue.sh, note: "tmux window, types /goal", tone: violet, at: [1, 4]}
  - {id: journal, name: queue journal, note: "queue-journal.tsv, sidecars", kind: store, at: [2, 4]}
  - {id: board, name: parse-board, note: board cluster, kind: ext, at: [0, 5]}
  - {id: tmux, name: tmux, kind: ext, at: [1, 5]}
edges:
  - {from: mega, to: orchestrate, label: run <dir>}
  - {from: orchestrate, to: megamerge, label: "per landed PR, merge-dry-run"}
  - {from: megamerge, to: gh, label: "squash merge, pr view"}
  - {from: orchestrate, to: dispatchgate, label: wave admission}
  - {from: orchestrate, to: handoffgen, label: "turn cap, usage"}
  - {from: orchestrate, to: claude, label: spawns}
  - {from: orchestrate, to: ledger, label: "START, TOKENS"}
  - {from: gauntlet, to: ledger, label: "outcome, record"}
  - {from: dispatch, to: dispatchgate, label: "plan, drift"}
  - {from: dispatch, to: registry, label: claim}
  - {from: dispatch, to: attempts, label: dispatch}
  - {from: dispatch, to: agenttool, label: worker per spec}
  - {from: registry, to: dispatchgate, label: overlap check}
  - {from: watch, to: queue, label: queue run plan}
  - {from: watch, to: board, label: queue-rows}
  - {from: queue, to: journal, label: "appends verdict, no-delta"}
  - {from: queue, to: tmux, label: send-keys /goal}
```

## Board and signal path

`backlog.sh` owns the row grammar and the only lock-held status flip. Proposers never write the board: they append `[staged]` blocks, and `board promote` is the human gate that turns a block into a `queued` row. A scheduled sweep syncs spokes, publishes, and mirrors rows to Hermes kanban; writeback turns a card move into a held PR.

```uml
id: c-board
type: component
title: Board and signal path
level: L2
review:
  - Rows go through `backlog.sh add` and the kit board is lint-clean after `board normalize`. Should lint run in CI so a hand edit cannot reintroduce short rows?
  - Writeback collapses four card states to `ready`, and a closed held PR is never re-proposed. Keep that, or map the states one to one?
nodes:
  - {id: proposers, name: proposers, note: "stats, reflect, session-audit, hooks", kind: ext, at: [0, 0]}
  - {id: format, name: staging-format, note: "grammar, staging_lock, .jq twin", tone: green, at: [1, 0]}
  - {id: parse, name: parse-board, note: "#queue{} allow-list", tone: green, at: [2, 0]}
  - {id: queue, name: "watch-board, queue", note: planes cluster, kind: ext, at: [3, 0]}
  - {id: spokes, name: spoke apps, note: "gh issues, Notion, Reminders, Multica", kind: ext, at: [4, 0]}
  - {id: staging, name: backlog-staging.md, note: "## [staged] blocks", kind: store, at: [1, 1]}
  - {id: cli, name: board CLI, note: board.sh dispatcher, tone: green, at: [2, 1]}
  - {id: sweep, name: board-sweep, note: "sync, digest, publish, mirror", tone: green, at: [3, 1]}
  - {id: sync, name: sync engine, note: "hub and spokes, 3-way merge", tone: green, at: [4, 1]}
  - {id: spine, name: "assign, wrap, audits", note: spine and hooks clusters, kind: ext, at: [0, 2]}
  - {id: promote, name: board promote, note: "calls add, 3 refusals", tone: green, at: [1, 2]}
  - {id: backlogsh, name: backlog.sh, note: "add, next, get, set, dedupe", tone: green, at: [2, 2]}
  - {id: mirror, name: mirror and writeback, note: "snapshot, held PR", tone: green, at: [3, 2]}
  - {id: hermes, name: Hermes kanban, kind: ext, at: [4, 2]}
  - {id: backlog, name: BACKLOG.md, note: "pipe table, Status column", kind: store, at: [2, 3]}
  - {id: flick, name: flick, note: wrap 7b shadow pick, tone: green, at: [0, 4]}
  - {id: jev, name: Jev or Clef API, kind: ext, at: [1, 4]}
edges:
  - {from: proposers, to: format, label: render_block}
  - {from: format, to: staging, label: appends under lock}
  - {from: promote, to: staging, label: reads, rewrites}
  - {from: promote, to: backlogsh, label: add queued row}
  - {from: cli, to: promote, label: promote}
  - {from: cli, to: backlogsh, label: "board, set"}
  - {from: cli, to: parse, label: queue-rows}
  - {from: backlogsh, to: backlog, label: add, set under lock}
  - {from: spine, to: backlogsh, label: "add, next, set state"}
  - {from: spine, to: flick, label: step 7b}
  - {from: queue, to: parse, label: board queue}
  - {from: sweep, to: cli, label: "sync, publish, mirror"}
  - {from: sweep, to: sync, label: per registry row}
  - {from: sync, to: spokes, label: "read, apply"}
  - {from: sync, to: backlog, label: spoke flips}
  - {from: sweep, to: mirror, label: mirror tick}
  - {from: mirror, to: hermes, label: hermes kanban}
  - {from: flick, to: jev, label: HTTPS pick}
```

## Session and knowledge

This cluster turns transcripts and ledgers into staged proposals, ledger rows and memory notes, and answers "done before?". Every LLM pass here fails open and exits 0, and a failed call lands in `egress-failures.log`, so an outage shows up there instead of reading as "nothing learned".

```uml
id: c-session
type: component
title: Session and knowledge
level: L2
review:
  - harvest and transcript.sh need `python3` for the shared parser. Check for it at install time, or keep the hooks fail-open?
  - "`session recall`, `handoffs.sh`, `explain.sh` and `pitch.sh` have no `bin/` forwarder, so callers use raw lib paths. Add forwarders before the workset module depends on two of them?"
nodes:
  - {id: transcripts, name: transcripts, note: "~/.claude/projects/*.jsonl", kind: store, at: [0, 0]}
  - {id: harvest, name: harvest hook and sweep, note: "PreCompact, 6h sweep, shared parser", at: [1, 0]}
  - {id: learned, name: learned-ledger.md, note: queued learnings, kind: store, at: [2, 0]}
  - {id: claude, name: claude -p, note: "haiku, sonnet", kind: ext, at: [3, 0]}
  - {id: recallcli, name: session recall, note: "--sessions, --tail", at: [0, 1]}
  - {id: stagehooks, name: stage hooks, note: "backlog-stage, intake-sweep", at: [1, 1]}
  - {id: curator, name: skill-curator, note: "drafts SKILL.md, human promote", at: [3, 1]}
  - {id: observe, name: "observe, intel, audit", note: "usage, weekly digest, deep audit", at: [0, 2]}
  - {id: staging, name: backlog staging, note: board cluster, kind: store, at: [1, 2]}
  - {id: reflect, name: reflect, note: "propose, drain, debt", at: [2, 2]}
  - {id: gates, name: "stats, run ledger", note: gates cluster, kind: ext, at: [3, 3]}
  - {id: handoffs, name: handoffs.sh, note: "list LIVE, DEAD; archive", at: [0, 4]}
  - {id: wrapdistill, name: wrap distill, note: "steps 1b, 7, 8", at: [1, 4]}
  - {id: precedent, name: "precedent, prose-rag", note: done before?, at: [2, 4]}
  - {id: memory, name: ".claude/memory, handoffs", note: repo-committed, kind: store, at: [3, 4]}
  - {id: explain, name: "explain, pitch, retro", note: grounded write-ups, at: [1, 5]}
  - {id: memtidy, name: memory-tidy, note: "memory-sweep, PR-gated", at: [3, 5]}
edges:
  - {from: recallcli, to: transcripts, label: reads}
  - {from: observe, to: transcripts, label: reads}
  - {from: harvest, to: transcripts, label: reads tail}
  - {from: harvest, to: learned, label: appends queued}
  - {from: harvest, to: claude, label: haiku}
  - {from: stagehooks, to: staging, label: stages}
  - {from: observe, to: staging, label: intel stages}
  - {from: reflect, to: staging, label: stages}
  - {from: reflect, to: gates, label: stats lenses}
  - {from: reflect, to: claude, label: sonnet}
  - {from: curator, to: claude, label: reviewer}
  - {from: wrapdistill, to: handoffs, label: "list, archive"}
  - {from: wrapdistill, to: precedent, label: find per candidate}
  - {from: wrapdistill, to: explain, label: retro call}
  - {from: wrapdistill, to: memory, label: incident note}
  - {from: precedent, to: memory, label: reads notes}
  - {from: precedent, to: gates, label: reads reasons}
  - {from: memtidy, to: memory, label: PR-gated edits}
```

## Hooks runtime

Every wired hook runs through `anchor-root.sh` (secrets-guard is the one exception), which also skips a hook whose module is off. The gate hooks live in the gates cluster and the capture hooks in session; this sheet holds the wiring, config, consumer install and the context hooks.

```uml
id: c-hooks
type: component
title: Hooks runtime and config
level: L2
review:
  - "`hooks.json` registers every hook and `anchor-root.sh` skips the ones whose module is off. Generate `hooks.json` per module, or accept one bash start per skipped hook?"
  - Migration of old logs runs at install and adopt only, so a plugin-only machine that never runs either keeps its old logs and sees a stderr note. Is the note enough, or should `/kit:start` offer the migration?
nodes:
  - {id: runtime, name: Claude Code runtime, note: event JSON on stdin, kind: ext, at: [0, 0]}
  - {id: anchor, name: anchor-root.sh, note: cd to repo root then exec, tone: gray, at: [1, 0]}
  - {id: pretool, name: PreToolUse guards, note: "secrets, tool-policy, spec-drift", tone: gray, at: [2, 0]}
  - {id: manifests, name: hook manifests, note: "hooks.json, settings.json", kind: store, at: [0, 1]}
  - {id: context, name: context hooks, note: "readiness, reinject, hints, budget", tone: gray, at: [2, 1]}
  - {id: codex, name: codex adapter, note: 5 hooks for Codex, tone: gray, at: [0, 2]}
  - {id: conv, name: convenience hooks, note: "format, offload, notify, approve", tone: gray, at: [2, 2]}
  - {id: snapshots, name: snapshot hooks, note: pre-compact backup, tone: gray, at: [2, 3]}
  - {id: statedirs, name: session state, note: ".claude/session-state, backups", kind: store, at: [3, 3]}
  - {id: gatehooks, name: gate hooks, note: gates cluster, kind: ext, at: [2, 4]}
  - {id: capture, name: capture hooks, note: session cluster, kind: ext, at: [2, 5]}
  - {id: configcli, name: bin/config, note: "list, get, explain, seams", tone: gray, at: [0, 6]}
  - {id: kitconfig, name: kit-config.sh, note: the only TOML reader, tone: gray, at: [1, 6]}
  - {id: kittoml, name: kit.toml layers, kind: store, at: [0, 7]}
  - {id: adopt, name: "adopt, onboard, install.sh", note: "consumer wiring, reads modules.tsv", tone: gray, at: [1, 7]}
  - {id: hookmodule, name: hook-module.sh, note: "off when [modules] says false", tone: gray, at: [1, 1]}
  - {id: modtable, name: modules.tsv, note: "module table: hooks, CLIs, default", kind: store, at: [1, 2]}
  - {id: consumer, name: consumer repo, note: "AGENTS.md, .claude/settings.json", kind: store, at: [2, 7]}
edges:
  - {from: runtime, to: anchor, label: fires}
  - {from: runtime, to: manifests, label: reads wiring}
  - {from: anchor, to: hookmodule, label: module on?}
  - {from: anchor, to: pretool, label: exec each family}
  - {from: anchor, to: context}
  - {from: anchor, to: conv}
  - {from: anchor, to: snapshots}
  - {from: anchor, to: gatehooks}
  - {from: anchor, to: capture}
  - {from: codex, to: gatehooks, label: dispatches 5}
  - {from: snapshots, to: statedirs, label: writes}
  - {from: context, to: statedirs, label: reads backup}
  - {from: configcli, to: kitconfig, label: get}
  - {from: kitconfig, to: kittoml, label: "project > operator > root"}
  - {from: hookmodule, to: modtable}
  - {from: hookmodule, to: kittoml, via: [[0.5, 1], [0.5, 7]]}
  - {from: adopt, to: kitconfig, label: module toggles}
  - {from: adopt, to: consumer, label: writes contract}
  - {from: adopt, to: kittoml, label: seeds .kit.toml}
```

## Audit loops

Split from the hooks sheet to keep both readable. Each audit skill gathers mechanically (Tier 1), hands the evidence to the read-only audit-scanner agent (Tier 2), applies only its one allowed mutation, and appends a cadence marker.

```uml
id: c-audit
type: component
title: Audit loops
level: L2
review:
  - Nothing schedules an audit; `bin/audit due` only reports age. Wire a cadence job, or keep audits operator-started?
  - Audit skills file rows through `backlog.sh add`, so a noisy audit can flood a board. Add a per-run row cap?
nodes:
  - {id: runs, name: audit-runs.log, note: ledger root, kind: store, at: [0, 0]}
  - {id: trigger, name: operator or schedule, kind: ext, at: [1, 0]}
  - {id: cadence, name: Cadence table, note: docs/patterns/audit-loop.md, kind: store, at: [2, 0]}
  - {id: ghapi, name: gh api, note: "workflows, secrets, runs", kind: ext, at: [0, 1]}
  - {id: audit, name: bin/audit, note: "due, cadences, ran", tone: gray, at: [1, 1]}
  - {id: worktree, name: worktree PR, note: the operator merges, kind: ext, at: [2, 1]}
  - {id: webcheck, name: webcheck, note: "stdlib HTTP probe, public sites", tone: gray, at: [0, 2]}
  - {id: skills, name: audit skills, note: "doc, ci, web, topology, repo, backlog, gauntlet, memory", tone: gray, at: [1, 2]}
  - {id: scanner, name: audit-scanner, note: "read-only judge, sonnet", tone: gray, at: [2, 2]}
  - {id: backlog, name: backlog.sh, note: board cluster, kind: ext, at: [0, 3]}
  - {id: hygiene, name: repohygiene.sh, note: 5 detectors, tone: gray, at: [1, 3]}
  - {id: registry, name: feature-registry, note: generate and cmp, tone: gray, at: [2, 3]}
edges:
  - {from: trigger, to: audit, label: due?}
  - {from: audit, to: runs, label: reads ages}
  - {from: audit, to: cadence, label: parses}
  - {from: skills, to: audit, label: ran <instance>}
  - {from: skills, to: scanner, label: evidence chunks}
  - {from: skills, to: webcheck, label: sites audit}
  - {from: skills, to: hygiene, label: scan}
  - {from: skills, to: registry, label: generate}
  - {from: skills, to: backlog, label: "set state, rows"}
  - {from: skills, to: worktree, label: opens PR}
  - {from: skills, to: ghapi, label: ci-drift reads}
```

## Workset (planned)

Planned: a workset is a whole work stream (one or more sessions, browser tabs, a handoff, refs to rows and PRs) that can be parked and restored. It sits beside session and board and reuses their reads rather than adding stores of its own beyond one file per workset. Everything on this sheet is amber because none of it exists in the kit yet.

```uml
id: c-workset
type: component
title: Workset beside session and board
level: L2
review:
  - Workset reads `session recall` and `handoffs.sh` through raw lib paths today. Add `bin/` forwarders as part of the fold?
  - The terminal launcher and the browser are host adapters. Ship the fold with both behind a config seam, or with the browser leg off?
lanes:
  - {id: host, name: host adapters and outside, tone: gray}
  - {id: ws, name: workset (planned), tone: amber}
  - {id: session, name: session cluster, tone: gray}
  - {id: board, name: board and planes, tone: gray}
nodes:
  - {id: launcher, name: terminal launcher, note: resumes a session, kind: ext, lane: host, at: [0, 0]}
  - {id: browser, name: Chromium browser over CDP, note: "list, open, close tabs", kind: ext, lane: host, at: [0, 1]}
  - {id: gh, name: gh, note: PR state, kind: ext, lane: host, at: [0, 4]}
  - {id: files, name: workset files, note: "one JSON per workset, machine-local", kind: store, tone: amber, lane: ws, at: [1, 0]}
  - {id: cli, name: workset CLI, note: "scan, park, brief, restore, close-tabs", tone: amber, lane: ws, at: [1, 1]}
  - {id: brief, name: brief, note: "live PR and row state, next step", tone: amber, lane: ws, at: [1, 2]}
  - {id: transcripts, name: transcripts, kind: store, lane: session, at: [2, 0]}
  - {id: recall, name: session recall, note: "--sessions, --tail", kind: ext, lane: session, at: [2, 1]}
  - {id: handoffs, name: handoffs.sh, note: "list, archive", kind: ext, lane: session, at: [2, 2]}
  - {id: backlogsh, name: backlog.sh get, note: row lookup, kind: ext, lane: board, at: [1, 4]}
  - {id: registry, name: goal-registry, note: who holds a worktree, kind: ext, lane: board, at: [2, 4]}
edges:
  - {from: cli, to: files, label: "writes, reads", tone: amber}
  - {from: cli, to: launcher, label: restore, tone: amber}
  - {from: cli, to: browser, label: tabs, tone: amber}
  - {from: cli, to: recall, label: finds sessions, tone: amber}
  - {from: recall, to: transcripts, label: reads}
  - {from: cli, to: handoffs, label: "reads, archives", tone: amber}
  - {from: cli, to: registry, label: claims, tone: amber}
  - {from: cli, to: brief, label: before restore, tone: amber}
  - {from: brief, to: backlogsh, label: row status, tone: amber}
  - {from: brief, to: gh, label: PR state, tone: amber}
```

## Ledger stores

The ledger root holds append-only text, one physical line per event. Every `runs/<rid>.log` line goes through `gate-ledger.sh` and `ledger_append`; only a GATE line with `ran` or `override` satisfies `check`, and every other line type is additive. The rid is the branch slug with its `type/` prefix stripped. Writers and readers per table:

- `runs/<rid>.log`: written by gate-ledger verbs (called by the spine commands, orchestrate, wt.sh, quiz-gate, significance-classify, coverage-delta, mutation-smoke, weekend-batch, harvest sweep). Read by ship-gate, mega-merge, lane-telemetry, stats, weekend-batch, batch-debt-warn, precedent, pitch, the mega projections and reflect.
- `proof-overrides.log`: written by `proof-ledger override` (operator, wrap-adopt, agents on docs paths). Read only by `proof-ledger is-overridden`.
- `completeness.log`: written by `lane-classify check` on a downgrade. Read by `lane-telemetry misfires`.
- `queue-journal.tsv`: written by queue.sh and the watch-board reaper. Read by watch-board dedup and `queue wait`.
- `audit-runs.log`: written by `audit ran`. Read by `audit due`.
- `merge-watch/<sid>.log` and the two `.cache` files: written and read by the one tool that owns each (batch-debt-warn, gate-ledger `check`, lane-telemetry).

```uml
id: erd-ledgers
type: erd
title: Ledger root stores
level: L3
review:
  - "`proof-overrides.log` keys on repo-id plus slug while runs key on rid. Should an override also land as a GATE override line in the run, so one file answers \"why did this ship\"?"
  - The check cache trusts file stat for 2 seconds. Acceptable, or key it on content hash?
tables:
  - name: START line
    at: [0, 0]
    cols: [[ts], [kind, "START | START-AMEND"], [lane], [classified], [type], [ctype, NULL], [repo]]
  - name: GATE line
    at: [1, 0]
    cols: [[ts], [phase], [status, "ran | skipped | override"], [reason]]
  - name: OUTCOME line
    at: [2, 0]
    cols: [[ts], [phase], [at, "start | end"], [caught, NULL], [dur_s, NULL], [policy, NULL]]
  - name: TOKENS line
    at: [3, 0]
    cols: [[ts], [in], [out], [cache_read], [cache_create], [cost, NULL], [phase, NULL]]
  - name: DEBT line
    at: [0, 1]
    cols: [[ts], [significance], [worthiness], [verdict], [response, NULL], [reason, NULL]]
  - name: run
    at: [1, 1]
    cols: [[rid, PK], [file, "runs/<rid>.log"]]
  - name: ROUND line
    at: [2, 1]
    cols: [[ts], [state, "open | closing | close | void | incomplete"], [token]]
  - name: proof override
    at: [0, 2]
    cols: [[ts], [repo_id], [slug, FK], [reason]]
  - name: gate-check cache entry
    at: [1, 2]
    cols: [[lane], [rid, FK], [kitlanes], [size], [mtime], [inode], [ctime], [verdict, "pass | fail:phases"]]
  - name: ACTION or MUTATION line
    at: [2, 2]
    cols: [[ts], [kind], [note]]
  - name: completeness line
    at: [0, 3]
    cols: [[ts], [chosen], [suggested], [desc]]
  - name: queue journal row
    at: [1, 3]
    cols: [[ts], [slug, "<repo>__<ID>"], [verdict, "done | gated | stalled | error"], [reason]]
  - name: audit run
    at: [2, 3]
    cols: [[epoch], [iso], [instance], [note]]
  - name: merge-watch line
    at: [3, 3]
    cols: [[ts], [session_id], [kind, "MERGE | WARNED"]]
rels:
  - {from: run, to: START line, cardinality: "1:N"}
  - {from: run, to: GATE line, cardinality: "1:0..N"}
  - {from: run, to: OUTCOME line, cardinality: "1:0..N"}
  - {from: run, to: TOKENS line, cardinality: "1:0..N"}
  - {from: run, to: DEBT line, cardinality: "1:0..N"}
  - {from: run, to: ROUND line, cardinality: "1:0..N"}
  - {from: run, to: ACTION or MUTATION line, cardinality: "1:0..N"}
  - {from: run, to: proof override, cardinality: "1:0..N", label: slug = rid}
  - {from: run, to: gate-check cache entry, cardinality: "1:0..N"}
```

## Repo-committed stores

What lives in git (or in the git common dir) and how one unit of work threads through it: a staged block becomes a row, a row becomes a goal draft, a draft targets a spec, and the spec owns its proof and notes. Mega-goal folders and the goal registry sit beside that chain.

```uml
id: erd-repo
type: erd
title: Repo-committed stores
level: L3
review:
  - The row-to-draft-to-spec chain is joined by hand-typed IDs and slugs, with no checker. Add a lint that a goal draft's `id` and `target_spec` resolve?
  - Goal drafts are gitignored and the registry lives in the git common dir, so neither survives a fresh clone. Is that intended?
tables:
  - name: staging block
    at: [0, 0]
    cols: [[title, PK], [state, "staged | promoted ID-N | rejected | expired"], [Intent], [Approach], [Tags], [Home], [Source]]
  - name: BACKLOG row
    at: [1, 0]
    cols: [[ID, PK], [Item], [Notes, "#u-* #f-* #queue{} #auto"], [Status, "queued .. shipped"]]
  - name: handoff
    at: [2, 0]
    cols: [[path, PK], [cited IDs], [state, "open | archived"]]
  - name: goal registry entry
    at: [0, 1]
    cols: [[slug, PK], [lane], [status, "running | blocked | ready | done"], [branch], [worktree], [touches]]
  - name: goal draft
    at: [1, 1]
    cols: [[slug, PK], [id, FK], [target_spec, FK], [status], [created]]
  - name: SPEC
    at: [2, 1]
    cols: [[NNN, PK], [slug, UQ], [Status, "DRAFT .. SHIPPED"], [Lane], [Depth], [Verification], [Review], [Test plan]]
  - name: decision brief
    at: [3, 1]
    cols: [[slug, PK], [verdict, "BUILD | RETHINK | KILL"], [Solution, NULL], [Design, NULL]]
  - name: attempt store
    at: [0, 2]
    cols: [[task, PK], [state], [winner, NULL], [result_ref, NULL], [excluded]]
  - name: verification log
    at: [2, 2]
    cols: [[slug, "PK FK"], [Command], [Exit], [Output], [Verdict], [NEGATIVE CONTROL, NULL]]
  - name: impl-notes
    at: [3, 2]
    cols: [[slug, FK], [entry, "## date title"]]
  - name: memory note
    at: [0, 3]
    cols: [[slug, PK], [description], [body], [MEMORY.md line]]
  - name: ROADMAP
    at: [1, 3]
    cols: [[megadir, PK], [SG line, "box, auto | gate | gate!, depends, PR #n"]]
  - name: goal file
    at: [2, 3]
    cols: [[SG id, PK], [Model], [Effort], [Harness], [Branch], [Touches], [Done]]
  - name: HANDOFF or DECISIONS
    at: [3, 3]
    cols: [[megadir, FK], [SG id, "FK NULL"], [body]]
rels:
  - {from: BACKLOG row, to: staging block, cardinality: "1:0..1", label: promoted from}
  - {from: BACKLOG row, to: handoff, cardinality: "0..N:0..N", label: cited by}
  - {from: BACKLOG row, to: goal draft, cardinality: "1:0..N", label: id}
  - {from: goal draft, to: SPEC, cardinality: "0..N:0..1", label: target_spec}
  - {from: goal registry entry, to: goal draft, cardinality: "0..1:0..1", label: slug}
  - {from: goal registry entry, to: attempt store, cardinality: "1:0..N", label: task}
  - {from: SPEC, to: decision brief, cardinality: "0..N:0..1", label: folds in}
  - {from: SPEC, to: verification log, cardinality: "1:0..1"}
  - {from: SPEC, to: impl-notes, cardinality: "1:0..1"}
  - {from: ROADMAP, to: goal file, cardinality: "1:N"}
  - {from: goal file, to: HANDOFF or DECISIONS, cardinality: "1:0..1"}
```

## Push gate

A `git push` or `gh pr create` from the agent passes two hooks in order. The safety-gate refuses destructive commands and default-branch pushes; the ship-gate then runs its checks in a fixed order and stops at the first gap. A pass still writes an OUTCOME pair, so the ledger shows the gate ran.

```uml
id: seq-push-gate
type: sequence
title: A push through the gates
level: L3
review:
  - Step 7 fails open (no base, bad ref, missing lib) while step 3 fails closed on an unparsable push. One policy for both?
  - "`start --amend` may only raise a lane, but any writer can pass `--lower --reason`. Should a lowering need a marker only the operator can set?"
participants:
  - {name: agent session, tone: violet}
  - {name: Claude Code runtime}
  - {name: anchor-root, tone: gray}
  - {name: safety-gate, tone: rose}
  - {name: ship-gate, tone: rose}
  - {name: push-refs, tone: rose}
  - {name: gate-policy, tone: rose}
  - {name: proof-ledger, tone: rose}
  - {name: gate-ledger, tone: rose}
messages:
  - {from: agent session, to: Claude Code runtime, text: "Bash git push", kind: call}
  - {from: Claude Code runtime, to: anchor-root, text: "PreToolUse JSON", kind: call}
  - {from: anchor-root, to: safety-gate, text: "cd root, exec", kind: call}
  - {from: safety-gate, to: anchor-root, text: "exit 0 (or 2 on main push)", kind: return}
  - {from: anchor-root, to: ship-gate, text: "cd root, exec", kind: call}
  - {from: ship-gate, to: push-refs, text: "parse command refs", kind: call}
  - {from: push-refs, to: ship-gate, text: "@@REF or @@DEFAULT-PUSH", kind: return}
  - {from: ship-gate, to: ship-gate, text: "fixture identity check", kind: call}
  - {from: ship-gate, to: gate-policy, text: "enabled proof_of_done --at base", kind: call}
  - {from: ship-gate, to: proof-ledger, text: "check root base slug", kind: call}
  - {from: proof-ledger, to: ship-gate, text: "0 proven, 1 gap", kind: return}
  - {from: ship-gate, to: gate-ledger, text: "outcome ship start", kind: call}
  - {from: ship-gate, to: gate-ledger, text: "show slug (last START-AMEND lane)", kind: call}
  - {from: ship-gate, to: gate-ledger, text: "check lane slug, then check full on hard paths", kind: call}
  - {from: gate-ledger, to: ship-gate, text: "missing gates or none", kind: return}
  - {from: ship-gate, to: gate-ledger, text: "outcome ship end caught=", kind: call}
  - {from: ship-gate, to: Claude Code runtime, text: "exit 2 BLOCKED, or exit 0", kind: return}
  - {from: Claude Code runtime, to: agent session, text: "blocked with override hint, or push runs", kind: return}
```

## Intake to land

One unit of work on the normal lane. Assign opens the run (START) and claims it; every phase command after that records its own gate, which the push gate later checks. Spec validation and the fix loop are the two bounded loops.

```uml
id: seq-lifecycle
type: sequence
title: One unit of work, intake to land
level: L3
review:
  - A small normal spec replaces steps 7 to 9 with `override Validate`. Is the size floor the right trigger for that skip?
  - The fix loop stops at 2 retries and then records PARTIAL (step 15). Should PARTIAL block ship, or only warn?
participants:
  - {name: operator, tone: blue}
  - {name: /kit:assign, tone: blue}
  - {name: /kit:spec, tone: blue}
  - {name: validators, tone: blue}
  - {name: /kit:execute, tone: blue}
  - {name: builder, tone: blue}
  - {name: verifiers, tone: blue}
  - {name: review-team, tone: blue}
  - {name: "ship, wrap", tone: blue}
  - {name: gate-ledger, tone: rose}
messages:
  - {from: operator, to: /kit:assign, text: "assign ID-NNN (after /kit:start)", kind: call}
  - {from: /kit:assign, to: /kit:assign, text: "grill: type-shaped questions", kind: call}
  - {from: /kit:assign, to: gate-ledger, text: "record grill; start rid lane type", kind: call}
  - {from: /kit:assign, to: operator, text: "goal draft, row claimed", kind: return}
  - {from: operator, to: /kit:spec, text: write the spec, kind: call}
  - {from: /kit:spec, to: operator, text: "DRAFT, approve?", kind: return}
  - {from: /kit:spec, to: validators, text: "validate round, 7 in parallel", kind: call}
  - {from: validators, to: /kit:spec, text: "APPROVED: Status VALIDATED", kind: return}
  - {from: /kit:spec, to: gate-ledger, text: "validate-round close", kind: call}
  - {from: operator, to: /kit:execute, text: "execute (Go?)", kind: call}
  - {from: /kit:execute, to: builder, text: whole-spec brief, kind: call}
  - {from: builder, to: /kit:execute, text: commit per task, kind: return}
  - {from: /kit:execute, to: verifiers, text: "task, integration, acceptance", kind: call}
  - {from: verifiers, to: /kit:execute, text: "PASS or FAIL:fixable (fix max 2)", kind: return}
  - {from: /kit:execute, to: gate-ledger, text: "record build ran (or PARTIAL)", kind: call}
  - {from: operator, to: review-team, text: review the branch, kind: call}
  - {from: review-team, to: gate-ledger, text: record review ran, kind: call}
  - {from: operator, to: "ship, wrap", text: ship, kind: call}
  - {from: "ship, wrap", to: gate-ledger, text: "record Ship ran pr=#N", kind: call}
  - {from: "ship, wrap", to: operator, text: "PR open (push passed the gates)", kind: return}
  - {from: operator, to: "ship, wrap", text: wrap, kind: call}
  - {from: "ship, wrap", to: operator, text: "merged, row shipped, report", kind: return}
```

## Mega-goal wave

One orchestrator cycle with `WAVE_CAP` of 2 or more. Admission is greedy in ROADMAP order and needs disjoint `## Touches`; a `gate` sub-goal is never admitted to a wave. Siblings drain on a failure and are never killed. The merge step is a dry run unless the operator set `WAVE_MERGE_CMD`.

```uml
id: seq-mega-wave
type: sequence
title: One orchestrate wave cycle
level: L3
review:
  - Step 12 refuses converge when two branches touched one file, after both ran. Check declared Touches against the real diff earlier?
  - Converge records `merge-dry-run` when `gh` does not report MERGED, and the wave carries on. Should the wave stop at the first unmerged PR?
participants:
  - {name: orchestrate, tone: violet}
  - {name: ROADMAP}
  - {name: dispatch-gate, tone: violet}
  - {name: git worktree}
  - {name: spec-next, tone: blue}
  - {name: gate-ledger, tone: rose}
  - {name: claude -p worker}
  - {name: mega-merge, tone: violet}
  - {name: gh}
messages:
  - {from: orchestrate, to: ROADMAP, text: "read unchecked SGs, deps", kind: call}
  - {from: orchestrate, to: dispatch-gate, text: "disjoint Touches per candidate", kind: call}
  - {from: dispatch-gate, to: orchestrate, text: admitted set, kind: return}
  - {from: orchestrate, to: git worktree, text: ".claude/worktrees/<SG>", kind: call}
  - {from: orchestrate, to: spec-next, text: reserve a SPEC number, kind: call}
  - {from: orchestrate, to: gate-ledger, text: "start rid (lane-classify)", kind: call}
  - {from: orchestrate, to: claude -p worker, text: "prompt + FLIP contract", kind: async}
  - {from: claude -p worker, to: gh, text: open PR, kind: call}
  - {from: claude -p worker, to: ROADMAP, text: "flip box (flip.lock)", kind: call}
  - {from: claude -p worker, to: orchestrate, text: exit code, kind: return}
  - {from: orchestrate, to: orchestrate, text: "reap: kill -0 poll, drain siblings", kind: call}
  - {from: orchestrate, to: git worktree, text: "converge: union of diffs, refuse overlap", kind: call}
  - {from: orchestrate, to: mega-merge, text: "merge pr rid lane", kind: call}
  - {from: mega-merge, to: gate-ledger, text: check lane rid, kind: call}
  - {from: mega-merge, to: gh, text: "squash merge (only with --execute)", kind: call}
  - {from: mega-merge, to: orchestrate, text: "0 (also on dry run)", kind: return}
  - {from: orchestrate, to: ROADMAP, text: "re-read; all checked: tier-4 close, HOLD", kind: call}
```

## Signal to row to ship

The signal path ends at a human: proposers only stage, and promote is the gate into the board. The sweep tick runs on its own schedule and touches rows only through sync and the Hermes mirror.

```uml
id: seq-signal
type: sequence
title: Signal to row, and the sweep tick
level: L3
review:
  - Promote refuses blocks older than 14 days while drain expires them at 30. Align the two windows?
  - One failed `git fetch` skips the mirror for every repo in the tick (step 13). Keep the all-or-nothing rule?
participants:
  - {name: proposer}
  - {name: staging}
  - {name: operator, tone: blue}
  - {name: board promote, tone: green}
  - {name: BACKLOG.md}
  - {name: /kit:assign, tone: blue}
  - {name: "/kit:ship, wrap", tone: blue}
  - {name: board-sweep, tone: green}
  - {name: sync engine, tone: green}
  - {name: Hermes kanban}
messages:
  - {from: proposer, to: staging, text: "append [staged] (dedup by title)", kind: call}
  - {from: operator, to: board promote, text: "promote n | all", kind: call}
  - {from: board promote, to: staging, text: "read, refuse stale or mis-homed", kind: call}
  - {from: board promote, to: BACKLOG.md, text: "board_lock, next_id, row queued", kind: call}
  - {from: board promote, to: staging, text: "mark [promoted ID-N]", kind: call}
  - {from: operator, to: /kit:assign, text: "assign --next", kind: call}
  - {from: /kit:assign, to: BACKLOG.md, text: "set claimed, then speccing", kind: call}
  - {from: operator, to: "/kit:ship, wrap", text: "ship, then wrap", kind: call}
  - {from: "/kit:ship, wrap", to: BACKLOG.md, text: "set shipped \"<PR>\"", kind: call}
  - {from: board-sweep, to: sync engine, text: "sync per registry row", kind: async}
  - {from: sync engine, to: BACKLOG.md, text: "spoke flips under board_lock", kind: call}
  - {from: board-sweep, to: BACKLOG.md, text: "publish: commit, push or rebase", kind: call}
  - {from: board-sweep, to: Hermes kanban, text: "mirror plan, apply (skip tick on fetch fail)", kind: call}
```

## Board row lifecycle

The Status column's leading keyword is the state; the rest of the cell is prose. `backlog.sh set` accepts any legal state from any state, so the arrows below are the paths callers actually take, not guards. `/kit:spec` sets `validated` when an APPROVED validate round closes on a spec with a `Board:` header; nothing sets the move out of it (rose).

```uml
id: sm-board-row
type: state
title: Board row status
level: L4
review:
  - "`/kit:spec` sets `validated`, but nothing sets the move from `validated` to `executing`. Should `/kit:execute` or assign set it?"
  - "`set` has no transition guard. Add one (for example, refuse shipped to claimed), or keep it permissive for hand repairs?"
states:
  - {name: queued, initial: true, at: [0, 1]}
  - {name: claimed, at: [1, 1]}
  - {name: speccing, at: [2, 0]}
  - {name: validated, at: [3, 0]}
  - {name: executing, at: [3, 1]}
  - {name: shipped, final: true, at: [4, 1]}
  - {name: parked, at: [3, 2]}
  - {name: dropped, final: true, at: [1, 2]}
transitions:
  - {from: queued, to: claimed, event: "assign --next, wt start"}
  - {from: claimed, to: speccing, event: assign (lane has spec)}
  - {from: claimed, to: executing, event: "assign (tiny), wayfind"}
  - {from: speccing, to: validated, event: "/kit:spec, round approved"}
  - {from: validated, to: executing, event: no setter, tone: rose}
  - {from: executing, to: shipped, event: "wrap, sync close, reconcile"}
  - {from: executing, to: parked, event: "wrap, reconcile"}
  - {from: queued, to: dropped, event: "wrap, reconcile, sync archive"}
  - {from: shipped, to: queued, event: spoke reopens, via: [[4, 2.6], [0, 2.6]]}
```

## Spec status

The spec's `Status:` header changes in place; nothing migrates the file. Execute accepts APPROVED or VALIDATED, but its preflight also needs a passing `validate` GATE (or an override) on normal, full and backfill lanes. Nothing sets PARKED except a hand edit.

```uml
id: sm-spec-status
type: state
title: Spec Status header
level: L4
review:
  - PARKED has no setter and no command reads it except the active-spec resolver. Give `/kit:wrap` a park verb?
  - A mid-flight amend keeps VALIDATED (add-only). Should an amend that adds a task re-open the validate round?
states:
  - {name: DRAFT, initial: true, at: [1, 0]}
  - {name: APPROVED, at: [1, 1]}
  - {name: VALIDATED, at: [1, 2]}
  - {name: SHIPPED, final: true, at: [1, 3]}
  - {name: PARKED, at: [0, 2]}
transitions:
  - {from: DRAFT, to: APPROVED, event: operator approves}
  - {from: APPROVED, to: APPROVED, event: NEEDS REVISION at ceiling}
  - {from: APPROVED, to: VALIDATED, event: "round APPROVED, or override Validate"}
  - {from: VALIDATED, to: VALIDATED, event: add-only amend}
  - {from: VALIDATED, to: SHIPPED, event: "/kit:ship (drafts archive)"}
  - {from: VALIDATED, to: PARKED, event: "hand edit (from any state)", tone: gray}
```

## Run ledger lifecycle

A run is the rid's file, read as a state by `check`. Nothing stores the state itself; `check` derives it from the lines each time (with a stat-keyed cache). `blocked` is what the push hook or mega-merge sees, not a line in the file.

```uml
id: sm-run-ledger
type: state
title: Run ledger, as check sees it
level: L4
review:
  - A run with no START (a queue run, or a sub-goal with no `**Branch:**`) shows lane `?` in telemetry and is never checked. Should queue runs write START?
  - An override reason reused for a second gate is refused (exit 65). Is a free-text reason enough for an override, or should it name a backlog row?
states:
  - {name: absent, initial: true, at: [1, 0]}
  - {name: started, at: [1, 1]}
  - {name: gating, at: [1, 2]}
  - {name: blocked, at: [0, 2]}
  - {name: complete, at: [1, 3]}
  - {name: shipped, final: true, at: [1, 4]}
transitions:
  - {from: absent, to: started, event: "start (assign, orchestrate, wt)"}
  - {from: started, to: started, event: start --amend}
  - {from: started, to: gating, event: first record}
  - {from: gating, to: gating, event: "record, override, inherit"}
  - {from: gating, to: blocked, event: "check exits 1 at push or merge", tone: rose}
  - {from: blocked, to: gating, event: record or override the gap}
  - {from: gating, to: complete, event: last required gate}
  - {from: complete, to: shipped, event: "push passes, record Ship on land"}
```

## Queue row run

One overnight queue row, from plan to verdict, as `queue.sh` and the watch-board reaper see it. `done` and `gated` are terminal for the watcher; plain `queue run` skips `done` and a `gated` row whose reason is `no-delta`. A row is `done` only after a HEAD move, a moved local branch tip or an operator PR created since the window opened.

```uml
id: sm-queue-row
type: state
title: Queue row run
level: L4
review:
  - A clean exit with no git delta is `gated` (`no-delta`), and `queue run` skips it on re-run. Should the reaper re-queue it once, or leave it for a human?
  - Three stalls quarantine a row with no alert. Should quarantine stage a proposal so a human sees it?
states:
  - {name: planned, initial: true, at: [0, 1]}
  - {name: in-flight, at: [1, 1]}
  - {name: done, final: true, at: [2, 0]}
  - {name: gated, final: true, at: [3, 0]}
  - {name: stalled, at: [2, 2]}
  - {name: error, at: [2, 1]}
  - {name: quarantined, final: true, at: [3, 2]}
  - {name: cooldown, at: [3, 1]}
transitions:
  - {from: planned, to: in-flight, event: "window opened, beat"}
  - {from: in-flight, to: done, event: "EXIT_SIGNAL true and a git delta", via: [[1, 0]]}
  - {from: in-flight, to: gated, event: "REASON, RUNNER_GATED, no-delta, protected path", via: [[1, -0.4], [3, -0.4]]}
  - {from: in-flight, to: error, event: "launch failed twice, breaker"}
  - {from: in-flight, to: stalled, event: "timeout, ceiling, beat 3600s", via: [[1, 2]]}
  - {from: stalled, to: planned, event: retry_after elapsed, via: [[2, 2.6], [0, 2.6]]}
  - {from: stalled, to: quarantined, event: 3 stalls}
  - {from: error, to: cooldown, event: cooldown_until set}
  - {from: cooldown, to: planned, event: cooldown elapsed, via: [[3, 0.55], [0, 0.55]]}
```

## Cross-cutting concepts

- Layered config. One TOML reader, `lib/config/kit-config.sh`, resolves a key from the project `.kit.toml`, then the operator `~/.config/dwarves-kit/kit.toml`, then the kit-root `kit.toml`. The project layer counts only when it is tracked and clean, or when read at a revision with `--at`. Two readers sit on top: `gate-policy.sh` for `[gate]` keys (any reader error means ON) and `lane-data.sh` for `[lane.*]` phases. Vendor enablement, `runner_host`, `probe_key_ref` and `[decide]` are root-only on purpose. `[modules]` decides which hooks run: `lib/config/modules.tsv` maps each hook to its module, and `anchor-root.sh` skips a hook whose module is off (the spine never is).
- The ledger root resolver. `kit-log-dir.sh` picks `$KIT_LEDGER_DIR`, else `$DWARVES_KIT_LOG_DIR`, else `[ledger].location`, else `${XDG_STATE_HOME:-~/.local/state}/dwarves-kit/logs`. A set-but-empty `KIT_LEDGER_DIR` is fatal. Every append goes through `lib/ledger/ledger.sh`, which collapses newlines so one event is one physical line. Hook audit logs use the same root through `hook-log-dir.sh`, in a `hooks/` subdirectory.
- Fail-open versus fail-closed, per gate. safety-gate: always on, documented accepted holes. ship-gate: closed on an unloadable ship-rules, an unparsable push in an adopted repo, a missing Lane; open when no kit `lib/` exists. proof-ledger `check`: open on no base, a bad ref or a missing lib. gate-policy: an unreadable reader means ON. Advisory measures (coverage-delta, mutation-smoke, check-edit, load-warn, money-gate without STRICT): always exit 0. Codex adapter: closed, but Codex treats a hook failure as non-blocking.
- Egress points. `claude -p --model haiku` from harvest and backlog-stage (transcript tails); `claude -p` sonnet from reflect propose, session-audit and the skill-curator reviewer; `claude -p` workers from the orchestrator and the queue; Jev or Clef HTTPS from flick (candidate slugs, gated by `decide.points`, `deny_words`, `word_gate`); webcheck HTTP to consumer-declared sites (http(s) only, same-host redirects); `hermes kanban` from the mirror and the sync spoke; `gh` from mega-merge, writeback, wrap and ci-drift. Every LLM egress fails open and exits 0.
- Worktree isolation and merge at the lead. Wave sessions, dispatch workers and `wrap start` each get a worktree under `.claude/worktrees/`. Workers never merge: the orchestrator converges one PR at a time under `flip.lock`, `/kit:dispatch` hands READY branches to the lead's `/kit:ship`, and tier-4 close HOLDs for a human. The serial orchestrator path and the queue still run in the real checkout.
- Staging as the human gate. Proposers (stats anomalies, reflect propose, session-audit triage, session-intel, the stage hooks, `wrap stage`) append `[staged]` blocks through one grammar (`staging-format.py`, with a `.jq` twin for bash). `board promote` is the gate that mints a row, and every row write goes through `backlog.sh add`, under the board lock. Staging writes go through one lock, `staging_lock`.
- One rid per run. The rid is the branch slug with `type/` stripped, derived after the branch exists. The same key joins assign-time records, ship-gate's push check, mega-merge and telemetry.

## Risks and technical debt

Ranked by blast radius, widest first. Open risks come first; accepted trade-offs follow. Closed items live in git and the PRs.

- Unsandboxed workers on shared state. Both executors run `--dangerously-skip-permissions`; the queue and the serial orchestrator work in the real checkout, and protected-path writes are detected after the run, only with sanitize on. Trigger: a worker edits outside its scope overnight. Mitigation: sanitize, the XPIA fence, `#queue{}` allow-listing, wave worktrees, the `flip.lock`.
- Self-reported completion, now narrower. The queue counts `done` only after a HEAD move, a moved local branch tip or an operator PR created since the window opened; otherwise the row is `gated` with reason `no-delta`. The orchestrator still trusts a flipped box plus a `PR #n`, and `attempt-state.sh` has no lock and relies on the lead calling it in sequence. Trigger: a sub-goal claims done with a flipped box and no real PR. Mitigation: the ROADMAP box needs a real `PR #n`; tier-4 close HOLDs for a human.
- Degrade paths. A vendor harness runs with no turn cap, watchdog or token capture; a failed SPEC reservation lets the worker pick its own number; a goal file with no `**Branch:**` skips START.

**Accepted trade-offs**

- Hermes bridges: two separate jobs, because retiring either breaks a running job.
- One spec file, many writers: replace-not-stack sections and a pinned blob keep voided rounds cheap.
- Narrow verifier allowlists: the narrow list is the safer default, and recheck re-executes what it allows.
- Plugin hooks register for every module: one bash start per skipped hook is cheap.
- Stat-keyed caches: the 2-second window is short and a recheck is cheap.
- Advisory and unwired parts: advisory by design, and the `bin/` forwarders arrive with the workset fold.

## Drift register

All 47 rows of the first drift pass were resolved in #989 to #1003, each either fixed or not applicable. The history is in git (`git log -p -- docs/SYSTEM-DESIGN.md`). New doc-versus-code drift goes in a fresh table here, with the columns Fix, Doc claim, Code reality and Locations.
