# Gauntlet run: kit USER persona, row J1 (doorway)

First post-generalization run (SPEC-235 engine, onboarding preset). Tutorial Path A executed as written.

## Inputs

| Input | Value |
|---|---|
| preset | onboarding (persona A, kit USER) |
| Artifact | README.md, docs/MANUAL.md, docs/guides/**, commands/onboard.md, commands/adopt.md |
| Card | J1 doorway: install from tarball, adopt into fixture repo, ship one tiny-lane change (frozen: `card.md`) |
| Checker | `check-submission-user.sh` (doorway) |
| Tier 1 | `bash tests/gauntlet/tier1.sh` |
| Probe | claude-sonnet-5, headless `claude -p`, one spend-capped key, 1800s cap |
| Clean room | container, `git archive HEAD`, answer key stripped |
| Runner | local (Air, colima) |

## Rounds

| Round | Tier 1 | Checker | K | Max severity | Cost | Wall clock | Turns |
|---|---|---|---|---|---|---|---|
| 1 | GREEN | GREEN | 4 | MAJOR | $1.01 | 3 min probe (+ ~3 min room build) | 54 |

`[[QL-VERDICT round=1 clean=false findings=4]]`

## Verdict: REVISE

The probe completed the card unaided (checker green twice, once with a stripped env; zero coaching; zero answer-key reads; 4 failed commands, all in one no-root jq detour, none retried identically). But K=4 findings stand, so this is not a converged pass: the surface owes a revision, then a replicate round (rule 9 needs two consecutive K=0 passes for SOLID). Findings: `round-1/findings.md`. Revision worklist filed on the board.

## Evidence

`round-1/room/` holds the full persisted room: `transcript.jsonl` (54 turns), `probe-stderr.log`, the checkers; the fixture repo and kit tarball stay untracked (nested-repo rule, see `.gitignore`), their evidence exported to `round-1/submission/` (probe-change.patch, PR.md, checker output). Scrub check: zero credential echoes in transcript/stderr. Note: this dir uses the runner's `<date>-<persona>-<row>` grammar (grandfathered instance form per SPEC-235).
