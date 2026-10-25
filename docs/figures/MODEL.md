# dwarves-kit figures

The figures in the README and the guides. Each one is a sheet below, drawn from this one file and saved as `<id>.png` beside it. Do not edit a PNG by hand: change the sheet, then run `bash lib/system-design/doc-figures render`. `bash lib/system-design/doc-figures check` fails when a sheet changed without a new render.

Colors mean the same on every figure: blue is the main path of a change, rose is a gate that can block, violet is a way to run many agents, green is the board and the test side, gray is a hook, and plain boxes belong to someone else.

## The loop

Every change walks the same path: think, spec, execute, review, docs, ship, wrap, and retro, which feeds the next idea. Rose arrows block you. Blue arrows only advise.

```uml
id: loop
type: state
title: The loop
level: L1
caption: "One change walks think, spec, execute, review, docs, ship, wrap and retro. Rose arrows are blocks (execute refuses an unvalidated spec, the verifiers stop a failed build, the ship-gate stops a push). Blue arrows advise; you decide."
states:
  - {name: /kit:think, initial: true, tone: blue, at: [0, 0]}
  - {name: /kit:spec, tone: blue, at: [1, 0]}
  - {name: /kit:execute, tone: blue, at: [2, 0]}
  - {name: /kit:review, tone: blue, at: [3, 0]}
  - {name: /kit:docs, tone: blue, at: [3, 1]}
  - {name: /kit:ship, tone: blue, at: [2, 1]}
  - {name: /kit:wrap, tone: blue, at: [1, 1]}
  - {name: /kit:retro, tone: blue, at: [0, 1]}
transitions:
  - {from: /kit:think, to: /kit:spec, event: the idea holds up, tone: blue}
  - {from: /kit:spec, to: /kit:execute, event: validated, guard: spec passes review, tone: rose}
  - {from: /kit:execute, to: /kit:review, event: built, guard: verifiers pass, tone: rose}
  - {from: /kit:review, to: /kit:docs, event: SHIP verdict, tone: blue}
  - {from: /kit:docs, to: /kit:ship, event: docs match, tone: blue}
  - {from: /kit:ship, to: /kit:wrap, event: PR open, guard: ship-gate passes, tone: rose}
  - {from: /kit:ship, to: /kit:execute, event: ship-gate blocks, guard: gap in proof or gates, tone: rose}
  - {from: /kit:wrap, to: /kit:retro, event: PR merged, tone: blue}
  - {from: /kit:retro, to: /kit:think, event: lessons feed the next idea, tone: blue}
```

## What adopt writes

`/kit:adopt` writes five small files into your repo and points them at the kit. It never overwrites a file you already have.

```uml
id: adopt
type: component
title: What /kit:adopt writes into your repo
level: L1
caption: "/kit:adopt adds a pointer file (AGENTS.md), a loader block (CLAUDE.md), a pointer to the lane matrix (WORKFLOW.md), the proof marker that turns the ship-gate on, and a starter .kit.toml. The pointers lead to the installed kit; nothing is copied."
lanes:
  - {id: repo, name: your repo, tone: blue}
nodes:
  - {id: adopt, name: /kit:adopt, note: "run once per repo", tone: blue, at: [0, 2]}
  - {id: agents, name: AGENTS.md, note: "four rules and a pointer", tone: blue, lane: repo, at: [1, 0]}
  - {id: claude, name: CLAUDE.md, note: "loader block imports AGENTS.md", tone: blue, lane: repo, at: [1, 1]}
  - {id: workflow, name: WORKFLOW.md, note: "pointer to the lane matrix", tone: blue, lane: repo, at: [1, 2]}
  - {id: marker, name: docs/verification/README.md, note: "proof marker, turns the ship-gate on", tone: rose, lane: repo, at: [1, 3]}
  - {id: config, name: .kit.toml, note: "starter modules and gates", tone: rose, lane: repo, at: [1, 4]}
  - {id: kit, name: installed kit, note: "lane matrix, classifiers, gates", kind: ext, at: [3, 2]}
edges:
  - {from: adopt, to: agents, tone: blue, via: [[0.5, 2], [0.5, 0]]}
  - {from: adopt, to: claude, tone: blue, via: [[0.5, 2], [0.5, 1]]}
  - {from: adopt, to: workflow, tone: blue}
  - {from: adopt, to: marker, tone: rose, via: [[0.5, 2], [0.5, 3]]}
  - {from: adopt, to: config, label: "created once", tone: rose, via: [[0.5, 2], [0.5, 4]]}
  - {from: agents, to: kit, label: points to, dashed: true, via: [[3, 0]]}
  - {from: workflow, to: kit, label: points to, dashed: true}
```

