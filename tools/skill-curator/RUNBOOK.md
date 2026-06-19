# cc-self-improve RUNBOOK

Operator-mid-incident guide. Symptom, diagnosis, fix. For daily use see [MANUAL.md](./MANUAL.md);
for the design see [docs/architecture.md](./docs/architecture.md).

The standing safety net: every reviewer/curate path **logs and exits 0** on any failure (a
self-improvement run must never break your session), and nothing here ever deletes a skill. So most
"incidents" are silent no-ops you discover later, not crashes.

## 1. Reviewer cost runs hot

- **Symptom:** the 7-day spend in the SessionStart line / `cc-improve status` is higher than expected.
- **Detect:** `cc-improve status`; or `jq -s 'map(.total_cost_usd)|add' ~/.claude/cc-self-improve/ledger.jsonl`.
- **Why:** one Haiku call per substantial session; the per-session trigger + single-flight lock bound
  it, so a spike usually means many short sessions or a too-large `transcript_k`.
- **Fix:** lower nothing first, check the rows. Then either keep `model = haiku`, raise `transcript_k`
  only if drafts lack context (it does not lower cost to lower it below the default), set
  `enabled = false`, or `bash deploy/uninstall.sh` as the kill switch.
- **Gap to know:** `curate` does NOT log a cost row, so a runaway weekly curator would NOT show in
  this line. Check the curator separately (incident 6).

## 2. Runaway / reentrant claude processes

- **Symptom:** several `claude -p` processes alive at once.
- **Detect:** `pgrep -fl 'claude -p'`; check the tool log `~/.claude/cc-self-improve/cc-self-improve.log`.
- **Why:** should be impossible. Guards: `--bare` strips hooks, the `CLAUDE_REVIEWING` sentinel makes
  the hook a no-op inside a reviewer, and the single-flight lock blocks a second concurrent run.
