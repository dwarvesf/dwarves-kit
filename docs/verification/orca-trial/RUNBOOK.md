# Orca trial runbook (lead only)

WARNING, read first: the trial needs Orca's Claude agent launch in bypass-permissions mode, and that is a PERSISTENT Orca setting that also governs every other repo opened in Orca, client repos included. `worker-start` has no per-worker permission option, and Orca has no CLI verb to read or change the mode (checked with `orca agent-context` and `worker-start --help`), so a shell trap cannot restore it. Record the prior value, set bypass, and restore the prior value in Orca's settings the moment the last arm ends (item in the cleanup checklist). While bypass is set, open no client repo in Orca. Never leave the setting changed.

The build ships all code and stub tests. The live steps below create real Runs, Tasks and worker terminals in the operator's Orca, visible on the phone. Only `orca orchestration reset` clears them globally, so the lead runs these by hand. Nothing here was run by the builder; treat every command as unrun until the capture proves it.

Spec: `docs/specs/SPEC-370-orca-mega-backend.md`, `## Trial plan`. Fixture: `docs/verification/orca-trial/fixture/`.

## Before step 0

| Check | How |
|---|---|
| Orca version | `orca --version` prints 1.4.209 or later |
| Permission mode pinned | Note the current Claude launch mode in Orca settings (write it in the trial record as `prior mode`). Set it to bypass-permissions, the same as Arm A's `CLAUDE_FLAGS=--dangerously-skip-permissions`. Write both settings into the trial record. A run where they differ is void. |
| Attestation exported | `export ORCA_PERMISSION_MODE=bypass` once the Orca setting is pinned; the backend refuses to run without it. It is an attestation, not a probe |
| Suite green | `bash tests/test-orchestrate-orca.sh` ends `Results: N passed, 0 failed` |

## Step 0: live capture on a throwaway copy

Build a scratch repo with a local bare origin (no GitHub) and a copy of the full fixture. The copy keeps all three sub-goals so `SG-03` and its never-dispatched `SG-03:accept` Task exist for the gate capture. Only SG-01 is meant to run: the runner is killed before SG-02 starts, and `orca-reset` cleans up whatever did start.

```bash
KIT=/Users/tieubao/workspace/dwarvesf/dwarves-kit          # or the worktree holding this branch
SCR=$(mktemp -d)                                            # keep the path, the capture reads it
git init -q --bare -b master "$SCR/origin.git"
git clone -q "$SCR/origin.git" "$SCR/repo"
mkdir -p "$SCR/repo/bin" "$SCR/repo/tests" "$SCR/repo/mega"
cp -R "$KIT/docs/verification/orca-trial/fixture/." "$SCR/repo/mega/"
printf '# wordcount scratch\n' > "$SCR/repo/README.md"
git -C "$SCR/repo" add -A && git -C "$SCR/repo" commit -qm init && git -C "$SCR/repo" push -q origin HEAD:master
# the path: selector needs the repo registered in Orca first
orca repo add --path "$SCR/repo" --json
```

Start Arm B on the copy in the background. Keep the runner pid: it must be killed before the stop-retry parks it forever and before `orca-reset` (which exits 75 while a runner lives).

```bash
export ORCA_PERMISSION_MODE=bypass
ORCA_POLL_SECS=15 bash "$KIT/lib/queue/orchestrate.sh" run "$SCR/repo/mega" --backend orca > "$SCR/run.log" 2>&1 &
RUNNER=$!
sleep 20; RUN=$(cat "$SCR/repo/mega/.orchestrate/orca/run"); echo "$RUN"
bash "$KIT/lib/queue/orchestrate.sh" status "$SCR/repo/mega"
```

Check 0, before anything relies on `worker-list --run` scoping (reset does): the list for this Run must hold only this Run's rows.

```bash
orca orchestration worker-list --run "$RUN" --json | jq '[.workers[] | (.runId // .run.id // "no-run-field")] | unique'
# expect exactly ["<this run id>"]. Foreign ids or "no-run-field": note it in the record. The backend scopes by its own
# map (map.tsv Task ids), so reset stays safe, but the finding decides whether assumption 1 below holds.
```

Capture one row per verb into the trial record (`docs/verification/orca-trial/<date>-trial.md`, section `## Capture`). Each block goes under a `### capture: <verb>` heading as a fenced `json` block, which is what AC14 parses. Every block must be non-null: the helper refuses null.