## Lanes

The classifier sizes a change before any code. You rarely pick a lane by hand.

```uml
id: lanes
type: component
title: Five lanes
level: L1
caption: "lane-classify sizes each change. Every lane runs a different set of phases. The default is normal. The classifier only suggests full; you assign it. A defect goes to bug, and a repo with no operate docs goes to backfill."
nodes:
  - {id: task, name: your task, note: "described in plain words", kind: ext, at: [0, 2]}
  - {id: classify, name: lane-classify, note: "reads the words, picks a lane", tone: blue, at: [1, 2]}
  - {id: tiny, name: tiny, note: "trivial edit: build, review", tone: blue, at: [2, 0]}
  - {id: normal, name: normal, note: "the default: spec, validate, test-plan, build, review, docs, ship", tone: blue, at: [2, 1]}
  - {id: full, name: full, note: "risk match, you assign: normal plus design, design critique, reflect", tone: rose, at: [2, 2]}
  - {id: bug, name: bug, note: "defect: debug first, then test-plan, build, review, ship", tone: blue, at: [2, 3]}
  - {id: backfill, name: backfill, note: "no operate docs: spec, validate, review, docs; no build", tone: blue, at: [2, 4]}
edges:
  - {from: task, to: classify}
  - {from: classify, to: tiny, via: [[1.5, 2], [1.5, 0]]}
  - {from: classify, to: normal, via: [[1.5, 2], [1.5, 1]]}
  - {from: classify, to: full}
  - {from: classify, to: bug, via: [[1.5, 2], [1.5, 3]]}
  - {from: classify, to: backfill, via: [[1.5, 2], [1.5, 4]]}
```

## The push gate

An agent pushes. The ship-gate hook runs first and checks the proof and the gates before the push happens.

```uml
id: push-gate
type: sequence
title: A push through the ship-gate
level: L3
caption: "The ship-gate runs before the push. It refuses a push to the default branch, then checks the proof ledger, the review verdict and the gate ledger, in that order. The first gap stops the push with exit 2 and a hint. With no gap the push runs."
participants:
  - {name: agent, tone: blue}
  - {name: Claude Code}
  - {name: ship-gate, tone: rose}
  - {name: ledgers, tone: rose}
messages:
  - {from: agent, to: Claude Code, text: "git push or gh pr create", kind: call}
  - {from: Claude Code, to: ship-gate, text: "hook runs before the command", kind: call}
  - {from: ship-gate, to: ship-gate, text: "push to the default branch? refuse", kind: call}
  - {from: ship-gate, to: ledgers, text: "proof ledger: proof for this branch?", kind: call}
  - {from: ledgers, to: ship-gate, text: "proof file, logged override, or gap", kind: return}
  - {from: ship-gate, to: ship-gate, text: "review verdict DO NOT SHIP? refuse", kind: call}
  - {from: ship-gate, to: ledgers, text: "gate ledger: gates this lane needs?", kind: call}
  - {from: ledgers, to: ship-gate, text: "all ran or overridden, or the missing ones", kind: return}
  - {from: ship-gate, to: Claude Code, text: "exit 0 allow, or exit 2 BLOCKED with a hint", kind: return}
  - {from: Claude Code, to: agent, text: "the push runs, or the block and its fix", kind: return}
```

## Board row states

A row on the backlog board holds one status word. Commands flip it as the work moves.

