# Proof of done: gate-path `| grep -q` under pipefail

Defect: the ship-gate impl-notes check failed a push of a branch whose notes file existed with entries. Root cause: `git show HEAD:<notes> | grep -v '^# ' | grep -q '[^[:space:]]'` under `set -o pipefail`. `grep -q` exits on its first match, the upstream `grep -v` takes SIGPIPE (141), and pipefail reports the pipeline failed even though the final grep matched.

## Repro (real file, deterministic)

| Step | Command | Result |
|---|---|---|
| Real notes file (23 KB) under pipefail, 8 runs | `git show HEAD:docs/implementation-notes/SPEC-254-alumni-claim-worker.md \| grep -v '^# ' \| grep -q '[^[:space:]]'` | exit 141 on all 8 runs |
| Same pipeline, pipefail off | same | exit 0 |

## Green run

| Step | Command | Result |
|---|---|---|
| Impl-notes + big-producer cases | `bash tests/test-ship-gate-impl-notes.sh` | PASS=19 FAIL=0 |
| Other ship-gate suites | `test-ship-gate-fail-closed`, `-coverage-map`, `-profiles`, `test-ship-pr-body-verified` | rc=0 each |
| Hook and codex-pin suites | `test-hooks`, `test-codex-hooks` | rc=0 each |
| Proof suites | every `tests/test-proof-*.sh` | rc=0 each |
| Registry | `bash lib/registry/feature-registry.sh check docs/FEATURES.md` | fresh |

## Negative control

Restore `hooks/ship-gate.sh` from the commit before the fix (`git checkout HEAD~1 -- hooks/ship-gate.sh`), run `bash tests/test-ship-gate-impl-notes.sh`: PASS=16 FAIL=3. Cases 15 (large notes), 16 (override at the head of a large ledger) and 17 (large BACKLOG naming the slug) go red. Restore with `git checkout HEAD -- hooks/ship-gate.sh`: PASS=19 FAIL=0.

## Fix

Each affected `producer | grep -q` becomes `grep -q ... < <(producer)`. A process substitution is not part of the pipeline status, so the early exit is invisible. Sites: 12 in `hooks/ship-gate.sh`, 7 in `lib/gate/proof-ledger.sh` (the proof body and changed-file lists), 3 in `hooks/anti-rationalization.sh` (the response text). Not changed: sites whose producer is one short value (a slug, a timestamp, a task sentence), which cannot fill a pipe buffer.
