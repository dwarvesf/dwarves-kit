# Proof of done: the auth hard-gate stops matching the bare word "session"

Spec: `docs/specs/SPEC-296-classify-session-word.md`. Board: ID-906.

| Check | Command | Result |
|---|---|---|
| Green run | `bash tests/test-lane-classify.sh` | 38/38 passed, the six SPEC-296 fixtures included |
| Negative control | restore `\bsession(s)?\b` in the auth entry, rerun the suite | 3 FAIL: the two misfire strings and their `--files commands/wrap.md` form classify `full` again; restored after |
| Regression guard | the pre-existing `add user authentication with jwt sessions` fixture, bare and with `--files docs/x.md` | still `full`, via `auth` |
| Tree-wide lints | `bash tests/run-all.sh --changed` | all suites green after the SPEC renumber and the FEATURES.md regeneration |

Reproduce: run the suite from the kit root; the negative control is the one-line `sed` that swaps the auth alternative back, then the suite, then `git checkout lib/classify/lane-classify.sh`.
