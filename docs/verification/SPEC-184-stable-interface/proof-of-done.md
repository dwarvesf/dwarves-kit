# Proof of done: SPEC-184 stable consumer interface

Lane: full · rid: `harness-ops-05-interface` · Type: spec-feature (design-bearing)

## Acceptance criteria

| # | Criterion (from `Done =`, goal 05) | Met |
|---|---|---|
| A1 | A stable entrypoint exists; consumers drive the harness through it, not a deep `$DWARVES_KIT/lib/...` path | yes |
| A2 | The adopt contract's injected CLAUDE.md block references the stable name, never a deep lib path | yes |
| A3 | The board works through the stable form | yes |
| A4 | NEGATIVE CONTROL: an internal lib rename does NOT break the stable consumer call; a deep-path consumer DOES break on the same rename | yes |
| A5 | Design-bearing pick recorded (dispatcher vs per-subsystem shims) with rationale | yes (SPEC-184 `## Design`) |

## Implementation

- `bin/board`, `bin/classify`, `bin/gate`: thin forwarders resolving `SELF_DIR/../lib/<sub>/<entry>.sh` (stable path, location-independent).
- `lib/adopt.sh`: injected CLAUDE.md block repointed to `$KIT_ROOT/bin/classify lane classify` + `$KIT_ROOT/bin/gate ledger` (was `lib/classify/lane-classify.sh` + `lib/gate/gate-ledger.sh`). The WORKFLOW pointer block is UNCHANGED (already stable; left clean for the sub-goal-12 cross-track seam).
- `install.sh`: deploys `bin/` next to `lib/` (copy in bash install, symlink in plugin-compat), removes it on uninstall.
- Docs: README "Project structure", `docs/architecture.md`, WORKFLOW.md doc-impact map.

## Confirmation run-table

| Check | Command | Result |
|---|---|---|
| Stable-entrypoint call (A1/A3) | `bash tests/test-stable-interface.sh` → "consumer drives the board through bin/board (stable)" | PASS |
| Adopt block repoint (A2) | same run → "adopt block no longer reaches any deep lib path" | PASS |
| NC, stable survives rename (A4) | same run → "NC: stable bin/board consumer STILL resolves after internal rename" | PASS |
| NC, deep path breaks (A4, control bites) | same run → "NC: deep-path consumer BREAKS on the rename" | PASS |
| Full suite regression | `bash tests/test-meta.sh` | 679/679 PASS |
| Adopt suite | `bash tests/test-adopt.sh` | 12/12 PASS |
| Install-compat (bin symlink) | `bash tests/test-install-compat.sh` | PASS |

## Run detail (verbatim)

```
$ bash tests/test-stable-interface.sh
ok   bin/board is executable
ok   bin/classify is executable
ok   bin/gate is executable
ok   bin/classify forwards to lane-classify (full)
ok   bin/gate forwards to gate-ledger (rid)
ok   consumer drives the board through bin/board (stable)
ok   adopt block references bin/classify (not lib/classify/*)
ok   adopt block references bin/gate (not lib/gate/*)
ok   adopt block no longer reaches any deep lib path
ok   NC baseline: stable consumer call GREEN before rename
ok   NC baseline: deep-path consumer GREEN before rename
ok   NC: stable bin/board consumer STILL resolves after internal rename
ok   NC: deep-path consumer BREAKS on the rename (proves the reach is the fragile part)
PASS: stable consumer interface
```

The negative control is the load-bearing evidence: in ONE test run, after renaming the
internal `lib/board/board.sh` (and updating only the one kit-owned `bin/board` line), the
consumer that points at the stable `bin/board` STILL resolves, while the consumer that
points at the deep `lib/board/board.sh` BREAKS. That is exactly the board-shim class of
bug (a consumer coupled to an internal lib path), now impossible for a `bin/`-referencing
consumer.

## Reproduce

```
cd <dwarves-kit>
bash tests/test-stable-interface.sh    # incl. the internal-rename negative control
bash tests/test-adopt.sh               # adopt block still renders + resolves
bash tests/test-meta.sh                # structural regression
```
