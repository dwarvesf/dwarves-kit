# Decision brief: declared state machines

**Status:** decided; phase 1 (the board row) ships with SPEC-417.
**Question:** the kit holds about 70 implicit state machines. Which one change helps the operator (UX), the kit developer (DX) and the agent (AX) at once, without breaking a caller?

## Decision

Every stateful entity declares its machine ONCE, in a data file owned by the entity's writer. Readers derive from it. Writers detect an undeclared move and say so; they block only where the kit already blocks (the ship boundary).

```
            lib/<area>/states.tsv   (state, class, next)
                     │  one declaration, owned by the writer
     ┌───────────────┼──────────────────────┬─────────────────────┐
     ▼               ▼                      ▼                     ▼
 writer verb     bash readers          python readers        agent / operator
 (set: notice    (derive sets at       (load at import,      (`machine` verb:
  on reopen)      source time)          same file)            where am I, where next)
                     ▲
                     │  tests/test-<area>-states.sh fails on a re-introduced copy
```

| Column | Meaning |
|---|---|
| `state` | the exact stored string; file order is render order |
| `class` | `active` (open, moving), `hold` (paused on purpose), `terminal` (closed by a human decision) |
| `next` | the forward path a caller normally takes; advisory, `-` for none |

**Why this one change serves all three:**

| Lens | Today | After |
|---|---|---|
| UX (operator) | a wrong `shipped -> queued` flip is silent | `set` prints a reopen notice; nothing is refused |
| DX (kit developer) | a new state means hunting 6 copies in 2 languages | a one-line edit in `states.tsv`; a test fails on any new copy |
| AX (agent) | "where can I go from here" lives in prose across WORKFLOW, SYSTEM-DESIGN and command files | `backlog.sh machine` answers it in one call |

**Rules it keeps:**
- PHILOSOPHY "Detect, don't dictate": no mid-flight transition is blocked. `attempt-state.sh` keeps refusing, because it guards a duplicate-dispatch bug, which is an irreversible cost.
- PHILOSOPHY "Bash over binaries": a TSV that `awk` and Python both read in five lines; no library, no runtime.
- CLAUDE.md "No premature abstraction": the convention is a file shape plus a test, not shared code. A shared loader waits for the third declared machine.
- SYSTEM-DESIGN's open review question ("add a guard, or keep `set` permissive for hand repairs?") resolves to: permissive, with a notice on a reopen.

**Rejected:**
- A generic `lib/fsm/` engine with enforced transitions: it would block sync, reconcile and hand repairs that jump states legitimately, and it breaks "Detect, don't dictate".
- Docs-only declaration (the current SDLC section): it already drifted from the code, so docs alone fail the brief.
- Fixing each copy by hand: the next state added re-creates the drift.

## Inventory

Every row was found by four read-only scouts and spot-checked in code. "Enforced" means a code guard on the move, not a membership check.

### Board, queue, goal, mega

| Machine | Store | Enforced | Top drift |
|---|---|---|---|
| Board row status | `_meta/BACKLOG.md` last cell | membership only (phase 1 declares it) | vocabulary copied in 6 code files; any-to-any moves |
| Hermes mirror (row to card) | `.board-mirror-snapshot.jsonl` | `case` map | 4 states collapse to `ready`; legacy `done` read, never written |
| Hermes writeback (card to row) | same snapshot | membership + `row_hash` | a card move writes `executing -> queued` with no notice |
| Mirror cleanup classes | derived | dispatch | third copy of the row-to-card map; archives where the mirror would `block` |
| Queue eligibility | row text `#queue{}` | allow-list | a finished run leaves its row `queued` |
| Queue job verdict | `queue-journal.tsv` | none | `queue run` and the watcher disagree on which verdicts are terminal |
| Queue liveness sidecars | `queue-runs/<slug>.{beat,status,guard}` | partial | three writers; a dead beat never reaches `done` |
| Mega sub-goal box | `ROADMAP.md` `[ ]/[x]/[X]/[~]` | idempotent flip | six readers parse the box six ways |
| Mega sub-goal events | `.orchestrate/events.log` | none | `blocked`, `held`, `merged` written, never read |
| Orca backend sub-goal state | derived | ordered rule table | none (a derivation) |
| Dispatch task and attempt | `kit-attempts/<task>.task` | **full** (`attempt-state.sh`) | the yardstick |
| Goal registry claim | `kit-goals/<slug>.goal` | none on `status` | documented `blocked/ready/done` never written |
| Goal draft | `.claude/goals/*.md` frontmatter | none | rewrite only fires when a `status:` line exists |
| PR merge eligibility | GitHub PR | full, fail-closed | three meanings of "held" across files |
| Mega reconcile | derived | full | label strings re-declared in `mega-review.py` |

