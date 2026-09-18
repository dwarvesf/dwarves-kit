# Proof of done: install never writes a CLI shim whose target is outside HOME

## What changed

`kit_write_cli_shim` in `install.sh` wrote to `$HOME/.local/bin` while its target came from `CLAUDE_DIR`. A fixture install that overrides `CLAUDE_DIR` and keeps the real `HOME` therefore wrote shims into the operator's PATH that pointed at the fixture's temp dir. The fixture deleted that dir on exit. The shims dangled, and `prose-rag` broke the UserPromptSubmit hook with "No such file or directory".

`tests/test-hooks.sh` (the install-by-copy block) runs `install.sh` this way on every run. An earlier fix sandboxed `HOME` in `test-install-compat.sh` only, so the class recurred.

The shim writer now skips any target outside `$HOME` and logs `[skip] <name> shim: target ... is outside $HOME (fixture install)`. A default install (`CLAUDE_DIR=$HOME/.claude`) and a sandboxed-HOME fixture both still get their shims.

## Gate table

| Claim | Evidence |
|---|---|
| a fixture CLAUDE_DIR outside HOME writes no shim into HOME | new case in `tests/test-install-clis.sh` |
| the skip is logged | same case |
| default and sandboxed-HOME installs still write shims | the existing cases in `tests/test-install-clis.sh` |
| the compat tripwire still holds | `tests/test-install-compat.sh` |
| the guard is load-bearing | negative control below |

## Run table

```
Command: bash tests/test-install-clis.sh
Exit: 0
test-install-clis: all 22 passed
Verdict: PASS
```

```
Command: bash tests/test-install-compat.sh
Exit: 0
PASS: install compat
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed
Exit: 0 for 16 suites; test-config-seams and test-meta hit the 300s runner ceiling with no failed assertion
Command: bash tests/test-config-seams.sh
Exit: 0   === 53/53 passed ===
Command: bash tests/test-meta.sh
Exit: 0   Passed: 853 / 853
Verdict: PASS
```

## Negative control

Removed the four-line `case "$target"` guard from `install.sh`, re-ran, restored with `git checkout install.sh`.

```
Command: bash tests/test-install-clis.sh   (guard removed)
  FAIL: no shim dir written into HOME
  FAIL: install logged the fixture skip
test-install-clis: 20 passed, 2 FAILED
Verdict: RED as expected; restored, green again
```

## Reproduce

`bash tests/test-install-clis.sh` from the repo root.
