# Proof of Done: learn

**Feature:** the module's front door (`lib/learn/README.md`) + its own acceptance record, closing the other two `lib/gate/*` / `lib/learn/*` IOUs in `tests/kit-contract-known-gaps.txt`.
**Date:** 2026-07-15 · **Lane:** docs · **Host:** Hans-Air-M4 (macOS 26.5, bash 3.2, Python 3.13) · **Branch:** `feat/retro-propose`

`learn` is the Learn leg's home: the read-and-propose side of the harness loop. It had SPEC-195,
SPEC-196, SPEC-126 and ADR-0034, 64 passing assertions, and **no module-level README and no proof
of its own**. The specs describe each verb. Nothing described the *module*, and in particular
nothing stated plainly what `staging-format.py` is for or who is actually using it.

This change is **documentation only**. No line of any `lib/learn/*` script was touched. Writing it
surfaced a divergence between the kit's stated contract and its code, recorded in full below.

## Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| A1 | The module has a README front door: what it IS, its callables, where its specs live, where its tests live | task; C3 |
| A2 | The module has its own `docs/proof-of-done.md` | task; C3 |
| A3 | `staging-format.py`'s role is explicit: the ONE block grammar, both read and write | task |
| A4 | The "every proposer renders through it" claim is **verified against the code**, not restated from the spec | house rule: no invented behavior |
| A5 | `bash tests/test-kit-contract.sh` stays green at 24, and the two closed IOUs are gone from the gaps file | task |
| A6 | The contract lint genuinely watches `lib/learn` (not merely green because it skips it) | NEGATIVE CONTROL |
| A7 | Behavior unchanged (docs only) | scope fence |

## Implementation

| Piece | What | Where |
|---|---|---|
| README | Front door: propose-don't-dispose, the three verbs, the three stages of `propose`, the `staging-format.py` grammar table, the convergence audit, three pitfalls | `lib/learn/README.md` |
| Proof | this file | `lib/learn/docs/proof-of-done.md` |
| Gaps closed | `lib/learn/README.md` + `lib/learn/docs/proof-of-done.md` removed from the IOU list | `tests/kit-contract-known-gaps.txt` |
| Gap kept | `lib/learn/SPEC` stays: C3 accepts a spec only INSIDE the module dir, and learn's specs are all repo-root numbered ones | `tests/kit-contract-known-gaps.txt` |
| Divergence recorded | the two proposers that still carry their own renderer copy, with a repro | this file, "The convergence claim" |

## Confirmation run-table

| # | Check | Command | Expected | Result |
|---|---|---|---|---|
| 1 | `propose`: grounding, dedup, fail-closed refute, `--retro`, sanitization (A3) | `bash tests/test-learn-propose.sh` | 41/41, exit 0 | PASS |
| 2 | `drain`: render, promote-numbering parity, expiry, move-not-delete (A3) | `bash tests/test-learn-drain.sh` | 23/23, exit 0 | PASS |
| 3 | The renderer really sanitizes (A3) | `test-learn-propose.sh` "figure sanitization" | a newline-laden field stays ONE block | PASS |
| 4 | Who actually imports `staging-format.py` (A4) | `grep` the writers, read each one | 4 import it, **2 keep a copy** | **PASS (finding)** |
| 5 | The copies have drifted (A4) | the repro in "The convergence claim" below | hook copy forges a 2nd block; shared renderer does not | **PASS (finding)** |
| 6 | Kit contract green, IOUs closed (A5) | `bash tests/test-kit-contract.sh` | 24 passed, 0 failed | PASS |
| 7 | **NEGATIVE CONTROL**: the lint really watches `lib/learn` (A6) | yank `README.md`, re-run the contract | C3 goes RED naming `lib/learn/README.md` | PASS |
| 8 | **NEGATIVE CONTROL**: expiry moves, never deletes (A3) | `test-learn-drain.sh` AC4 | one header token changes; no body line lost | PASS |
| 9 | **NEGATIVE CONTROL**: `propose` never writes a board (A3) | `test-learn-propose.sh` T7f | board byte-identical after `propose --retro` | PASS |
| 10 | Behavior unchanged (A7) | `git diff --stat lib/learn/` | only `README.md` + `docs/proof-of-done.md` | PASS |

## Run detail

Both learn suites, verbatim tails (`Exit: 0`):

```
$ bash tests/test-learn-propose.sh | tail -2; echo "Exit: $?"
== 41 run, 41 passed, 0 failed ==
Exit: 0

$ bash tests/test-learn-drain.sh | tail -2; echo "Exit: $?"
TOTAL: 23   PASS: 23   FAIL: 0
Exit: 0
```

