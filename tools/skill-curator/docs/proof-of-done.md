# Proof of Done: cc-self-improve (multi-feature index)

Per SPEC-016 this is the canonical proof for the tool, indexing per-phase features. cc-self-improve
is built in three phases (cc-elevation-r4 sub-goals 02/03/04); each phase appends its feature block.

| Phase / feature | Sub-goal | Status |
|---|---|---|
| **A , skill-draft reviewer** (parser + no-write reviewer + trusted staging + cost ledger) | 02 | DONE (below) |
| **B , promote gate + SessionStart surfacing + install + full async/reentrancy/staging-gate suite** | 03 | DONE (below) |
| **C , skill-library curator** (consolidate + archive never delete) + weekly propose-only launchd + round close-out | 04 | DONE (below) |

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

---

## Feature B: promote gate + surfacing + install (cc-elevation-r4 sub-goal 03)

**Date:** 2026-06-19 · **Lane:** full · **Host:** Hans-Air-M4 (macOS 26.5) · **Spec:** SPEC-103 TASK-006..010

Closes the human gate and makes the loop visible + installable. `/skill-review` (via `bin/skill-review`)
is the ONLY writer of `~/.claude/skills/`; the background reviewer never is.

### Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| B1 | `skill-review promote` moves a draft into `~/.claude/skills/`; reject discards (to `_rejected/`, never rm) | TASK-007 |
| B2 | promote refuses to overwrite a live skill without `--force`; `--force` backs up the old (never rm) | TASK-007 |
| B3 | promote refuses a draft that still contains a secret | TASK-007 + secret guard |
| B4 | promote/reject leave unrelated live skills untouched | TASK-007 |
| B5 | the staging-by-path gate: a draft lands only under proposals/; a traversal slug cannot escape; model has no write | TASK-006 |
| B6 | SessionStart surfacing shows "N memory, M skill drafts, $X/wk" | TASK-008 |
| B7 | a `sleep 30` reviewer does not delay the hook return (fully async) | TASK-009 / first-class AC |
| B8 | a reviewer cannot trigger a reviewer (no runaway recursion) | TASK-009 |
| B9 | install is idempotent (twice = no dup), backs up settings.json, all entries `async:true` | TASK-010 |
| B10 | uninstall removes ONLY this tool's entries; auto_promote knob default OFF, references-add-only | TASK-010 + goal |

### Implementation

| Piece | What | Where |
|---|---|---|
| Promote core | list / promote (refuse-overwrite, secret-refuse, force-backup) / reject (-> `_rejected/`) | `lib/promote.sh` |
| Promote CLI | the only writer of `~/.claude/skills/` | `bin/skill-review` |
| Promote skill | human slash-command; delegates the quality bar to `superpowers:writing-skills` | `skills/skill-review/SKILL.md` |
| Surfacing | line = cc-harvest queued-memory count + draft count + 7-day spend | `lib/surface.sh` + `hooks/sessionstart-surface.sh` |
| Install | idempotent jq read-merge-write (PreCompact+SessionEnd+SessionStart, async), backup-first, atomic | `deploy/install.sh` / `uninstall.sh` |
| auto_promote | OFF by default; references-add-to-existing-umbrella only (never new skill / body edit) | `lib/promote.sh:auto_promote_eligible` |

### Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Promote gate (B1-B4,B10) | `bash tests/test-promote.sh` | `all 9 passed` | PASS |
| Staging gate (B5) | `bash tests/test-staging-gate.sh` | `all 5 passed` | PASS |
| Surfacing (B6) | `bash tests/test-surface.sh` | `all 4 passed` | PASS |
| Fully async (B7) | `bash tests/test-async.sh` | `all 2 passed` | PASS |
| Reentrancy (B8) | `bash tests/test-reentrancy.sh` | `all 3 passed` | PASS |
| Install idempotent (B9,B10) | `bash tests/test-install.sh` | `all 6 passed` | PASS |
| shellcheck | `shellcheck -S warning ...` | clean | PASS |

### Run detail

```
$ for t in test-staging-gate test-promote test-surface test-async test-reentrancy test-install; do bash tests/$t.sh | tail -1; done
test-staging-gate: all 5 passed
test-promote: all 9 passed
test-surface: all 4 passed
test-async: all 2 passed
test-reentrancy: all 3 passed
test-install: all 6 passed

$ bash tests/test-async.sh | sed -n '1,2p'
[1] a slow (sleep 30) reviewer does not delay the hook return (<1.5s)
  ok: hook returned in 0.12s while the reviewer still sleeps 30s
```

### Negative controls (Feature B)

