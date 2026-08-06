# Proof of done: research-architecture contract backfill (SPEC-210, ID-452 item 3/6)

Backfills spec + test coverage for `agents/research-architecture.md`, a read-only research subagent that previously had neither, AND its dispatch contract in `commands/spec.md` Step 2, pinned from both sides. The suite pins identity + auto-delegation description, the exact 5-entry read-only tool roster (with a no-write-grant negative), the Mode A dispatch line, the Mode B inline fallback prompt, the brownfield gate, cross-file write-target agreement, the six research question labels, the mcp routing sentence, the output template, the three rules, and the SPEC-087 distilled-return contract; one assertion per SPEC-210 Test plan row.

## Confirmation runs

| # | Check | Command | Exit | Verdict |
|---|---|---|---|---|
| 1 | New suite green | `bash tests/test-research-arch-contract.sh` | 0 | PASS (28/28) |
| 2 | Negative control | strip the patterns-not-listings sentence from the tracked agent body, re-run suite | 1 | RED (26/28, exactly the 2 predicted FAILs) |
| 3 | Restore | `mv -f` the sed `.bak` over the file, re-run suite | 0 | PASS (28/28), sha256 byte-identical |
| 4 | Meta suite | `bash tests/test-meta.sh` | 0 | PASS (732/732) |

## Run detail

Run 2 removed only the sentence ` Patterns, not exhaustive listings.` from `agents/research-architecture.md` (substring removal via `sed -i.bak`, NOT a whole-line delete: row 16's pin `Max 60 lines.` and row 17's pin share one physical line of the body, the adjacency class SPEC-208's critique first caught, so only a substring strip keeps the blast radius at one pin). Exactly two assertions went RED, both predicted in SPEC-210 row 25:

- `row 17: patterns-not-listings rule` (the pinned claim, gone from the file)
- `NC setup: the strip actually changed the scratch copy` (the in-suite negative control found nothing left to strip, an expected, named side effect, not a blast-radius surprise)

The other 26 assertions stayed green. In particular, the predicted survivors confirm the pins discriminate rather than co-fire: row 16 (`Max 60 lines.`, same physical line, proves substring granularity), row 18 (the concrete-examples sentence on the adjacent line, proves the strip did not over-reach the line boundary), and every `commands/spec.md` row including row 10's Mode B pin, which contains its own `Max 60 lines.` copy inside the untouched dispatcher file. Run 3 restored the file and verified byte-identity: sha256 identical before and after (prefix `1246c64de45a`, truncated here because the repo's secret-guard hook rejects full 64-hex literals in authored files; re-derive with `shasum -a 256 agents/research-architecture.md`), and `git status --porcelain` clean on the path.

The suite also carries a PERMANENT in-suite negative control (SPEC-210 row 24): every invocation strips the same sentence from a mktemp scratch copy (tracked file untouched) and asserts the stripped pin fails on the copy while the same-line and adjacent-line neighbor pins still pass. Falsifiability re-proves itself on every run, mirroring `tests/test-memory-tidy-contract.sh` and `tests/test-loop-engineering-contract.sh`.

## Side findings (recorded, not fixed)

- The agent body's output contract instructs writing `docs/research/architecture.md`, but the frontmatter grants no Write tool; under a strictly enforced grant the agent cannot produce that file. Rows 5 and 11 pin both sides so whichever side a future fix changes, exactly one row breaks and surfaces SPEC-210.
- The Mode B inline fallback prompt asks only 4 of the agent's 6 questions (omits shared utilities and config pattern). Row 10 pins today's text verbatim; closing the divergence breaks row 10 and surfaces the note.

## Reproduce

```
bash tests/test-research-arch-contract.sh
# live negative control:
sed -i.bak 's/ Patterns, not exhaustive listings\.//' agents/research-architecture.md
bash tests/test-research-arch-contract.sh   # expect exit 1, exactly 2 FAIL (row 17 + NC setup)
mv -f agents/research-architecture.md.bak agents/research-architecture.md
bash tests/test-research-arch-contract.sh   # expect exit 0, 28/28
bash tests/test-meta.sh
```

Full trail: SPEC-210 (`docs/specs/SPEC-210-research-architecture-contract.md`), including the 3-lens critique (rounds 14 -> 4 findings, max severity CRITICAL -> LOW, verdict SOLID) and the honest lens-skip triage.
