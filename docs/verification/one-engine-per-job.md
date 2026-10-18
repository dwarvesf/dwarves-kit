# Verification -- one-engine-per-job

Four jobs each had two or three implementations. This change keeps one per job: one transcript parser, one board mirror engine, one hook log root. The Hermes bridge item hit its stop condition and changed nothing. Design notes: `docs/implementation-notes/one-engine-per-job.md`.

## Gate table

| Claim | Evidence |
|---|---|
| harvest and skill-curator output is unchanged | byte-identity block and harvest parity, below |
| the shared parser rejects the shapes harvest used to crash on | `lib/session/tests/test-parse-transcript.sh`, 19 checks |
| `board mirror --engine sync` no longer routes to a second engine | `tests/test-board-mirror.sh`, 108 checks |
| `cockpit.py` keeps what live spokes import | `tests/test-sync.sh`, 235 checks |
| hook logs land in `<ledger root>/hooks`, migrated once, never deleted | `tests/test-hook-log-dir.sh`, 17 checks |
| the hook edits did not move any other hook behavior | the suite table below |
| each control is load-bearing | three negative controls below |

## Green run

```
Command: bash tests/test-harvest-parity.sh
Exit: 0
Output:
harvest parity: 171 passed, 0 failed
Verdict: PASS
```

```
Command: bash lib/session/tests/test-parse-transcript.sh && bash lib/skill-curator/tests/test-transcript-parse.sh
Exit: 0
Output:
smoke: all 19 passed
test-transcript-parse: all 6 passed
Verdict: PASS
```

```
Command: old jq transcript_text (git show ab38a33d:hooks/harvest.sh) vs parse_transcript.py --harvest-text, then old transcript.sh vs --tail-text, cmp on each pair
Exit: 0
Output:
same max=12000       88B sample.jsonl
same max=300         88B sample.jsonl
same max=0           88B sample.jsonl
same max=12000       82B sample-transcript.jsonl
same max=300         82B sample-transcript.jsonl
same max=0           82B sample-transcript.jsonl
same max=12000    12022B real session transcript (3 MB)
same max=300        304B real session transcript (3 MB)
same max=0       226859B real session transcript (3 MB)
same k=1       34B sample-transcript.jsonl
same k=40     115B sample-transcript.jsonl
same k=1      667B real session transcript
same k=40  133667B real session transcript
Verdict: PASS
```

```
Command: bash tests/test-board-mirror.sh
Exit: 0
Output:
TOTAL: 108   PASS: 108   FAIL: 0   SKIP: 0
Verdict: PASS
```

```
Command: bash tests/test-sync.sh
Exit: 0
Output:
235 passed in 6.58s
Verdict: PASS
```

```
Command: bash tests/test-hook-log-dir.sh
Exit: 0
Output:
hook-log-dir: 17 passed, 0 failed
Verdict: PASS
```

The hook edits touch nine hooks, so each hook's own suite ran on the final tree:

| Suite | Result |
|---|---|
| `tests/test-codex-hooks.sh` (pins repinned with `lib/codex/repin.sh`) | 94 passed, 0 failed |
| `tests/test-citation-guard-parity.sh` | exit 0 |
| `tests/test-gate-opt-in.sh`, `tests/test-gate-opt-out.sh` | ALL PASS, ALL PASS |
| `tests/test-board-row-gate.sh` | PASS=73 FAIL=0 |
| `tests/test-ship-gate-default-push.sh` | PASS=37 FAIL=0 |
| `tests/test-ship-gate-review-verdict.sh` | pass=37 fail=0 |
| `tests/test-mega-gate-parity.sh` | PASS=12 FAIL=0 |
| `tests/test-kit-contract.sh` | 25 passed, 0 failed |
| `tests/test-kit-foldin-hooks.sh`, `tests/test-meta-plugin-hooks.sh` | all passed |
| `tests/test-board.sh`, `tests/test-board-writeback.sh` | 57 passed 1 skipped; 69 passed 1 skipped |
| `tests/test-hooks.sh`, `tests/test-lanes-data.sh` | exit 0 (run before the last one-line helper fix) |
| `bin/test-affected --base master` | 68 of 77 pass. 7 timed out under a machine load of 100 to 170; 6 of them re-ran green alone, and `test-wrap-land.sh` never got the shared test lock. 2 failed: `test-kit-contract.sh` (fixed, now 25 of 25) and `test-outcome-emit-sweep.sh`, which fails the same way on master (an unpaired outcome bracket in `commands/debug.md`) |

## Negative control

Each mutation was applied to a committed tree, the suite went RED, and the file was restored.

### Shared parser: the strict flag

Mutation: `parse_lines` stops raising on a non-object line, so `--harvest-text` would stage text from a transcript the original harvest crashed on.

```
Command: bash lib/session/tests/test-parse-transcript.sh
Exit: 0 (green before mutation)
Output:
    ok: MAX keeps the last characters
    ok: MAX=0 keeps everything
    ok: crash shape 'obj' prints nothing, exit 1
    ok: crash shape 'msg' prints nothing, exit 1
    ok: crash shape 'content' prints nothing, exit 1
    ok: crash shape 'text' prints nothing, exit 1
    ok: crash shape 'utf8' prints nothing, exit 1
    ok: missing file exits 1
  
  smoke: all 19 passed

Mutation: sed -i '' 's/            if strict:/            if False:/' lib/session/parse_transcript.py
Changed: lib/session/parse_transcript.py
Exit: 1 (under mutation, RED expected)
Output:
    ok: MAX keeps the last characters
    ok: MAX=0 keeps everything
    FAIL: crash shape 'obj' rc=0 out=xx
    ok: crash shape 'msg' prints nothing, exit 1
    ok: crash shape 'content' prints nothing, exit 1
    ok: crash shape 'text' prints nothing, exit 1
    ok: crash shape 'utf8' prints nothing, exit 1
    ok: missing file exits 1
  
  smoke: 1 FAILED, 18 passed

Restore: git checkout HEAD -- lib/session/parse_transcript.py
Exit: 0 (green after restore)
Verdict: PASS
```

