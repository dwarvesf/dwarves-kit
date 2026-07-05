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
$ (cd "$T" && bash <kit>/lib/gate/proof-gate.sh contract "add a data-pull CLI command")
type=data-tool class=behavioral
$ (cd "$T" && bash <kit>/lib/gate/proof-gate.sh contract "benchmark tool X vs Y")
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

---

## 2026-06-10 hardening: @AGENTS.md loader + --dry-run/--refresh (PR #25), review-driven fixes

The absorption PR (A1 `@AGENTS.md` import, A2 `--dry-run`/`--refresh`) went through the kit's own
3-lens review-team. Review caught a **CRITICAL data-loss path** (3 reviewers independently): on
`--refresh`, the awk block-strip ran to EOF when the `<!-- /kit:adopt -->` END marker was missing,
silently truncating CLAUDE.md. Fixed: a pre-check refuses `--refresh` when START has no matching
END, an awk `END{if(drop)exit 3}` + `|| exit 1` backstop, exact-line (`grep -qxF`) marker matching,
atomic WORKFLOW.md write, a temp-cleanup trap, and `cmp`-before-reporting-"updated".

### GREEN: --refresh refuses to truncate (the fix)

```
$ R=$(mktemp -d); git -C "$R" init -q; bash lib/adopt.sh "$R" >/dev/null
$ printf 'IMPORTANT-PROJECT-RULES-AFTER-BLOCK\n' >> "$R/CLAUDE.md"
$ grep -v '<!-- /kit:adopt -->' "$R/CLAUDE.md" > x && mv -f x "$R/CLAUDE.md"   # drop the END marker
$ wc -l < "$R/CLAUDE.md"          # 9
$ bash lib/adopt.sh --refresh "$R"
adopt: ... has '<!-- kit:adopt -->' but no '<!-- /kit:adopt -->' line; refusing --refresh (would truncate).
$ echo $?                          # 1
$ wc -l < "$R/CLAUDE.md"          # 9 (untouched; the tail line survived)
```

### NEGATIVE CONTROL: the OLD awk on the same file (proves the bug was real)

```
$ awk -v s='<!-- kit:adopt -->' -v e='<!-- /kit:adopt -->' \
    '$0==s{drop=1} drop&&$0==e{drop=0;next} !drop{print}' "$R/CLAUDE.md" | wc -l
1     # the pre-fix code collapses 9 lines to 1: it would have eaten the project rules
```

### Suite (expanded)

`bash tests/test-adopt.sh` -> PASS=12 FAIL=0 (added: refuse-on-missing-END, real stale-body
re-sync, no-clobber-on-refresh of AGENTS.md + proof marker, dry-run-on-adopted writes nothing).
`bash tests/test-meta.sh` -> 392/392.

## Verdict: PASS (review-hardened)