```uml
id: board-row
type: state
title: Board row status
level: L4
caption: "A board row moves from queued to shipped. /kit:assign claims it, /kit:spec marks it validated, /kit:execute marks it executing when the build starts, and /kit:wrap closes it."
states:
  - {name: queued, initial: true, tone: green, at: [0, 1]}
  - {name: claimed, tone: green, at: [1, 1]}
  - {name: speccing, tone: green, at: [2, 0]}
  - {name: validated, tone: green, at: [3, 0]}
  - {name: executing, tone: green, at: [3, 1]}
  - {name: shipped, final: true, tone: green, at: [4, 1]}
  - {name: parked, tone: green, at: [3, 2]}
  - {name: dropped, final: true, tone: green, at: [1, 2]}
transitions:
  - {from: queued, to: claimed, event: "/kit:assign --next", tone: green}
  - {from: claimed, to: speccing, event: "/kit:assign, lane has a spec", tone: green}
  - {from: claimed, to: executing, event: "/kit:assign, tiny lane", tone: green}
  - {from: speccing, to: validated, event: "/kit:spec, round approved", tone: green}
  - {from: validated, to: executing, event: "/kit:execute, build starts", tone: green}
  - {from: executing, to: shipped, event: "/kit:wrap", tone: green}
  - {from: executing, to: parked, event: "/kit:wrap", tone: green}
  - {from: queued, to: dropped, event: "/kit:wrap", tone: green}
```

## Execute

`/kit:execute` hands a whole spec to one builder, then checks the result once at the end.

```uml
id: execute
type: sequence
title: /kit:execute, build then verify
level: L3
caption: "One builder commits once per task. The end verifiers then check every task, the wiring between tasks, and the acceptance criteria. A fixable failure goes to the fix-agent and the failing verifier runs again, at most twice. A failure that needs a decision goes to you."
participants:
  - {name: builder, tone: blue}
  - {name: /kit:execute, tone: blue}
  - {name: verifiers, tone: green}
messages:
  - {from: /kit:execute, to: /kit:execute, text: "plan shown; you say go", kind: call}
  - {from: /kit:execute, to: builder, text: "whole-spec brief", kind: call}
  - {from: builder, to: /kit:execute, text: "one commit per task", kind: return}
  - {from: /kit:execute, to: verifiers, text: "task, integration, acceptance", kind: call}
  - {from: verifiers, to: /kit:execute, text: "PASS, FAIL fixable, or FAIL escalate", kind: return}
  - {from: /kit:execute, to: /kit:execute, text: "fix-agent, then rerun (max 2)", kind: call}
  - {from: /kit:execute, to: /kit:execute, text: "PASS: you move on to review", kind: call}
  - {from: /kit:execute, to: /kit:execute, text: "escalate or PARTIAL: you decide", kind: call}
```

## Review

`/kit:review-team` reads the diff through several lenses and writes one verdict into the spec.

```uml
id: review
type: sequence
title: Review and the ship check
level: L3
caption: "/kit:review-team sends the diff to its lenses in parallel, merges the findings, and writes a ## Review section with one verdict into the spec. /kit:ship reads that verdict and stops on DO NOT SHIP. The ship-gate refuses the push for the same verdict."
participants:
  - {name: lenses, tone: rose}
  - {name: /kit:review-team, tone: rose}
  - {name: you, tone: blue}
  - {name: /kit:ship, tone: blue}
  - {name: ship-gate, tone: rose}
messages:
  - {from: you, to: /kit:review-team, text: "review the branch", kind: call}
  - {from: /kit:review-team, to: lenses, text: "the diff, in parallel", kind: call}
  - {from: lenses, to: /kit:review-team, text: "findings with confidence", kind: return}
  - {from: /kit:review-team, to: /kit:review-team, text: "merge; write the verdict in the spec", kind: call}
  - {from: /kit:review-team, to: you, text: "SHIP, FIX THEN SHIP or DO NOT SHIP", kind: return}
  - {from: you, to: /kit:ship, text: "ship", kind: call}
  - {from: /kit:ship, to: /kit:ship, text: "read the verdict in the spec", kind: call}
  - {from: /kit:ship, to: you, text: "DO NOT SHIP: stop, fix first", kind: return}
  - {from: /kit:ship, to: ship-gate, text: "push or open the PR", kind: call}
  - {from: ship-gate, to: /kit:ship, text: "refuses while the verdict is DO NOT SHIP", kind: return}
```

## Several pieces of work

Two commands handle more than one piece. Mega-goal is for dependent pieces. Dispatch is for independent ones.

