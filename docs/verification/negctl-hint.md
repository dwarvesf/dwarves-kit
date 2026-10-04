# Verification -- negctl-hint

`proof-gate.sh`'s behavioral rigor hint, and its no-registry-row `contract` fallback, now
name `lib/gate/negctl.sh` instead of asking for "a negative control" with no pointer to the
tool that mechanises it.

## Green run

```
Command: bash tests/test-hooks.sh
Exit: 0
Verdict: PASS (Passed: 499 / 499, "All tests passed.")
```

```
Command: bash lib/gate/proof-gate.sh requirement 'add a flag'
Exit: 0
Output: behavioral: run the REAL primary flow end-to-end (not a proxy test), record the
run in docs/verification/<spec-slug>.md, and include a negative control (revert -> RED ->
restore; lib/gate/negctl.sh runs this).
```

## Negative control

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-hooks.sh" "sed -i.bak 's/lib\/gate\/negctl\.sh runs this//; s/via lib\/gate\/negctl\.sh//' lib/gate/proof-gate.sh && rm -f lib/gate/proof-gate.sh.bak"
Exit: 0
Verdict: PASS
```

Full negctl transcript:

```
## Negative control (negctl)
Command: bash tests/test-hooks.sh
Exit: 0 (green before mutation)
Mutation: sed -i.bak 's/lib\/gate\/negctl\.sh runs this//; s/via lib\/gate\/negctl\.sh//' lib/gate/proof-gate.sh && rm -f lib/gate/proof-gate.sh.bak
Changed: lib/gate/proof-gate.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/gate/proof-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation stripped both `negctl.sh` pointers, `tests/test-hooks.sh` went RED on the new
"proof req: behavioral names negctl.sh" assertion, and the tree restored clean, confirming
the test actually depends on the fix rather than passing regardless.

## Not proven

- The `stateful` and `inert` rigor hints were confirmed by reading `proof-gate.sh` to not
  mention a negative control at all, so they were left untouched; no automated check pins
  that absence.
