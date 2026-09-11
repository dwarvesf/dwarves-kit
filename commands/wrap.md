---
description: "The session-scoped landing step after ship: flips board rows, merges the operator's own green PRs one at a time, checks deploys, tidies branches and worktrees, writes the activity line, calls /kit:retro when a shipped PR merged, and prints the skim-first report. Use when the operator says to wrap up or close out the session, land the work, or run the end-of-session routine: 'wrap up', 'wrap this up', 'close out', 'let's wrap', 'session wrap', 'land it', 'pack this up for the day', 'wrap up, update items status, commit, merge PRs and clean up worktrees and stale branches, then pull the latest', 'tổng kết session', 'wrap lại đi'. Also the door for the distill half when an operator has wired the seams: 'distill this session', 'check if you can learn from this session and distill anything into scripts, tools or skills for future replay'."
---

Self-intro (AGENTS.md "Self-intro" convention): open your first reply with exactly one banner line, `[kit:wrap] Land the session after ship: board rows, merges, deploy check, tidy, activity line, retro.`, then proceed.

You are the session's landing step. The operator just shipped, or is ending the session, and nothing in the kit lands that session on its own: board rows stay unflipped, the operator's own green PRs stay unmerged, a merged-but-undeployed PR goes unnoticed, branches and worktrees pile up, and `/kit:retro` never runs. Your job is one pass over every repo the session touched, closing out every step below in order.

## When this runs

- After `/kit:ship` completes, for the repo that just shipped.
- At the end of a session, before the operator closes the terminal.
- Whenever the operator asks to land, wrap up, or close out the session.
- Never mid-build: a spec still mid-execute has nothing to land yet.

## Prerequisites

- Each named repo (or the current repo, when none is named) is a git repository. A non-repo argument prints a skip line and the rest proceed.
- `gh` is optional. When it is absent or unauthenticated, every branch that is not a plain ancestor of the default branch verdicts `unknown: LEAVE` and `bin/wrap merge` refuses with exit 1; the command still runs the other seven steps and reports the degraded state, it never stops for this reason alone.

## Process

Bracket the phase for timing (SPEC-129) before starting: `bash lib/gate/gate-ledger.sh outcome <rid> wrap start`.

Run the steps below once per repo the session touched (the current repo when the operator names none). Positional repo arguments; wrap never discovers touched repos on its own (Out of Scope).

**Scan for candidates before step 0, act on them at step 7b.** Step 7b's scan reads the session and nothing else, and it is the one step whose input degrades with every step that runs before it: six steps of scan, merge, and pull output later, the model is reasoning about branches and has lost what it did four times by hand at 14:00. So the scan runs FIRST, ahead of even the seams: write the candidate list (label, what was repeated or written, how many times) to the scratch file the step 9 report will use. Step 7b then runs precedent and acts on that list, never on a fresh recollection. The old standalone closeout ran this scan as its first move, before any landing, and produced an enhancement to an existing tool most sessions; the same scan at step 7 produced none across its first two weeks, because by then there was nothing left in context to scan.

### Step -1: the seams

An operator can hang one skill on each side of this command. Read both keys first:

```bash
. lib/config/kit-config.sh
kit_config_get_root wrap.before ""
kit_config_get_root wrap.after ""
```

An empty value means no skill runs on that side, which is the default for both. A named skill runs at its side's position and its report lines fold into step 9's report after the `FYI` line. Both keys resolve with `kit_config_get_root`, so each comes from the operator `kit.toml` or the kit-root `kit.toml` and never from a project `.kit.toml`: they name code this command runs, and a project toml rides inside an untrusted PR.

**Pick the side by what the skill needs.** `wrap.before` runs ahead of step 0, so it sees the session's uncommitted state; a skill that must read a working tree before wrap commits or tidies it belongs there. `wrap.after` runs after step 8 and before the step 9 report, so the landing is already done; a skill that only reads what the session produced belongs there. **`after` is the right side for a knowledge flush**, and the reason is the operator's time: a flush on the `before` side greps every note store while the git work waits behind it, so the landing an operator asked for arrives last. Nothing in a flush informs a board flip or a merge, so nothing is gained by paying for it first.

