# kit-weekly: the ONE kit scheduler (macOS LaunchAgent)

ADR-0034 decision 9: the kit ships ONE weekly scheduler, a single LaunchAgent
running a small dispatcher over a declarative jobs list, instead of a plist per
job. The per-job `session-intel-weekly` agent is retired; its digest now rides
the jobs list. Adding a weekly job = one `jobs.txt` line, never a new daemon.

```
bash deploy/macos/install                          # render plist + bootstrap (idempotent; retires session-intel-weekly)
launchctl kickstart -k gui/$(id -u)/kit-weekly     # run now
tail -f ~/.claude/intel/kit-weekly.log             # watch a run
```

Service graph: `kit-weekly.plist` -> `kit-weekly` dispatcher (exports a
launchd-safe PATH; the bare launchd PATH silently hollowed every digest for
three weeks once) -> each `jobs.txt` line in order:

| Job | Command | What it writes |
|---|---|---|
| `session-intel` | `bin/session intel run` | `~/.claude/intel/intel-YYYY-MM-DD.md`, the weekly digest: harness scorecard (`stats digest`), usage, repo health, merge + extract-workflow proposals |
| `kit-retro` | `bin/learn propose` | cited, deduped, adversarially-checked proposals into the staging file (review with `learn drain`, promote with `board promote`) |
| `prose-rag-index` | `bin/prose-rag index` | incremental recall-index refresh (`~/.claude/prose-rag/index.bin`). Opt-in by config: with no `PROSE_RAG_CORPUS` (and no built engine) it skips clean, exit 0, db untouched |

**Consumer env (optional).** launchd gives jobs a bare env (Claude Code's
`settings.json` env exists only inside sessions). If `~/.config/kit-weekly/env`
exists, the dispatcher sources it before running jobs; per-machine config like
`PROSE_RAG_CORPUS` lives there, never in the kit repo.

**Jobs-list contract.** `<job-name> <command relative to the kit root, or
absolute>`, one per line; `#` comments and blank lines skipped. A malformed line
or a command that does not resolve to an executable logs + skips; a failing job
logs + continues. Nothing crashes the week. Override the list per run with
`KIT_WEEKLY_JOBS=/path/to/jobs.txt`.

**Consumer split (SPEC-126).** The kit owns the template, the dispatcher, and
the jobs list; the CONSUMER instantiates the plist (`bash deploy/macos/install`
is that click). Job inputs that are tenant-specific (`OPS_TOOLKIT`, staging or
backlog paths) resolve via the same env channels the tools themselves document.

**Consumer bridge (optional).** The kit ships no monitoring endpoint or secret.
If an executable exists at `~/.config/kit-weekly/bridge`, the dispatcher runs it
best-effort after the jobs (liveness heartbeat, notification, anything
tenant-side); a bridge failure never fails the week. (Moved from the retired
`~/.config/session-intel/bridge` path; re-point your bridge if you had one.)

BTM rules honored: `ProgramArguments[0]` is the dispatcher's own absolute path
(never `/bin/sh`), and the launcher has no `.sh` extension, so Login Items shows
"kit-weekly" with the exec icon.

Uninstall: `launchctl bootout gui/$(id -u)/kit-weekly && rm ~/Library/LaunchAgents/kit-weekly.plist`
