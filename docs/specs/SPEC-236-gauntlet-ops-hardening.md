# Spec: Gauntlet ops hardening (failing-round evidence, path grammar, probe recipe, watch)
Generated: 2026-08-31
Status: VALIDATED
Lane: full
References: `tests/gauntlet/cleanroom/run.sh` (the runner whose fail path loses evidence; imitate its existing stage/persist structure); `docs/verification/gauntlet/2026-08-31-user-J1-nw/ROUNDS.md` + the session scratchpad probe launcher it records (the working omp/NW recipe to promote verbatim); `lib/queue/pane-tail.jq` (the existing formatter the watch surface reuses); `../2026-08-06-kit-user/` and `deploy/gauntlet-campaign` (the legacy path grammar being reconciled).

## Problem

Four operational gaps left open by SPEC-235's generalization, all hit live on 2026-08-31 (board rows ID-489, ID-491 kit-side, ID-492, ID-493):

1. **A failing round destroys its own evidence** (ID-492). `run.sh` runs `docker run` under `set -euo pipefail`; a non-zero probe exit terminates the script before the `RUN_OUT` persist block, and the EXIT trap wipes the stage. Rules 6/8 (honest halt, never trim a record) are violated by the runner itself. Three consecutive environment-failure rounds tonight left nothing behind until the probe script was hand-patched to exit 0. Secondary: the `node:22-slim` room lacks `tail`/`ps`, so a probe-cmd using them dies opaquely.
2. **Run-path grammar has zero conforming producers** (ID-489). SPEC-235 mandates `docs/verification/gauntlet/<date>-<preset>-<slug>/` for new runs; the onboarding instance docs prescribe `<date>-kit-user/` and the campaign runner writes `campaign-current`, both grandfathered. The grammar stays dead text until the instance conforms.
3. **The cheap-probe recipe lives in a session scratchpad** (ID-493). The omp + NeuralWatt probe worked end to end (two run records prove it) but the recipe, including two hard-won rules (heredoc-from-variable does NOT reprocess escapes; omp blocks on non-TTY stdin without `</dev/null`), exists nowhere durable.
4. **A live round has no status surface** (ID-491 kit-side). Tonight's rounds were watched via ad-hoc session monitors. The kit already ships `lib/queue/pane-tail.jq`; nothing points it at a gauntlet room.

## Solution

### Approaches considered

1. **Surgical per-gap fixes inside the existing files** (chosen). `rc` capture + unconditional persist in run.sh; dated dirs + a compat symlink in the campaign runner; a tutorial recipe section; a small `watch.sh` beside the runner. Tradeoff: four small diffs, no new abstractions.
2. **A first-class probe-harness slot in run.sh** (for gap 3): a `PROBE_HARNESS=claude|omp` switch materializing the right probe-cmd. Rejected: two harnesses do not earn a plugin system (YAGNI); the recipe block teaches the same thing at zero code cost, and PROBE_CMD already IS the extension point.
3. **Hard-wire bg-run (ops-toolkit) as the kit's run launcher** (for gap 4). Rejected: the kit is a shared dwarvesf product; a dependency on a personal-monorepo tool inverts ownership. bg-run stays an operator convention (one tutorial line); the kit-native watch surface reuses what the kit already ships.

### Chosen approach + why

Approach 1. Every gap closes inside files that already own the behavior; the only new file is `watch.sh`, which composes two existing pieces (stage-dir discovery + pane-tail.jq).

### Extensibility & boundaries

- Load-bearing dimension: number of probe harnesses. The tutorial recipe section is where the next harness's recipe lands (a second section, not a code change); run.sh's PROBE_CMD contract stays the single seam.
- Unit boundaries: run.sh owns room lifecycle + persist; gauntlet-campaign owns run-dir naming for campaign runs; watch.sh is read-only over the stage dir and never mutates a round.

### Architecture

See `## Design`.

## Picture

