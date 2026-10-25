# gate

The **Check stage's** engine (ADR-0034, stage names per the 2026-07-18 amendment: Shape / Build / Watch / Check / Reflect; formerly "Govern leg"). Every
phase boundary in the kit routes through this module. It is what makes a lane a *contract*
instead of a suggestion.

Three things here can actually stop you: the lane gate (`gate-ledger.sh`), the proof gate
(`proof-ledger.sh`) and the dispatch gate (`dispatch-gate.sh`). `hooks/ship-gate.sh` also holds
a few rules of its own (default-branch push, DO NOT SHIP verdict, fixture identities, the
hard-path floor). Everything else here observes, classifies, or nudges. Which claims are real
blockers, and what enforces each, is `docs/hard-rules.tsv`.

```
     kit.toml [lane.<name>] (lane-data.sh)       the branch diff
                    |                                  |
                    v                                  v
        gate-ledger.sh  (the LANE gate)      proof-ledger.sh  (the PROOF gate)
        "did every required gate run?"       "is there a fresh proof of done?"
              fails CLOSED                         fails OPEN
                    \                                  /
                     `------> hooks/ship-gate.sh <----'
                                 (exit 2 = block)
```

The proof gate is diff-keyed and spec-independent. The lane gate keys on the spec's `Lane:`
(and on the diff's hard-path floor), so both fire the same whether the work came through
`/kit:execute` or a freeform `/goal` loop. Both are off until `[gate] proof_of_done` and
`[gate] lane_gates` are on (see "Turning a gate on").

## The callables

Entry point is `bin/gate <verb>` (stable; SPEC-184). It forwards to `gate.sh`, which owns the
verb grammar and adds no logic. Call any script directly by path too; both work.

| Verb | Script | What it does | Can it block? |
|---|---|---|---|
| `gate ledger` | `gate-ledger.sh` | The lane gate + the run ledger. Records every gate decision, checks a run for completeness. | **yes** (`check` exit 1) |
| `gate proof-ledger` | `proof-ledger.sh` | The proof-of-done gate. Classifies the branch diff, demands a matching fresh proof. | **yes** (`check` exit 1) |
| `gate dispatch` | `dispatch-gate.sh` | Disjointness gate for `/kit:dispatch`. Two goals run in parallel only if their `## Touches` globs are provably disjoint. Also the drift guard. | **yes** (serializes / exit 1 on drift) |
| `gate policy` | `gate-policy.sh` | The `[gate]` on/off reader (opt-in: on only when the key resolves to `true`). `enabled <key> [root]` exits 0 when a gate is on for that project. Hooks call it instead of reading config. | no |
| `gate proof` | `proof-gate.sh` | Classifier, not a gate. `class`, `requirement`, `classes`: task description to proof class + the artifact that work-type owes. `contract "<task>"`: what that work-type owes. `skeleton <slug>`: a fillable `docs/verification/<slug>.md` on stdout. `coverage <spec> [proof.md ...]`: which spec criteria a proof covers. | no |
| `gate redteam` | `redteam-gate.sh` | Records one rung-4 redteam round (GATE, TOKENS and OUTCOME lines in one call) so the rung-4 cost is measurable. Missing `cost=` is rejected. | no (rc 64 on bad arguments) |
| `gate quiz` | `quiz-gate.sh` | The star-tap NUDGE. Builds 5 diff-grounded questions, routes through the `understand.teach` seam. | no (nudge only) |
| `gate coverage-delta` | `coverage-delta.sh` | Advisory. Source lines moved but test lines did not? Warn. | no (always exit 0) |
| `gate mutation-smoke` | `mutation-smoke.sh` | Advisory. Mutates a changed line, re-runs the suite. A surviving mutation means the suite does not bite. | no (always exit 0) |
| (by path) | `recheck-sample.sh` | `decide <rid> [N]`: should `/kit:execute` recheck this run's end-verifier PASSes? Keyed on the rid, records the decision. | no |
| (by path) | `check-edit.sh` | `<base> [files]`: did the build edit or weaken its own check? Prints `check-edited:` / `check-weakened:` lines. | no (always exit 0) |
| `gate proof-table` | `proof-table-gen.{sh,py}` | Generates a run-table from a rid's ledger. Refuses to write `proof-of-done.md`. | no |
| `gate verify-counts` | `verify-counts.sh` | Regenerates `docs/verification/COUNTS.md` from live suite runs. (`verif-counts`: legacy alias) | no |

