# Proof of done: SPEC-238 prepared gauntlet room

2026-09-01. Acceptance: the room image carries a pinned omp+bun toolchain
resolvable by the round's real user (`-u node`, `HOME=/tmp/probe-home`); the
cheap-probe recipe skips the per-round npm install when the image has it
baked and falls back unchanged when it does not.

## Task table

| Task | What | Verdict |
|---|---|---|
| TASK-001 | `tests/gauntlet/cleanroom/Dockerfile`: pinned `bun@1.4.0` + `@oh-my-pi/pi-coding-agent@18.0.11` via `npm install -g`, global bin on PATH for every user | PASS |
| TASK-002 | `docs/guides/gauntlet-tutorial.md` recipe: `command -v omp` guard (writes `omp-baked` signal) + fallback install; text-file-granular `omp-state` copy, `models.yml`/`config.yml` excluded, binaries deleted | PASS |
| TASK-003 | Live verification: image builds, all four binaries resolve as `-u node` | PASS (below) |
| TASK-004 | Persist-check leg E (binary canary) | OWED, not blocking (see Not covered) |

## Green run

Command: `docker build -f tests/gauntlet/cleanroom/Dockerfile -t kit-gauntlet-room tests/gauntlet/cleanroom`
Exit: 0
Output: `Step 3/6 : RUN npm install -g bun@1.4.0 @oh-my-pi/pi-coding-agent@18.0.11`,
`added 158 packages in 46s`, `Successfully built ... Successfully tagged kit-gauntlet-room:latest`.
Verdict: PASS

Command: `docker run --rm -u node -e HOME=/tmp/probe-home kit-gauntlet-room bash -lc 'command -v omp && command -v bun && command -v claude && omp --version'`
Exit: 0
Output:
```
/usr/local/bin/omp
/usr/local/bin/bun
/usr/local/bin/claude
omp/18.0.11
```
Verdict: PASS. This is the load-bearing check (validation W2): `npm install -g`
places binaries on the global bin, which is on PATH for every user, not just
root. A root-only install (or a non-global `npm install` under root's HOME)
would have left the round's real user, `-u node` with `HOME=/tmp/probe-home`,
unable to resolve `omp`/`bun`.

Command: `bash tests/gauntlet/cleanroom/persist-check.sh` (regression check:
confirms the Dockerfile change did not break the existing scrub/persist
pipeline; legs A-D predate this spec)
Exit: 0
Output: `PASS leg A` / `PASS leg B` / `PASS leg C` / `PASS leg D` / `PERSIST-CHECK: GREEN`
Verdict: PASS

Command: `bash tests/gauntlet/tier1.sh`
Exit: 0
Output: `TIER1: GREEN` (T1.1-T1.5, including `shellcheck -x tests/gauntlet/*.sh
tests/gauntlet/cleanroom/*.sh tests/gauntlet/deploy/gauntlet-campaign`)
Verdict: PASS

Command: `bash -n` on the extracted `docs/guides/gauntlet-tutorial.md` recipe block
Exit: 0
Verdict: PASS (TASK-002 acceptance; the block also names `models.yml` in its
exclusion comment, per acceptance)

## Contrast: pre-bake state (what this replaces)

Before this spec, every round paid a per-round `npm install --prefix
"$HOME/omptool" @oh-my-pi/pi-coding-agent bun` (~1 min, network-dependent).
2 of 3 environment failures on 2026-08-31 were install-path failures, one a
flaky `bun` npm postinstall (`ENOENT` renaming `@oven/bun-linux-aarch64` in
`/tmp`). Two rounds in one campaign could also run different probe-tool
versions since npm always resolved `latest`. The baked image removes both:
the install cost is paid once at `docker build` (layer-cached, free until the
Dockerfile changes), and versions are pinned in the Dockerfile, bumped only
deliberately.

## Not covered here

TASK-004 (persist-check leg E, a binary canary proving a NUL-bearing file
never survives the `omp-state` copy raw) is not implemented in this pass, per
explicit scope direction. `tests/gauntlet/cleanroom/persist-check.sh` still
has only legs A-D; the omp-state copy's own binary-file skip (TASK-002, the
`file --mime-encoding` check) is the mitigation in place today, unverified by
an automated leg. Owed: add leg E, write a NUL-padded file under
`$HOME/.omp` inside a probe round, assert it never reaches `RUN_OUT` intact
(deleted by the copy step or refused by the existing scrub).

A live NW round exercising the recipe's `omp-baked` signal + `omp-state`
persistence end-to-end (the SPEC's TASK-003 "live NW round" framing) was not
run. This proof instead uses the direct `-u node` binary-resolution command,
which is the load-bearing claim (validation W2) and does not require spend.
