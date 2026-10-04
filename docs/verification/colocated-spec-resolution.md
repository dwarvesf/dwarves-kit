# Proof of done: co-located spec resolution

Branch `fix/colocated-spec-resolution` at `05ae6017`. Spec: `docs/specs/SPEC-386-colocated-spec-resolution.md`.

## Green run

```
Command: bash tests/test-spec-find.sh
Exit: 0
Output: test-spec-find: 55 passed, 0 failed
Verdict: PASS
```

## Negative control (revert -> RED -> restore)

Mutant: `return 0` after the root `ls` in `spec_files` (root-only lookup, the pre-branch behavior).

```
Command: bash tests/test-spec-find.sh   # mutant
Exit: 1
Output: test-spec-find: 35 passed, 20 failed
Verdict: RED as expected

Command: bash tests/test-spec-find.sh   # restored
Exit: 0
Output: test-spec-find: 55 passed, 0 failed
Verdict: PASS (file clean vs HEAD: yes)
```

Reproduce: run the commands above; the mutant is one inserted line.
