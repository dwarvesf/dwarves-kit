# Proof of done: output-offload + deterministic-verify (SG-06)

| | |
|---|---|
| **Profile** | feature (behavioral) |
| **Proof class** | behavioral: hook threshold test + real offload run + grep on the doc |
| **Spec** | token-optim-v2 goals/06-offload-verify.md |
| **Canonical** | this file |

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| AC1 | PostToolUse hook detects tool output > ~2k tokens | PASS | R1, R2 |
| AC2 | Full payload offloaded to a file (reversible, nothing dropped) | PASS | R1, R2 |
| AC3 | A short pointer left in context (no payload re-paste) | PASS | R1, R2 |
| AC4 | Output <= threshold passes through untouched | PASS | R1 |
| AC5 | Verify guidance prefers deterministic / cheap-model over Opus | PASS | R3 |
| AC6 | Native `BASH_MAX_OUTPUT_LENGTH` lever documented | PASS | R3 |
| AC7 | A test pins the offload threshold | PASS | R1 |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | `output-offload.sh` PostToolUse hook (size-detect -> file + terse pointer) + WORKFLOW.md verify-cost-routing + output-discipline |
| Where | `hooks/output-offload.sh`, `hooks/hooks.json` (PostToolUse `*` entry), `tests/test-hooks.sh` (6 cases), `WORKFLOW.md` |
| How it runs | reads JSON stdin, fast-path skips small payloads, coerces `tool_response` to a string, offloads over `OFFLOAD_MAX_TOKENS` (default 2000, ~4 chars/token) |
| Reversibility | full payload written to `~/.cache/dwarves-kit/offload/`; the hook only adds a pointer, never strips |

## 3. Confirmation (recorded runs)

| Run | When | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 | 2026-06-29 | `bash tests/test-hooks.sh` | 0 | PASS 432/432 (6 new offload cases incl. threshold boundary + reversibility) |
| R2 | 2026-06-29 | real hook run on a 12000-char Grep `tool_response` | 0 | offloaded to a 12001-byte file + one-line pointer |
| R3 | 2026-06-29 | `grep -ic deterministic/cheap WORKFLOW.md`; `grep -c BASH_MAX_OUTPUT_LENGTH` | 0 | 5 / 4 / 1 hits -> guidance present |

## 4. Run detail

### R1 GREEN, threshold pinned + reversibility
- `bash tests/test-hooks.sh` -> `Passed: 432 / 432. All tests passed.`
- New cases: small (80 chars, under ~100-char budget at `OFFLOAD_MAX_TOKENS=25`) is NOT offloaded;
  large (400 chars) emits the pointer + names the file; the offload file holds the full 400 chars
  (+newline = 401 bytes); the pointer does not re-paste the payload.

### R2 real offload (the primary flow)
- A 12000-char Grep `tool_response` (~3000 est. tokens) produced:
  `{"additionalContext":"[dwarves-kit] Grep output was large (~3000 tokens, over the 2000-token
  offload threshold). Full payload saved to .../offload/20260629T...-Grep-5e06cf4b.txt. ..."}`
- The saved file was 12001 bytes (full payload + newline). Reversible, nothing dropped.

### R3 verify-routing + native lever documented
- WORKFLOW.md "Verification cost routing (cheap-first)": deterministic check -> cheap-model ->
  Opus reviewer. "Output discipline": `BASH_MAX_OUTPUT_LENGTH` at the source for Bash + the hook
  for non-Bash.

## 5. Honest limitation (recorded)
A PostToolUse hook runs AFTER the tool result is captured, so it cannot strip the current turn's
output. The real per-turn saver for shell output is the native `BASH_MAX_OUTPUT_LENGTH` (source
cap). The hook's value for non-Bash tools is a durable recoverable copy + a scope-narrowing nudge;
the aggregate token win is the source cap + behavior change. See implementation-notes.

## 6. Reproduce
```
git switch feat/output-offload
bash tests/test-hooks.sh        # 432/432
BIG=$(printf 'z%.0s' $(seq 1 12000)); jq -cn --arg r "$BIG" '{tool_name:"Grep",tool_response:$r}' \
  | XDG_CACHE_HOME=/tmp/demo bash hooks/output-offload.sh    # prints the pointer; file under /tmp/demo
```
