# Spec: Security hardening for proof-table-gen path handling + ledger neutering

Generated: 2026-07-04
Status: VALIDATED
Lane: full (a security-remediation lane over PoC-confirmed findings: a HIGH arbitrary-file-write,
a MEDIUM code/comment invariant mismatch, a LOW symlink-follow. Correctness-critical, so full.)

## Problem

The security review of the merged kit-run-integrity run surfaced three grounded, PoC-confirmed
findings:

**HIGH , path traversal / arbitrary file write in `lib/proof-table-gen.py`.** The CLI's only
required arg, `rid`, is used UNSANITIZED to build both the read path
(`ledger_path = os.path.join(log_dir, "runs", f"{rid}.log")`) and the default write path
(`out_path = os.path.join(kit_root, "docs", "runs", f"{rid}.md")`). The only guard checks the
final BASENAME is not literally `proof-of-done.md`; it does NOT confine the resolved path to
`docs/runs/`. PoC (confirmed): `rid="/tmp/x/pwned"` writes `/tmp/x/pwned.md` (`os.path.join`
drops the prefix on an absolute component); `rid="../../victim/pwned"` resolves outside
`docs/runs/`. The file's own docstring claims "the default out-path is always under docs/runs/",
a provably false contract. Separately, the explicit-`out-path` branch bypasses even the basename
check.

**MEDIUM , comment/code mismatch in `mutation()` (`lib/gate-ledger.sh`).** The comment claims
values are sanitized so "a value can never smuggle a second KV" by neutering embedded `=`, but
the code only does `tr '\n\r' ' ' | tr ' ' '_'`; it never touches `=`. `debt()` already does
`tr '=' ':'` for exactly this reason. A `file=`/`reason=` value containing `=` therefore smuggles
a second `KEY=value` token into the emitted `| MUTATION |` line.

**LOW , symlink follow in `lib/mutation-smoke.sh`.** The mutation loop guards with `[ -f "$file" ]`
(which FOLLOWS symlinks) and then `cp`/rewrites the file, so a tracked symlink is written THROUGH.
Not exploitable today (candidate files come from the repo's own source list), but belt-and-suspenders.

## Solution

**HIGH , `lib/proof-table-gen.py`:**
1. Normalize `rid` before it touches ANY path, matching `lib/gate-ledger.sh`'s `runid()` charset
   exactly: replace `/` and space with `-`, then drop every char outside `[A-Za-z0-9._-]`. Apply to
   both `ledger_path` (read) and the default `out_path` (write). (The `gate-ledger.sh rid` CLI verb
   derives from the git branch and ignores an arbitrary arg, so it cannot normalize a caller string;
   a charset-exact Python port is the correct reuse , see the implementation note.)
2. Confine the FINAL resolved `out_path`: compute `runs_root = realpath(KIT_ROOT/docs/runs)` and
   require `realpath(out_path)` to be `runs_root` or under `runs_root + os.sep`. Enforce this EVEN
   when an explicit `out-path` arg is supplied. Reject with a non-zero exit + stderr if outside.
3. Keep the existing `proof-of-done.md` basename refusal (run it BEFORE the confinement check so the
   canonical-file case keeps its specific message).

**MEDIUM , `mutation()`:** add `tr '=' ':'` to the free-text value neutering pipeline, so every
value (at least `file=`/`reason=`) matches the comment's stated invariant.

**LOW , `lib/mutation-smoke.sh`:** add an explicit `[ -L "$file" ] && continue` so a symlinked
target is SKIPPED, not written through.

**Test seam (`lib/proof-table-gen.sh`):** split `SCRIPT_ROOT` (where the script lives; sources libs
+ locates the .py) from `KIT_ROOT` (the logical root for confinement + default out-path; defaults to
`SCRIPT_ROOT`, honors a pre-set env override). Lets tests exercise confinement against a throwaway
`docs/runs/` without polluting the repo.

**Not changed:** the ledger marker formats (read-only for the .py); the CLI surfaces
(`proof-table-gen.sh <rid> [out-path]`, `gate-ledger.sh mutation ...`); the mutation-smoke bite logic;
any acceptance/coverage-delta rendering.

## Design

The sanitization + confinement contract (the pinned invariant this spec is validated against):

- **Charset invariant.** `_normalize_rid(r)` is exactly `re.sub(r'[^A-Za-z0-9._-]', '', r.replace('/', '-').replace(' ', '-'))`.
  For all inputs the result contains only `[A-Za-z0-9._-]` , no `/`, no `..` path SEGMENT survives as a
  traversal (a literal `..` collapses to the harmless filename fragment `..` joined by `-`, never a
  parent-dir step, because every `/` is already gone). An input that normalizes to empty is rejected.
- **Confinement invariant.** Let `runs_root = os.path.realpath(os.path.join(KIT_ROOT, 'docs', 'runs'))`.
  The generator writes `out_path` ONLY IF `real = os.path.realpath(out_path)` satisfies
  `real == runs_root or real.startswith(runs_root + os.sep)`. This holds for BOTH the default path
  (built from `runs_root` + the normalized rid) AND any explicit `out-path` arg. Otherwise: stderr +
  non-zero exit, no write. `os.path.realpath` resolves `..` and symlinks, so neither a `../` explicit
  path nor a symlink pointing outside can escape. Portable (realpath needs no existence).
- **Ordering.** basename-`proof-of-done.md` refusal runs FIRST, then confinement , the canonical case
  keeps its specific message; every other out-of-tree path is rejected by confinement.

These two invariants together make the docstring's "only writes under docs/runs/" claim TRUE.

## Verification

Run `bash tests/test-security-hardening.sh` (new), `bash tests/test-proof-table-gen.sh`,
`bash tests/test-mutation-smoke.sh`, `bash tests/test-meta.sh`. All exit 0.

Acceptance criteria:
1. `rid="../../victim/pwned"` and an absolute `rid="/tmp/.../pwned"` are CONFINED (write lands under
   docs/runs) or REJECTED; no file is written outside docs/runs.
2. An explicit out-path outside docs/runs is REJECTED (non-zero exit, stderr, no write).
3. A normal rid still writes `docs/runs/<rid>.md`; the `proof-of-done.md` basename is still refused.
4. NEGATIVE CONTROL: reverting the sanitization+confinement makes the traversal PoC write outside
   docs/runs again (RED); restoring re-confines (green).
5. A `file=`/`reason=` value containing `=` no longer adds a second KV to the `| MUTATION |` line
   (exact KV count asserted). NEGATIVE CONTROL: reverting leaks the `=`.
6. mutation-smoke skips a symlinked target.
7. No regression: the three existing suites stay green.

Proof: `docs/verification/kri-security-hardening.md` (table-first).

## After state

- `lib/proof-table-gen.py`: `_normalize_rid` + realpath confinement; docstring contract now true.
- `lib/proof-table-gen.sh`: SCRIPT_ROOT/KIT_ROOT split.
- `lib/gate-ledger.sh`: `mutation()` neuters `=`.
- `lib/mutation-smoke.sh`: symlink skip.
- `tests/test-security-hardening.sh`: new; wired into `.github/workflows/test.yml`.
- `tests/test-proof-table-gen.sh`: out-paths moved under a temp KIT_ROOT/docs/runs.