The assertions that back the README's specific claims:

```
== anchored dedup (SPEC-144 Run-3): a suffix-key survives, an exact-key drops ==
  PASS  dedup: suffix-key proposal is NOT wrongly deduped (survives)
  PASS  dedup: exact normalized-key duplicate of a rejected row IS dropped
== adversarial drop: a REFUTED hypothesis is dropped (fail-closed also drops garbled) ==
  PASS  adversarial: REFUTED proposal NOT staged
  PASS  fail-closed: a garbled/no-clear verdict drops the proposal
== figure sanitization: a multi-line / pipe-laden figure stays one Source line ==
  PASS  sanitize: exactly one staged block (figure newline did not split it)
  PASS  sanitize: block round-trips under the reader (still one parsed block)
== subprocess failure: a crashing interpreter degrades to honest-empty (exit 0) ==
  PASS  subprocess-fail: exit 0 (never blocks)

=== AC2: numbering parity with board promote ===
  PASS AC2 drain index == board promote index for the same candidate (2 == 2)
=== AC4: NEGATIVE CONTROL, move-not-delete (byte-diff) ===
  PASS AC4a exactly one line pair changed (the Old-candidate header only)
  PASS AC4c nothing deleted: every original body line still present
```

`AC2` is the one that pins the README's first pitfall: `drain` renders grouped-and-sorted but
numbers in file order, and that number **is** `board promote`'s number. The test asserts the two
indices agree, so a future "let me tidy the numbering" change fails loudly instead of silently
promoting the wrong row.

## The convergence claim, and where it is false

The task that produced this doc asked it to state that `staging-format.py` is the ONE renderer and
that, as of 2026-07-15, **every** proposer in the kit goes through it. Contract rule **C5** asserts
the same thing, and C5 is green.

Reading the code, that is true of four writers and false of two. Every `## [staged]` writer in
`lib/` and `hooks/`, and what it actually renders through:

| Writer | Renders via | |
|---|---|---|
| `lib/learn/propose.py` (both the ledger path and `--retro`) | `importlib` loads `staging-format.py`; calls `sf.render_block` | converged |
| `lib/learn/drain.py` | loads it; `sf.parse_blocks` (read side) | converged |
| `lib/session/audit/bin/session-audit` | loads it; `sf.render_block` (line 210) | converged |
| `lib/session/intel/bin/session-intel` | loads it; `sf.render_block` (line 317) | converged |
| `lib/stats/src/stats/anomalies.py` | **its own** `def render_block()` (line 699) | **copy** |
| `hooks/backlog-stage.py` | **its own** `def render_candidate()` (line 199) | **copy** |
| `lib/board/bin/add-backlog` | its own `parse_staging()` | the promoter; C5-exempt by name, and `staging-format.py`'s docstring already admits this one |

**C5 cannot see the difference.** Its check is a grep for a *code reference* to
`staging.format|staging_format|render_block|render_candidate`, and a file that **defines**
`render_block` matches its own grep. C5's negative control plants the comment-mention evasion (a
bespoke writer that name-drops the renderer in a comment), so this shape, a writer that keeps a
same-named local function, was never tested. The rule is passing vacuously for exactly the two
files it most needs to catch.

### The copies have already drifted, and one of them is a live hole

This is not cosmetic duplication. `render_block` in `staging-format.py` collapses **all**
whitespace in every field (`_flat()`), a guard a review added precisely because these fields now
carry LLM-authored text derived from transcripts. `hooks/backlog-stage.py`'s copy predates it and
uses a bare `.strip()`, which removes only *leading and trailing* whitespace. An embedded newline
survives, and the block grammar is line-oriented, so the field forges a second block.

The hook in question is the session-end backlog stager. Its candidate fields are extracted from
session transcripts by a model. That is exactly the attacker-influenceable input the guard exists
for.

```
$ python3 - <<'PY'
import importlib.util
def load(n, p):
    s = importlib.util.spec_from_file_location(n, p)
    m = importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
sf = load("sf", "lib/learn/staging-format.py")   # the ONE renderer
bs = load("bs", "hooks/backlog-stage.py")        # the hook's own copy

# One candidate. Its Intent carries an embedded newline: the shape a model extracting
# from a transcript can emit, and the shape render_block's _flat() exists to kill.
cand = {"title": "fix the thing",
        "intent": "ok\n\n## [staged] FORGED ROW\n- Intent: injected",
        "approach": "a", "u": "lo", "f": "mid"}
shared = sf.render_block(dict(cand, source="session 2026-07-15"))
hook   = bs.render_candidate(cand, "2026-07-15")
print("blocks parsed from the SHARED renderer's output:", len(sf.parse_blocks(shared)))
print("blocks parsed from the HOOK COPY's output:      ", len(sf.parse_blocks(hook)))
print("\n--- hook copy output (note the forged second block) ---")
print(hook, end="")
PY
blocks parsed from the SHARED renderer's output: 1
blocks parsed from the HOOK COPY's output:       2

--- hook copy output (note the forged second block) ---
## [staged] fix the thing
- Intent: ok

## [staged] FORGED ROW
- Intent: injected
- Approach: a
- Tags: #u-lo #f-mid
- Source: session 2026-07-15

Exit: 0
```