```
 run.sh (round lifecycle)                     gauntlet-campaign (unattended)
 ┌─────────────────────────────┐              ┌──────────────────────────────┐
 │ stage → build → docker run  │              │ writes <date>-onboarding-<J>/│
 │   rc captured (survives     │              │ + campaign-current symlink   │
 │   set -e)  ──────────────┐  │              │   (plist consumer unchanged) │
 │ persist RUN_OUT ALWAYS ◀─┘  │              └──────────────────────────────┘
 │ teardown (trap)             │
 └──────────┬──────────────────┘              docs/guides/gauntlet-tutorial.md
            │ stage dir                       ┌──────────────────────────────┐
            ▼                                 │ + "Cheap probe: omp/NW       │
 watch.sh (read-only) ── tail -f transcript   │   recipe" section (PROBE_CMD │
   │ pane-tail.jq render + docker ps line     │   block + 2 quoting rules +  │
   ▼                                          │   bg-run as optional launcher│
 operator terminal                            └──────────────────────────────┘
```

## Design

**Ordering:** run.sh persist semantics first (other tasks read rounds it persists), campaign naming second, docs last.

### Approaches considered + chosen

Per `## Solution`; the one design-bearing decision is persist-on-every-path.

### Diagram

```
 docker run …/.probe-cmd.sh          # no longer the script-killing line
   │ rc=0 ──────────────┐
   │ rc≠0 ── || rc=$? ──┤           # set -e survives; rc recorded
   ▼                    ▼
 [ -n "$RUN_OUT" ] → cp -R stage → RUN_OUT   # UNCONDITIONAL, pass or fail
   ▼
 exit "$rc"                          # honest exit code preserved for callers
```

### ADR link(s)

None: reversible mechanics; the design record is this spec + SPEC-235.

### Boundaries & failure modes

Touches only `tests/gauntlet/` scripts and guide docs. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- `run.sh`: same CLI (`run.sh <persona> [ROW]`, env `PROBE_CMD`, `RUN_OUT`, `ANTHROPIC_API_KEY`, `GAUNTLET_STAGE_DIR`). NEW invariant: when `RUN_OUT` is set, the room's `/work` contents are persisted for EVERY docker exit code (`cp` failures reported with `|| echo`, never fatal), and run.sh's own exit code equals the probe's. The exit code is real only if the probe command propagates it: `run-remote.sh`'s `PROBE_DEFAULT` (and the tutorial recipe) currently END with `echo probe-exit=$?`, making every probe script exit 0; both become `rc=$?; echo probe-exit=$rc; exit $rc`.
- `run-remote.sh` (validation round, criticals 1-2): the LOCAL leg execs run.sh (fine); the REMOTE leg runs `ssh ... bash -s` under `set -e` and dies BEFORE the rsync pull when run.sh honestly exits non-zero, stranding the record on the runner host. Fix in the same task: capture the ssh exit (`|| rc=$?`), always pull, exit `$rc`. `gauntlet-campaign`'s bare invocation under `set -e` gets the same capture.
- `gauntlet-campaign` (reworked after validation critical 3: the runner uses `campaign-current/<row>` dir-existence as its per-row done-markers, so any repoint-per-row scheme restarts the matrix). New shape: ONE dated container per campaign PASS, `docs/verification/gauntlet/<date>-onboarding-campaign/`, chosen at pass start; row dirs live inside it, preserving the worklist semantics within a pass; `campaign-current` is a convenience symlink to the active pass container, repointed ONLY when a new pass starts (previous pass complete, or operator reset). A legacy real `campaign-current` directory is preserved by moving it to its start-date name before the symlink is created. The plist references only `KIT_ROOT` + the launcher (validated: no path consumer exists), so no plist change and no compat constraint; the symlink is operator convenience, not compatibility (DEC-004 revised).
- `watch.sh [--latest|--last]`: read-only; finds the newest `room.*` under `GAUNTLET_STAGE_DIR` (required, with a teach-line: the mktemp default is undiscoverable, and remote-leg rounds stage on the runner host, so watch is LOCAL rounds only), prints the `docker ps` line, then follows `transcript.jsonl`. Format-aware (validation critical 5: `pane-tail.jq` keys on claude stream-json `.type==assistant/user` and renders an omp v3 transcript as blank): sniff the first line; claude-format pipes through `lib/queue/pane-tail.jq`, omp v3 pipes through a small inline jq filter (message text + tool events from `message_end`/`tool_execution_*`), unknown format falls back to plain `tail`. `--last` renders the newest FINISHED room without following (testability + the no-live-room case).
- Tutorial: a new `## Cheap probe: omp + an OpenAI-compatible endpoint` section carrying the PROBE_CMD block verbatim from the proven run, the two quoting rules, the `</dev/null` rule, the key-slot convention, and one line naming `bg-run` (ops-toolkit) as an optional launcher convention.
- Invariants: engine rules 1-10 untouched; QL-VERDICT grammar untouched; `kit.toml` keys untouched.