**Report the outcome, whichever side ran.** Step 9 owes a `**Seam:**` line and the lint fails without it. A seam that never ran because no key was set, and a seam that was silently skipped, are different facts; the `**Built:**` line exists for exactly this reason at step 7b, and the same hole is here. A named skill that fails to run is `SKIPPED: <why>`, never silence.

Read the three autonomy knobs in the same call, once, and carry the values through the pass:

```bash
. lib/config/kit-config.sh
kit_config_get_root wrap.merge_own_prs true
kit_config_get_root wrap.tidy_worktrees true
kit_config_get_root wrap.build_candidates true
```

Each governs exactly one step: `merge_own_prs` step 3, `tidy_worktrees` step 5, `build_candidates` step 7b. The shipped defaults are all `true`, so wrap acts. Every one of the three authorizes a write, which is why all three resolve with `kit_config_get_root` and never from a project `.kit.toml`. A `false` turns that step's action into a report line; it never turns the step off, and it never relaxes a refusal the tools make on their own. Name every knob read as `false` in the report's `FYI`, so a step that stayed its hand says why.

### Step 0: concurrent-writer check

Foreign activity in a repo's checkout means either signal is present: a worktree reflog entry newer than the session start, or an `index.lock` file that is older than 5 seconds or persists for 5 seconds (a lock that clears within the window is ordinary git traffic). Run `bin/wrap scan <repo>` for the checkout, ahead/behind count, dirty files, worktrees, branch verdicts, and the operator's own open PRs.

- `bin/wrap scan <repo>` is report only; it never writes.
- On foreign activity: STOP, report what was found, and leave that repo alone for the rest of the pass. Do not touch a dirty file this session did not write.
- The check runs again, repo by repo, immediately before steps 3, 5, and 6 (the three steps that write). A repo that goes foreign between checks drops out of the remaining steps for that repo only.

### Step 1: board rows

For every backlog row whose source of truth this session closed, flip it through THAT repo's board wrapper, `<repo>/_meta/board set <ID> shipped|parked|dropped "<PR or SHA>"` (or `<repo>/board set` where the wrapper lives at the root); with no wrapper, `bin/board set <ID> <state> --backlog-file <repo>/_meta/BACKLOG.md`. A bare `bin/board set` without `--backlog-file` targets the kit's own board, never the wrapped repo's. A row this session merely touched, without closing its source of truth, stays where it is.

### Step 2: commit by name

Commit any of the operator's own outstanding work under its own name and message. This step is a command-layer judgment call, not a verb: `wrap` owns no commit write. Skip it when nothing of the operator's own is outstanding.

### Step 3: merge the operator's own PRs

`wrap.merge_own_prs` false: merge nothing, report every own open PR as `OPEN` under `Shipped`, and say in `FYI` that the knob is off. Steps 4 onward still run.

Otherwise re-run the step 0 check first. Then, once per PR: `bin/wrap merge --apply <repo>`. It merges exactly one own, green PR whose base is the default branch and reports every skip reason for the rest.

- `wrap merge` never runs twice for the same PR in one call; call it again for the next PR.
- When the session's open PRs form a chain, follow SPEC-065 order: retarget every dependent onto its grandparent's target first, then merge parent-first, oldest ancestor first.
- Never merge a PR the operator did not open.

### Step 4: deploy check

A merged PR is not a deployed one. For a repo whose deploy is a `workflow_dispatch`, dispatch it and confirm `headSha == merge SHA` before the report claims `DEPLOYED`. A repo with no dispatch-shaped deploy has nothing to check here; say so plainly rather than guessing at a deploy that does not exist.

- The command checks a deploy; it never dispatches one on its own initiative (Out of Scope). Dispatching happens only when the operator asked for this repo's deploy as part of landing the session.

### Step 5: branches, worktrees, pull

Re-run the step 0 check first. Then, in this order: remove the session's own worktree (the bullet below), `bin/wrap scan <repo>` again to see the current branch verdicts, `bin/wrap apply --worktrees <repo>` as a dry run, read every `SKIP` line, then `bin/wrap apply --apply --worktrees <repo>` to execute. Close the step by re-running `bin/wrap scan <repo>`: that final scan, not memory, is what step 9's `Left alone` reports.