### The lane gate (`gate-ledger.sh`)

The single source for "which gates does this lane require" is the **`[lane.<name>]` blocks in
`kit.toml`**, read by `lane-data.sh` (project `.kit.toml` when tracked and clean, then the
operator overlay, then the kit root). A phase in `phases` and not in `light` is required.
`docs/WORKFLOW.md` carries the human-readable matrix, projected from that data and checked by
`doc-projection-check.sh`; code never parses it.

```bash
rid=$(gate ledger rid)                       # branch slug, `type/` prefix stripped
gate ledger required full                    # the lane's required gate keys
gate ledger record "$rid" Build ran "note"   # a gate decision
gate ledger check full "$rid"                # exit 0 iff every required gate has ran|override
gate ledger progress "$rid" full             # step k/n + checklist
gate ledger inherit "$rid" full --from <spec-rid>   # a task branch carries its spec's gates
gate ledger record-batch "$rid" full think=ran:"design PR" reflect=override:"at wrap"   # several gates, one call
```

### Recording many gates at once

`record-batch <rid> <lane> [--evidence-default "<text>"] <phase>=<ran|skipped|override>:<evidence> ...` is for a build whose design phases ran elsewhere: another repo, another host, or an approved design PR. It opens the run with `start` when no ledger exists, or corrects it with `start --amend` (keeping the classified lane, type and repo of the last START line). It then records each named phase through `record` or `override`, so the line format, the grill-skip reason enum and the distinct-override-reason guard apply unchanged. Last, it runs `check <lane> <rid>` and exits with that status, so 0 means the lane is complete.

Each item carries its own evidence. `--evidence-default` fills any item with none. The whole set is replayed against a scratch ledger first, so a refusal writes nothing, START line included: an unknown phase, an unknown state, a phase given twice, or empty evidence exits 64, and a reason reused across two overrides exits 65 (give each override its own evidence). Unlike `plan-record`, only the named phases need a line. Unlike `inherit`, the evidence is the caller's word and no parent ledger is read.

### Task branches under a validated spec

A multi-task spec passes think, design, design-critique, spec, validate, design-record and test-plan once, on its own rid. Each task branch is its own rid, and the ship-gate checks the full lane on it. `inherit <rid> full --from <spec-rid>` writes one `override` line per spec-level gate, with the reason `inherited from <spec-rid>: <phase> ran there at <ts>`. It refuses, and writes nothing, unless the LAST GATE line for every one of those phases in the spec rid's ledger is `ran`. Build, review, docs, ship and reflect are never inherited.

What it attests: a `ran` line is the last line for that phase in the named parent's ledger on this host. It does not attest approval, or that the task belongs to that spec. The verb is lead-only; no command, hook or skill calls it. A parent that itself inherited is refused, with the real spec rid named. A child that already inherited from a different parent exits 65. Re-running the same call is a no-op per phase already written. v1 serves the `full` lane only and reads the kit-root lane data, the same as the ship-gate's hard-path floor.

Records are append-only, redacted (no command bodies), and one physical line per call
(`oneline()` collapses newlines, because a forged `| ran |` line would otherwise make
`check()` believe a gate ran).

### Ledger line grammar

```
TS | START   | lane=.. classified=.. type=.. repo=..
TS | GATE    | <phase> | ran|skipped|override | [reason]
TS | ACTION  | <text>
TS | TOKENS  | in=N out=N cache_read=N cache_create=N [cost=N]
TS | DEBT    | significance=.. worthiness=.. verdict=.. [response=..] [reason=..]
TS | OUTCOME | <phase> | start|end | at=<epoch> [caught=<bool> dur_s=N]
TS | MUTATION| verdict=flag|clean|skip [k=v ...]
```

**The load-bearing invariant:** only a `| GATE |` line in state `ran` or `override` satisfies
`check()`. Every other marker is *additive*, meaning `check()` / `override()` / `descent()` and
the ship-gate all ignore it (they key on `$2=="GATE"`). A TOKENS, DEBT, OUTCOME or MUTATION line
can never fake, satisfy, or mask a gate. Keep that property when adding a marker verb.

