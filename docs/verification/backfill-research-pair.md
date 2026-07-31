# Proof of done: research-pitfalls + research-stack contract backfill (SPEC-211, ID-452 items 4+5/6)

Backfills spec + test coverage for `agents/research-pitfalls.md` and `agents/research-stack.md` (two read-only research subagents that previously had neither) AND their per-agent dispatch deltas in `commands/spec.md` Step 2, pinned from both sides. Combined per the item-3 rationale: identical skeleton, same dispatcher SPEC-210 already pins, so the suite covers only the DELTAS: identities + auto-delegation descriptions, the exact 6-entry read-only tool rosters (pitfalls adds `wc` to `find`/`git log`; stack swaps to `cat`/`head`/`wc` with NO git access), the model-tier split (sonnet vs haiku, the roster's only haiku research agent), each body's category list + mcp routing + output template + rules, the two Mode A dispatch lines, the two Mode B fallback prompts verbatim, the SPEC-087 distilled-return contract in both, and region-anchored write-target agreement; one assertion per SPEC-211 Test plan row. Shared dispatcher rows (Step 2 heading, parallel-4 sentence, Mode A/B gate sentence) stay SPEC-210's and are not re-pinned.

## Confirmation runs

| # | Check | Command | Exit | Verdict |
|---|---|---|---|---|
| 1 | New suite green | `bash tests/test-research-pair-contract.sh` | 0 | PASS (41/41) |
| 2 | Live NC, pitfalls | strip the real-risks sentence from the tracked pitfalls body, re-run suite | 1 | RED (39/41, exactly the 2 predicted FAILs) |
| 3 | Restore, pitfalls | `mv -f` the sed `.bak` over the file, re-run suite | 0 | PASS (41/41), sha256 byte-identical |
| 4 | Live NC, stack | strip the don't-guess sentence from the tracked stack body, re-run suite | 1 | RED (39/41, exactly the 2 predicted FAILs) |
| 5 | Restore, stack | `mv -f` the sed `.bak` over the file, re-run suite | 0 | PASS (41/41), sha256 byte-identical |
| 6 | Meta suite | `bash tests/test-meta.sh` | 0 | PASS (732/732) |

## Run detail

Run 2 removed only the sentence ` Only report real risks, not style preferences.` from `agents/research-pitfalls.md` (substring removal via `sed -i.bak`, NOT a whole-line delete: row 8's pin `Max 40 lines.` shares one physical line with row 9's pin, the adjacency class SPEC-208 first caught). Exactly two assertions went RED, both predicted in SPEC-211 row 35:

- `row 9: real-risks-not-style rule` (the pinned claim, gone from the file)
- `NC setup (pitfalls): the strip actually changed the scratch copy` (the in-suite `! cmp -s` setup guard found nothing left to strip; the SPEC-211 critique's CRITICAL finding made this guard explicit in the spec's own rows 33/34 rather than tacit knowledge from SPEC-210's materialized script)

The other 39 assertions stayed green, including every stack row, every dispatcher row, and the entire stack in-suite NC (rows 34a-c plus its setup guard), proving the two agents' pins do not co-fire. Meaningful survivors: row 8 (`Max 40 lines.`, same physical line, proves substring granularity; its `$C` Mode B copy in row 28 also stayed green, untouched file) and row 10 (the critical-definition sentence on the adjacent line, proves the strip did not over-reach the line boundary). Run 3 restored and verified byte-identity: sha256 identical before and after (prefix `53b1bc052236`, truncated because the repo's secret-guard hook rejects full 64-hex literals in authored files; re-derive with `shasum -a 256 agents/research-pitfalls.md`), `git status --porcelain` clean on the path.

Run 4, after run 3's restore was byte-verified (the two live NCs never overlap: one tracked file mutated at a time, per row 36), removed only ` Don't guess.` from `agents/research-stack.md`. Exactly two RED, both predicted in SPEC-211 row 36:

- `row 23: don't-guess rule`
- `NC setup (stack): the strip actually changed the scratch copy`

Survivors: row 22 (`Only report what you can verify from files.`, same physical line) and row 21 (`Max 50 lines of output. Be concise.`, adjacent line) stayed green, as did every pitfalls row and the entire pitfalls in-suite NC. Run 5 restored: sha256 prefix `6a5a9ea78e92` identical before and after (re-derive with `shasum -a 256 agents/research-stack.md`), porcelain clean.

The suite carries TWO permanent in-suite negative controls (SPEC-211 rows 33/34), one per agent: every invocation strips each agent's sentence from its own mktemp scratch copy (tracked files untouched), asserts the `! cmp -s` setup guard, the stripped pin's failure, and the two named survivors per agent. Falsifiability re-proves itself on every run, mirroring `tests/test-research-arch-contract.sh`.

## Side findings (recorded, not fixed)

- BOTH agent bodies instruct writing `docs/research/{pitfalls,stack}.md`, but neither frontmatter grants a Write tool; under a strictly enforced grant neither agent can produce its file (same class as SPEC-210 side finding a, now confirmed across 3 of the 4 research agents). Rows 4/17 pin the grants and rows 30/31 pin the instructions, so whichever side a future fix changes, exactly one row per agent breaks and surfaces SPEC-211.
- The Mode B pitfalls fallback prompt asks 6 of the agent's 7 categories (omits stale dependencies) and drops the mcp routing. Row 28 pins today's text verbatim; rows 5/6 pin the body side; closing the divergence breaks exactly one row.
- The Mode B stack fallback prompt names `get_architecture()` while the agent body names `get_structure()`, an mcp call-name divergence (Mode B's name matches the live codebase-memory-mcp tool surface; the body's does not appear in it), and asks 4 of the agent's 5 categories (omits Infrastructure). Row 29 pins the Mode B side, row 19 the body side.

## Reproduce

```
bash tests/test-research-pair-contract.sh
# live negative control 1 (pitfalls):
sed -i.bak 's/ Only report real risks, not style preferences\.//' agents/research-pitfalls.md
bash tests/test-research-pair-contract.sh   # expect exit 1, exactly 2 FAIL (row 9 + pitfalls NC setup)
mv -f agents/research-pitfalls.md.bak agents/research-pitfalls.md
bash tests/test-research-pair-contract.sh   # expect exit 0, 41/41
# live negative control 2 (stack), only after the restore above is verified:
sed -i.bak "s/ Don't guess\.//" agents/research-stack.md
bash tests/test-research-pair-contract.sh   # expect exit 1, exactly 2 FAIL (row 23 + stack NC setup)
mv -f agents/research-stack.md.bak agents/research-stack.md
bash tests/test-research-pair-contract.sh   # expect exit 0, 41/41
bash tests/test-meta.sh
```

Full trail: SPEC-211 (`docs/specs/SPEC-211-research-pair-contract.md`), including the 3-lens critique (rounds 10 -> 5 findings, max severity CRITICAL -> LOW, verdict SOLID) and the honest lens-skip triage.