### Data model changes
None.
### API changes
None beyond the interfaces above.
### UI changes
None.
### Infrastructure changes
`Dockerfile` gains a one-line comment naming the missing-basics constraint (`tail`/`ps` absent in slim; probe-cmds must use `cat`/shell builtins), a comment, not a package install, so the image stays minimal and rule 7's small surface holds.

## Task Breakdown

### Phase 1: runner correctness
- [ ] TASK-001 (`tests/gauntlet/cleanroom/run.sh`, `tests/gauntlet/cleanroom/run-remote.sh`, `tests/gauntlet/cleanroom/Dockerfile`, new `tests/gauntlet/cleanroom/persist-check.sh`): rc capture (`|| rc=$?`) + unconditional `RUN_OUT` persist (`|| echo`-guarded cp) + `exit $rc` in run.sh; `PROBE_DEFAULT` propagates the probe exit (`rc=$?; echo probe-exit=$rc; exit $rc`); run-remote's remote leg captures the ssh exit, always pulls the record, exits `$rc`; Dockerfile slim-image comment. `persist-check.sh` is STANDALONE (not tier1: needs docker; prints `SKIP: docker unavailable` and exits 0 without it). Acceptance: with `RUN_OUT` set and `PROBE_CMD='exit 7'`, the room persists AND run.sh exits 7; with `exit 0` behavior unchanged; both legs proven by persist-check.sh.

### Phase 2: grammar reconcile
- [ ] TASK-002 (`tests/gauntlet/deploy/gauntlet-campaign`, `tests/gauntlet/README.md`, `commands/gauntlet.md`, `tests/gauntlet/tier1.sh`): campaign pass-container naming per Interfaces (dated container at pass start, row dirs inside, `campaign-current` symlink repointed only at new-pass start, legacy real dir preserved under its start-date name); campaign invocation gets the `|| rc=$?` capture so a failing row still reaches the runner's own logging; README's path prescriptions updated; the command's grandfather clause narrows to "pre-2026-09 records"; tier1's shellcheck line extends to cover `cleanroom/*.sh` and `deploy/gauntlet-campaign`. Acceptance: `! grep -qE '<date>-kit-user/|^.*docs/verification/gauntlet/[0-9-]+-kit-user' tests/gauntlet/README.md` as a prescriptive path (historical mentions in prose citing past records stay allowed, checked by eye); worklist resume semantics unchanged within a pass (row done-markers still resolve through the container path).

### Phase 3: docs + watch
- [ ] TASK-003 (`docs/guides/gauntlet-tutorial.md`): the cheap-probe recipe section per Interfaces, with the PROBE_CMD block updated to propagate the probe exit (`rc=$?; echo probe-exit=$rc; exit $rc`). Acceptance: section contains the PROBE_CMD block, both quoting rules, `</dev/null`, the key-slot convention, and the bg-run line; `bash -n` on the extracted block passes.
- [ ] TASK-004 (`tests/gauntlet/cleanroom/watch.sh`, tutorial mention): the format-aware read-only watch per Interfaces. Acceptance: `shellcheck -S warning` clean; `--last` renders BOTH a claude-format sample AND the real omp transcript at `docs/verification/gauntlet/2026-08-31-user-J1-nw/round-1/room/transcript.jsonl` to non-empty output; refuses with a teach-line when `GAUNTLET_STAGE_DIR` unset; states local-rounds-only.

## After state

- [ ] A failing probe round leaves its full room in `RUN_OUT`. (Today: `set -e` wipes it.) Checkable: the TASK-001 check script.
- [ ] Campaign + instance docs produce `<date>-onboarding-<slug>` dirs; `campaign-current` is a symlink. (Today: `<date>-kit-user/` prose + literal `campaign-current` dir.)
- [ ] The omp/NW probe recipe is reproducible from the tutorial alone. (Today: session scratchpad only.)
- [ ] `watch.sh` gives a live formatted view of any running round. (Today: ad-hoc monitors.)

## Acceptance Criteria (global)

