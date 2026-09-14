# Proof of done: Codex hook parity

Profile: feature. Proof class: behavioral.

## Acceptance criteria

| Area | Verdict | Evidence |
|---|---|---|
| Package and offline behavior | PASS | Codex package loaded and 84 contract tests passed |
| Claude regression | PASS | 498 hook tests passed and both Claude manifests remained byte-identical to the baseline |
| Repository projection | PASS | 852 meta tests passed after feature registry regeneration |
| Security review | PASS | No open security finding after token, path, cwd, and trust-boundary fixes |
| Architecture review | PASS | Shared policy spine and macOS/Linux checksum fallback accepted |
| Test coverage review | PASS | All offline test-plan rows covered, including isolated ship block-to-allow transition |
| Live Codex dispatch | PASS | All five hard controls fired in a disposable Codex home |
| Trust invalidation | PASS | One modified hook definition returned to needs-review state |

## Test plan coverage

| Test plan row | Evidence |
|---|---|
| 1-10 | R1 |
| 11 | Documentation and three-lens review |
| 12 | R2 and R3 |
| 13 | R4 |
| 14 | R5 |

## Run detail

### R1 GREEN

Command: `bash tests/test-codex-hooks.sh`

Exit: 0

Output excerpt: `84 passed, 0 failed`

Verdict: PASS

### R2 GREEN

Command: `env -u NO_COLOR TERM=xterm bash tests/test-hooks.sh`

Exit: 0

Output excerpt: `Passed: 498 / 498` and `All tests passed.`

Verdict: PASS

### R3 GREEN

Command: `bash tests/test-meta.sh`

Exit: 0

Output excerpt: `Passed: 852 / 852` and `All meta tests passed.`

Verdict: PASS

### R4 LIVE CODEX

Command: install the branch package into an isolated authenticated Codex home, trust all five definitions through `/hooks`, then run safe disposable probes.

Exit: 0

Output excerpt: Codex reported active counts `PreToolUse 4` and `Stop 1`. Live dispatch blocked `git push origin main`, `cat .env`, an invalid commit subject, and an incomplete feature push. The Stop hook rejected `I will leave this as a follow-up task.` and Codex continued with a clean completion.

Verdict: PASS

### R5 NEGATIVE CONTROL

Command: add a benign `true &&` prefix to one trusted safety hook definition, refresh the local plugin, and reopen Codex.

Exit: 0

Output excerpt: Codex displayed `1 hook is new or changed` and kept that definition pending review. The exact original command was restored afterward.

Verdict: PASS

### R6 NEGATIVE CONTROL

Command: `CODEX_HOOKS_FILE=<manifest-with-safety-hook-removed> bash tests/test-codex-hooks.sh`

Exit: nonzero

Expected output: the required safety policy count fails. Restoring the original manifest returns R1 to green.

Verdict: PASS

## Reproduce

Run `bash tests/test-codex-hooks.sh`, `env -u NO_COLOR TERM=xterm bash tests/test-hooks.sh`, and `bash tests/test-meta.sh` from the repository root.

The live Codex probes use only disposable repositories and harmless fixture content. They do not read production credentials or contact a git remote.

## Known baseline failures

The optional `bash tests/run-all.sh` project sweep remains red outside this change. The unchanged baseline reproduces the same failures in reflect compatibility, repo-hygiene TSV expectations, and detached-process inspection under the current sandbox. Its `test-hooks` color failure passes with the documented `env -u NO_COLOR TERM=xterm` invocation used in R2.
