# Gauntlet run: kit USER persona, row J1, REVISED surface (ID-490)

The revision-and-replicate run closing the cross-probe findings from `../2026-08-31-user-J1/` (sonnet) and `../2026-08-31-user-J1-nw/` (omp/deepseek). Surface revisions landed on this branch first (README no-root jq recipe + hand-copy warning + hook-activation caveat, WORKFLOW.md keyword index, MANUAL gate-ledger grammar block); both rounds below built from the revised committed HEAD.

## Inputs

As the `-nw` run (onboarding preset, J1 doorway card, omp + neuralwatt/deepseek-v4-flash probe, container room, local runner). Probe-tier caveat carries over; NW flat-rate makes replication ~free, which is why the cheap probe ran the replicate.

## Rounds

| Round | Checker | K | command-not-found | rejected gate writes | answer-key reads | Turns |
|---|---|---|---|---|---|---|
| 1 | GREEN | 0 | 0 | 0 | 0 | 46 |
| 2 (replicate) | GREEN | 0 | 0 | 0 | 0 | 26 |

`[[QL-VERDICT round=1 clean=true findings=0]]`
`[[QL-VERDICT round=2 clean=true findings=0]]`

## Verdict: SOLID (rule 9 satisfied: two consecutive unaided passes)

The revisions demonstrably changed probe behavior: round 1's transcript shows the probe following the README's new static-binary jq recipe (curl to `~/bin`, 19 related actions, zero dead-ends vs the pre-revision round's 10-call no-root saga) and discovering gate-ledger grammar via the MANUAL's documented no-args usage path (zero rejected writes vs 2 before). Deliberate usage-printing is documented discovery, not friction, so it carries no finding.

Standing caveats (patterns limits 3/8): SOLID is proven for the flash-tier probe in a container; the first real human adopter's day one is the next data point, and a periodic sonnet-probe round remains worth it since the stronger probe originally surfaced the hook-activation gap in prose the cheap probe only hit as a consequence.

## Evidence

`round-{1,2}/room/` per the nested-repo rule (fixture repo + kit tarball untracked, patch + checker output in `round-N/submission/`). Scrub: NW key confirmed absent from both persisted rounds.
