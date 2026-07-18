# Proof of done: ledger-observatory feature `schema` (SG-01, ledger-event schema)

> Per-feature record. The canonical multi-feature index is
> [`../proof-of-done.md`](../proof-of-done.md); this file is its `schema` feature detail.

| | |
|---|---|
| **Profile** | doc + contract (no app behavior) |
| **Proof class** | data-tool (spec/port the surface -> build -> recorded live run + negative control) |
| **Work-type dialect** | data-tool |
| **Spec** | [`../specs/SPEC-126-ledger-event-schema.md`](../specs/SPEC-126-ledger-event-schema.md) |
| **Canonical** | the tool index [`../proof-of-done.md`](../proof-of-done.md) (this is the `schema` feature detail) |

## 1. Acceptance criteria

| # | Criterion (measurable) | Status | Evidence |
|---|---|---|---|
| AC1 | Canonical schema doc names the kit's real `ISO8601 \| VERB \| payload` grammar, states plainly which verbs are k=v and which aren't | PASS | R1 |
| AC2 | Doc confirms the ~10 existing kit stores (backed by real greps, not memory) | PASS | R1 |
| AC3 | Planned `DEBT` (understanding-gate) + `TOKENS` (kit-face) marker shapes confirmed to conform on arrival | PASS | R2 |
| AC4 | 3 outlier adapter contracts specified (field-map + sample record); tg-cleanup sample is synthetic, verified no real data | PASS | R1, R3 |
| AC5 | Conformance check + tests: real line passes, DEBT/TOKENS pass, malformed line REJECTED (negative control), 3 outlier samples parse | PASS | R2 |
| AC6 | Read-only: no producer ledger's format changed, no live log dir written to | PASS | R2, R4 |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | Schema doc + adapter contracts + a grep/parse conformance checker + its test suite; no code implementing the adapters (02's job) |
| Where | `tools/ledger-observatory/{README.md,docs/{ledger-event-schema.md,adapter-contracts.md},tests/{lib/conform.sh,test-schema-conform.sh}}` |
| How it runs | `bash tools/ledger-observatory/tests/test-schema-conform.sh`, no daemon, no engine |
| Touches | Additive only; `lib/gate-ledger.sh`, `tide`, `tg-cleanup` all read, none modified |

## 3. Confirmation run table

| # | Command | Result |
|---|---|---|
| R1 | `bash tools/ledger-observatory/tests/test-schema-conform.sh` (outlier + Tier-A section) | 11/11 PASS |
| R2 | same run, negative-control section (`no timestamp` / `unknown verb` / `no pipe delimiters` / `START missing token`) | all 4 correctly REJECTED |
| R3 | `python3` scan of `adapter-contracts.md` against the live `tg-cleanup/*.json` titles/ids | no real-value leak (2 substring false positives on single letters, verified benign) |
| R4 | `shellcheck tests/lib/conform.sh tests/test-schema-conform.sh` | exit 0, no findings |

## 4. Run detail

Command: `bash tools/ledger-observatory/tests/test-schema-conform.sh`

```
$ bash tools/ledger-observatory/tests/test-schema-conform.sh
== Tier A: a real line copied from a live kit ledger ==
PASS  real live kit line passes (PASS START)

== Tier A: the planned debt + token marker shapes (generated, never hand-typed) ==
PASS  generated TOKENS line passes (kit-face SG-03 shape) (PASS TOKENS)
PASS  generated DEBT line passes (understanding-gate SG-02 shape) (PASS DEBT)

== Negative control: a malformed line is REJECTED (load-bearing) ==
NEGATIVE CONTROL:
PASS  no timestamp (FAIL not an ISO8601 UTC timestamp: 'not-a-timestamp')
PASS  unknown verb (FAIL unknown verb: 'BOGUS' (want one of START|START-AMEND|GATE|ACTION|TOKENS|DEBT))
PASS  no pipe delimiters at all (FAIL not an ISO8601 UTC timestamp: 'just a plain line with no structure whatsoever')
PASS  START missing required k=v token (FAIL START payload missing required token 'lane=')

== Outlier adapter samples parse under their contract ==
PASS  learned-ledger.md sample matches its 5-column contract
PASS  learned-ledger.md sample is the one actually embedded in adapter-contracts.md
PASS  tide state.sqlite 'moves' field-map matches tools/tide/src/tide/state.py
PASS  tg-cleanup sample record has every field the adapter contract claims

== 11 passed, 0 failed ==
```

Exit: 0
Verdict: PASS

## 5. Reproduce

```bash
cd ~/workspace/<owner>/ops-toolkit
bash tools/ledger-observatory/tests/test-schema-conform.sh
```

## 6. Rollback

This branch is additive-only (no existing file modified or deleted; confirmed by
`git diff main --stat` showing 0 deletions) and touches no runtime state, daemon, or
live store. Rollback = `git revert` this branch's commits, or simply delete
`tools/ledger-observatory/`; nothing else in the repo references it yet (SG-01 is the
first sub-goal, seeding the folder SG-02 builds on).