```bash
TRIAL="$KIT/docs/verification/orca-trial/$(date +%F)-trial.md"
cap() { [ -n "$2" ] && [ "$2" != null ] || { echo "capture $1 is empty: fix before continuing" >&2; return 1; }
        printf '\n### capture: %s\n\n```json\n%s\n```\n' "$1" "$2" >> "$TRIAL"; }
cap task-list   "$(orca orchestration task-list --run "$RUN" --json | jq '.tasks[0]')"
cap worker-list "$(orca orchestration worker-list --run "$RUN" --json | jq '.workers[0]')"
D=$(orca orchestration worker-list --run "$RUN" --json | jq -r '.workers[0] | (.dispatchId // .id)')
cap worker-show "$(orca orchestration worker-show --dispatch "$D" --json)"
cap check       "$(orca orchestration check --run "$RUN" --peek --json)"
```

`gate-list` needs a gate. Gate the never-dispatched accept Task, then record whether `task-list --ready` still lists a gated Task.

```bash
T=$(orca orchestration task-list --run "$RUN" --json | jq -r '.tasks[] | select(.title | endswith(":accept")) | .id' | head -1)
[ -n "$T" ] || { echo "no SG-03:accept Task in this Run" >&2; }
orca orchestration gate-create --task "$T" --question "capture only" --options '["accept","rework"]' --run "$RUN" --json
cap gate-list "$(orca orchestration gate-list --run "$RUN" --json | jq '.gates[0]')"
orca orchestration task-list --run "$RUN" --ready --json | jq --arg t "$T" 'any(.tasks[]; .id==$t)'   # gated Task still listed as ready?
```

Branch check: Orca must create exactly the fixture's `**Branch:**` line.

```bash
BR=$(git -C "$SCR/repo" branch -a --list '*orca-trial-sg-01*' | tr -d ' *'); echo "$BR"
printf '\nbranch created by Orca: %s\n' "$(printf '%s' "$BR" | sed 's#^remotes/origin/##')" >> "$TRIAL"
# a mismatch with feat/orca-trial-sg-01 stops the trial until the backend passes a name Orca keeps verbatim
```

Two design checks:

| Check | Command | Record |
|---|---|---|
| Task id on every `worker-list` row (the Dispatch to Task rejoin) | `orca orchestration worker-list --run "$RUN" --json \| jq '.workers[0] \| keys'` | the field name that holds the Task id. The backend reads `.taskId`. If rows carry no Task id, switch `_orca_sg_state` and `_orca_latest_disp` in `lib/queue/orca-backend.sh` to `dispatch-show --task T --json` per map Task before step 1. |
| Stop then retry | `orca orchestration worker-stop --dispatch "$D" --json`, then `orca orchestration task-list --run "$RUN" --json \| jq '.tasks[0].status'`, then `orca orchestration worker-start --task <T1> --retry-of "$D" --agent claude --worktree new-top-level --name feat/orca-trial-sg-01 --repo path:"$SCR/repo" --run "$RUN" --json` | whether Orca accepts the retry and the Task status after each step, as `### capture: stop-retry` |

Kill the runner now. After the stop it parks the sub-goal forever, and reset refuses while it lives.

```bash
kill "$RUNNER"; wait "$RUNNER" 2>/dev/null
```

### Stub assumption checks (all must be confirmed or fixed before step 1)

Every row is an assumption the stub and `lib/queue/orca-backend.sh` make. Run the command on the capture Run (`$RUN`, `$T` a map Task id, `$D` its Dispatch id), record the result under `### capture: assumptions` in the trial record, and fix the stub and backend together on any mismatch.