- `<repo>` is the MAIN checkout path, never the session's cwd. Resolve it once: `main=$(git -C <cwd> rev-parse --path-format=absolute --git-common-dir)` then strip the trailing `/.git`. Off the main checkout `apply` sees the feature branch as current and never pulls, which is how a repo stays behind while the report claims it landed.
- Pass `--worktrees` on every call, dry run and apply alike, unless `wrap.tidy_worktrees` is false. It is the flag the operator asks for by saying "clean up worktrees", and `apply` refuses a dirty, detached, or checked-out worktree on its own, so the flag is not the safety. Omitting it also strands every branch a worktree holds: `apply` skips those with `held by a worktree` and the branch survives with it. With the knob false, drop the flag, leave every worktree, list them under `Left alone`, and name the knob in `FYI`; the session's own worktree bullet below is unaffected, because that removal is proven per worktree rather than swept.
- `bin/wrap apply` without `--apply` changes nothing; always read its dry-run SKIP lines before adding `--apply`.
- Pull on the default branch is `--ff-only`; off the default branch, `apply` fetches the default branch into itself instead and reports a refusal as `FAILED`, never forced. That fetch refuses outright when the default branch is checked out in another worktree, which is the second way a repo stays behind; the main-checkout rule above is what avoids both.
- The session's own `EnterWorktree` worktree goes FIRST, before `wrap apply` runs, so the harness records the removal instead of finding the directory gone. Once `wrap scan` proves its branch squash-merged (tip matches the PR head) and the worktree is clean, remove it: `ExitWorktree remove` with `discard_changes: true` (the squashed commits are not ancestors of the default branch, so the tool asks; the proof is the confirmation), then `git branch -D <branch>`. The operator gave that confirmation once, as a standing rule, and a worktree whose PR merged this session is finished work, never something to keep. `ExitWorktree keep` only when the worktree is dirty, the branch is not proven merged, or the proof is unavailable (no `gh`); say which in `Left alone`. A plain secondary worktree still routes through `wrap apply --worktrees` and skips when dirty, detached, or held by the checked-out branch.
- Never remove a dirty or foreign worktree, under `--worktrees` or otherwise.
- Never force-push and never rewrite history to make a delete or a pull succeed.

### Step 6: activity line

Re-run the step 0 check first. Then: `bin/wrap log "<slug>: <one sentence>"`. When the current directory is a git worktree of the repo that holds the configured file, the same repo-relative file inside that worktree is written instead, so the line is committable on the session's branch; the main checkout's copy is left alone. With no `wrap.activity_log` key in the kit-root `kit.toml`, it prints the line and says where it did not land; that is a clean result, not a failure.

### Step 7: understand

The process half of distill (SPEC-249): a DEBT marker for the run, new-tool candidates checked against precedent, and one memory note per incident this session caused. Three lettered sub-steps, each prints one line when idle.

Sub-step `b` BUILDS what it can rather than proposing it, and it builds through the lane, never around it. A tiny-lane candidate is built and verified here, because a wrong call costs one revert and a staged row that waits for a yes costs a round trip on work the operator already asked for. Anything heavier is staged with its goal drafted, because a spec, a review, or a root cause does not fit in the minutes an operator gave you to close the session, and a change that skips them is unreviewed and undocumented wherever it lands. A row is staged on its own merits too, whatever its lane, when the candidate fails the `Needs you` admission test, meaning its scope is a judgment whose options carry different irreversible outcomes. Sub-step `c` writes one memory note and never a board row.

a. DEBT marker.

```bash
rid_out="$(bash lib/gate/gate-ledger.sh rid 2>&1)"; rid_rc=$?
```

**Every skip in this sub-step skips ONLY this sub-step.** `a` is the DEBT marker and nothing else; `b` and `c` do not depend on a run id, a run log, or the classifier, and they run whatever `a` reported. A real session on 2026-09-09 read `skipped: no run id` as "step 7 does not apply" and never ran `b`, which is the step that builds rather than proposes. If `a` skips, say so and go straight to `b`.

