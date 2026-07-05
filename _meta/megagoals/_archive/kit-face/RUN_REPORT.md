# Run report , kit-face

**Run:** 2026-07-03 12:42-15:52 (+07) · repo dwarves-kit · mode delegate (`claude -p` workers) · 9/9 shipped, PRs #128-#137
**Totals:** wall 3h10m · worker time 2h19m · conductor+merge 51m · **parallel potential 1h08m (-64%)**

## Timeline (1 col = 4 min · `█` opus · `▒` sonnet)

```
              12:42   13:00          14:00          15:00       15:52
                 ·      |              |              |            ·
W1  04 tiers      ▒▒▒▒▒                                              20m #128
    05 provenance      ▒▒▒▒                                          14m #129
    06 persona             ▒▒▒                                       12m #130
    03 tokens                  ████████                              32m #132
    09 roleagents                        ▒▒▒▒▒                       21m #133
W2  07 donemodes                                   ██████            22m #134
W3  01 readme                                            ▒▒           6m #135
    02 docsindex                                            ▒         4m #136
W4  08 release                                                 ██     8m #137
    ─────────────────────────────────────────────────────────────
    same DAG,     ░░░░░░░░ W1‖ 32m
    parallel              ░░░░░ W2 ░ W3 ░░ W4        done by ~13:50
```

All five wave-1 sub-goals ran **serially** though the DAG allowed parallel; the ghost
lane is the wavefront projection (W1 max 32m -> W2 22m -> W3 6m -> W4 8m = 68m + merges).
That gap is what subagent-delegate / wavefront dispatch closes.

## Worker minutes by model

```
opus    ████████████▍        62m  (45%)   3 workers , the design-bearing sub-goals
sonnet  ███████████████▍     77m  (55%)   6 workers , execution / docs
```

## Gate coverage (`●` recorded in run ledger · deep-lane columns right of `│`)

```
                  sp  gr  sv  tp  bu  re  do  sh  ve  va │ th  de  dc  rf
04 tiers           ●   ●   ●   ●   ●   ●   ●   ●   ●     │
05 provenance      ●   ●●  ●   ●   ●   ●   ●   ●   ●     │
06 persona         ●   ●   ●   ●   ●   ●   ●   ●   ●     │
03 tokens    opus  ●   ●   ●   ●   ●   ●   ●   ●       ● │  ●   ●   ●   ●
09 roleagents      ●   ●   ●   ●   ●           ●        ● │  ●   ●   ●   ●
07 donemodes opus  ●   ●   ●   ●   ●   ●   ●   ●         │
01 readme          ●   ●   ●   ●   ●   ●   ●   ●         │
02 docsindex       ●   ●   ●   ●   ●   ●   ●   ●         │
08 release   opus  ●   ●       ●   ●   ●   ●   ●         │

sp spec · gr grill · sv spec-validate · tp test-plan · bu build · re review
do docs · sh ship · ve verify · va validate │ th think · de design
dc design-critique · rf reflect        deep lane clusters on the design sub-goals
```

## Callable stack

```
/goal conductor (delegate · absorbed 1 terse line per worker)
├─ claude -p kit-face-04-tiers        sonnet   rid=kit-face-04-tiers
├─ claude -p kit-face-05-provenance   sonnet
├─ claude -p kit-face-06-persona      sonnet
├─ claude -p kit-face-03-tokens       OPUS     deep lane: think→design→critique→reflect
├─ claude -p kit-face-09-roleagents   sonnet   deep lane: think→design→critique→reflect
├─ claude -p kit-face-07-donemodes    OPUS
├─ claude -p kit-face-01-readme       sonnet
├─ claude -p kit-face-02-docsindex    sonnet
└─ claude -p kit-face-08-release      OPUS     held gate; Han merged e375e57
```

In-worker subagent fan-out (spec-validate lenses, verifiers, reviewers) leaves no
per-dispatch trace under `claude -p`; under subagent-delegate each dispatch writes its
own transcript jsonl and this tree gains a third level.

## Tokens

Not captured for this run: SG-03 shipped the TOKENS capture mid-run (#132); the only
ledger rows today are its own test fixtures. Capture begins next run (stream-to-file
for `claude -p`; harness-native `subagent_tokens` for subagent workers).

## Render policy (data vs render)

This md IS the committed record: tables + ASCII/box-drawing only (renders in terminal,
GitHub, and Obsidian alike; no renderer dependency, no repo fat). Rich renders are
DERIVED and never committed , hosted Artifact (this run:
https://claude.ai/code/artifact/0182650b-0e18-4355-88db-d91f2e0cf9b9 ) or scratchpad html.
Re-derive the numbers any time:

    duckdb -c "SELECT regexp_extract(filename,'kit-face-([0-9a-z-]+)\.log',1) sg,
      count(*) FILTER (trim(col1)='GATE') gates, min(col0) started, max(col0) ended
      FROM read_csv('~/.local/state/dwarves-kit/logs/runs/kit-face-*.log', delim='|',
        header=false, filename=true, strict_mode=false,
        columns={'col0':'VARCHAR','col1':'VARCHAR','col2':'VARCHAR','col3':'VARCHAR','col4':'VARCHAR'})
      GROUP BY 1 ORDER BY started"