### The review verdict rule (`ship-rules.sh`)

`hooks/ship-gate.sh` refuses a `git push` or `gh pr create` while the branch spec's last review
verdict is `DO NOT SHIP`. `ship_rule_review_verdict` finds the spec the way the lane check does
(`spec-find.sh`), then reads every `## Review` section (an exact heading, so `## Review
disposition` does not count). The LAST `Verdict:` line there whose value starts with `SHIP`,
`FIX THEN SHIP` or `DO NOT SHIP` wins; `/kit:review` and `/kit:review-team` write it as
`### Verdict: ...` and replace the section on a re-run, so a fresh review clears the block.
Code fences and other verdict words (`SOLID`, `SECURE`) are skipped. No section, no verdict or an
unreadable spec passes, and the other rules still apply. The spec is read as committed at the
pushed head, so an uncommitted edit does not clear a committed DO NOT SHIP.

A branch can edit its own verdict line, so the rule also cross-checks the run ledger. The review
commands (`/kit:review`, `/kit:review-team`, `/kit:battery`) record `review ran "<verdict> ..."`
after they write the spec, with the verdict (`SHIP`, `FIX THEN SHIP` or `DO NOT SHIP`) as the first
words of the reason. `gate-ledger.sh review-verdict <rid>` prints the LAST such verdict; a record
whose reason starts with anything else is skipped and never clears an earlier one. When that
verdict differs from the spec's last verdict, the push is refused with both verdicts named;
re-running the review records and writes the new one. A spec with no verdict at all is refused
only against a recorded `FIX THEN SHIP` or `DO NOT SHIP`: a recorded `SHIP` softens nothing. The
reason must start with the verdict followed by a space, `:`, `;`, `,`, `.` or the end, so
`SHIP-clean` is not a verdict.
A run with no recorded verdict is checked on the spec alone, as before. The ledger sits outside
the branch, so a commit cannot soften it, but any ledger writer can append a line: this check
raises the cost of a softened spec, it does not sign anything. The rule runs before the lane
checks, so it holds whatever the spec's `Lane:` says. It logs `BLOCKED | ship-gate | <slug>
(review verdict DO NOT SHIP)` or `(review verdict mismatch: spec '<v>', ledger '<v>')` to
`ship-gate.log`. Key: `[gate] review_verdict`, default ON, read
at the merge base (an opt-out must already sit on the default branch). Proof:
`tests/test-ship-gate-review-verdict.sh`, `tests/test-gate-ledger-amend.sh` (the reader).

### Amending a run's lane

`gate ledger start --amend <rid> <lane> ...` appends a `START-AMEND` line; every reader, ship-gate
included, takes the LAST one as the run's lane. An amend may raise the lane. It refuses (exit 65,
nothing written) to lower it, because a lighter lane sheds required gates. Order: `tiny` <
`normal` = `bug` = `backfill` < `full`. The special lanes sit at `normal`'s rank, so moving
between them stays free and a drop from `full` to either needs the flags. An amend to any other
name (`tiny2`, `Tiny`) exits 64, because ship-gate reads the lane back as `[a-z-]+` and a look-alike
would read as `tiny`. To lower on purpose:

```
gate ledger start --amend --lower --reason "<why>" <rid> <lighter-lane> <classified> <type> ...
```

That first appends `GATE | lane-lower | override | <from> -> <to>: <reason>`, which lane
telemetry counts like any gate override, then the `START-AMEND`. `--lower` and `--reason` go
before the rid; `--lower` without a reason, or with a blank one, exits 64. `record-batch` amends
through the same path and has no such flags, so it cannot lower a run: run `start --amend --lower`
first. The ledger is append-only text, so a writer who bypasses
the verb can still append a raw line; the guard stops the sanctioned verb from doing it
silently. Proof: `tests/test-gate-ledger-amend.sh`.

### The hard-path floor and what it ignores

`ship_rule_floor` makes a diff that touches a hard path (migration, auth, secret, CI, infra or kit config) owe the full lane's gates, whatever lane the spec names. It does not count a diff
that only changes documentation, or one whose changed lines in a non-doc file are blank lines
or `#` comments (`lane-classify.sh floor`). Anything it cannot decide keeps the floor: a
secret-pattern path, a symlink, a gitlink, an unknown file type, a mode change, a NUL byte, a
heredoc, triple-quote or YAML block file, a change next to a shebang or directive, a
scanner-suppression comment, or more than 50 hits or 8 seconds of scanning. The proof gate
sizes itself the same way: a diff made only of `*.md`/`*.txt`, `.kit.toml`, and documentation
or asset files under `docs/` classes `inert`. Source, build files and secret-shaped paths under
`docs/` keep their class. Proof: `tests/test-ceremony-fits-diff.sh`.