### Gate, proof, spec, hooks

| Machine | Store | Enforced | Top drift |
|---|---|---|---|
| Spec `Status:` header | `docs/specs/*.md` | none; no script writes it | 8 values in use, 62 specs with none; 5 readers disagree on "live" |
| Spec task box | `- [ ]` / `- [x]` | guard (exits 3/4/5) | none |
| Gate phase | `runs/<rid>.log` `GATE` lines | partial | `check()` passes on ANY `ran`, a later `skipped` does not undo it |
| Run lane | `START`/`START-AMEND` lines | lowering guard | three sources for the lane, two copies of the rank |
| Validate round | `ROUND` lines | real guards, hand-coded | no table; 400 lines of `case` and awk |
| Debt tap | `DEBT` lines | enum on write | `wave` is both a verdict and a response |
| Proof class | derived | pure function | two classifiers, same names, different inputs |
| Proof verdict | `docs/verification/*.md` | last line wins | `PASS` anywhere counts |
| Proof asset | `assets.json` + `.pending` | partial | reader checks `pending`, writer never writes it |
| Spec number reservation | `spec-reservations.log` + lock dir | owner token + TTL | none |
| Harvest ledger | `learned-ledger.md` | real guard | none |
| Hook session markers | `/tmp` and state files | partial | first Stop is a no-op by design |

### Wrap, session, sync, reflect, release

| Machine | Store | Enforced | Top drift |
|---|---|---|---|
| Wrap land outcome | shell globals, `LAND:` line | none | `ship` does not handle the `draft` kind |
| Wrap ship step | globals, `SHIP:` line | none | none |
| Branch merge proof | git + `gh` | three copies of one ladder | scan and apply label the same branch differently |
| Worktree sweep | porcelain + locks | ordered guards | none |
| PR merge gate | `gh pr view` JSON | none | callers compare a verdict sentence by string |
| Stray carry | `wrap/stray-*` branches | none | none |
| Adopt row | globals | none | rows matched by free text |
| Handoff file | dir depth | partial | closed set re-declared |
| Sync link | `~/.cache/backlog-sync/*.state.json` | caps + terminal guard | `parked` is neither active nor terminal in sync's sets (now `hold`) |
| Spoke status maps | code constants | none | `claimed` and `speccing` both map to Multica `todo` |
| Skill draft | `skill-proposals/` dirs | partial | rejected drafts can re-stage; `promote --force` can nest a draft |
| Staging block | `## [staged]` headers | partial | `expired`, `rejected`, `promoted` have no exits |
| Debt disposition | `DEBT` lines | total function | `mark-paid` skips its own "pending" guard |
| Release cut | VERSION, tag, CHANGELOG | none | commit can land with no tag; `--dry-run` discards edits |

### Commands, skills, other lib (prose-held machines)

