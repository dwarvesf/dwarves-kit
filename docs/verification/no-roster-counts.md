# Proof of done: no-counts policy (retire literal roster numbers from the docs)

Profile: fix   Proof class: behavioral

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | README.md and docs/architecture.md carry no literal roster counts (headers, layout comments, headline tally) | PASS | R1 |
| 2 | Row-completeness checks survive: live tree vs doc table rows, both sides computed, no maintained number | PASS | R1 |
| 3 | A reintroduced count fails the new tripwire (negative control) | PASS | R2 |
| 4 | `sync_counts` (whose sole job was maintaining those numbers) is gone; a suite run leaves the tree byte-identical | PASS | R3 |

## 2. Rationale and implementation

Operator policy (2026-08-10): roster counts in prose churn on every addition and cost more to
maintain than they inform. The ops-toolkit convention already says it: "no hardcoded counts in
docs; if a count is load-bearing, derive it."

| Aspect | Detail |
|---|---|
| Docs | README.md: numbers stripped from the Hooks/Commands/Agents+Skills summary headers and the three directory-layout comments. architecture.md: the `Total: N commands + N agents = **N entries**.` headline removed (the inventory table itself is the truth). |
| Registry | `lib/registry/feature-registry.sh` loses `sync_counts` and its call: with no numbers to sync, its only remaining effect was rewriting files. `generate` still produces `docs/FEATURES.md` unchanged. |
| Tests | `tests/test-meta.sh`: the literal-number assertions (SPEC-113 layout counts, SG-10 header counts, architecture headline, SPEC-085 summary parity) are replaced by two NO-COUNT tripwires (a stray number failing loudly) while every row-completeness check stays: README hooks/commands/agents/skills table rows == live files, architecture inventory rows == live count. A new command still cannot ship without its doc rows. |
| Reversibility | `git revert`. |

## 3. Confirmation (runs)

| Run | Command | Exit | Verdict |
|---|---|---|---|
| R1 | `bash tests/test-meta.sh` on the de-numbered tree | 0 | PASS (799/799) |
| R2 | reintroduce `(36, ` in the Commands header, rerun | 1 | RED: `README carries no literal roster counts ... got '1'` |
| R3 | checksum README/architecture/FEATURES, run suite, re-verify | 0 | byte-identical |

## 4. Run detail

### R1 GREEN
```
Passed: 799 / 799
All meta tests passed.
```
(Total assertions drop from 809: the retired count assertions leave the suite, the two
tripwires join it.)

### R2 NEGATIVE CONTROL
```
FAIL README carries no literal roster counts (headers/layout) (expected '0', got '1')
```
A process note for honesty: the first restore after this control used `git checkout --
README.md` while the de-numbering edits were still unstaged, reverting them to the committed
(counted) version; the tripwire then reported all 6 original counts, which is itself a second
demonstration that it catches real strays. Edits re-applied and staged; final state green.

### R3 NO-MUTATION
```
suite exit=0
README.md: OK
docs/architecture.md: OK
docs/FEATURES.md: OK
```

## 5. Reproduce

```
bash tests/test-meta.sh
grep -cE '<b>(Agents|Commands|Skills|Hooks)</b> \([0-9]+' README.md   # 0
```
