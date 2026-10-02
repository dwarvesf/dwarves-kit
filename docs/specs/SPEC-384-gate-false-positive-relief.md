# Spec: gate false-positive relief (a precise session auth path, one audited lane-wide override)
Generated: 2026-10-02
Status: DRAFT
Lane: full
Type: spec-feature
Depth: blind-spot (failure: the narrowed auth path lets a real session-auth change ship without the full lane's gates)
File: `docs/specs/SPEC-384-gate-false-positive-relief.md`
References: `docs/retro/RETRO-2026-10-02-observe-cost-dedup.md` (the two action items this spec closes); `docs/specs/SPEC-296-classify-session-word.md` (the same narrowing, done once for the task-TEXT regex; imitate its shape: name the auth meanings that keep firing, pin both directions); `lib/classify/lane-classify.sh` (`_HP_auth`, `_path_kind`, `_floor_scan`); `lib/gate/gate-ledger.sh` (`override`, `required`, `check`, `plan_record` for the refuse-before-write habit); `tests/test-lanes-data.sh` (`case_floor_paths`, the path truth table); `tests/test-lane-classify.sh`; `tests/test-ledger-durability.sh` (AC6/AC7, the override guard)

## Problem

PR #877 edited `lib/session/observe/bin/session-observe`, a transcript-session tool. Two gate behaviors turned a small fix into a slog.

1. **False positive.** `_HP_auth` lists `sessions?` as a bare path segment: `(^|/)(...|sessions?)(/|\.[a-z]+$)`. Any directory named `session/` or `sessions/`, and any file named `session.<ext>`, counts as auth. The kit's own `lib/session/` module holds 93 tracked files, and every one hits the auth hard path. The ship-gate floor then demanded the full lane's 12 required gates.
2. **Override cost.** Recovering needed 12 `gate-ledger.sh override <rid> <phase> "<reason>"` calls. The ledger rejects a reason already used for a different gate (exit 65). Each call needed an invented suffix, and 11 first attempts failed.

## Solution

### Approaches considered

T1, the auth path:

- **A. Path-only meaning test.** A session path counts as auth when the path itself carries an auth word, or under a named auth dir. Tradeoff: `src/session/index.ts` (an express-session config module) drops to normal, because nothing in its path says auth.
- **B. Path meaning plus a diff signal.** Approach A, plus: a session-dir path with no auth word in its path still counts when its ADDED lines carry an auth signature (cookie, csrf, jwt, password, ...). Tradeoff: one more awk pass at the floor, and the rule reads two inputs.
- **C. Allowlist `lib/session/`.** Exclude the kit's own module by name. Tradeoff: kit-specific, fixes one repo, and every consumer with a transcript or game-session dir keeps the false positive.

T2, the override:

- **D. New verb `override-lane <rid> <lane> <reason>`.** One call writes one GATE override line per required gate, each reason tagged with the gate. Tradeoff: a new verb to document.
- **E. Magic phase `override <rid> all-lane <reason>`** (the retro's wording). Tradeoff: overloads the phase argument of an existing verb with a value that is not a phase. A typo'd phase today is a harmless extra line; a magic value makes one string mean "every gate".
- **F. Reuse `plan-record --override`.** Tradeoff: plan-record needs a disposition for every PLAN phase (grill, lite phases included) and still enforces distinct reasons. It solves the call count, not the invented-suffix problem.

### Chosen approach + why

B for T1. A alone narrows a security hard path with a known blind spot (`src/session/index.ts`); the diff signal closes it at ship time, where the floor already reads the added lines. C fixes one repo and leaves every consumer wrong. B stays a strict narrowing: the diff signal only fires on paths the old regex already matched.

D for T2. A dedicated verb leaves `override`'s contract and its 65 guard byte-identical, and makes a lane-wide override a distinct, greppable event. E hides a blanket bypass inside the per-gate verb. F does not remove the suffix invention.

### Extensibility & boundaries

- Load-bearing dimension for T1: the list of auth words. A new auth meaning (say `saml`) is one alternative in one regex. A consumer that wants a session dir hard regardless adds it to `[lanes] extra_hard_paths`; that knob only adds, so the narrowing is recoverable per repo without a kit change.
- Load-bearing dimension for T2: the number of gates a lane requires. The verb reads `required <lane>`, so a lane that grows a gate is covered with no code change.
- Units. `_is_auth_path <path>` (one path, used by `_path_kind`) and the floor's auth pass (many paths, one awk pass) share the same three regex constants. `override_lane` composes `required` and `override`; it adds no new line format.

### Architecture

See `## Design`.

## Picture

```
 T1: the auth hard-path test (lane-classify.sh)

   changed path ──► core auth regex? (auth/, oauth/, rbac, permissions,
        │            *login*, *password*, *jwt*)  ── yes ──► full auth
        │ no
        ▼
   old session alternative?  (session/ | sessions/ | session.<ext>)
        │ no ──► not auth
        ▼ yes
   path has a session(s)/ DIR segment?
        │ no (bare session.ts, middleware/session.js) ──► full auth
        ▼ yes
   auth word in the path? (token, cookie, csrf, store, middleware, ...)
        │ yes (api/sessions/token.go) ──► full auth
        ▼ no (lib/session/observe/bin/session-observe)
   [floor only] added lines of THIS path carry an auth signature?
        │ yes (cookie:, httpOnly, jwt, password, ...) ──► full auth
        ▼ no
     not auth   (classify --files stops one box earlier: it has no diff)


 T2: one audited lane-wide override (gate-ledger.sh)

   override-lane <rid> <lane> "<reason>"
        │  reason empty after trim? ── yes ──► exit 64, nothing written
        │  lane unknown to `required`? ── yes ──► exit 64, nothing written
        ▼
   gates = required(lane) ∪ required(lane, kit root only)
        │  drop gates that already carry a ran|override line
        ▼
   for each gate g:  override(<rid>, g, "<reason> [lane-override lane=<lane> gate=<g>]")
        │                        (the existing writer; the 65 guard still runs)
        ▼
   ACTION line: lane-override lane=<lane> gates=<n> written=<k> reason=<reason>
   stderr:      LANE-OVERRIDE: <k> gate(s) of lane <lane> overridden for run <rid> ...
        │
        ▼
   check() / ship-gate floor / progress / lane-telemetry read the GATE lines as today
```

## Design

Design-bearing: yes. It narrows a hard path (a security boundary) and adds a ledger verb that relaxes an audit guard on purpose.

### Approaches considered + chosen

See `## Solution` above. No new tradeoff surfaced in the design view.

### Diagram

See `## Picture` (flowchart for T1, sequence for T2). ASCII by house rule.

### ADR link(s)

`docs/decisions/0024-gate-ledger-and-ship-enforcement.md` owns the override path. This spec extends it with no lasting irreversible choice: both changes revert with one commit, and no ledger line format changes. No new ADR. The trade-off is recorded in `## Decision Log` (DEC-3) and in `lib/gate/README.md`'s "An override is not a skeleton key".

### Boundaries & failure modes

Out of bounds: the task-text auth regex (SPEC-296 owns it), every other hard-path kind, the proof-of-done override (`proof-ledger.sh override`), and the ship-gate hook. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

**T1, `lib/classify/lane-classify.sh`.**

- Inputs: one changed path (`_path_kind`, from `--files`), or the base..head path list and added lines (`floor`).
- Constants (names are the builder's choice; the semantics are the contract):
  - `CORE`: today's `_HP_auth` with `|sessions?` removed from the segment alternation. Every other alternative unchanged.
  - `SESS`: `(^|/)sessions?(/|\.[a-z]+$)`, exactly the alternative removed from `CORE`. Keeping it byte-identical is what makes the change a strict narrowing.
  - `SDIR`: `(^|/)sessions?/`, a session DIRECTORY segment.
  - `MEAN` (auth word in the path, separator-bounded so `restore` does not hit `store`): `(^|[/_.-])(tokens?|cookies?|csrf|xsrf|jwt|authn?|authz|login|logout|signin|signout|oauth|passport|credentials?|secrets?|stores?|middlewares?)([/_.-]|$)`.
  - `HL_SESS` (auth signature in an added line, case-insensitive): `cookie|csrf|xsrf|httponly|samesite|passport|bcrypt|argon2|jwt|password|passwd|express-session|session[_-]?(secret|store|cookie|token)`. Bare `token` is deliberately absent: transcript tooling says "token" for LLM tokens (261 hits in `lib/session/`).
- Path rule: a path is `auth` iff `CORE` matches, or (`SESS` matches and (`SDIR` does not match or `MEAN` matches)).
- Floor-only diff rule: a path that matched `SESS` but failed the path rule is still `auth` when one of its added lines (non-doc files only, the floor's existing `_DOC_AWK` skip) matches `HL_SESS`. It reports `full auth: <path>`.
- Outputs: unchanged shapes. `floor` prints `full <kind>: <path>` or nothing; `classify/explain --files` reasons read `hard path in --files (auth: <path>)`.
- Invariants:
  - Strict narrowing: every path or diff the new rule marks `auth` was marked by the old `_HP_auth`. No path goes from "not hard" to "hard".
  - Floor cost stays flat: one grep or awk pass per kind over the path list, one pass over the added lines. `floor-timing` (1000 paths) stays under its limit.
  - `[lanes] extra_hard_paths` still only adds.

**T2, `lib/gate/gate-ledger.sh`.**

- New verb: `override-lane <rid> <lane> <reason...>`. Also reachable as `gate ledger override-lane ...` through `bin/gate`'s existing forwarder.
- Validation, all before any write, each exit 64 with nothing written:
  - missing rid or lane;
  - reason empty after `oneline` and whitespace trim;
  - lane unknown: `required <lane>` exits non-zero (same fail-closed reading `check()` uses).
- Gate set: `required <lane>` (project-resolved) union `LANES_KIT_ONLY=1 required <lane>` (kit root), deduplicated, in kit plan order. The union matters: the ship-gate floor checks `check full --kit-lanes`, the spec-lane check uses the project-resolved list, and one call must satisfy both.
- Already-disposed gates (a `ran` or `override` GATE line exists for the phase) are skipped and named, never re-labelled as overridden.
- Each remaining gate is written by the existing `override()` with reason `<reason> [lane-override lane=<lane> gate=<phase>]`. The per-gate tag makes each reason distinct, so the 65 guard passes by construction and still blocks a hand-typed `override` that reuses a tagged reason on another gate.
- Then one `ACTION` line: `lane-override lane=<lane> gates=<n> written=<k> reason=<reason>`.
- stdout: one `<phase> override` line per written gate and one `<phase> already-disposed` line per skipped gate, then the `check` verdict the way `plan-record` prints it. stderr: `LANE-OVERRIDE: <k> gate(s) of lane <lane> overridden for run <rid> with one reason; review with: gate-ledger.sh show <rid>`.
- Exit: 0 when the writes happened (k may be 0); 64 on refusal; any non-zero from `override()` propagates, and the message names how many lines were written.
- Invariants: no ledger line format changes; `override` (single gate) and its 65 guard stay byte-identical; `check()`, `progress()`, `descent()`, `lane-telemetry` and the ship-gate need no change.

### Data model changes

None. The ledger gains lines in the existing `GATE ... override` and `ACTION` shapes.

### API changes

One new ledger verb (`override-lane`). The usage line and the header comment of `gate-ledger.sh` list it.

### UI changes

None.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Core

- [ ] TASK-1 (T1): Split `_HP_auth` into the `CORE` / `SESS` / `SDIR` / `MEAN` constants. Apply the path rule in `_path_kind` and in `_floor_scan`'s auth pass. Add the floor-only `HL_SESS` diff rule on the added-lines pass. Extend `case_floor_paths` in `tests/test-lanes-data.sh` and add a session block to `tests/test-lane-classify.sh` (rows in `## Test plan`). Acceptance: AC1 to AC5.
- [ ] TASK-2 (T2): Add `override_lane` and its dispatch, usage, and header lines to `lib/gate/gate-ledger.sh`. Add cases to `tests/test-ledger-durability.sh` beside AC6/AC7. Acceptance: AC6 to AC10.
- [ ] TASK-3 (docs): `lib/gate/README.md` "An override is not a skeleton key" gains the lane-wide override and its stated trade-off (DEC-3); `WORKFLOW.md` "Gate ledger and ship enforcement" names the verb next to `override`. Acceptance: AC11.

## After state

- [ ] `lane-classify.sh explain --files lib/session/observe/bin/session-observe "add a flag"` prints `normal`. (Today: `full`, reason `hard path in --files (auth: lib/session/observe/bin/session-observe)`.)
- [ ] `lane-classify.sh floor <kit> 5030a8cc^ 5030a8cc` prints nothing. (Today: `full auth: lib/session/observe/bin/session-observe`.)
- [ ] `src/auth/session.ts`, `middleware/session.js`, `api/sessions/token.go`, `src/session.ts`, `app/sessions/cookie_store.rb` still hit the floor as `full auth`.
- [ ] `gate-ledger.sh override-lane <rid> full "<reason>"` on an empty run writes 12 GATE override lines and 1 ACTION line, and `check full <rid>` exits 0. (Today: 12 calls, each with its own invented reason.)
- [ ] `override-lane` with an empty reason or an unknown lane exits 64 and writes nothing.

## Acceptance Criteria (global)

Each AC runs with `KIT_PROJECT_ROOT=/nonexistent` for classifier checks (pins the built-in hard paths) and an isolated `DWARVES_KIT_LOG_DIR` for ledger checks.

- [ ] AC1 (false positive gone, `--files`): `bash lib/classify/lane-classify.sh classify --files "<p>" "add a flag"` prints `normal` for `lib/session/observe/bin/session-observe`, `lib/session/session.sh`, `lib/session/recall/session_recall.py`, `lib/session/observe/tests/nondict-edge/proj/session.jsonl`.
- [ ] AC2 (true positives stay full, `--files`): the same command prints `full` for `src/auth/session.ts`, `middleware/session.js`, `api/sessions/token.go`, `src/session.ts`, `app/sessions/cookie_store.rb`, `lib/sessions/oauth/x.go`.
- [ ] AC3 (floor, path rule): in a temp repo (`case_floor_paths` harness), adding each AC2 path makes `floor` print `full auth: <path>`; adding each AC1 path with content `x` prints nothing.
- [ ] AC4 (floor, diff rule): a temp repo adding `src/session/index.ts` with content `app.use(session({ cookie: { httpOnly: true } }))` makes `floor` print `full auth: src/session/index.ts`. The same path with content `x` prints nothing.
- [ ] AC5 (strict narrowing): over the kit's `git ls-files` plus every AC1 to AC4 path, no path is auth under the new rule and not auth under the old `_HP_auth`. The check prints `0` violations (the old regex is held as a literal inside the test).
- [ ] AC6 (one call, full lane): on an empty run, `bash lib/gate/gate-ledger.sh override-lane r1 full "hard path false positive"` exits 0; `show r1` holds 12 `| GATE | <phase> | override | hard path false positive [lane-override lane=full gate=<phase>]` lines and 1 `| ACTION | lane-override lane=full gates=12 written=12 ...` line; `check full r1` exits 0; `check full r1 --kit-lanes` exits 0.
- [ ] AC7 (not silent): the AC6 call prints a `LANE-OVERRIDE:` line on stderr naming the rid, the lane, and the count.
- [ ] AC8 (refusals): `override-lane r2 full ""` and `override-lane r2 full "   "` exit 64; `override-lane r2 bogus "x"` exits 64; `show r2` afterward reports no ledger.
- [ ] AC9 (no relabel): with `record r3 build ran "built"` first, `override-lane r3 full "fp"` writes 11 override lines, none for `build`, and prints `build already-disposed`.
- [ ] AC10 (guard unchanged): after AC6, `override r1 design "hard path false positive [lane-override lane=full gate=spec]"` exits 65; the existing AC6/AC7/S3 rows in `tests/test-ledger-durability.sh` stay green.
- [ ] AC11 (docs): `grep -n "override-lane" lib/gate/README.md WORKFLOW.md lib/gate/gate-ledger.sh` hits all three files, and the README paragraph names the trade-off (one reason now covers every gate of a lane).
- [ ] AC12 (no regression): `bash tests/test-lane-classify.sh`, `bash tests/test-lanes-data.sh`, `bash tests/test-ledger-durability.sh`, `bash tests/test-meta.sh` all exit 0.

## Test plan

| Case | AC | Kind |
|---|---|---|
| four `lib/session/` paths via `classify --files` -> `normal` | AC1 | unit (truth table) |
| six session-auth paths via `classify --files` -> `full` | AC2 | unit (truth table) |
| `case_floor_paths` gains the six AC2 paths in its hit list and the four AC1 paths in its no-hit list | AC3 | unit (real git) |
| `src/session/index.ts` with a cookie/httpOnly line -> `full auth`; same path with `x` -> nothing | AC4 | unit (real git) |
| `lib/session/x.sh` whose added line says `output_tokens += n` -> nothing (bare token is not a signature) | AC4 | unit (real git), edge |
| `docs/session/notes.md` adding `cookie` -> nothing (doc skip holds) | AC4 | unit (real git), edge |
| `lib/session/restore.sh` -> not auth (`restore` is not `store`) | AC1 | unit, edge |
| old-vs-new subset scan over `git ls-files` plus the fixtures: 0 violations | AC5 | property |
| `override-lane` on an empty run: 12 tagged lines, 1 ACTION, `check full` and `check full --kit-lanes` pass | AC6 | unit |
| stderr carries `LANE-OVERRIDE:` | AC7 | unit |
| empty reason, whitespace reason, unknown lane -> 64, no ledger file | AC8 | unit, negative |
| a pre-recorded `build ran` is skipped, 11 lines written | AC9 | unit |
| hand `override` reusing a tagged reason on another gate -> 65; AC6/AC7/S3 rows green | AC10 | regression |
| `floor-timing`, `floor-non-ascii` (`src/auth/prénom.ts`), SPEC-296 block | AC12 | regression |

Negative controls (each must turn a named row red; dry traces in `## Grounding`):

- NC-1: put `|sessions?` back into `CORE`. AC1 rows go red.
- NC-2: drop the `MEAN` clause from the path rule. AC2's `api/sessions/token.go`, `app/sessions/cookie_store.rb`, `lib/sessions/oauth/x.go` rows go red.
- NC-3: drop the floor diff rule. AC4's cookie row goes red.
- NC-4: make `override-lane` skip the lane validation. AC8's `bogus` row goes red.
- NC-5: write one untagged line per gate. AC6 goes red at the second gate (exit 65 from the guard).

## Verification

```bash
bash tests/test-lane-classify.sh
bash tests/test-lanes-data.sh
bash tests/test-ledger-durability.sh
bash tests/test-meta.sh
KIT_PROJECT_ROOT=/nonexistent bash lib/classify/lane-classify.sh floor "$PWD" 5030a8cc^ 5030a8cc   # prints nothing
```

## Grounding

Live samples, run 2026-10-02 in this worktree (`KIT_PROJECT_ROOT=/nonexistent`, so the kit's own `extra_hard_paths` do not mask the built-in rule).

**S1, the retro diff at the floor today.**

```
$ git show --stat --format= 5030a8cc
 docs/verification/observe-cost-dedup.md            | 45 +++++++++++
 lib/session/observe/bin/session-observe            | 89 ++++++++++++++++------
 .../dddddddd-0000-0000-0000-000000000000.jsonl     |  4 +
 .../subagents/agent-a.jsonl                        |  3 +
 lib/session/observe/tests/smoke.sh                 | 20 +++++
$ lane-classify.sh floor "$PWD" 5030a8cc^ 5030a8cc
full auth: lib/session/observe/bin/session-observe
$ git show --format= -U0 5030a8cc -- . ':!*.md' ':!docs/**' | grep '^+' | grep -Eic '<HL_SESS>'
0
```

So under the new rule the retro diff has no path meaning and no diff signature: the floor prints nothing.

**S2, `classify --files` today, per path** (`explain --files <p> "add a flag"`, first two lines):

```
lib/session/observe/bin/session-observe   -> full  reason: hard path in --files (auth: lib/session/observe/bin/session-observe)
lib/session/session.sh                    -> full  reason: hard path in --files (auth: lib/session/session.sh)
src/auth/session.ts                       -> full  reason: hard path in --files (auth: src/auth/session.ts)
middleware/session-store.js               -> normal reason: bounded feature/fix (default)
middleware/session.js                     -> full  reason: hard path in --files (auth: middleware/session.js)
api/sessions/token.go                     -> full  reason: hard path in --files (auth: api/sessions/token.go)
src/session.ts                            -> full  reason: hard path in --files (auth: src/session.ts)
app/sessions/cookie_store.rb              -> full  reason: hard path in --files (auth: app/sessions/cookie_store.rb)
lib/session/recall/session_recall.py      -> full  reason: hard path in --files (auth: lib/session/recall/session_recall.py)
```

Finding: `middleware/session-store.js` is NOT a hard path today (`session-store.js` is neither `session/` nor `session.<ext>`). Pinning it `full` would widen the rule, which this spec forbids (DEC-2). The middleware true-positive row is `middleware/session.js`, which is full today and stays full.

**S3, a prototype of the path rule** (an awk one-off in `$TMPDIR`, the constants above, not committed):

```
old=full  new=-     lib/session/observe/bin/session-observe
old=full  new=-     lib/session/session.sh
old=full  new=-     lib/session/observe/tests/nondict-edge/proj/session.jsonl
old=full  new=full  src/auth/session.ts
old=full  new=full  middleware/session.js
old=-     new=-     middleware/session-store.js
old=full  new=full  api/sessions/token.go
old=full  new=full  src/session.ts
old=full  new=full  app/sessions/cookie_store.rb
old=full  new=-     app/views/sessions/new.html.erb
old=full  new=-     src/session/index.ts          (the floor diff rule recovers it when the diff says cookie/httpOnly/...)
old=full  new=-     lib/session/restore.sh
old=full  new=full  lib/sessions/oauth/x.go
old=-     new=-     src/authors.go
kit git ls-files: old=full 93, new=full 0, new-but-not-old 0
```

**S4, calibrating `HL_SESS` against `lib/session/` content** (`git grep -Eic <word> -- lib/session`, summed):

```
cookie 0 · csrf 0 · httponly 0 · samesite 0 · set-cookie 0 · passport 0 · bcrypt 0
session[_-]?(secret|store|cookie|token) 0 · jwt 1 · password 5 · session[_-]?id 26 · token 261
```

`token` and `session_id` are excluded for that reason. The `jwt`/`password` hits are secret-redaction code in `lib/session/recall/session_recall.py` and its test; an added line there still goes full, which is the safe side (see Edge Cases).

**S5, the lane's required set and the ledger guard today** (isolated `DWARVES_KIT_LOG_DIR`):

```
$ gate-ledger.sh required full          # 12 lines
think design design-critique spec validate design-record test-plan build review docs ship reflect
$ LANES_KIT_ONLY=1 gate-ledger.sh required full | wc -l
12
$ gate-ledger.sh required bogus; echo rc=$?
unknown lane 'bogus' (no valid [lane.bogus] data in kit.toml)
rc=1
$ gate-ledger.sh override demo think "false-positive hard path"; echo rc=$?
rc=0
$ gate-ledger.sh override demo design "false-positive hard path"; echo rc=$?
override rejected: reason already used for another gate in run 'demo' -- each gate override needs its own reason
rc=65
$ gate-ledger.sh check full demo
MISSING-GATE: design (required for lane 'full'; no ran/override entry in the ledger)
...
```

**S6, baseline suites before any change:** `tests/test-lane-classify.sh` `38/38 passed`; `tests/test-lanes-data.sh` `PASS floor-paths`, `PASS floor-timing (180ms for 1000 paths)`, `PASS floor-timing-30k (1757ms for 30000 paths)`; `tests/test-ledger-durability.sh` `37/37 passed`.

**Dry traces of the negative controls.**

- NC-1. Mutation: `CORE` regains `|sessions?`. Fixture: `classify --files lib/session/observe/bin/session-observe "add a flag"`. Path: `main classify` -> `_extract_files` -> `classify_core` step 3 -> `_files_hard_hit` -> `_path_kind` -> `CORE` matches `(^|/)session/` -> `LANE=full`. Red: the AC1 rows in `tests/test-lane-classify.sh` (`expected normal, got full`) and `case_floor_paths` (no-hit list now hits).
- NC-2. Mutation: the path rule becomes `CORE or (SESS and not SDIR)`. Fixture: `api/sessions/token.go`. Path: `CORE` misses; `SESS` matches `sessions/`; `SDIR` matches, so the session clause fails; `_path_kind` returns nothing; `LANE=normal`. Red: the AC2 rows for `api/sessions/token.go`, `app/sessions/cookie_store.rb`, `lib/sessions/oauth/x.go`.
- NC-3. Mutation: delete the `HL_SESS` pass. Fixture: temp repo with `src/session/index.ts` = `app.use(session({ cookie: { httpOnly: true } }))`. Path: `floor` -> `_floor_scan` -> path pass: `SDIR` matches, `MEAN` misses, no path hit -> added-lines pass: no data-loss signature -> (pass deleted) -> prints nothing. Red: the AC4 cookie row (`expected 'full auth: src/session/index.ts', got ''`).
- NC-4. Mutation: `override_lane` drops its `required` exit-code check. Fixture: `override-lane r2 bogus "x"`. Path: `required bogus` fails, its empty output yields zero gates; the verb writes the ACTION line and exits 0. Red: the AC8 `bogus` row (`expected exit 64, got 0`; `show r2` finds a ledger).
- NC-5. Mutation: the tag is dropped, so every line carries the bare reason. Fixture: `override-lane r1 full "hard path false positive"`. Path: gate 1 (`think`) writes; gate 2 (`design`) reaches `override()`'s guard, which finds the same reason on `think` and returns 65; the verb propagates it. Red: AC6 (`expected exit 0 and 12 lines, got 65 and 1 line`).

Not sampled: no external API or CLI output is asserted. The `.kit.toml` overlay union in the gate set is traced from code (`check --kit-lanes` at `hooks/ship-gate.sh` `_floor_check`), not from a live repo with a hollowed project lane.

## Edge Cases

1. `lib/session/restore.sh`: `MEAN` is separator-bounded, so `restore` does not hit `store`. Not auth.
2. `app/views/sessions/new.html.erb` (a Rails login form): no path meaning, so `classify --files` says normal. At the floor, an added line with `password` makes it `full auth` through the diff rule. A view edit with no auth signature ships on its spec lane.
3. `src/session/index.ts` (an express-session module): normal by path; full at the floor when the added lines configure a cookie, secret, or store.
4. A `lib/session/` edit adding a `password` redaction pattern: full at the floor through the diff rule. That is the safe side; the code handles secrets.
5. A session-dir path under a named auth dir (`src/auth/sessions/x.ts`): `CORE` matches `auth/`. Unchanged.
6. A doc under a session dir that says "cookie" (`docs/session/notes.md`): the floor's existing doc skip drops its added lines. Not auth.
7. `override-lane` on a run where every required gate already ran: writes 0 override lines, still writes the ACTION line with `written=0`, exits 0.
8. `override-lane` run twice with the same reason: the second call finds every gate already disposed (`override` counts) and writes 0 gate lines. Idempotent.
9. `override-lane` with a reason containing ` | ` or a newline: `oneline` collapses newlines; the guard's `$5..NF` reconstruction already handles ` | ` (S3 row).
10. A project `.kit.toml` that drops phases from the full lane: the union still overrides the kit root's 12, so the floor's `--kit-lanes` check passes.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| A real session-auth change ships without the full lane (the blind spot) | A session-dir file with auth code but no auth word in the path and no `HL_SESS` word in the added lines | The task-text auth flags (SPEC-296) still suggest full; a repo pins its own dirs via `[lanes] extra_hard_paths`; the word lists are one-line additions |
| The diff rule re-creates the false positive | A tooling PR under `session/` goes full on a word like `password` in a fixture | Expected and safe-side; the operator uses `override-lane` with a reason, which is the audited path |
| `override-lane` becomes the default habit | `lane-override` ACTION lines grow in `lane-telemetry` | Every use is one greppable ACTION line plus tagged GATE lines; the README names when to use it (a confirmed false positive) |
| A partial write mid-loop | `override-lane` exits non-zero after k lines | The message names k; the run re-applies safely because written gates count as already disposed |
| Floor slows on large diffs | `floor-timing` exceeds its limit | One extra awk pass per input file; the timing case guards it |

## Out of Scope

- Making `middleware/session-store.js` (or any `session-<word>.<ext>` file) a hard path. It is not one today; adding it is a widening (DEC-2).
- The task-text auth regex (`_hard_re` auth entry); SPEC-296 already narrowed it.
- Changing `override`'s 65 guard, or the proof-of-done override in `proof-ledger.sh`.
- Advertising `override-lane` in the ship-gate's BLOCKED message (DEC-4).
- Other hard-path kinds (migration, secret, ci, infra, kit-config).

## Touches

- lib/classify/**
- lib/gate/**
- tests/**

## Decision Log

- DEC-1: T1 uses path meaning plus a floor-only diff signal (approach B). Path-only (A) leaves `src/session/index.ts` blind; an allowlist (C) fixes one repo. Rejected: A, C.
- DEC-2: The change is a strict narrowing, held by AC5's subset scan. The lead's example `middleware/session-store.js` is not a hard path today (Grounding S2), so it is not pinned full; `middleware/session.js` takes its place as the middleware row. Rejected: widening `SESS` to `session[-_]<word>` names, which would add new full-lane hits the operator did not ask for.
- DEC-3 (security trade-off, stated plainly): `override-lane` lets ONE reason dispose every required gate of a lane. That deliberately relaxes the per-gate distinct-reason guard (exit 65), whose purpose is to stop one reason pasted across all gates. The relaxation is bounded: the verb is separate from `override`, so the guard on single-gate overrides is unchanged; every gate still gets its own GATE line, tagged with the lane and the gate, so `check()`, the ship-gate, `progress`, and `lane-telemetry` read it as today; one ACTION line and one stderr line mark the event; and a gate that already ran is never relabelled. Accepted risk: an agent that wants to skip a lane can now do it in one call instead of twelve. The guard never stopped that (twelve suffixed reasons were always possible); it only made it tedious, and the tedium fell hardest on honest false positives.
- DEC-4: The ship-gate BLOCKED message keeps pointing at per-gate `override`. Advertising `override-lane` at the block point would make the bypass the path of least resistance. It is documented in `lib/gate/README.md` and `WORKFLOW.md`. Rejected: a hooks/ edit.
- DEC-5: New verb `override-lane`, not a magic `all-lane` phase on `override` (E) and not `plan-record` (F). The verb leaves `override`'s contract byte-identical.
- DEC-6: The gate set is the union of the project-resolved and kit-root `required` lists, so one call satisfies both the spec-lane check and the floor's `--kit-lanes` check.
- DEC-7: Unknown lane and empty reason exit 64 ("wrote nothing, correct the argument"), matching `plan-record` and `validate-round`; `check()` keeps its own exit 1.
- DEC-8: The narrowing also lowers the negative-control obligation for `lib/session/` edits in a repo with `[gate] negative_control = full`, because `proof-ledger.sh _negctl_required` reads the same floor. Accepted as the intended consequence: those paths were never auth.

## Open questions

(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