- **Promote is the only skills/ writer (B5)**: a draft with a path-traversal slug
  (`../../../skills/evil`) is sanitized by `safe_slug` and lands contained under proposals/; nothing
  appears under skills/. The reviewer source pins `--allowedTools ""` (model has no write at all).
- **Reject never deletes (B1)**: reject MOVES the draft to `_rejected/` (asserted recoverable),
  never `rm`. `--force` promote backs the displaced live skill up to `_replaced/` before replacing.
- **Secret cannot be promoted (B3)**: a draft body carrying a synthetic `sk-ant-...` is refused
  (exit 3, not moved). Without the scan it would promote.
- **Fully async (B7)**: a `sleep 30` reviewer still returns the hook in ~0.12s; the reviewer only
  launches (LAUNCHED marker), it is never awaited.
- **No reviewer recursion (B8)**: a reviewer mock that re-invokes the hook increments its counter
  exactly once , the nested hook no-ops because `CLAUDE_REVIEWING` is set for the model call.
- **Install surgical (B9/B10)**: a pre-existing unrelated hook survives install + uninstall; a second
  install adds zero duplicate entries; uninstall removes only `cc-self-improve` commands.

### Reproduce (Feature B)

```bash
cd tools/cc-self-improve
for t in test-promote test-staging-gate test-surface test-async test-reentrancy test-install; do bash tests/$t.sh; done
# install dry-run against a throwaway settings.json (never the real one):
TMP=$(mktemp -d); CC_SI_SETTINGS=$TMP/settings.json CC_SI_STATE_DIR=$TMP/state bash deploy/install.sh
jq '.hooks | {PreCompact,SessionEnd,SessionStart}' $TMP/settings.json
CC_SI_SETTINGS=$TMP/settings.json CC_SI_STATE_DIR=$TMP/state bash deploy/uninstall.sh
```

### Rollback (Feature B install touches a persistent file: ~/.claude/settings.json)

`deploy/install.sh` is the only state-mutating step (it edits `settings.json`). It is fully
reversible and tested:

- **Rollback path 1 (surgical):** `deploy/uninstall.sh` removes ONLY this tool's hook entries,
  leaving any other hooks intact (test-install B5). It is idempotent.
- **Rollback path 2 (restore):** install backs the file up FIRST to `settings.json.bak-<ts>` before
  writing (test-install B3); restore by copying that backup back over `settings.json`.
- The write is atomic (jq to a temp file, validated, then `mv`); a jq failure leaves `settings.json`
  unchanged. No partial writes.

Recorded rollback run (against a throwaway settings.json, never the real one):

```
Command: CC_SI_SETTINGS=$T bash deploy/install.sh   # 3 cc-self-improve entries added
Command: CC_SI_SETTINGS=$T bash deploy/uninstall.sh # entries removed, unrelated kept
Exit: 0   (verified by tests/test-install.sh -> "test-install: all 6 passed")
```

---

## Feature C: skill-library curator + round close-out (cc-elevation-r4 sub-goal 04)