| # | Assumption | Command to confirm | Backend reads | If it differs |
|---|---|---|---|---|
| 1 | `worker-list --run` may return rows of other Runs; the backend must not rely on the filter (this is Check 0 above) | `orca orchestration worker-list --run "$RUN" --json \| jq '[.workers[] \| (.runId // .run.id)] \| unique'` | scopes every row by the Task ids in `map.tsv` (`orca-reset` and derive) | none needed if only `$RUN` shows; the scoping stays either way |
| 2 | Rows are newest first, so the first row per Task is its latest Dispatch | `orca orchestration worker-list --run "$RUN" --json \| jq '[.workers[] \| (.createdAt // .startedAt // .updatedAt)]'` after a stop-then-retry made two rows for one Task | first row per `taskId` | sort by the timestamp field in `_orca_latest_disp` and `_orca_sg_state` |
| 3 | Paging: a Run's rows fit one page | `orca orchestration worker-list --run "$RUN" --json \| jq '.page'` | reads one page only | follow `page.nextCursor` before a mega above the page size |
| 4 | Stopped and released rows persist in `worker-list` | after `worker-stop` then `worker-release`: `orca orchestration worker-list --run "$RUN" --json \| jq --arg d "$D" '[.workers[] \| select(.dispatchId==$d)] \| length'`, and again with `--terminal-state released` | the prior-Dispatch guard also reads `executing` events, so a dropped row cannot restart a Task; derive shows INDETERMINATE `no-dispatch-row` for it | none for the guard; note which filter shows released rows |
| 5 | A `--retry-request` key replays the first result | run `task-create --spec x --task-title x --run "$RUN" --retry-request probe-1 --json` twice; the two ids must match; then `orca orchestration request-show --help` for the lookup verb | `--retry-request` on `task-create`, `worker-start`, `gate-create` | if ids differ, the lost-response rule is unsafe: stop and report |
| 6 | Task status words | `orca orchestration task-list --run "$RUN" --json \| jq '[.tasks[].status] \| unique'` across a full life (create, dispatch, complete) | `pending ready dispatched completed failed blocked` | map new words in `_orca_sg_state` |
| 7 | Dispatch fields: status words, liveness words, `agentWait` location | `orca orchestration worker-show --dispatch "$D" --json \| jq 'keys, .projection, .observation'` and `worker-list` row keys | `dispatchStatus` (`stopped`), `projection.liveness` (`live`, `exited`, `unverifiable`), `observation.agentWait` on the list row | if `agentWait` only exists on `worker-show`, add a per-running-Dispatch `worker-show` read |
| 8 | Message fields and the `type` set | `orca orchestration inbox --run "$RUN" --json \| jq '[.messages[] \| keys] \| add \| unique'` and `jq '[.messages[].type] \| unique'` after a worker asks a question | `id type taskId dispatchId replyTo createdAt`; types `worker_done heartbeat question escalation` | rename in `_orca_msg_acted` and the derive query |
| 9 | `createdAt` type (seconds, milliseconds or ISO text) | `orca orchestration inbox --run "$RUN" --json \| jq '.messages[0].createdAt \| type'` | the status footer age handles all three | none if it renders a sane age |
| 10 | Delivery shape and whole-batch replay | `orca orchestration check --run "$RUN" --json \| jq '.delivery \| keys'` twice without `--ack`; the id must repeat | `.delivery.id`, `.delivery.messages[]` | adjust `_O_CK` reads in `orca_gate` |
| 11 | Gate row fields | `orca orchestration gate-list --run "$RUN" --json \| jq '.gates[0] \| keys'` before and after `gate-resolve` | `id taskId status (pending or resolved) resolution (accept or rework)` | adjust `_orca_gate_of` |
| 12 | Permission mode: the launched Claude worker really runs in bypass | attach to the SG-01 worker with `orca orchestration worker-read --dispatch "$D"` and confirm no permission prompt appears; `worker-start` has no permission option and Orca has no read verb, so the backend only checks `ORCA_PERMISSION_MODE=bypass` (an attestation, not a probe) | `ORCA_PERMISSION_MODE` at pre-flight | if a prompt appears, the attestation was wrong: fix Orca's setting, do not weaken the check |

Field names that differ from the stub (`tests/fixtures/orca-stub/orca`, assumptions listed in the implementation notes): fix the stub and `lib/queue/orca-backend.sh` together, commit with a subject containing `from live capture`, and re-run `bash tests/test-orchestrate-orca.sh` green before step 1.

## Cleanup after step 0 (roll the capture copy back)

The runner is already killed. Reset needs no live runner.

```bash
bash "$KIT/lib/queue/orchestrate.sh" orca-reset "$SCR/repo/mega"
# remove the worktree Orca created for the capture (Orca never deletes it on stop)
orca worktree rm --worktree branch:feat/orca-trial-sg-01 --force --json
```

`orca-reset` stops and releases this Run's Dispatches and blocks its Tasks. It never calls the global reset. Then delete the scratch dir `$SCR` yourself.

What still persists after cleanup, with no per-item CLI removal:

| Item | Where it lives | How it goes away |
|---|---|---|
| The Run and its blocked Tasks, the capture gate, messages | Orca's database | only the global `orca orchestration reset --tasks`, which the operator runs, and only when no other Run is live |
| The scratch repo registration | Orca's repo list (`orca repo list` shows it; there is no `repo rm`) | remove the project in Orca's UI |
| The branch `feat/orca-trial-sg-01` | the scratch repo | gone with `$SCR` |
| The persistent Claude launch mode (bypass) | Orca settings | restore the recorded `prior mode` by hand, and tick it off in the trial record |

Repeat the same cleanup after each measured arm (steps 1 and 2), for that arm's copy.

## Steps 1 and 2: the two arms

Follow `## Trial plan` (Arms, Injected faults, Measures, Decision rule) in the spec. Two fresh copies of the fixture, `Model: sonnet` in each goal file, `WAVE_CAP` and the 60-second cadence the same in both, permission mode pinned as above. Arm B: `ORCA_POLL_SECS=60 bash "$KIT/lib/queue/orchestrate.sh" run <copyB> --backend orca` with the runner pid saved, and the conductor reads only `orchestrate.sh status <copyB>`. Seal the SG-02 answer (`-l`) in the trial record before the run. AC12 and AC14 close only after this record exists. When both arms end, restore the Orca launch mode.
