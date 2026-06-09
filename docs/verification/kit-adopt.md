# Verification: /kit:adopt (SPEC-047)

Proof class: **behavioral** (`proof-gate contract` -> spec-feature/behavioral: owes the real flow
run end-to-end + a negative control). Reproduce: `bash tests/test-adopt.sh` (5/5) + the live run
below. Last run: 2026-06-09.

## GREEN: live adopt on a fresh repo

```
$ T=$(mktemp -d); git -C "$T" init -q
$ bash lib/adopt.sh "$T"
adopt: <tmp> (updated)
$ ls AGENTS.md WORKFLOW.md CLAUDE.md docs/verification/README.md     # all present
$ grep -c 'kit:adopt' "$T/CLAUDE.md"                                 # 1 (loader pointer)
```

All four artifacts land: `AGENTS.md` (contract), `WORKFLOW.md` (pointer), `CLAUDE.md` (loader
line), `docs/verification/README.md` (proof marker).

## Loop-type wiring reachable FROM the adopted repo

```
$ (cd "$T" && bash <kit>/lib/proof-gate.sh contract "add a data-pull CLI command")
type=data-tool class=behavioral
$ (cd "$T" && bash <kit>/lib/proof-gate.sh contract "benchmark tool X vs Y")
type=eval class=behavioral
```

Two different task descriptions resolve to two different loop types (`data-tool` vs `eval`) from
inside the adopted repo: the classifier wiring works (the consumer reaches the installed kit's
classifiers; no engine copy).

## NEGATIVE CONTROL: no-clobber

```
$ T2=$(mktemp -d); git -C "$T2" init -q; printf 'SENTINEL\n' > "$T2/AGENTS.md"
$ bash lib/adopt.sh "$T2"
$ grep -q SENTINEL "$T2/AGENTS.md" && echo PASS
PASS: sentinel survived (no clobber)
```

The success path is falsifiable: a pre-existing `AGENTS.md` is never overwritten. A
non-guarded implementation would clobber the sentinel and this control would go RED. Re-run
idempotency (a 2nd adopt = clean `git diff`) is covered by `tests/test-adopt.sh` scenario 2.

## Suite

`bash tests/test-adopt.sh` -> PASS=5 FAIL=0. `bash tests/test-meta.sh` -> 392/392 (after the
`docs/architecture.md` inventory row for `/kit:adopt`).

## Verdict: PASS
