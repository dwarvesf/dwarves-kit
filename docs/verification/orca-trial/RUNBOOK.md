# Orca trial runbook (lead only)

The build ships all code and stub tests. The live steps below create real Runs, Tasks and worker terminals in the operator's Orca, visible on the phone. Only `orca orchestration reset` clears them globally, so the lead runs these by hand. Nothing here was run by the builder; treat every command as unrun until the capture proves it.

Spec: `docs/specs/SPEC-370-orca-mega-backend.md`, `## Trial plan`. Fixture: `docs/verification/orca-trial/fixture/`.

## Before step 0

| Check | How |
|---|---|
| Orca version | `orca --version` prints 1.4.209 or later |
| Permission mode pinned | In Orca, set the Claude agent launch to bypass-permissions, the same as Arm A's `CLAUDE_FLAGS=--dangerously-skip-permissions`. Write both settings into the trial record. A run where they differ is void. |
| Suite green | `bash tests/test-orchestrate-orca.sh` ends `Results: N passed, 0 failed` |

## Step 0: live capture on a throwaway copy (SG-01 only)

Build a scratch repo with a local bare origin (no GitHub) and a one-sub-goal copy of the fixture.

```bash
KIT=/Users/tieubao/workspace/dwarvesf/dwarves-kit          # or the worktree holding this branch
SCR=$(mktemp -d)                                            # keep the path, the capture reads it
git init -q --bare -b master "$SCR/origin.git"
git clone -q "$SCR/origin.git" "$SCR/repo"
mkdir -p "$SCR/repo/bin" "$SCR/repo/tests" "$SCR/repo/mega"
cp -R "$KIT/docs/verification/orca-trial/fixture/." "$SCR/repo/mega/"
printf '# wordcount scratch\n' > "$SCR/repo/README.md"
# keep only SG-01 in the capture copy
grep -v -E '^- \[ \] SG-0[23]' "$SCR/repo/mega/ROADMAP.md" > "$SCR/roadmap.tmp" && cat "$SCR/roadmap.tmp" > "$SCR/repo/mega/ROADMAP.md"
git -C "$SCR/repo" add -A && git -C "$SCR/repo" commit -qm init && git -C "$SCR/repo" push -q origin HEAD:master
```

Start Arm B on the copy, in the background, and note the Run id.

```bash
ORCA_POLL_SECS=15 bash "$KIT/lib/queue/orchestrate.sh" run "$SCR/repo/mega" --backend orca > "$SCR/run.log" 2>&1 &
sleep 20; RUN=$(cat "$SCR/repo/mega/.orchestrate/orca/run"); echo "$RUN"
bash "$KIT/lib/queue/orchestrate.sh" status "$SCR/repo/mega"
```

Capture one row per verb into the trial record (`docs/verification/orca-trial/<date>-trial.md`, section `## Capture`). Each block goes under a `### capture: <verb>` heading as a fenced `json` block, which is what AC14 parses.

```bash
TRIAL="$KIT/docs/verification/orca-trial/$(date +%F)-trial.md"
cap() { printf '\n### capture: %s\n\n```json\n%s\n```\n' "$1" "$2" >> "$TRIAL"; }
cap task-list   "$(orca orchestration task-list --run "$RUN" --json | jq '.tasks[0]')"
cap worker-list "$(orca orchestration worker-list --run "$RUN" --json | jq '.workers[0]')"
D=$(orca orchestration worker-list --run "$RUN" --json | jq -r '.workers[0] | (.dispatchId // .id)')
cap worker-show "$(orca orchestration worker-show --dispatch "$D" --json)"
cap check       "$(orca orchestration check --run "$RUN" --peek --json)"
```

`gate-list` needs a gate. Create one on the never-dispatched accept Task of a full-fixture copy, or on any pending Task of this Run, then record whether `task-list --ready` still lists that gated Task.

```bash
T=$(orca orchestration task-list --run "$RUN" --json | jq -r '.tasks[] | select(.status=="pending" or .status=="ready") | .id' | head -1)
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
| Stop then retry | `orca orchestration worker-stop --dispatch "$D" --json`, then `orca orchestration task-list --run "$RUN" --json \| jq '.tasks[0].status'`, then `orca orchestration worker-start --task <T> --retry-of "$D" --agent claude --worktree new-top-level --name feat/orca-trial-sg-01 --repo path:"$SCR/repo" --run "$RUN" --json` | whether Orca accepts the retry and the Task status after each step, as `### capture: stop-retry` |

Field names that differ from the stub (`tests/fixtures/orca-stub/orca`, assumptions listed in the implementation notes): fix the stub and `lib/queue/orca-backend.sh` together, commit with a subject containing `from live capture`, and re-run `bash tests/test-orchestrate-orca.sh` green before step 1.

Then roll the capture copy back:

```bash
bash "$KIT/lib/queue/orchestrate.sh" orca-reset "$SCR/repo/mega"
```

`orca-reset` stops and releases this Run's Dispatches and blocks its Tasks. It never calls the global reset. Blocked Tasks stay in Orca's database until a global `orca orchestration reset --tasks`, which only the operator runs, and only when no other Run is live.

## Steps 1 and 2: the two arms

Follow `## Trial plan` (Arms, Injected faults, Measures, Decision rule) in the spec. Two fresh copies of the fixture, `Model: sonnet` in each goal file, `WAVE_CAP` and the 60-second cadence the same in both, permission mode pinned as above. Arm B: `ORCA_POLL_SECS=60 bash "$KIT/lib/queue/orchestrate.sh" run <copyB> --backend orca`, and the conductor reads only `orchestrate.sh status <copyB>`. Seal the SG-02 answer (`-l`) in the trial record before the run. AC12 and AC14 close only after this record exists.
