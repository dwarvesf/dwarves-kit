# Proof of done, kit-foldin SG-01: lib/ subsystem regroup

**Task:** regroup `lib/`'s flat files into subsystem subdirs
(`board/ queue/ gate/ classify/ spec/ goal/ telemetry/ session/`) with a
resolution strategy that keeps every cross-subsystem sibling call working.
**Class:** behavioral · **Lane:** normal · **rid/slug:** `kit-foldin-01-lib-regroup`
**Branch:** `refactor/kit-foldin-01-lib-regroup`

## Resolution strategy chosen: (b) per-subsystem shims

The kit's `lib/` scripts resolve siblings from their own `BASH_SOURCE` dir
(`$DIR/<callee>.sh`), so a moved caller looks for its callee in its NEW subsystem
dir, a shim at the old flat root is never consulted (the false-green). Chosen
**(b)** over (a) because it keeps **zero call-site edits** (the goal's quality
bar: "if any call-site needs editing, the shim is wrong"). Two symlink classes:

- **33 root compat shims** `lib/<name>.sh -> <subsystem>/<name>.sh`, external
  flat-path callers (tests, hooks, commands, install.sh) + any root-entry chain.
- **21 cross-subsystem shims** `lib/<caller>/<callee>.sh -> ../<callee-subsys>/<callee>.sh`, the transitive closure of each subsystem's cross-subsystem calls, so a script
  invoked at its real subsystem path resolves siblings (e.g. `queue/gate-ledger.sh`
  + `queue/kit-log-dir.sh`, since `gate-ledger.sh` sources `kit-log-dir.sh`).

Orphans (`adopt.sh explain.sh pitch.sh precedent.sh`) stay at `lib/` root, no
`misc/` bucket. `handoff-gen` + `handoff/` moved together into `goal/`.
`lib/session/` created empty (`.gitkeep`) for SG-03.

## Confirmation run-table (green run)

| Check | Command | Exit | Verdict |
|---|---|---|---|
| Baseline suite (pre-move) | `for t in $(ci-list); do bash "$t"; done` | 0 | PASS=40 FAIL=0 |
| Suite after move | `for t in $(ci-list); do bash "$t"; done` | 0 | PASS=40 FAIL=0 |
| Suite after README+proof | `for t in $(ci-list); do bash "$t"; done` | 0 | PASS=40 FAIL=0 |
| NC1 orchestrate.sh@queue | `source lib/queue/orchestrate.sh; _emit_start` | 0 | PASS |
| NC2 mega-merge.sh@goal | `bash lib/goal/mega-merge.sh` | 64 | PASS (source resolved, no FATAL) |

`ci-list` = `grep -oE 'tests/test-[a-z0-9-]+\.(sh|bats)' .github/workflows/test.yml | sort -u` (the authoritative CI suite, 40 tests).

```
Command: bash <each CI test> (baseline, pre-move)
Exit: 0
Verdict: PASS  (PASS=40 FAIL=0)

Command: bash <each CI test> (after move + README + proof)
Exit: 0
Verdict: PASS  (PASS=40 FAIL=0, identical to baseline)
```

## LOAD-BEARING negative controls (the point of this sub-goal)

The suite alone is a false-green: tests invoke lib scripts by the OLD flat path
(`$DIR`=root), so root shims mask the real failure mode. The real test drives the
engines from their REAL subsystem path so `$DIR` becomes the subsystem dir.

### NC1, orchestrate.sh from lib/queue/
Sourced `lib/queue/orchestrate.sh` (`ORCH_DIR=.../lib/queue`) and called
`_emit_start`, firing `$ORCH_DIR/lane-classify.sh`, `$ORCH_DIR/task-type-classify.sh`,
and `$ORCH_DIR/gate-ledger.sh start` (gate-ledger then sources `$DIR/kit-log-dir.sh`).
```
Command: source lib/queue/orchestrate.sh; _emit_start "$mega" SG-01
--- ORCH_DIR = .../lib/queue
--- _emit_start rc=0
--- output: [orchestrate] [telemetry] SG-01 START recorded (rid=nc-probe lane=normal type=spec-feature).
Exit: 0
Verdict: PASS  (orchestrate@queue resolved lane-classify+task-type-classify+gate-ledger cross-subsystem)
```

### NC2, mega-merge.sh from lib/goal/
`bash lib/goal/mega-merge.sh` (`MM_DIR=.../lib/goal`) executes the top-level
`source "$MM_DIR/kit-log-dir.sh" || { echo FATAL...; exit 1; }` at load, then reaches usage.
```
Command: KIT_LOG_DIR=$(mktemp -d) bash lib/goal/mega-merge.sh
usage: mega-merge.sh {gate <rid> <lane>|merge <pr> <rid> <lane> ...}
Exit: 64
Verdict: PASS  (mega-merge@goal sourced kit-log-dir cross-subsystem; no FATAL)
```

### NEGATIVE CONTROL, resolver backstop (revert → RED → restore → GREEN)
Removed `lib/goal/kit-log-dir.sh` (the cross-subsystem shim mega-merge sources),
confirmed the dependent engine goes RED, restored, confirmed GREEN.
```
Command: mv lib/goal/kit-log-dir.sh /tmp/x; KIT_LOG_DIR=$(mktemp -d) bash lib/goal/mega-merge.sh
lib/goal/mega-merge.sh: line 53: .../lib/goal/kit-log-dir.sh: No such file or directory
FATAL: lib/telemetry/kit-log-dir.sh missing or unreadable
Exit: 1
Verdict: RED (expected - resolver broken)

Command: mv /tmp/x lib/goal/kit-log-dir.sh; KIT_LOG_DIR=$(mktemp -d) bash lib/goal/mega-merge.sh
Exit: 64
Verdict: PASS (restored - source resolved, no FATAL; shim symlink intact: lib/goal/kit-log-dir.sh -> ../telemetry/kit-log-dir.sh)
```
The dependent engine flips exactly with the shim's presence, the resolver is
load-bearing, not decorative. A plain `git mv` with only root shims would leave
NC1/NC2 broken (the moved caller's `$DIR/<callee>.sh` points into the empty new
subsystem dir), which is why strategy (b)'s per-subsystem shims are required.

**Overall Verdict: PASS**

## Reproduce

```bash
cd <kit-worktree>
ci(){ grep -oE 'tests/test-[a-z0-9-]+\.(sh|bats)' .github/workflows/test.yml | sort -u; }
p=0; f=0; for t in $(ci); do bash "$t" >/dev/null 2>&1 && p=$((p+1)) || f=$((f+1)); done; echo "PASS=$p FAIL=$f"

# NC1: orchestrate from subsystem path
d=$(mktemp -d); mkdir -p "$d/goals"; printf -- '- [ ] SG-01 x\n' > "$d/ROADMAP.md"
printf '**Branch:** refactor/probe\n' > "$d/goals/01-x.md"
( KIT_LOG_DIR=$(mktemp -d); source lib/queue/orchestrate.sh; _emit_start "$d" SG-01 )

# NC2 + NEGATIVE CONTROL: mega-merge from subsystem path
KIT_LOG_DIR=$(mktemp -d) bash lib/goal/mega-merge.sh                                     # rc 64, no FATAL
mv lib/goal/kit-log-dir.sh /tmp/x; KIT_LOG_DIR=$(mktemp -d) bash lib/goal/mega-merge.sh  # FATAL rc 1
mv /tmp/x lib/goal/kit-log-dir.sh; KIT_LOG_DIR=$(mktemp -d) bash lib/goal/mega-merge.sh  # rc 64
```