- **Fix:** `pkill -f reviewer-run`; the lock self-heals (a dead holder's lock is stolen). If it keeps
  happening, `bash deploy/uninstall.sh` and report it, the reentrancy guard has a hole.

## 3. Stuck lock (reviews silently stop)

- **Symptom:** sessions end but no drafts ever stage; the log says `single-flight , another reviewer
  in flight, skipping` every time.
- **Detect:** `ls ~/.claude/cc-self-improve/state/reviewer.lock.d/` and
  `cat ~/.claude/cc-self-improve/state/reviewer.lock.d/pid`.
- **Why:** the atomic mkdir lock is auto-stolen only when the recorded `pid` is dead. If the pid file
  is empty/unreadable (a write failed) or a live unrelated process reused that pid, the steal is
  skipped and every run no-ops.
- **Fix:** confirm no live reviewer (`pgrep -fl reviewer-run`), then remove the lock dir:
  `rm -rf ~/.claude/cc-self-improve/state/reviewer.lock.d`. Note the config key is `reviewer.lock`
  but the lock is the `.d` directory; the bare file never exists.

## 4. settings.json corruption / install went wrong

- **Symptom:** Claude Code fails to start, or hooks misbehave after an install.
- **Detect:** `jq -e . ~/.claude/settings.json` (does it parse?); `ls ~/.claude/settings.json.bak-*`.
- **Why:** install validates JSON first and aborts if the existing file is invalid; it backs up to
  `settings.json.bak-<ts>`, then writes atomically (jq to a temp file, validate, `mv`). A mid-write
  crash leaves the original intact.
- **Fix:** restore the newest backup: `cp ~/.claude/settings.json.bak-<ts> ~/.claude/settings.json`.
  To cleanly remove just this tool: `bash deploy/uninstall.sh` (surgical, matches only
  `cc-self-improve` command paths). Note: install was never run against the live settings during the
  build, you ran it, so a fresh install is the first live mutation.

## 5. A draft will not promote

- **Symptom:** `skill-review promote <slug>` refuses.
- **Detect:** read the exit code and the stderr line.
- **Map:** `2` = no such draft / bad slug (check `skill-review list`). `3` = REFUSED, the SKILL.md
  still contains a secret-shaped string; scrub it (the regex set is in `lib/common.sh:contains_secret`).
  `4` = a live skill of that name exists; re-run with `--force` (it backs the old one up to
  `skill-proposals/_replaced/` first). `5` = mkdir/move failure (permissions on `~/.claude/skills/`).
- **Fix:** address the specific code above. Reject instead with `skill-review reject <slug>` if the
  draft is not worth promoting (it moves to `_rejected/`, recoverable).

## 6. The weekly curator fired `--apply` by mistake

- **Symptom:** skills moved to `_archive/` without you running `--apply`.
- **Detect:** `launchctl print gui/$(id -u)/mini.cc-curator | grep -c apply` (must be `0`);
  inspect `~/Library/Logs/cc-self-improve/curator.*.log`.
- **Why:** the plist must invoke `cc-improve curate` with NO `--apply`. A hand-edited installed plist
  is the only way this happens.
- **Fix:** nothing was deleted, so recover with `cc-improve restore <name>` per the manifest
  (`~/.claude/skills/_archive/manifest.tsv`). Then re-deploy the plist from the repo template (never
  hand-edit the installed copy) per the curator runbook. Anti-drift: edit the template, redeploy.

## 7. Transcript schema drift (reviewer no-ops or drafts garbage)

- **Symptom:** drafts stop appearing, or a draft looks malformed.
- **Detect:** `bash tests/test-transcript-parse.sh` against the committed fixture.
- **Why:** the parser (`lib/transcript.sh`, jq over `.type` in {user,assistant} with
  `.message.content[].text`) is locked to a sample schema. If Claude Code changes the transcript
  shape, the parser yields an empty summary and the reviewer no-ops (it does not draft garbage).
- **Fix:** dump a current transcript, re-lock `tests/fixtures/sample-transcript.jsonl`, and adjust
  the jq filter if the shape moved.

## 8. Curator data-loss scare / non-git skills dir

- **Symptom:** a skill is "gone" after a curate `--apply`.
- **Detect:** `ls ~/.claude/skills/_archive/`; `cat ~/.claude/skills/_archive/manifest.tsv`.
- **Why:** archive is `git mv` to `_archive/`, never `rm`. On a non-git `~/.claude/skills/`, it falls
  back to plain `mv` + a manifest line + a WARN (so there is no git history behind the move, but it is
  still recoverable).
- **Fix:** `cc-improve restore <name>`. If `~/.claude/skills/` is not a git repo, consider
  `git init` there so archive/restore carry history.

## 9. Memory count reads 0 silently

- **Symptom:** the SessionStart line says `0 staged memory` when cc-harvest has queued rows.
- **Detect:** `cat "$CC_SI_MEMORY_LEDGER"` (default
  `~/workspace/tieubao/ops-toolkit/_meta/learned-ledger.md`); check it exists and has `| ... | queued |`
  rows.
- **Why:** `lib/surface.sh` hardcodes that default path and counts queued rows by regex. If the
  ops-toolkit repo moved or cc-harvest changed its ledger table format, the count reads 0 with no error.
- **Fix:** export `CC_SI_MEMORY_LEDGER` to the real path (in the hook env or your shell). This is a
  known brittle coupling; it affects only the surfaced count, not capture.

## Where things live

| What | Path |
|---|---|
| Config | `~/.claude/cc-self-improve/config.toml` |
| Cost ledger | `~/.claude/cc-self-improve/ledger.jsonl` |
| Tool log | `~/.claude/cc-self-improve/cc-self-improve.log` |
| Single-flight lock | `~/.claude/cc-self-improve/state/reviewer.lock.d/` (dir + `pid`) |
| Curator reports + heartbeat | `~/.claude/cc-self-improve/curator-report-*.md`, `curator.heartbeat` |
| Staged drafts | `~/.claude/skill-proposals/<slug>/SKILL.md` (+ `_rejected/`, `_replaced/`) |
| Live skills + archive | `~/.claude/skills/`, `~/.claude/skills/_archive/` (+ `manifest.tsv`) |
| Launchd logs | `~/Library/Logs/cc-self-improve/curator.{out,err}.log` |
| settings.json backups | `~/.claude/settings.json.bak-<ts>` |

## Kill switch

`bash deploy/uninstall.sh` removes the hooks. `bootout` the curator LaunchAgent if installed:
`launchctl bootout gui/$(id -u)/mini.cc-curator`. Both are reversible; neither deletes your ledger,
drafts, or skills.