```uml
id: several-pieces
type: component
title: Mega-goal and dispatch
level: L2
caption: "/kit:mega turns one destination into a chain of dependent sub-goals, one PR each; sub-goals with disjoint Touches share a wave of two, and the run ends on an exit check at the destination. /kit:dispatch fires several already-validated specs at once, one worktree each, behind a disjointness gate."
lanes:
  - {id: mega, name: "/kit:mega, dependent pieces", tone: violet}
  - {id: dispatch, name: "/kit:dispatch, independent pieces", tone: violet}
nodes:
  - {id: dest, name: Destination, note: "one roadmap, 3 to 8 sub-goals", tone: violet, lane: mega, at: [0, 0]}
  - {id: sg1, name: Sub-goal 1, note: "its own PR", tone: violet, lane: mega, at: [1, 0]}
  - {id: sg2, name: Sub-goal 2, note: "wave of two", tone: violet, lane: mega, at: [2, 0]}
  - {id: sg3, name: Sub-goal 3, note: "wave of two", tone: violet, lane: mega, at: [2, 1]}
  - {id: exit, name: Exit check, note: "a test at the destination", tone: violet, lane: mega, at: [3, 0]}
  - {id: specs, name: Validated specs, note: "each lists its Touches", tone: violet, lane: dispatch, at: [0, 2]}
  - {id: gate, name: Disjointness gate, note: "PARALLEL or WAIT", tone: rose, lane: dispatch, at: [1, 2]}
  - {id: workers, name: One worker per spec, note: "own worktree, in parallel", tone: violet, lane: dispatch, at: [2, 2]}
  - {id: merge, name: You merge, note: "/kit:ship, one PR each", tone: blue, lane: dispatch, at: [3, 2]}
edges:
  - {from: dest, to: sg1, tone: violet}
  - {from: sg1, to: sg2, tone: violet}
  - {from: sg1, to: sg3, tone: violet}
  - {from: sg2, to: exit, tone: violet}
  - {from: sg3, to: exit, tone: violet}
  - {from: specs, to: gate, label: plan, tone: violet}
  - {from: gate, to: workers, label: admits, tone: rose}
  - {from: workers, to: merge, tone: violet}
```

## Gauntlet

The gauntlet asks one question: can a median agent reach the outcome using only what you ship?

```uml
id: gauntlet
type: sequence
title: One gauntlet run
level: L3
caption: "Each round builds a fresh clean room from committed files. A probe agent tries the task with no help, and a checker scores the result. On a fail, a separate reviser edits the artifact, the room is torn down, and a new round starts. The run ends on two passes in a row (SOLID) or at the round cap of three."
participants:
  - {name: you, tone: blue}
  - {name: /kit:gauntlet, tone: violet}
  - {name: clean room, tone: violet}
  - {name: probe, tone: violet}
messages:
  - {from: you, to: /kit:gauntlet, text: "run the gauntlet", kind: call}
  - {from: /kit:gauntlet, to: /kit:gauntlet, text: "cheap checks first", kind: call}
  - {from: /kit:gauntlet, to: clean room, text: "build fresh from committed files", kind: call}
  - {from: clean room, to: probe, text: "artifact and task card, nothing else", kind: call}
  - {from: probe, to: clean room, text: "its output and transcript", kind: return}
  - {from: clean room, to: /kit:gauntlet, text: "hand the output back", kind: return}
  - {from: /kit:gauntlet, to: /kit:gauntlet, text: "checker scores it", kind: call}
  - {from: /kit:gauntlet, to: /kit:gauntlet, text: "fail: reviser edits the artifact", kind: call}
  - {from: /kit:gauntlet, to: clean room, text: "tear down; the next round starts fresh", kind: call}
  - {from: /kit:gauntlet, to: you, text: "SOLID, REVISE or RECONSIDER", kind: return}
```

## Wrap

`wrap` lands a finished branch and cleans up behind it.

