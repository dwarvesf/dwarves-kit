# Proof of done: loop-engineering contract backfill (SPEC-209, ID-452 item 2/6)

Backfills spec + test coverage for `skills/loop-engineering/SKILL.md`, a prompt-file skill that previously had neither. The suite pins the skill's contract claims (four gate criteria, three shapes + routing question, severity-aware convergence, two-tier scan contract, campaign-reuses-Goal-loop, search-select preconditions + two mandatory adaptations, lineage claim structure) as grep assertions, one per SPEC-209 Test plan row.

## Confirmation runs

| # | Check | Command | Exit | Verdict |
|---|---|---|---|---|
| 1 | New suite green | `bash tests/test-loop-engineering-contract.sh` | 0 | PASS (32/32) |
| 2 | Negative control | strip the flat-K sentence from the tracked SKILL body, re-run suite | 1 | RED (30/32, exactly the 2 predicted FAILs) |
| 3 | Restore | `mv` the sed backup over the file, re-run suite | 0 | PASS (32/32), sha256 byte-identical |
| 4 | Meta suite | `bash tests/test-meta.sh` | 0 | PASS (732/732) |

## Run detail

Run 2 removed only the sentence `A flat K still counts as progress if the worst severity dropped.` from `skills/loop-engineering/SKILL.md` (substring removal via `sed`, NOT a whole-line delete: row 13's pin and row 14's first fragment share one physical line of the body, the same adjacency class SPEC-208's critique caught, so only a substring strip keeps the blast radius at one fragment). Exactly two assertions went RED, both predicted in SPEC-209 row 28:

- `row 14: severity-aware convergence rule (two fragments)` (the pinned claim, gone from the file)
- `NC setup: the strip actually changed the scratch copy` (the in-suite negative control found nothing left to strip, an expected, named side effect, not a blast-radius surprise)

The other 30 assertions stayed green. In particular, three predicted survivors confirm the pins discriminate rather than co-fire: row 14's first fragment (previous physical line), row 13's pin (same physical line as that fragment), and row 24's Lineage restatement (`A flat finding-count still counts`, deliberately different wording). Run 3 restored the file and verified byte-identity: sha256 identical before and after (prefix `f9fb5c9665bb`, truncated here because the repo's secret-guard hook rejects full 64-hex literals in authored files; re-derive with `shasum -a 256 skills/loop-engineering/SKILL.md`), and `git status --porcelain` clean on the path.

The suite also carries a PERMANENT in-suite negative control (SPEC-209 row 27): every invocation strips the same sentence from a mktemp scratch copy (tracked file untouched) and asserts the stripped fragment fails on the copy while the three neighbor pins still pass. Falsifiability re-proves itself on every run, mirroring `tests/test-memory-tidy-contract.sh`.

## Reproduce

```
bash tests/test-loop-engineering-contract.sh
# live negative control:
sed -i.bak 's/A flat K still counts as progress if the worst severity dropped\. //' skills/loop-engineering/SKILL.md
bash tests/test-loop-engineering-contract.sh   # expect exit 1, exactly 2 FAIL (row 14 + NC setup)
mv -f skills/loop-engineering/SKILL.md.bak skills/loop-engineering/SKILL.md
bash tests/test-loop-engineering-contract.sh   # expect exit 0, 32/32
bash tests/test-meta.sh
```

Full trail: SPEC-209 (`docs/specs/SPEC-209-loop-engineering-contract.md`), including the 3-lens critique (rounds 13 -> 3 findings, max severity HIGH -> LOW, verdict SOLID) and the honest lens-skip triage.