**Date:** 2026-06-19 · **Lane:** full · **Host:** Hans-Air-M4 (macOS 26.5) · **Spec:** SPEC-103 TASK-011..014 · **Merge: GATE (held for Han's click)**

The explicitly-missing piece: a curator that consolidates the skill library into umbrellas and
archives stale/superseded skills , **never deletes**. Propose-only by default; a weekly launchd runs
report-only; the human runs `--apply`.

### Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| C1 | `cc-improve curate` reports clusters + archive candidates and changes NOTHING without `--apply` | TASK-011 |
| C2 | The curator MODEL has no write (`--allowedTools ""`); the trusted wrapper does the git mv | DEC-008 |
| C3 | `--apply` archives via `git mv` to `skills/_archive/` , NEVER `rm` (no `rm` in the code path) | TASK-012 |
| C4 | `cc-improve restore <name>` round-trips an archived skill back | TASK-012 |
| C5 | A pinned/protected skill is never archived (wrapper guard, not just prompt) | hermes-patterns C rule 2 |
| C6 | Non-git `skills/` falls back to `mv` + manifest + warning (still no rm) | TASK-012 |
| C7 | `absorbed_into` recorded in the archive manifest | hermes-patterns C archive-forwarding |
| C8 | curator-unavailable / bad JSON -> nothing changed, exit 0 | safe-to-wire |
| C9 | The weekly launchd is propose-only (no `--apply` in the plist), BTM-friendly | TASK-013 |

### Implementation

| Piece | What | Where |
|---|---|---|
| Inventory | name + description + first paragraph + mtime + pinned, over skills/ | `lib/curate.sh:curate_inventory` |
| Curator (no write) | `claude -p --allowedTools ""` returns a JSON plan; seam `CC_SI_CURATOR_CMD` | `lib/curate.sh:run_curator` |
| Report | propose-only banner + the model's narrative + proposed archives/clusters | `lib/curate.sh:curate_run` |
| Archive | `git mv` to `_archive/` (non-git -> `mv`+manifest+warn); pinned-guard; never rm | `lib/curate.sh:_archive_one` |
| Restore | `git mv` back (or `mv`) | `lib/curate.sh:curate_restore` |
| Prompt | hermes-patterns C: umbrella-building, never-delete, pairwise-distinctness-wrong-bar, propose-only banner | `prompts/curator.md` |
| Launchd | weekly propose-only; `ProgramArguments` = `bin/cc-improve curate` (no `--apply`, no `.sh`) | `deploy/macos/mini.cc-curator.plist` + runbook |

### Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Curator suite (C1-C8) | `bash tests/test-curate.sh` | `all 9 passed` | PASS |
| Propose-only no-op (C1) | test-curate 2 | report+heartbeat written, no skill moved | PASS |
| git-mv archive (C3) | test-curate 3 | deploy-gcp moved to _archive/, content intact | PASS |
| no rm in path (C3) | test-curate 6 | no `rm` command in curate.sh | PASS |
| pinned protected (C5) | test-curate 4 | keep-me not archived | PASS |
| restore round-trip (C4) | test-curate 7 | skill moved back, content intact | PASS |
| non-git fallback (C6) | test-curate 8 | mv-archived + manifest | PASS |
| absorbed_into (C7) | test-curate 5 | manifest records `absorbed_into=deploy-aws` | PASS |
| unavailable-safe (C8) | test-curate 9 | exit 0, no change | PASS |
| plist valid + propose-only (C9) | `plutil -lint`; grep plist | OK; no `--apply` | PASS |
| shellcheck | `shellcheck -S warning ...` | clean | PASS |

### Run detail

```
$ bash tests/test-curate.sh | tail -1
test-curate: all 9 passed

$ CC_SI_CURATOR_CMD="cat env.json" cc-improve curate          # propose-only, fresh state dir
curate: report -> .../curator-report-20260619-172755.md
curate: propose-only , 1 archive candidate(s); nothing changed. Review ..., then --apply.
$ cat .../curator.heartbeat
2026-06-19T17:27:55+0700

$ CC_SI_CURATOR_CMD="cat env.json" cc-improve curate --apply
curate --apply: archived 1 skill(s) via git mv to _archive/ (none deleted)
$ ls skills skills/_archive
skills:        deploy-aws
skills/_archive: deploy-gcp  manifest.tsv
```

### Negative controls (Feature C)

- **Propose-only is real (C1)**: a curate with a non-empty archive plan moves NOTHING and writes a
  report; skills/ is byte-for-byte unchanged. Only `--apply` mutates.
- **Never deletes (C3)**: archive is `git mv` (content preserved under `_archive/`, recoverable); a
  test greps the curate code path and finds no `rm` command. Restore round-trips it.
- **Pinned is protected (C5)**: a plan that (mis)names a pinned skill does not archive it , the
  wrapper refuses by frontmatter, independent of the prompt.
- **Unavailable-safe (C8)**: a non-zero / bad-JSON curator leaves the library unchanged and exits 0.

### Rollback / live deploy (gate; host-touching launchd)

The curator code is read-only by default; the only persistent-state action is `--apply` (archive),
which is reversible via `cc-improve restore <name>` (git mv back) , nothing is ever deleted. The
weekly launchd + vps-mon onboarding are the operator's deploy-time steps at approval:

```
Command: launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/mini.cc-curator.plist
Command: launchctl print gui/$(id -u)/mini.cc-curator | grep -i program   # = .../bin/cc-improve
Exit: 0
Rollback: launchctl bootout gui/$(id -u)/mini.cc-curator ; rm the plist copy (the repo template stays)
```

- **vps-mon `monitored` confirmation: [UNAVAILABLE: requires live Mini deploy].** The job is
  auto-discovered by the Mini launchd collector once installed; the curator emits
  `~/.claude/cc-self-improve/curator.heartbeat` each run for the scheduled-job liveness signal. The
  live `monitored` check is in `deploy/macos/cc-curator-runbook.md` for Han to run at deploy. Held
  for his click (this is the `gate` sub-goal).

### Reproduce (Feature C)

```bash
cd tools/cc-self-improve
bash tests/test-curate.sh
plutil -lint deploy/macos/mini.cc-curator.plist
```