### Mirror engine: the prior revision

Mutation: `board.sh` and `cockpit.py` go back to the revision that still had `--engine sync`. Exactly one check goes RED, the new one.

```
Command: bash tests/test-board-mirror.sh
Exit: 0 (green before mutation)
Output:
  --- NC9d: terminal rows default to one summary line, per-row lines are opt-in ---
    PASS NC9d: default log has no per-row skip line
    PASS NC9d: default log has a per-repo count of skipped terminal rows
    PASS NC9d: BOARD_MIRROR_VERBOSE=1 restores the per-row lines
  
  === Coverage delta ===
    PASS coverage delta: board-mirror checks went from 0 to 107 in this suite
  
    ---------------------------------------------
    TOTAL: 108   PASS: 108   FAIL: 0   SKIP: 0

Mutation: git show ab38a33d:lib/board/board.sh > lib/board/board.sh; git show ab38a33d:lib/sync/cockpit.py > lib/sync/cockpit.py
Changed: lib/board/board.sh, lib/sync/cockpit.py
Exit: 1 (under mutation, RED expected)
Output:
  --- NC9d: terminal rows default to one summary line, per-row lines are opt-in ---
    PASS NC9d: default log has no per-row skip line
    PASS NC9d: default log has a per-repo count of skipped terminal rows
    PASS NC9d: BOARD_MIRROR_VERBOSE=1 restores the per-row lines
  
  === Coverage delta ===
    PASS coverage delta: board-mirror checks went from 0 to 107 in this suite
  
    ---------------------------------------------
    TOTAL: 108   PASS: 107   FAIL: 1   SKIP: 0

Restore: git checkout HEAD -- lib/board/board.sh lib/sync/cockpit.py
Exit: 0 (green after restore)
Verdict: PASS
```

### Hook log root: the hooks/ subdir

Mutation: the helper returns the ledger root itself instead of `<root>/hooks`.

```
Command: bash tests/test-hook-log-dir.sh
Exit: 0 (green before mutation)
Output:
  hook-log-dir: 17 passed, 0 failed

Mutation: sed -i '' 's#dir="$root/hooks"#dir="$root"#' lib/telemetry/hook-log-dir.sh
Changed: lib/telemetry/hook-log-dir.sh
Exit: 1 (under mutation, RED expected)
Output:
    FAIL default is the XDG ledger root plus hooks: want '/var/folders/dr/n3x74rr93kvfjf1873pyjvp80000gn/T//kit.5pVaR7/h.L3UlGT/xdg/dwarves-kit/logs/hooks' got '/var/folders/dr/n3x74rr93kvfjf1873pyjvp80000gn/T//kit.5pVaR7/h.L3UlGT/xdg/dwarves-kit/logs'
    FAIL DWARVES_KIT_LOG_DIR moves it: want '/var/folders/dr/n3x74rr93kvfjf1873pyjvp80000gn/T//kit.5pVaR7/h.L3UlGT/pin/hooks' got '/var/folders/dr/n3x74rr93kvfjf1873pyjvp80000gn/T//kit.5pVaR7/h.L3UlGT/pin'
    FAIL KIT_LEDGER_DIR beats the alias: want '/var/folders/dr/n3x74rr93kvfjf1873pyjvp80000gn/T//kit.5pVaR7/h.L3UlGT/led/hooks' got '/var/folders/dr/n3x74rr93kvfjf1873pyjvp80000gn/T//kit.5pVaR7/h.L3UlGT/led'
    FAIL an empty KIT_LEDGER_DIR falls back to the XDG root, never a relative path: want '/var/folders/dr/n3x74rr93kvfjf1873pyjvp80000gn/T//kit.5pVaR7/h.L3UlGT/xdg/dwarves-kit/logs/hooks' got '/var/folders/dr/n3x74rr93kvfjf1873pyjvp80000gn/T//kit.5pVaR7/h.L3UlGT/xdg/dwarves-kit/logs'
    FAIL safety-gate logs into <root>/hooks: want '1' got ''
  hook-log-dir: 12 passed, 5 failed

Restore: git checkout HEAD -- lib/telemetry/hook-log-dir.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Rollback

Revert the branch's commits (`git revert` each, or revert the merge). Nothing needs a data fix:

- Hook logs: the old `~/.claude/dwarves-kit/logs` directory is never deleted or rewritten, so a reverted hook reads and writes it again. Files the helper copied into `<ledger root>/hooks/` stay behind and are harmless; delete that directory by hand if wanted.
- `board mirror --engine sync` returns after a revert, still dry-run only.
- `hooks/codex-hooks.json` pins move back with the hook files in the same revert.

## Not proven

- The Hermes bridges were inventoried, not changed. Both are in live use, so the operator picks whether to retire either.
- `tests/test-wrap-land.sh` never ran: it waited on the shared test lock another worker held. It does not touch the changed files directly.
- The third jq transcript copy named in the risk list (the audit agent) was not found as code and is untouched.
- The first-use log migration ran only against fixtures and temp homes, never against a real machine's old log dir.
