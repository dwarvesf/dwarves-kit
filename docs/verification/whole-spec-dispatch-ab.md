# Whole-spec dispatch: A/B run, arm A (old spine)

Measured 2026-09-30. Arm B (new spine) is not recorded here yet. Dispatches and tokens come from `stats ceremony` (SPEC-367 reader), cross-checked against `stats query` on `subagent_runs` and the subagent `meta.json` descriptions.

## Arm A (old spine)

Dispatches: 18
Tokens: 605367

| Field | Value |
|---|---|
| rid | `ab-old-run3` (attempts 1 and 2 below used other rids) |
| Kit | `~/.claude/dwarves-kit` symlinked to the master checkout at `148c69239cb26140c5c3cbc1a3348e582e543847` (origin/master and master equal; no SPEC-369 code) |
| Fixture | `tests/fixtures/whole-spec-dispatch/ab-medium`, source commit `4dac4ce0e887fa980f63ebc127638e4b067a1dd2`; SPEC-001-wordstat, 4 tasks, full lane |
| Command | `claude -p "/kit:execute docs/specs/SPEC-001-wordstat.md" --permission-mode bypassPermissions`, claude 2.1.285, scratch dir outside `~/workspace`, branch `feat/ab-old-run3` |
| Wall time | 16m52s (06:32:18Z to 06:49:10Z), exit 0 |
| Build verdict | All 4 tasks passed first time, no retries, no escalation; 31 unit tests pass; final re-audit passed. Review round 1 returned FIX THEN SHIP (0 critical, 0 high, 3 medium, 2 low). The lead stopped at its context limit before applying the review fixes, so arm A has no fix-agent dispatch and no post-fix re-verify. |
| Fixture Verification commands on the result | 6 of 6 pass (`bash tests/run.sh`, sample counts, `--top 2`, `--json --top 2`, missing file exits 2, empty input) |
| Tag joins | 18 by `tag` (every dispatch of this run carries `rid=ab-old-run3`) |

### Dispatches by agentType (tag joins only, 18)

| agentType | Count | Role |
|---|---|---|
| general-purpose | 4 | task workers, one per task |
| kit:task-verifier | 4 | one per task |
| kit:recheck-verifier | 5 | four per task plus one on integration |
| kit:integration-verifier | 1 | wiring check |
| kit:code-reviewer | 2 | architecture and test-coverage lenses |
| kit:security-reviewer | 1 | security lens |
| kit:advisor | 1 | extra review lens |
| kit:meta-agent | 0 | persona meta-agent did not fire on this run |

### Tokens (subagents only)

| Measure | Tag-only (trusted) | Reader total (21 incl. 3 window joins) |
|---|---|---|
| Net (input + output + cache-creation) | 605,367 | 834,777 |
| Cache-read (separate) | 1,678,688 | 4,876,178 |
| Output | 40,825 | 58,884 |
| Dispatches | 18 | 21 |

`Tokens: 605367` above is the tag-only net figure.

## Why the reader total is not the arm figure

The reader joined 3 extra `general-purpose` runs to `ab-old-run3` with `rid_source=window` (first_ts 06:37, 06:40, 06:45). Their transcripts sit in another Claude session (`-Users-tieubao-workspace-tieubao-ops-toolkit/67ea60ca-...`) that ran concurrently and dispatched without a `rid=` tag. The window fallback attributed them to this run. They are not part of this arm. The reader's per-run row, `dispatches_per_task` (5.25) and `tokens_per_task` (208,694) therefore overstate the arm; the tag-only figures give 4.5 dispatches per task and 151,342 net tokens per task.

## Caveats that affect trust

| Item | Effect |
|---|---|
| Subagents only | The lead (orchestrator) session's own tokens are not in any figure; the lead ran to its context limit, so the lead share is large and unmeasured here |
| Concurrent sessions | Window-join contamination above; arm B must run with no other untagged dispatching session, or be read tag-only |
| Validator skipped by override | The validate gate was recorded as an audited ledger override (`gate-ledger.sh override`) because the full-lane validator stopped the headless run twice (see attempts). Arm A therefore measures the build spine, not validation. Arm B must be started the same way to compare like with like |
| Build not fully closed | No fix round, no ship; the old spine would add a fix-agent and re-verify dispatches after review |
| Smaller than the estimate | 18 observed against the roughly 56 in R12 for a medium feature; this fixture has 4 tasks and no retries, so it sits under the estimate's shape |
| Model tiers | `meta.json` model shows `?` for verifiers, advisor and integration verifier; workers ran sonnet, security-reviewer opus |
| n = 1 | One run per arm, no variance estimate |

## Earlier attempts (same fixture lineage, not the arm)

| Attempt | rid | Outcome | Dispatches | Net tokens | Cache-read |
|---|---|---|---|---|---|
| 1 | `ab-old-spine` | Stopped at the validation preflight: 2 criticals (two word definitions; no `## Design`). 7 validator lenses plus 1 meta-agent. No task ran. | 8 | 443,197 | 1,203,152 |
| 2 | `ab-old-take2` | Fixture fixed, validator ran again (7 lenses), 4 new criticals (bytes API, `## Picture`, edge cases outside ACs, task dependencies). Stopped before task 1. | 7 | 398,520 | 679,095 |
| 3 (this arm) | `ab-old-run3` | Spec folded by hand, validate recorded as ledger override, full build ran. | 18 | 605,367 | 1,678,688 |

Attempts 1 and 2 show what a full-lane validation round costs in this spine: about 7 to 8 dispatches and 0.4 M net tokens each, and it does not converge headless because the preflight forbids the loop from folding criticals. That cost is outside arm A.

## Reproduce

1. Copy `tests/fixtures/whole-spec-dispatch/ab-medium` to a scratch dir from `mktemp -d`, `git init -b main`, commit, branch `feat/<rid>`.
2. `bash ~/.claude/dwarves-kit/lib/adopt.sh --no-single-source .` and commit.
3. `gate-ledger.sh start <rid> full normal feature feature ab-medium`, then `gate-ledger.sh override <rid> validate "<reason>"`.
4. `claude -p "/kit:execute docs/specs/SPEC-001-wordstat.md" --permission-mode bypassPermissions`.
5. `bash bin/stats ceremony --from <start> --to <end> --json`, then read tag-only rows with `stats query "SELECT ... FROM subagent_runs WHERE rid='<rid>' AND rid_source='tag'"`.
