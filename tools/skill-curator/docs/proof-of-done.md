# Proof of Done: cc-self-improve (multi-feature index)

Per SPEC-016 this is the canonical proof for the tool, indexing per-phase features. cc-self-improve
is built in three phases (cc-elevation-r4 sub-goals 02/03/04); each phase appends its feature block.

| Phase / feature | Sub-goal | Status |
|---|---|---|
| **A , skill-draft reviewer** (parser + no-write reviewer + trusted staging + cost ledger) | 02 | DONE (below) |
| B , promote gate + SessionStart surfacing + install + full async/reentrancy/staging-gate suite | 03 | pending |
| C , skill-library curator (consolidate + archive, never delete) + weekly propose-only launchd | 04 | pending |

---

## Feature A: skill-draft reviewer (cc-elevation-r4 sub-goal 02)

**Date:** 2026-06-19 · **Lane:** full · **Host:** Hans-Air-M4 (macOS 26.5) · **Spec:** SPEC-103 TASK-001..005

### Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| A1 | A returned draft is staged under `~/.claude/skill-proposals/<slug>/SKILL.md` , and ONLY there | goal Done + SPEC-103 DEC-003 |
| A2 | The reviewer MODEL has no filesystem write (`--allowedTools ""`); only the trusted wrapper writes | SPEC-103 DEC-008 |
| A3 | A no-signal session yields no draft (null is a valid outcome) | goal Done + hermes-patterns B |
| A4 | A draft carrying a secret is dropped, never staged | goal Done + TASK-004 |
| A5 | A ledger line per run records `total_cost_usd` (cost observability) | first-class AC #1 |
| A6 | `claude` missing / non-zero / malformed JSON -> exit 0, no draft (safe-to-wire) | Edge Cases 2,3 |
| A7 | Single-flight: an in-flight reviewer skips this fire | SPEC-103 DEC-005 / TASK-003 |
| A8 | The hook returns fast (detached); reentrancy + disabled gates hold | TASK-003 + first-class AC #2/#3 |
| A9 | Transcript parser locked against a committed sample schema | TASK-002 |

### Implementation

| Piece | What | Where |
|---|---|---|
| Transcript parser | bash + jq; last-K user+assistant text turns; skips thinking/tool/summary | `lib/transcript.sh` |
| Reviewer (no write) | `claude -p --bare --no-session-persistence --allowedTools "" --model haiku --output-format json`; returns `{draft|null, reason}` | `lib/reviewer-run.sh:run_reviewer` |
| Two-layer parse | envelope `.total_cost_usd`/`.usage` + `.result`; `.result` parsed as the draft JSON | `lib/reviewer-run.sh:main` |
| Secret guard | wrapper drops a draft whose body matches a high-precision secret pattern | `lib/common.sh:contains_secret` |
| Staging writer | the ONLY draft writer; writes `skill-proposals/<slug>/SKILL.md`, never `skills/` | `lib/reviewer-run.sh:main` |
| Cost ledger | one JSONL row per run (`staged`, `slug`, `total_cost_usd`, tokens, `note`) | `lib/reviewer-run.sh:_ledger` |
| Single-flight | portable mkdir-atomic lock (macOS has no `flock(1)`) | `lib/common.sh:si_acquire_lock` |
| Hook | PreCompact/SessionEnd: reentrancy + enabled gate, detached `setsid`/`nohup` spawn, <200ms | `hooks/skill-review.sh` |
| Reviewer prompt | built from `docs/hermes-prompt-patterns.md` A (signals/preference/naming/do-not-capture) + B (selective, null valid, secret ban) | `prompts/review-skill.md` |
| CLI | `cc-improve status`: staged-draft count + 7-day loop spend | `bin/cc-improve` |

### Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Transcript parse (A9) | `bash tests/test-transcript-parse.sh` | `all 6 passed` | PASS |
| Reviewer wrapper (A1-A7) | `bash tests/test-reviewer.sh` | `all 10 passed` | PASS |
| Hook async + gates (A8) | `bash tests/test-hook-async.sh` | `all 4 passed` | PASS |
| Stage-only-proposals (A1/A2) | test-reviewer 1,2 | draft under proposals/, skills/ untouched | PASS |
| Cost ledger (A5) | test-reviewer 3 | ledger line with `total_cost_usd` | PASS |
| Null draft (A3) | test-reviewer 4 | nothing staged, `note=null-draft` | PASS |
| Secret dropped (A4) | test-reviewer 5 | not staged, `note=dropped-secret` | PASS |
| Unavailable/bad-json (A6) | test-reviewer 6,7 | exit 0, no draft | PASS |
| Single-flight (A7) | test-reviewer 8 | lock held -> skipped | PASS |
| Hook non-blocking (A8) | test-hook-async 1,2 | hook returns 0.11s, detached reviewer stages | PASS |
| Reentrancy/disabled (A8) | test-hook-async 3,4 | no-op | PASS |
| `--allowedTools ""` pinned (A2) | test-reviewer 10 | source pins empty allowedTools | PASS |
| shellcheck | `shellcheck -S warning bin hooks lib tests` | clean | PASS |

### Run detail

```
$ bash tests/test-transcript-parse.sh | tail -1
test-transcript-parse: all 6 passed
$ bash tests/test-reviewer.sh | tail -1
test-reviewer: all 10 passed
$ bash tests/test-hook-async.sh | tail -1
test-hook-async: all 4 passed

$ bash tests/test-hook-async.sh | sed -n '1,2p'
[1] hook returns fast (<1.5s) even though the reviewer sleeps 2s (detached, non-blocking)
  ok: hook returned in 0.11s, exit 0

$ cc-improve status            # against a seeded ledger
  staged skill drafts: 1
  reviewer runs (7d): 2   staged: 1
  loop spend (7d): $0.002
```

### Negative controls

- **Model-no-write is structural (A2)**: with `CC_SI_SKILLS_DIR` pointed at a temp dir, a staged
  run leaves `skills/` empty (test-reviewer 2) , the wrapper writes only to `skill-proposals/`. The
  source pins `--allowedTools ""` (test-reviewer 10). The full adversarial staging-gate test (a
  reviewer with no Write cannot write under `skills/` even on an injected transcript) is sub-goal 03.
- **Secret never staged (A4)**: a draft body carrying a synthetic `sk-ant-...` token is dropped
  (`note=dropped-secret`, no file written). Without the wrapper scan the file would land; the test
  asserts it does not.
- **Null is a real outcome (A3)**: a `{"draft":null}` envelope stages nothing and logs
  `note=null-draft`, proving the loop is selective (not Hermes's always-do-something).
- **Non-blocking is real (A8)**: a 2s-sleep reviewer still lets the hook return in 0.11s, and the
  draft appears only afterward , the reviewer ran detached, not in the hook's foreground.
- **Single-flight is real (A7)**: a pre-held lock (live holder pid) makes the run skip; nothing
  staged. Release the lock and it would stage.

### Reproduce

```bash
cd tools/cc-self-improve
bash tests/test-transcript-parse.sh && bash tests/test-reviewer.sh && bash tests/test-hook-async.sh
# dry-run the wrapper with a mock envelope (no live model):
TMP=$(mktemp -d); export CC_SI_STATE_DIR=$TMP/s CC_SI_PROPOSALS_DIR=$TMP/p
jq -n --arg tp tests/fixtures/sample-transcript.jsonl '{session_id:"x",transcript_path:$tp}' > $TMP/pay.json
jq -nc '{type:"result",total_cost_usd:0.001,result:({draft:{slug:"demo",name:"demo",description:"d",body:"---\nname: demo\n---\n# demo\n"},reason:"r"}|tojson)}' > $TMP/env.json
CC_SI_REVIEWER_CMD="cat $TMP/env.json" bash lib/reviewer-run.sh $TMP/pay.json
cat $TMP/p/demo/SKILL.md; cat $CC_SI_STATE_DIR/ledger.jsonl
```