**A non-zero `rid_rc` is a STRUCTURAL skip, not a clean one.** This is `gate-ledger.sh rid` refusing outright: landing from `master`/`main`, a detached HEAD, or a branch whose slug strips empty. There is no branch to key a ledger entry to, so the DEBT marker was never reachable this run, which is a different fact than "nothing to record." Print `skipped (structural): DEBT marker impossible this run (<rid_out>)`, quoting the tool's own reason. Do not synthesize a rid from anything other than the branch: the ledger's rid is the SAME key `hooks/ship-gate.sh` checks at push (SPEC-070), so a rid tied to the session instead of the branch would write an entry the ship-gate can never find and no other reader can trace back to a branch, a second failure mode worse than the skip it would replace.

Otherwise `rid="$rid_out"` and resolve the log dir with `logdir=$(bash -c 'source lib/telemetry/kit-log-dir.sh; kit_resolve_log_dir')` (the file is source-only and prints nothing when run as a command); a missing `runs/<rid>.log` prints `skipped: no run log`; a `| DEBT |` line already in it prints `skipped: DEBT marker present`. Otherwise `bash lib/classify/significance-classify.sh record <rid> "<one-line session description>"`; a non-zero exit prints `skipped: classifier failed (rc N)` and the step continues to b. These three remain plain skips: the rid exists, so the marker was reachable and simply had nothing to add.

