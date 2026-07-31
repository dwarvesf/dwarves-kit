# Proof of done: memory-tidy contract backfill (SPEC-208, ID-452 item 1/6)

Backfills spec + test coverage for `skills/memory-tidy/SKILL.md`, a prompt-file skill that previously had neither. The suite pins the skill's contract claims (four-slot verdict grammar with per-slot evidence, UNSURE-never-deleted, PR gate, derived index, danger check, read-only fan-out, apply-step safety) as grep assertions, one per SPEC-208 Test plan row.

## Confirmation runs

| # | Check | Command | Exit | Verdict |
|---|---|---|---|---|
| 1 | New suite green | `bash tests/test-memory-tidy-contract.sh` | 0 | PASS (28/28) |
| 2 | Negative control | strip the UNSURE sentence from the tracked SKILL body, re-run suite | 1 | RED (26/28, exactly the 2 predicted FAILs) |
| 3 | Restore | `mv` the sed backup over the file, re-run suite | 0 | PASS (28/28), sha256 byte-identical |
| 4 | Meta suite | `bash tests/test-meta.sh` | 0 | PASS |

## Run detail

Run 2 removed only the sentence `UNSURE notes are never deleted; list them in the report.` from `skills/memory-tidy/SKILL.md` (substring removal via `sed`, NOT a whole-line delete: the row-13 pin `A verdict with no checkable evidence is not actionable` shares the same physical line, so a line delete would flip two content rows; the SPEC-208 critique round 1 proved this by simulation). Exactly two assertions went RED, both predicted in SPEC-208 row 26:

- `row 14: UNSURE never deleted + operator list` (the pinned claim, gone from the file)
- `NC setup: the strip actually changed the scratch copy` (the in-suite negative control found nothing left to strip, an expected side effect, not a blast-radius surprise)

The other 26 assertions stayed green, confirming the suite pins the claim it targets, not incidental state. Run 3 restored the file and verified byte-identity: sha256 identical before and after (prefix `c60bdb3d965ca896`, truncated here because the repo's secret-guard hook rejects full 64-hex literals in authored files; re-derive with `shasum -a 256 skills/memory-tidy/SKILL.md`), and `git status --porcelain` clean on the path.

The suite also carries a PERMANENT in-suite negative control (SPEC-208 row 25): every invocation strips the same sentence from a mktemp scratch copy (tracked file untouched) and asserts row 14's pin fails on the copy while row 13's pin still passes. Falsifiability re-proves itself on every run, mirroring `tests/test-test-writer-contract.sh` AC3.

## Reproduce

```
bash tests/test-memory-tidy-contract.sh
# live negative control:
sed -i.bak 's/ UNSURE notes are never deleted; list them in the report\.//' skills/memory-tidy/SKILL.md
bash tests/test-memory-tidy-contract.sh   # expect exit 1, exactly 2 FAIL (row 14 + NC setup)
mv -f skills/memory-tidy/SKILL.md.bak skills/memory-tidy/SKILL.md
bash tests/test-memory-tidy-contract.sh   # expect exit 0, 28/28
bash tests/test-meta.sh
```

Full trail: SPEC-208 (`docs/specs/SPEC-208-memory-tidy-contract.md`), including the 3-lens critique (rounds 11 -> 2 findings, max severity CRITICAL -> LOW, verdict SOLID) and the honest lens-skip triage.