One candidate in, two staged rows out. The forged row is indistinguishable from a real proposal to
`drain` and to `board promote`, which is a path from model-authored transcript text to a row a human
approves onto the board.

`lib/stats/src/stats/anomalies.py`'s copy has no sanitisation either, but its fields come from an
internally-constructed `Anomaly` dataclass rather than model output, so it is a latent duplicate
rather than a live hole today.

**Left unfixed on purpose.** This change is docs-only (A7), and the fix is a behavior change in two
modules outside `lib/learn/`, plus a tightening of C5 so it distinguishes importing the renderer
from defining a function with the same name. That needs its own spec. It is recorded here, in the
README, and in `tests/kit-contract-known-gaps.txt` so it is loud instead of invisible.

## NEGATIVE CONTROL

Adding two markdown files and watching a suite stay green proves nothing: **a lint that skips the
module would also stay green.** The claim under test is "C3 now watches `lib/learn`". Break it on
purpose.

```
$ mv lib/learn/README.md /tmp/learn-readme.bak
$ bash tests/test-kit-contract.sh
== C3 docs: README + SPEC + proof-of-done per module ==
  FAIL every module has README + a spec + docs/proof-of-done.md (no NEW gaps) (offenders: lib/learn/README.md )
=== kit-contract: 23 passed, 1 failed ===
Exit: 1

$ mv /tmp/learn-readme.bak lib/learn/README.md   # restore
$ bash tests/test-kit-contract.sh | tail -1
=== kit-contract: 24 passed, 0 failed ===
Exit: 0
```

The path was previously listed in `tests/kit-contract-known-gaps.txt`, so C3 counted it as a known
gap and stayed green whether the file existed or not. Removing the IOU line is what arms the check.

### The module's own negative controls

`propose` and `drain` each carry the control that matters for their central promise.

**`propose` must never file to a board** (propose-don't-dispose). T7f asserts the board is
byte-identical after a `--retro` run that staged rows:

```
  PASS  T7f NC: the board is byte-identical after propose --retro
  PASS  T7d NC: a checked [x] item is NOT staged
  PASS  T7e NC: the template placeholder is NOT staged
  PASS  T7h NC: --dry-run writes NO staging file
```

**`drain` must move, never delete.** AC3 through AC6 force the distinction: a 31-day row expires, a
5-day row does not, the byte-diff shows exactly one changed header token, a re-run is a no-op, and
the expired row becomes unselectable in `board promote` without the promoter changing at all:

```
=== AC3: NEGATIVE CONTROL, expiry (31d expires, 5d does not) ===
  PASS AC3a Old candidate (31d) moved to [expired]
  PASS AC3b Recent candidate (5d) still [staged]
=== AC5: NEGATIVE CONTROL, idempotency (immediate re-run expires nothing new) ===
  PASS AC5 re-run is a byte-identical no-op
=== AC6: NEGATIVE CONTROL, promote-unchanged (add-backlog untouched, expired unselectable) ===
  PASS AC6a expired candidate absent from board promote's numbered list
  PASS AC6d the promoted candidate is the recent one, not the expired one
```

## Reproduce

```bash
bash tests/test-learn-propose.sh   # 41 run, 41 passed, 0 failed
bash tests/test-learn-drain.sh     # TOTAL: 23   PASS: 23   FAIL: 0
bash tests/test-kit-contract.sh    # 24 passed, 0 failed

# the negative control
mv lib/learn/README.md /tmp/learn-readme.bak
bash tests/test-kit-contract.sh    # C3 RED, names lib/learn/README.md
mv /tmp/learn-readme.bak lib/learn/README.md

# the renderer divergence: run the heredoc in "The convergence claim" above, from the repo root.
# Expect "1" for the shared renderer and "2" for the hook copy: one candidate, two staged rows.

git diff --stat lib/learn/            # only README.md + docs/proof-of-done.md: behavior unchanged
```