**The teacher seam.** Once the marker is written (or found already present), run `bash lib/gate/quiz-gate.sh teacher` (the one resolver every seam-adjacent site cites; never read `understand.teach` any other way). Empty: print `skipped: no teacher` plus the path to the material a teacher would need (`<logdir>/runs/<rid>.log`, the DEBT line itself) and stop there, sub-step `a` is done. Named: invoke that skill through the Skill tool, handing it the rid, the DEBT row just written, and the run's diff (`git diff <base>..<rid's head>` where derivable). The engine never decides what the teaching looks like; it writes the record and, when a teacher is configured, hands the record over. This sub-step never names a skill itself.

b. Candidates. Act on the list the pre-step-0 scan wrote. A candidate is one of three things, and the first two are what the scan looks for: a manual multi-step procedure this session ran three or more times, or the operator called recurring (the same `jq` over transcripts, the same mutate/test/restore loop, the same board flip by hand); a one-off script or snippet written this session that solves a problem more general than the session's (a probe, a helper, a check that a tool over there should own); or an enhancement the operator asked for and the session deferred. **What the session BUILT as its task is NOT a candidate**: that is the deliverable, `Shipped` already carries it, and listing it here is how a wrap reports `Built:` every time and enhances nothing. **That exclusion covers the OUTPUT, never the METHOD.** When the deliverable IS manual labour (a triage pass, an audit done by hand, a migration walked file by file), the procedure that produced it is the candidate the scan most needs, and excluding it removes the only one worth having. The question to ask of the session is whether the operator got a result or a mechanism: a result plus a repeated method is a candidate, every time. **Repetition the session DELEGATED counts too.** A procedure run three times by three subagents appears once in the lead's own tool history, so the scan reads one dispatch and misses it; count what the session CAUSED to happen, not what the lead typed. Both holes were found the same way on 2026-09-10, by the operator asking twice why a four hour manual cleanup produced no candidate. The check runs on the first candidate, not the third, because a single-purpose script written next to an existing tool is the fragment this step exists to prevent. `wrap.build_candidates` false: run the precedent check AND the lane classifier anyway, then stage every candidate with the `bin/wrap stage` line below, quote the top hit in the FYI bullet where one came back, and close each `Built:` item as `(lane=<lane>, staged: build_candidates off)` with no goal draft. Building is what the knob governs; checking precedent and sizing the work are not optional at either setting, because a staged row that names neither the tool it should have joined nor the lane it owes recreates the fragment one release later.

Otherwise, for each candidate run `bin/precedent find --surface inventory --json "<two or three words>"`. The answer decides the HOME and the report token, and it decides nothing else:

- **`nothing_matched` false, a hit came back.** The candidate is an enhancement to something that already exists, which is the whole reason this check runs. Its home is that hit and its token is `ENHANCE`. Do not write a sibling beside it. A single-purpose script written next to an existing tool is the fragment this step exists to prevent, and quoting the tool it should have joined prevents nothing.
- **`nothing_matched` true.** The candidate is new. Its home is the repo that would own it and its token is `NEW (precedent: nothing matched)`.

**Then size it, and the size decides where the build happens.** A build that lands from inside wrap is still a change in a real repo, so it owes the same lane discipline as any other change; an inline edit-and-commit at session close is how an unreviewed, undocumented change enters an estate:

```bash
bash lib/classify/lane-classify.sh classify "<the candidate in one line>"
bash lib/classify/lane-classify.sh classify --files "<paths>" "<the candidate in one line>"   # when the touched files are known
```

- **`tiny`.** One obvious edit: a flag on an existing verb, a case in an existing table, a line of copy. BUILD IT NOW in the home repo, on its own branch, never on that repo's default branch. Run one verification command before the commit (the home repo's own test for the file you touched, or the smallest command that fails if the edit is wrong) and QUOTE its output in your report; a `task-verifier` against the candidate's intent stands in where the repo has no such command. Commit under its own name only after the check is green. Report it with `lane=tiny` and the check that ran.
- **`normal`, `full`, `bug`, or `backfill`.** Do not build it here. Wrap is the landing step and these lanes owe a spec, a review, or a root cause first, none of which fits in the minutes an operator gave you to close the session. Two writes instead, in this order: stage the row with `bin/wrap stage "<title>" "<intent>" "<home>" --repo <the checkout of that home repo>`, then draft the goal for it, a six-section operating directive (Context-to-read / Constraints / Operating rules / Validation loop / Done-when / Pause-if) at `.claude/goals/<slug>.md` in that home repo, the shape `/kit:assign` writes and the shape the next session runs. Name the lane and the `Done =` line in the draft. Report it with `lane=<lane>` and the draft path.

The staging row lands in the home repo's `_meta/backlog-staging.md`, so `--repo` is what puts it there: without it the row lands in the current repo and `<home>` is only a text field (`already staged` from the verb needs no bullet). The draft path is also the goal pointer the drain fence below asks for, so a row staged this way is drainable where a bare row is not.

**Model tier for any worker you dispatch, at either size.** Sonnet is the default worker. Opus takes the verification arm, and takes the build too when the candidate touches security, money, or a data model. Haiku takes mechanical fan-out only (grep, read, a flat transform). Never dispatch a worker on the session's own model by default.

**Open the top hit rather than trusting its name**: `bin/precedent find --explain '<label as printed>'`. A hit that covers half the candidate still means ENHANCE that home, a verb, a flag, or a step in the existing skill, never a sibling next to it. The cases this gate was built from, so none is re-derived: a python board-flip written five times while `board set` existed; a merge helper one `.gitattributes` line replaced; two lessons filed as new memory notes while a note and a skill section already held them; kit features proposed that already existed as `/kit:*` commands; a session that hand-rolled `jq` over the session transcripts four times while `session recall` existed, and the mutate/test/restore loop four times while `proof-ledger.sh` was the home. Two first rungs came out of those: "which session did X" is `session recall <terms> --project <repo-name> --sessions`, and a proof's negative control is `bash lib/gate/negctl.sh <root> "<test-cmd>" "<mutate-cmd>"` after the change is committed.

**A hit on a memory note or a research file is NOT the home for the build.** `bin/precedent` indexes prose as a hit kind, so a note often tops the list. A note is where the lesson goes AFTER the build, or instead of the build only when no mechanism exists. **When the hit list holds a prose home and a code home, the CODE home wins.** That rule was learned by taking the first line of a hit list whose second line named `lib/wrap/wrap.sh`, the file the fix eventually went into, while the session wrote three markdown files and shipped no mechanism. When nothing mechanical was possible, say so in the report: add `PROSE-ONLY: <reason>` as its own bullet, or append the token to the inline item. It is honest when the work is one human judgment per run, and dishonest when you repeated a procedure and wrote a note about it.

**Never grep or Read across repos, notes, or research to answer the overlap question yourself.** The scan is sub-second and costs no tokens; the model scanning the estate is the spend this gate removes.

No candidates: `NOTHING: no candidates`, and that word is NOTHING, never SKIPPED. SKIPPED is reserved for the step not running (the knob was false and nothing could be staged, the scan never ran, a tool refused); an empty scan is a result, and `SKIPPED: nothing to build` is the one line that says both and means neither, which the lint now rejects. Nothing here reaches a public repo or an outward-facing surface; a candidate that would (a publish, a send, a charge) is never built here, it goes to `Needs you` under the admission test.

**Draining what was staged.** Read `kit_config_get_root wrap.drain_staged false`. False, the default: report each staged row and its home in `FYI` and stop. This is the one knob in this command whose default does not act, and the reason is worth stating plainly: `queue run` drives a real interactive claude in a tmux window under `QUEUE_CLAUDE_FLAGS` (default `--dangerously-skip-permissions`) for up to `QUEUE_TIMEOUT_SECS` per row. Every other knob here governs finishing work the operator already asked for. This one starts work nobody has decided on yet, at the moment the operator said to stop.

True: drain, under three fences.

- **Scope is this session's own rows.** Write a tsv of `slug<TAB>repo<TAB>pointer` for the rows THIS pass staged, then `bash lib/queue/queue.sh run <tsv> --sanitize-prompt --max-megas <count>`. Never `--from-boards`: that reads the whole board queue and would run rows this session never touched. Pass `--sanitize-prompt` explicitly because this command authored the tsv, not the operator, and operator authorship is the trust boundary that flag exists to replace.
- **A row without a goal pointer is never drained.** `wrap stage` writes prose (Intent, Approach, Tags, Home) and `queue run` needs a pointer path. A row this pass staged through the lane route above carries the draft it wrote at `.claude/goals/<slug>.md`, which is that pointer. A row from the knob-false path or an earlier session carries none: report each in `FYI` with the reason and the step that closes it, `/kit:assign`, which turns a board row into a goal draft. Do not invent a pointer to make a row runnable.
- **Report what was dispatched, not what will happen.** The queue is asynchronous and its journal is the record. Name the tsv, the row count, and the journal path in `FYI`; never claim an outcome the queue has not written yet.

c. Incidents. For every `docs/incidents/*.md` written this session whose `## Root cause` names our own mistake, `bin/wrap knowledge-root <repo>` gives the directory. A note already there naming the incident id in its first heading: `skipped: note exists`. Otherwise write one note, how to work here and what to do differently, plus its `MEMORY.md` index line, in that directory. An empty `## Root cause` writes nothing. A `knowledge-root:` fallback line on stderr becomes an FYI bullet, not a skip. No incidents: `skipped: no incidents`.

For each note this sub-step actually wrote, run `bash lib/gate/quiz-gate.sh teacher` (same resolver as `a`, one read per note is fine, it never changes mid-run). Empty: print `skipped: no teacher` plus the note's path and stop. Named: invoke that skill through the Skill tool, handing it the note's path and the incident file it was written from. As in `a`, this sub-step never names which skill runs; it only decides whether one does.

### Step 8: reflect

Resolve the kit log dir (`bash -c 'source lib/telemetry/kit-log-dir.sh; kit_resolve_log_dir'` prints it) and grep the run ledgers under it for a `| GATE | ship | ran | shipping pr=#<n>` line naming any PR number merged in step 3. Anchor the number so `#7` never matches `#71`: `grep -rE "shipping pr=#<n>([^0-9]|$)" "<log dir>"`. Any hit means run `/kit:retro` now, before the report. No hit means no spec cycle shipped this session; skip retro and say so in the report's FYI line.

### Step 8b: the after seam

Invoke the skill named by `wrap.after`, read back in step -1, through the Skill tool now. The landing is finished, so this skill reads what the session produced rather than racing it. Its report lines fold into step 9 after the `FYI` line, and its outcome is what the `**Seam:**` line names. An empty key runs nothing and reports `NOTHING: no seam configured`.

### Step 9: report

Print the skim-first block below. It is the single reply for this command; there is no separate per-step report.

```
## Wrap: <session slug, 3 to 6 words>

✅ **Needs you:** NOTHING
   -- or --
🔴 **Needs you:**
a. DECIDE | RUN | REVIEW | UNBLOCK <what>. <why it sits with the operator>. <the one command or the decision>.
b. ...

**What happened**
- **<workstream>**: <the problem as the operator saw it>. <root cause in one clause>. <what changed>. <how it was proven>.

**Shipped**
- **<repo>**: #<pr> (<sha>) DEPLOYED <run or fleet line> | #<pr> 🟡 MERGED, NOT DEPLOYED | #<pr> OPEN

**Left alone:**
- <repo>: <files / worktrees / branches>, <whose>, PULL BLOCKED
   -- or --
- NOTHING

**Built:** <label> ENHANCE <home>: <file, insertion point> (lane=tiny, verified: <check>, <commit>)
   -- or -- NOTHING: no candidates
   -- or -- SKIPPED: <why the step did not run>
   -- or, for two or more candidates --
**Built:**
- <label> ENHANCE <home>: <file, insertion point> (lane=tiny, verified: <check>, <commit>)
- <label> NEW (precedent: nothing matched): <path> (lane=normal, staged + goal drafted: <path>)
- <label> NEW (precedent: nothing matched): <path> (lane=full, staged: build_candidates off)

**Seam:** <side> <skill name> ran: <its one-line outcome>
   -- or -- NOTHING: no seam configured
   -- or -- SKIPPED: <why>

**FYI:**
- <what changes for the operator from now on>
- <a state the operator will meet next time>
   -- or --
- NOTHING
```

- `Needs you` leads and is always present, even as `NOTHING`. It is a lettered action list; it sits at the top, ahead of every other section, because this report is read from the top and the items are the whole point.
- **Admission test, run it on every drafted item before the report prints.** An item earns a place in `Needs you` only when the operator is the ONLY one who can do it. Three classes qualify: it needs a human credential or presence (a root password, a GUI, 2FA, a physical device); it is irreversible and outward-facing (send the email, charge the card, terminate the host, delete in production); or it is a judgment whose options carry different irreversible outcomes. Everything else fails the test. For each failing item, RUN IT NOW, then move it to `What happened` in the past tense. Merging your own green PR, pulling the default branch, installing what you just merged, dispatching an established deploy, and rerunning a check all fail the test: they are work, and the report is written after the work, not instead of it.
- The failure mode this test exists to stop: a finished build parked behind "say go and I will merge it". That reads as diligence and costs the operator a round trip to type "ok". Landing the change is part of finishing it. When something genuinely blocks, `Needs you` names the blocker, never the permission.
- **Run the lint before printing.** Write the drafted report to a scratch file and check it: `bash lib/wrap/report-lint.sh <file>`. Exit 1 names a `Needs you` item that asks permission instead of stating a blocker; go do that item, move it to `What happened`, and re-run until the lint is clean. A `warn` line names an item built around a command the kit can run with no blocker stated: read it again, and either state the blocker or do the work. The lint judges phrasing, not reversibility, so it catches the one shape that is always wrong and leaves the judgment calls to the admission test above.
- Exactly two emoji, no others: `✅` or `🔴` leads `Needs you` (green only when it says `NOTHING`), and `🟡` marks a `MERGED, NOT DEPLOYED` PR, the one `Shipped` state that still needs a hand. Nothing on section headers, lettered items, or in prose.
- Status words stay UPPERCASE tokens, always the same ones: `NOTHING`, `DEPLOYED`, `MERGED, NOT DEPLOYED`, `OPEN`, `PULL BLOCKED`, and a leading verb on each `Needs you` item from `DECIDE`, `RUN`, `REVIEW`, `UNBLOCK`. Prose stays lowercase.
- `What happened` is one bullet per workstream, two to four sentences: the problem as the operator saw it, the root cause, what changed, how it was proven. A ten-minute session earns one bullet; a long one earns five or six.
- `Shipped` is one line per repo: PR number, merge SHA, deploy state.
- `Left alone` and `FYI` are bullet lists, one item per repo or fact, never joined with `|` or `;`.
- `Left alone` is derived from step 5's closing `bin/wrap scan`, never written from memory of what the steps intended. Every worktree, branch, and dirty file that scan still reports gets a bullet with its owner and the reason, one bullet per repo, so the operator knows a repo is not fully clean and why. A single `- NOTHING` bullet only when that final scan came back clean.
- `FYI` closes the message: one bullet per fact that changes what the operator will MEET next time but owes them nothing right now. Two kinds qualify, and only two. A STATE that shifted under them: a default that changed, a file that moved, a job that will fire. Or a FOLLOW-UP already captured in a durable home: a staged candidate, an unproven claim recorded in a proof file, a parked question. The second kind is future work, often the most interesting work in the report, and saying so is the point of the lane.
- **Every `FYI` bullet of the second kind NAMES ITS HOME**, the file or board where the follow-up already lives. That is this section's own admission test. A bullet carrying future work with no home is a task hiding in the read-only lane, which is how a good idea reaches the end of a session and dies there; give it a home first, then report the path. A bullet that needs a decision, a command, or a review FROM THE OPERATOR was misfiled and belongs in `Needs you` instead.
- The lane is read-and-move-on, never do-nothing-forever. The operator picks the follow-up back up from its home, not from a report they would have to remember. A single `- NOTHING` bullet when there is nothing to report.
- A staged candidate, a filed memory note, or a knowledge-root fallback from step 7 is an `FYI` bullet naming the file or the reason, in the existing `FYI` grammar.
- **`**Built:**` is REQUIRED, and the lint fails without it.** After `FYI`, reporting step 7b's outcome as exactly one of three states: named, `NOTHING: no candidates` when the scan ran and found none, or `SKIPPED: <why>` when the step did not run. NOTHING and SKIPPED stay on the header line always; they are whole-outcome states, never a bullet, and never mixed with bullets. A named outcome takes either shape: INLINE keeps one candidate on the `**Built:**` line itself, `<label> ENHANCE <home>: <file, insertion point>` or `<label> NEW (precedent: nothing matched): <path>`, each followed by its LANE and how it closed; LIST is a bare `**Built:**` header followed by one `- ` bullet per candidate in that same per-item grammar, for two or more candidates a single joined line cannot hold legibly. Every candidate, inline or in a bullet, owes the ENHANCE or NEW token: it is the slot that forces naming the existing tool the candidate joins, and it is checked per item, not per line, so one bare `path (commit)` buried among two good bullets still fails and the lint names which bullet. A `Built:` item with no ENHANCE or NEW is the session's own deliverable wearing 7b's label. Every item also carries the LANE it was sized at and how it closed, one of `(lane=tiny, verified: <the check that ran>, <commit>)` for one built here, `(lane=<lane>, staged + goal drafted: <path>)` for one routed on, or `(lane=<lane>, staged: build_candidates off)` when the knob stayed wrap's hand: a candidate built at session close is invisible everywhere else, so naming the lane says which discipline it passed and naming the check says the build was proven rather than asserted. `SKIPPED: nothing to build` collapses two states into one and still fails. A skipped 7b and an empty 7b used to look identical, which is how the step that builds instead of proposing got silently dropped from a whole session. This line is the trace every other step already leaves. The lint also WARNS (never fails), on any candidate whether inline or a bullet, when a `NEW (precedent: nothing matched)` item's path exists and its files speak CDP (`session.Runtime.evaluate` and siblings): that candidate already has a home in browser-harness-js's learnings, not a sibling script here. The lint REFUSES a `**Built:**` whose every item targets prose (a memory note, a research file, a handoff), because a precedent hit on a note is not a build; `PROSE-ONLY: <reason>` as its own bullet, or appended to the inline item, is how a session says no mechanism was possible and why.
- **`**Seam:**` is REQUIRED, and the lint fails without it.** One line, after `**Built:**`, reporting step -1's seams as exactly one of three: which side ran which skill and its outcome, `NOTHING: no seam configured` when neither key was set, or `SKIPPED: <why>` when a named skill did not run. It carries the same three-state rule as `**Built:**` and for the same reason: a seam that was never configured and a seam that was silently dropped read identically without it, and the seam is where an operator's whole distill half lives.
- An overlay (a consumer's own routing, distill, or knowledge-capture step) appends its own labelled sections after `FYI`, in the same shape: a bold label line followed by bullets, one item per note, candidate, or queue entry; the kit's grammar stops there. A `wrap.before` skill's report lines fold in at that same place.
- No table unless the session touched four or more repos. No restating what each step did.

Record the run (SPEC-139), one line: `bash lib/gate/gate-ledger.sh record <rid> wrap ran "<summary>"`. Close the timing bracket (SPEC-129): `bash lib/gate/gate-ledger.sh outcome <rid> wrap end caught=<true if a repo hit step 0's foreign-activity STOP, else false>`.

## What this command does NOT do

- Never force-pushes.
- Never rewrites history.
- Never merges a PR it did not open.
- Never touches a dirty file.
- Never removes a dirty or foreign worktree.
- Never dispatches a deploy on its own initiative; it checks one the operator already dispatched or asked it to dispatch as part of this pass.