## Turning a gate on

The blocking quality gates are OPT-IN. The kit root says `false` for every key except
`board_row_gate`, `fixture_identities` and `review_verdict`, so a fresh install blocks nothing else until someone turns a gate on.
`/kit:adopt` is the exception for the repo it adopts: it seeds `lane_gates = true` and `proof_of_done = true` in that repo's `.kit.toml`, so an adopted repo enforces both from the first push, while a raw install keeps the kit root defaults (off).
Those three default on; a repo opts out with `<key> = false` in a committed
`.kit.toml`, under the same committed-and-clean rule as any project `false`. Two places do that, and both apply on
the next hook fire, no re-adopt, no restart:

```toml
# machine-wide, every repo: ~/.config/dwarves-kit/kit.toml (the operator overlay)
# per repo: <repo>/.kit.toml, committed (adopt seeds this block with each key explained)
[gate]
proof_of_done      = true    # ship-gate: proof-of-done check (ADR-0025)
lane_gates         = true    # ship-gate: lane x phase required-gate check + no-Lane refusal (ADR-0024)
understanding_gate = true    # anti-rationalization Stop hook (ADR-0031)
commit_format      = true    # commit-subject lint
board_row_gate     = false   # board-row-gate hook: default ON, so the useful setting is false
fixture_identities  = false  # ship-gate fixture git identity check: default ON, so the useful setting is false
review_verdict     = false   # ship-gate DO NOT SHIP review verdict check: default ON, so the useful setting is false
```

`lib/gate/gate-policy.sh enabled <key> [root]` is the one reader; hooks call it and never
touch the config themselves (the "no hook reads kit.toml" lint in `tests/test-install-modules.sh`
stays load-bearing). A gate is on only when its key resolves to a literal `true` (project
`.kit.toml` > operator overlay > kit root). An unknown key is on, and only exit 1 from the
reader means off: a missing, truncated, or unreadable reader means on, so a broken kit never
drops a gate an operator turned on. Every skip leaves a line: `OFF-BY-CONFIG | <gate> | <slug>`
in `logs/ship-gate.log`, and an `OFF-BY-CONFIG` row in `anti-rationalization.log` /
`commit-format.log`. Advisories are not gates and keep printing. `safety-gate.sh` and
`secrets-guard.sh` have no key: they guard destructive git and credential leaks, not quality,
and are always on.

The trust model, stated plainly. The project file wins over the operator overlay on purpose:
a repo decides its own gates, so the overlay sets the machine default and a repo can go either
way (this is the one `[gate]` exception to the `kit_config_get_root` rule for PR-borne keys).
Turning a gate ON from the project file is never commit-gated. A project-level `false` over an
operator `true` applies only once `.kit.toml` is tracked and clean; an uncommitted or edited
copy leaves the gate on and prints a one-line hint, so an opt-out always rides inside a PR
where a review sees it. Pulling a branch that flips a key flips it for your own pushes on that
branch too. `adopt` seeds the block with the values that resolved at adopt time (operator, else
the kit default), each key explained in a comment; delete a line to follow the operator setting
again. The proof classifier treats a `.kit.toml`-only diff as inert, whatever key it touches:
harness config owes no proof-of-done. Proof: `tests/test-gate-opt-out.sh`, `tests/test-gate-opt-in.sh`.

## Specs and decisions