```uml
id: wrap
type: sequence
title: Landing a branch with wrap
level: L3
caption: "/kit:wrap flips the board row first. wrap land then pushes the branch, opens or adopts the PR, waits for checks, squash-merges, and checks that the merge applied exactly the PR's change. It then deletes the remote branch, pulls the main checkout, and removes the worktree."
participants:
  - {name: board, tone: green}
  - {name: /kit:wrap, tone: blue}
  - {name: wrap land, tone: blue}
  - {name: GitHub}
messages:
  - {from: /kit:wrap, to: board, text: "set the row to shipped, with the PR", kind: call}
  - {from: /kit:wrap, to: wrap land, text: "land the worktree branch", kind: call}
  - {from: wrap land, to: GitHub, text: "push; open or adopt the PR", kind: call}
  - {from: wrap land, to: GitHub, text: "wait for checks; squash-merge", kind: call}
  - {from: GitHub, to: wrap land, text: "merged", kind: return}
  - {from: wrap land, to: wrap land, text: "verify the merge matches the PR", kind: call}
  - {from: wrap land, to: GitHub, text: "delete the remote branch", kind: call}
  - {from: wrap land, to: wrap land, text: "fast-forward the main checkout", kind: call}
  - {from: wrap land, to: wrap land, text: "remove worktree and local branch", kind: call}
  - {from: wrap land, to: /kit:wrap, text: "landed", kind: return}
```

## Debug

`/kit:debug` finds the root cause before it allows a fix.

```uml
id: debug
type: state
title: The debug loop
level: L3
caption: "The loop builds a fast pass or fail check first, then traces the cause, compares with working code, and tests one hypothesis at a time. A fix needs a recorded root cause. After three failed fixes the loop stops and asks you to question the design; it never tries a fourth."
states:
  - {name: 0 Feedback loop, initial: true, tone: blue, at: [0, 0]}
  - {name: 1 Root cause, tone: blue, at: [1, 0]}
  - {name: 2 Compare, tone: blue, at: [2, 0]}
  - {name: 3 Hypothesis, tone: blue, at: [3, 0]}
  - {name: 4 Fix, tone: blue, at: [3, 1]}
  - {name: Fixed, final: true, tone: green, at: [4, 1]}
  - {name: 3-fix wall, final: true, tone: rose, at: [3, 2]}
transitions:
  - {from: 0 Feedback loop, to: 1 Root cause, event: bug repeats on demand, tone: blue}
  - {from: 1 Root cause, to: 2 Compare, event: cause found, tone: blue}
  - {from: 2 Compare, to: 3 Hypothesis, event: differences listed, tone: blue}
  - {from: 3 Hypothesis, to: 4 Fix, event: hypothesis confirmed, guard: root cause recorded, tone: rose}
  - {from: 4 Fix, to: Fixed, event: new test passes, guard: nothing else broke, tone: green}
  - {from: 4 Fix, to: 1 Root cause, event: fix failed, guard: fewer than 3 tries, tone: blue, via: [[1, 1]]}
  - {from: 4 Fix, to: 3-fix wall, event: third fix failed, tone: rose}
```

## The V-model

Every level of building has a test at the same level. The left arm builds. The right arm proves.

```uml
id: v-model
type: component
title: The V-model
level: L1
caption: "The left arm builds from the request down to the code. The right arm tests from one task up to the original request. Dashed lines pair each build level with the test at the same level. A failure shows at the level that can see it."
nodes:
  - {id: brief, name: Brief, note: "/kit:think, /kit:assign", tone: blue, at: [0, 0]}
  - {id: design, name: Design, note: "/kit:design", tone: blue, at: [0, 1]}
  - {id: spec, name: Spec, note: "/kit:spec", tone: blue, at: [0, 2]}
  - {id: execute, name: Execute, note: "/kit:execute", tone: blue, at: [0, 3]}
  - {id: accept, name: acceptance test, note: "does it meet the original ask?", tone: green, at: [2, 0]}
  - {id: system, name: system test, note: "whole suite, end to end", tone: green, at: [2, 1]}
  - {id: integ, name: integration test, note: "do the tasks wire together?", tone: green, at: [2, 2]}
  - {id: task, name: task test, note: "does each task meet its criteria?", tone: green, at: [2, 3]}
edges:
  - {from: brief, to: design, tone: blue}
  - {from: design, to: spec, tone: blue}
  - {from: spec, to: execute, tone: blue}
  - {from: task, to: integ, tone: green}
  - {from: integ, to: system, tone: green}
  - {from: system, to: accept, tone: green}
  - {from: brief, to: accept, label: same level, dashed: true, tone: green}
  - {from: design, to: system, label: same level, dashed: true, tone: green}
  - {from: spec, to: integ, label: same level, dashed: true, tone: green}
  - {from: execute, to: task, label: built, tone: green}
```