| Machine | Where the state lives | Gap |
|---|---|---|
| Gauntlet run and round | `ROUNDS.md`, `round-N/` dirs, agent memory | replicate count stored nowhere |
| Test-plan critique | spec section + `[[QL-VERDICT]]` | `SOLID` never machine-read; same-day freshness passes |
| Greenlight loop | agent memory only | retry and iteration counters reset on context loss |
| Audit pass | `audit-runs.log` | no in-flight or failed state |
| Audit verdict grammar | PR body | per-skill extensions; `OK`/`DANGER` never emitted |
| Onboard wizard | nothing | restart re-detects |
| Wayfind ticket | `tickets/*.md` `Status:` | claim is a git push race |
| Bench `RunState` | memory | unknown status reads as `pass`; `run_end` always `pass` |
| Migration sentinel | `.migrated` files | a symlinked dir is never retried |

## Rollout

| Phase | Machine | Why this order |
|---|---|---|
| 1 (SPEC-417) | board row | the hub: 7 writers, 6 copies, both languages |
| 2 | spec `Status:` | 5 readers disagree on "live"; no writer script exists. Shipped in #1106 |
| 3 | gate phase + lane | `check()` on stale `ran`; three lane sources. Shipped in #1114, #1116, #1124 |
| 4 | queue verdict + mega box | two readers, two terminal sets; six box parsers. Shipped in #1105, #1122, #1125 |

Each later phase reuses the phase 1 shape: a `states.tsv` beside the writer, a `machine` verb, a copy-detector test. The second and third instances decide whether a shared loader earns its place.

## Simplification pass

A cleanup pass followed phase 1. Each PR removed a duplicate spelling or a second source of truth, with no stored data rewritten.

| PR | What shipped |
|---|---|
| #1104 | Audit verdict grammar cut to five words |
| #1105 | Queue terminal set unified; dead goal status fields removed |
| #1106 | Spec Status machine in `lib/spec/states.tsv` with one reader helper (rollout phase 2) |
| #1107 | skill-curator reviewer revived: `--bare` could not log in; signal gate on by default |
| #1108 | Wrap PR gate decides by code, not by sentence |
| #1109 | NEEDS-REVISION has one spelling; INCONCLUSIVE folds into FAIL; dead proof `pending` removed; bench `unknown` is never pass; one lane rank |

**Kept on purpose.** Each is a separate concept, not a copy.
- Gate `ran` / `skipped` / `override`
- Validate round states
- Land kind
- Attempt state
- `SOLID` / `REVISE` / `RECONSIDER`
- Staging headers
- The mutation marker that `break-it` reads

## Second pass

The operator settled the open items, and a second batch removed the next layer of duplicates and real bugs.

| PR | What shipped |
|---|---|
| #1112 | `spec-status.sh set`; `/kit:ship` writes `Status: SHIPPED` in the feature PR |
| #1113 | Debt verdict `wave` becomes `log`, response `wave` becomes `accept`; mega keeps `wave`; readers accept both |
| #1114 | `check()` decides on each phase's latest GATE row; NEEDS-REVISION writes `rejected` |
| #1116 | Override rows carry `via=hand\|plan\|batch\|inherit\|lane-lower`; the alert counts hand overrides on required phases only |
| #1121 | `release` dry-run keeps edits and checks the tag first; `promote --force` aborts on a failed backup; rejected drafts never re-stage; prose `PASS` no longer greens a proof |
| #1122 | ROADMAP box grammar declared once in `lib/mega/box.tsv` for every reader; `mega review` sees SG-NN roadmaps; "held" reads recorded markers only |
| #1123 | One wrap merge-proof ladder; callers branch on its code |
| #1124 | One effective-lane resolver; the ship check takes the stricter of spec header and ledger lane; plain `start` validates the lane |
| #1125 | SG-NN rows get a branch signal; a parked-only mega lists as `(parked)` |

**Still open, each needs its own design.**
- Prose-held counters (gauntlet rounds, greenlight retries, the onboard step) live only in agent context.
- `stalled` and `blocked` carry several meanings across queue and mega.
- The validate round machine is correct but hand-coded; a declared table would cost more than it saves today.