| Where | What |
|---|---|
| `docs/decisions/0024-gate-ledger-and-ship-enforcement.md` | The lane gate + why mid-flight never blocks |
| `docs/decisions/0025-proof-of-done-ship-gate.md` | The proof gate |
| `docs/decisions/0026-colocated-table-first-proof.md` | Where a proof lives, and its shape |
| `docs/decisions/0031-understanding-gate.md` | The star-tap nudge (quiz-gate) |
| `docs/decisions/0035-durable-ledger-root.md` | Where the ledger is written |
| `docs/specs/` | `SPEC-032` dispatch, `SPEC-042/044` proof-of-done, `SPEC-048` ship-gate fail-closed, `SPEC-071/077` ledger fixes, `SPEC-076` V-model descent, `SPEC-097` ledger durability, `SPEC-125` quiz-gate, `SPEC-129` outcome-emit, `SPEC-130` coverage-delta, `SPEC-131` mutation-smoke, `SPEC-132/133` proof-table |

This module has no module-local `SPEC.md`; its specs are the numbered ones at the repo root.
That is why `lib/gate/SPEC` is still an open IOU in `tests/kit-contract-known-gaps.txt`.

## Tests

```bash
bash tests/test-gate-outcome.sh          # SPEC-129 outcome markers + the additive property
bash tests/test-gate-vocab-recording.sh  # every required gate name has a command that records it
bash tests/test-ledger-durability.sh     # SPEC-097 durable root, override guard, forgery
bash tests/test-ledger-substrate.sh      # the one append substrate
bash tests/test-quiz-gate.sh             # SPEC-125 grounded questions + anti-fatigue
bash tests/test-ship-gate-fail-closed.sh # SPEC-048
bash tests/test-ship-gate-refs-block.sh  # a push the gate cannot account for is refused in an adopted repo
bash tests/test-ceremony-fits-diff.sh    # docs-only diffs class inert; comment-only edits skip the hard-path floor
bash tests/test-ship-gate-review-verdict.sh # DO NOT SHIP verdict blocks; last wins; ledger cross-check; key off
bash tests/test-gate-ledger-amend.sh        # start --amend raises freely, lowering needs --lower --reason; review-verdict reader
bash tests/test-gate-opt-out.sh          # [gate] false switches each quality gate off (machine has them on); safety gate immune
bash tests/test-gate-opt-in.sh           # kit defaults: every quality gate off; a project true turns one on
bash tests/test-ship-gate-profiles.sh    # install-dependent, see below
```

## The three things a newcomer gets wrong

**1. Recording a gate is not the same as passing it.** `check()` counts only `ran` and
`override`. But `progress()` and `descent()` count a phase as *disposed* if it is anything other
than a bare skip, so a `skipped` entry **with a reason** shows up as a green tick in `progress`
and still fails `check`. The checklist saying done does not mean the ship-gate agrees. That
divergence is deliberate (a skip is a decision worth seeing, not a pass), but it surprises
everyone once.

**2. The two gates fail in opposite directions.** (`hooks/ship-gate.sh` itself is a mix: its header lists where it closes and where it opens.) The lane gate **fails closed**: an unknown
lane is refused, because reading an empty required-list would vacuously pass and let a run ship
with zero gates enforced. The proof gate **fails open**: no repo, no base, empty diff, missing
tooling all return 0, because a gate bug must never block unrelated work. If you are adding a
check, decide which one you are, and say so.

**3. An override is not a skeleton key.** Two guards you will hit. A reason already used to
override a *different* gate in the same run is rejected (exit 65), because one reason pasted
across every gate defeats the audit trail. And a proof-of-done override does **not** excuse
changed source files: it covers docs and sanctioned `deploy/` paths only. Overriding a branch
that touches `.sh`/`.py`/`.go` still blocks, by name.

Two smaller ones. `rid` is the branch slug with its leading `type/` segment stripped, and it must
stay byte-identical to `hooks/ship-gate.sh`'s `${BRANCH#*/}`; off a work branch it fails loudly
rather than record under a wrong key. And `tests/test-ship-gate-profiles.sh` prints
`[NO EXECUTABLE CHECK: ship-gate hook not installed]` and passes when the kit is not installed to
`~/.claude/dwarves-kit`, so a green run there proves nothing on a dev checkout.