- [ ] All task ACs pass; `bash tests/test-meta.sh` failure set stays an exact subset of master's
- [ ] `shellcheck -S warning` clean on both touched/new scripts
- [ ] Zero changes outside `tests/gauntlet/`, `commands/gauntlet.md` (grandfather sentence), `docs/guides/gauntlet-tutorial.md`

## Verification

```
cd <worktree>
bash tests/gauntlet/cleanroom/persist-check.sh     # standalone; rc=7 persists + exit preserved; SKIPs cleanly without docker
shellcheck -S warning tests/gauntlet/cleanroom/run.sh tests/gauntlet/cleanroom/run-remote.sh tests/gauntlet/cleanroom/watch.sh tests/gauntlet/deploy/gauntlet-campaign
bash tests/gauntlet/cleanroom/watch.sh --last      # against the real omp record: non-empty (GAUNTLET_STAGE_DIR pointed at a fixture)
bash tests/test-meta.sh                            # subset-of-master failures
grep -q "heredoc" docs/guides/gauntlet-tutorial.md && echo quoting-rule-present
```

## Edge Cases

1. `RUN_OUT` unset + failing probe: no persist target exists; run.sh still exits with the probe's code and the trap wipes the stage (unchanged, correct: interactive/debug use).
2. Persist itself fails (disk full, bad path): report the cp error and still exit with the PROBE's code, not the cp's (the round's outcome is the probe's outcome).
3. `campaign-current` exists as a real directory from the legacy grammar: preserved by moving it to its start-date container name; the symlink then points at it, so its row done-markers survive and the in-flight pass resumes, never restarts.
4. watch.sh with no live room: `--last` prints the newest finished room's rendered tail instead of blocking.
5. Two rooms live simultaneously (parallel rounds): `--latest` picks newest mtime and SAYS which it picked.
6. Persist of a FAILED round copies probe-stderr/install logs into `docs/verification/`: rule 8's scrub-before-commit applies to failed rounds exactly as to passes; the run-record `.gitignore` still excludes fixture/kit trees, and the operator scrubs logs before any commit (one sentence added to the run-record contract by TASK-002's grandfather edit).

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Persist change breaks the green path | persist-check.sh runs both rc=0 and rc=7 legs | revert is one hunk |
| Campaign symlink breaks the launchd consumer | TASK-002 AC greps the plist + runner for the resolved path | `campaign-current` name preserved as symlink |
| Recipe block drifts from working reality | it is copied verbatim from a proven run record and `bash -n`-checked | rerun the recorded run |

## Out of Scope

- Installing packages into the slim image (comment only).
- A probe-harness plugin system (PROBE_CMD stays the seam).
- bg-run as a kit dependency (optional convention, one tutorial line).
- vps-mon heartbeats (ops-toolkit bg-run Phase 2).

## Decision Log

- DEC-001: persist-on-every-path with the probe's exit code preserved; rationale: rules 6/8 apply to the runner itself, tonight's three evidence-less failures are the red arm.
- DEC-002: kit-native watch over pane-tail.jq; bg-run stays an operator convention. Rationale: ownership boundary, the kit cannot depend on a personal monorepo.
- DEC-003: recipe block over harness slot. Rationale: two harnesses do not earn a plugin system; PROBE_CMD is already the seam.
- DEC-004 (revised, validation round): `campaign-current` is a convenience symlink to the active pass container, repointed only at new-pass start. Original compat rationale was FALSE (the plist references no path; the only consumer is the campaign runner itself); the symlink survives purely as a stable human/agent entry point, and the pass-container shape exists to preserve the runner's dir-existence worklist semantics (validation critical 3).
- DEC-005 (validation round): panel found 5 criticals + 6 warnings, all folded: probe-exit propagation through PROBE_DEFAULT + the recipe (the old `echo probe-exit=$?` tail made every probe exit 0); run-remote's remote leg strands records (capture + always-pull); pass-container naming instead of per-row dirs; format-aware watch (pane-tail.jq is claude-format-only; omp gets an inline filter, verified against the real -nw transcript); `! grep -q` ACs; persist-check standalone with docker SKIP; tier1 shellcheck glob extension; explicit `|| echo` on persist cp; failed-round scrub sentence; watch local-rounds-only.

## Open questions

(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
