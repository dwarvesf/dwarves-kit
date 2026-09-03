# Implementation notes: negctl fail-closed (battery fixes over #483)

The spec is the battery report over #483 (verifier N2 FAIL, security HIGH 1-2, reviewer
H1/H2/M3/M4/L11/L12, advisor H1-H2). This note carries only what those findings left open.

## 2026-09-04 00:50 negctl moves to its own script

Context: advisor and reviewer both said a tree-mutating, fail-closed tool does not belong in
proof-ledger.sh, whose banner promises FAILS OPEN.
Decision: `lib/gate/negctl.sh` is the implementation; `proof-ledger.sh negctl` stays as a
one-line forwarder so the verb already documented in #483 keeps working.
Why: the shared thing is the output grammar (a string contract), not code; the gate's three
FATAL `source` lines were inherited for nothing.
Alternatives: keep the function and flip the banner (rejected: the banner is right for the
gate). Impact: `docs/verification/README.md` names `negctl.sh` first, the verb second.

## 2026-09-04 00:50 restore set and tree assertion

Decision: the restore set is `git diff HEAD --name-only -z` (staged and unstaged) into an
array, restored with `git checkout HEAD --` quoted, rc checked; a snapshot of
`status --porcelain --untracked-files=all` taken before the first test run must match the
snapshot after restore, or the verdict is FAIL with the delta printed.
Why: the verifier reproduced an unrestored space-named path; the security lens showed a staged
mutation reported `Changed: <nothing>`, and an untracked leftover was silent.
Tradeoff: the refusal still ignores untracked files (`--untracked-files=no`), because refusing
on any scratch file would block most real repos; the before/after snapshot catches what the
mutation did to them instead.

## 2026-09-04 00:50 check() rejects a FAIL verdict

Decision: `Verdict: FAIL` joins `INCONCLUSIVE` in the last-verdict rejection in both branches
of `check()`.
Why: reviewer H1 proved a pasted negctl FAIL block satisfied the gate.
Open question: hand-written proofs that spell a failed run some other way still pass; the
grammar only knows `Verdict:`. Left as is.

## 2026-09-04 00:50 not done

- Auto-recording a negctl run in the gate ledger (advisor, "keep, after wiring"): not built.
- `--mutate-file <script>`: `bash -c` quoting works; not built until a real quoting failure.
