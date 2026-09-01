# Sub-goal 03: cost + model signals

**Time budget:** ~3-4h · **Depends on:** 02 (same file) · **Branch:** feat/cc-elev-r3-03-cost-model · **PR base:** feat/cc-elev-r3-02-session-shape

## Outcome

cc-observe gains a `cost` view from the transcript `usage` block (input/output/cache tokens per
turn, model id):

1. **tokens by model** , Opus vs Sonnet vs Haiku share per day and per task-shape; surfaces over/under-powered routing.
2. **cache economics** , cache-read vs cache-create token ratio (the biggest cost lever, per the research note).
3. **cost-per-merged-PR** , tokens (and $-estimate via a pricing table) correlated to merged PRs per repo. Cost-per-outcome, not cost-per-token.

## Quality bar

Read-only, stdlib. The $-estimate uses a small embedded pricing table (borrow ccusage's shape;
hardcode current 4.x prices with a dated comment, not a network call). The PR-correlation reads
`git log` for merge commits in the window per repo, no GitHub API needed; degrade to tokens-only
if git is unavailable. Make clear these are estimates (Max-plan flat-rate; this is attribution,
not billing).

## How to close the loop

- Implement in `tools/cc-observe/bin/cc-observe` on top of 02's branch. Parse `message.usage` (input_tokens, output_tokens, cache_read/creation, model).
- Fixtures: entries carrying a `usage` block across two models; smoke asserts the by-model split + a cache ratio, with a negative control (a turn with no `usage` is skipped, not counted as zero-cost noise).
- Verify: smoke green; `cc-observe cost --days 7` on real data shows a believable model split + cache ratio.
- Update proof + README/SPEC. Note the pricing-table date.

**Done =** cc-observe surfaces tokens-by-model + cache-economics + cost-per-merged-PR (table + `--json` + in `report`), proven on fixtures + negative control, smoke green, docs/proof updated, pricing-table dated; on PR #NN, based on 02's branch.

## Scope edges

**In:** the three cost/model signals, embedded dated pricing table, fixtures, smoke, proof, docs.
**Out:** delivery (SG-05); a live billing integration; per-edit gating (that is cc-money-gate, separate).
**Not:** a network pricing fetch; treating estimates as authoritative billing; durable writes.

## Where to look

02's branch + `tools/cc-observe/bin/cc-observe`, transcript `message.usage` shape, [ccusage](https://github.com/ryoppippi/ccusage) pricing-table shape, `git log --merges` per repo under `~/workspace/<owner>`, the research note's cost section.

## PR body

Outcome: cc-observe cost/model signals (tokens-by-model / cache-economics / cost-per-merged-PR).
Verify: smoke green with a no-usage negative control; real-run model split in the proof.
Roadmap: `_meta/megagoals/cc-elevation-r3/ROADMAP.md` (sub-goal 03). Stacked on 02.

## Notes (deviation, 2026-06-15)

cost-per-merged-PR (third signal in the Outcome) was DEFERRED, not shipped. No clean data path: transcripts are cross-repo while merges are per-repo; ops-toolkit squash-merges so `git log --merges` finds ~0; real per-PR attribution needs gh PR data, not transcript data. Shipped the two clean signals (tokens-by-model + cache economics). Deferral logged to NOTES `## Proposed additions`; rationale in SPEC Non-goals + impl-notes `01-observability.md` 2026-06-15.
