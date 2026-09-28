# Implementation notes: permission-auto-approve write-bypass fix

Spec: `docs/specs/SPEC-340-auto-approve-writes.md` (VALIDATED). Only the delta
from the Contract lives here.

## Hook shape

- The per-tool safe-flag sets are `case` pattern lists inside `flag_ok <kind>
  <tok>`, not associative arrays (bash 3.2 has none). Three scan shapes:
  `scan_flags` (non-flag args unrestricted: find, file, git log/diff/show),
  `scan_exact` (every arg must be in the set: git branch, git tag), and the
  inline remote check (at most one token in {-v, --verbose, show}).
- `WORDS` is initialized to `()` before `read -ra` because bash 3.2 raises
  unbound-variable on `${#unset[@]}` under `set -u`, not just on `"${arr[@]}"`.
- `LC_ALL=C` is a plain assignment immediately before the stage-b `[[ =~ ]]`
  test; bash applies it to its own regex compilation.
- The git global-flag cases (`git -c ...`, `git -C ...`) fall through at stage-f
  by landing on the `*)` subcommand arm, not through a dedicated rule: `-c` is
  not an allowed subcommand, so the subcommand gate does the work.
- The non-Bash / empty-command early exit emits a `bash-gate` debug line too;
  it is not one of the six AC6 tokens (it is not a stage) but keeps the "every
  fall-through is diagnosable" contract uniform.

## Test changes

- The whole permission block (plus the cosmetic-module invocations of this
  hook) runs through `"${PAA_BASH:-/bin/bash}"`, so the default suite exercises
  the production 3.2 interpreter; `PAA_BASH=$(command -v bash)` re-runs under
  the PATH bash.
- Group (c) adds the six AC6 stderr asserts, one per instrumented token
  (`nul-guard`, `stage-a`, `stage-b`, `stage-c`, `stage-e`, `stage-f`).

## Deviations and notes

- The spec's second negative control (NUL guard mutated to `jq contains`) is
  jq-version-dependent: jq >= 1.7 keeps NULs in strings, so on this host
  (jq 1.8.2) the mutation is behavior-preserving and negctl correctly reports
  the control as not red. A third control neutralizing the guard
  (`any(. == 0)` -> `any(. == -1)`) does go red on a53/c1 and is the run that
  proves the NUL case has teeth here.
- `git remote show` (no remote name) approves per the spec's rule as written
  ("zero or one further token"); bare `git remote show` errors at run time
  anyway, so no capability is gained.
