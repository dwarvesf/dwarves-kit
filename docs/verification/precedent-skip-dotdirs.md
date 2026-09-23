# Verification -- precedent-skip-dotdirs

`scan_kit_verbs` in `lib/precedent/inventory.py` now prunes any dot-directory
component (`.venv`, `.git`, `.cache`, ...) while walking `lib/`, so a
virtualenv's `bin/` scripts no longer surface as kit verbs; a real
`lib/<x>/bin/<tool>` entry point is unaffected.

## Green run
```
Command: bash tests/test-precedent.sh
Exit: 0
Verdict: PASS (82/82, including the new "lib scan: a .venv/bin script is
  skipped while its bin/ sibling is indexed" case)

Command: RUN_ALL_TIMEOUT_SECS=600 bash tests/run-all.sh --changed
Exit: 1
Verdict: PASS for every suite except test-no-personal-paths, which fails
  identically on a clean origin/master checkout (pre-existing, since #744,
  unrelated to this change; confirmed by cloning origin/master to a scratch
  dir and running the same suite there).
```

## Negative control
```
Command: git checkout HEAD~2 -- lib/precedent/inventory.py && bash tests/test-precedent.sh
Exit: 1
Outcome: RED as designed -- "lib scan: a .venv/bin script is skipped while
  its bin/ sibling is indexed" fails (rc=0 got="True True": the .venv/bin/
  python fixture was indexed alongside the real bin/ tool, confirming the
  test catches the bug). Restored with
  git checkout HEAD -- lib/precedent/inventory.py, re-ran: back to PASS, 82/82.
```

## Not proven
- Does not cover the four real virtualenv rows under `lib/stats/.venv/bin/`
  named in the bug report directly (that `.venv` is gitignored and absent
  from this checkout); the fixture reproduces the same shape (an executable
  script under a dot-directory's `bin/`) instead.
