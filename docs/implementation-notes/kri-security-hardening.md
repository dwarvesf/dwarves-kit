# Implementation notes: kri-security-hardening (SPEC-134)

Delta from the spec. References the spec for decisions; records only what the spec did not pin.

## 2026-07-04 Wrapper KIT_ROOT override (test seam)

Context: SPEC-134 §Design confines `proof-table-gen.py`'s output under
`realpath(KIT_ROOT/docs/runs)`, enforced EVEN for an explicit out-path. The existing
`tests/test-proof-table-gen.sh` passed explicit out-paths under `$WORK` (outside docs/runs),
which the new confinement rejects.
Decision: split `lib/proof-table-gen.sh` into `SCRIPT_ROOT` (where the script lives, used to
source libs + locate the .py, always the real repo) and `KIT_ROOT` (the LOGICAL root used for
output confinement + default out-path, defaults to `SCRIPT_ROOT` but honors a pre-set env
override). Tests set `KIT_ROOT` to a throwaway dir with a `docs/runs/`, so the confinement is
exercised against a real docs/runs without polluting the repo.
Why: the confinement is untestable otherwise (either pollute the real repo's docs/runs or can't
supply a confined explicit path). The split is a minimal, legitimate test seam; libs still load
from SCRIPT_ROOT so a fake KIT_ROOT can't break sourcing.
Alternatives: (a) new tests call the .py directly with custom env (kept for the security PoC test,
but the EXISTING regression test drives the wrapper, so the wrapper still needed the seam);
(b) leave existing tests writing to the real docs/runs (pollutes repo, rejected).
Impact: `lib/proof-table-gen.sh` gains a 1-line KIT_ROOT default-with-override; existing test
setup points KIT_ROOT at a temp dir and writes outputs under its docs/runs.

## 2026-07-04 rid normalizer implemented in Python, not shelled out

Context: §Design (a) says reuse the kit's `runid()` normalizer if practical, else match its
charset exactly in Python.
Decision: implement in Python (`_normalize_rid`), matching `runid()`'s two-step transform
exactly: replace `/` and space with `-`, then drop every char outside `[A-Za-z0-9._-]`.
Why: the `bash lib/gate-ledger.sh rid` CLI verb derives the rid from the git BRANCH and ignores
any argument (confirmed: `rid "../../victim/pwned"` returns the branch slug), so it cannot
normalize an arbitrary caller-supplied rid. Shelling out would not do the job; a charset-exact
Python port is the correct reuse.
Impact: one small pure function; unit-covered against the `../../` and absolute-path PoCs.
