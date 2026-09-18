# Proof of done: wrap land adopts the operator's own open PR

Spec: `docs/specs/SPEC-299-wrap-land-adopts-open-pr.md`. Notes: `docs/implementation-notes/SPEC-299-wrap-land-adopts-open-pr.md`.

## Green run

| Command | Exit | Output | Verdict |
|---|---|---|---|
| `bash tests/test-wrap.sh` (stub and SPEC-299 tests committed before the code) | 1 | `625 passed, 27 FAILED of 652` | RED as expected |
| `bash tests/test-wrap.sh` (after the build and review fixes) | 0 | `all 656 passed` | PASS |
| live: this PR opened by hand, then landed with the branch's own `bin/wrap land` | 0 | `adopted PR`, `tree verified` | see the PR thread |

## Negative control

`bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh" "sed -i '' 's/  elif \[ \"\$open_count\" -eq 1 \]; then/  elif false; then/' lib/wrap/wrap.sh"`

| Step | Exit | Verdict |
|---|---|---|
| green before mutation | 0 | PASS |
| adoption branch disabled | 1 | RED as expected |
| `git checkout HEAD -- lib/wrap/wrap.sh`, rerun | 0 | GREEN |

Reproducible: the suite runs on a stubbed `gh` and local bare repos, with no network.
