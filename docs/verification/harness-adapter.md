# Proof of done: multi-vendor headless dispatch adapter + `fable` tier fix

ID-390. Branch `feat/multi-vendor-dispatch`. Lane `normal` (`lane-classify.sh classify` -> `normal`).

## What this is

`lib/queue/harness.sh` resolves a CLI-agent vendor to the argv that runs it **headlessly**, so a
mega-goal sub-goal can be dispatched to codex / pi / opencode and pay that vendor's quota instead of
the Claude one. Plus the `fable` tier fix, which is an unrelated live regression found while reading
the routing code.

**Status:** wired. A goal file declares `Harness: <vendor>` and orchestrate.sh dispatches that
sub-goal to that vendor. Absent header -> `claude` -> every pre-existing path runs byte-identically.

## Why not the prior art's approach

Read from AI-Builder-Club `skills/open-agent-teams` (`tdel`, 145 lines of bash). It solves the same
problem by puppeting each vendor's **interactive TUI** through `tmux send-keys`, which forces it to
carry: busy-pane string scraping (`esc to interrupt` vs `esc interrupt`, per vendor), trust-dialog
detection, a double-Enter workaround for prompts that open a slash-autocomplete popup, and an
agent-authored `touch <file>.done` completion signal.

Every vendor installed here has a real non-interactive mode, so this adapter drives that instead.
None of the above has an analogue in a headless run: the exit code is a real exit code.

The kit already had the parts that are actually hard and that `tdel` has no answer for: a dependency
graph (`depends SG-NN`), a disjointness gate, one git worktree per concurrent worker, drift
detection, dep-aware size-capped handoff, and **grounded completion** (a re-read of ROADMAP.md, so a
sub-goal cannot self-claim done). Only the per-vendor argv table was missing.

## Acceptance criteria

| # | Criterion | Where |
|---|---|---|
| A1 | Prompt-delivery mode is correct per vendor (stdin vs trailing positional) | `harness_prompt_mode` |
| A2 | Model + effort resolve to each vendor's own flag spelling | `harness_argv` |
| A3 | Absent model/effort emit NO flag, so the vendor default wins (matches orchestrate.sh's "absent field -> session inherits its tier") | `harness_argv` |
| A4 | codex effort survives as ONE argv token with its embedded TOML quotes | `harness_argv` |
| A5 | Unknown vendor is rejected (exit 64), never silently defaulted to claude | `harness_known` |
| A6 | An unset flags var degrades to a clean flagless argv, never a truncated one | `${VAR:-}` reads |
| A7 | `Model: fable` passes orchestrate.sh's allowlist | `_ROUTE_MODEL_ALLOWLIST` |
| A8 | An off-allowlist tier is still rejected (negative control: the fix widened the list, it did not remove the gate) | `_route` |
| A9 | `tier_of` normalizes fable, so a fable ledger row does not become its own bogus tier | `route-suggest.sh` |

Wiring criteria (phase 2):

| # | Criterion | Where |
|---|---|---|
| B1 | Absent `Harness:` -> claude -> the original `$CLAUDE_CMD` path, byte-identical | `_harness_of` default |
| B2 | `Harness:` parse is case-insensitive and trimmed | `_harness_of` |
| B3 | An unknown harness hard-stops (64); it NEVER falls back to claude | `_harness_of` |
| B4 | The claude tier allowlist applies to claude only, so `Model: gpt-5` under `Harness: codex` is admitted verbatim | `_route` |
| B5 | The same `Model: gpt-5` with NO harness is still rejected (negative control) | `_route` |
| B6 | A vendor sub-goal actually EXECS that vendor, with the prompt on the declared channel | `_run_one_session_vendor` |
| B7 | Requesting stream / det-handoff / token capture on a vendor WARNs and degrades, never blocks dispatch | `_run_one_session_vendor` |
| B8 | Grounded completion still governs: a vendor session advances only on the flipped ROADMAP box | `cmd_run` (unchanged) |

## Implementation

| File | Change |
|---|---|
| `lib/queue/harness.sh` | new. `harness_list` / `harness_known` / `harness_prompt_mode` / `harness_argv`, plus a CLI for eyeballing a resolved argv. `case`-based vendor table, bash-3.2 safe. |
| `lib/queue/orchestrate.sh` | sources harness.sh; new `_harness_of` (the one place the vendor is decided) + `_run_one_session_vendor`; `_route` scopes the tier allowlist to claude; `_run_one_session` branches on harness; the dispatch log line names the real harness; `_ROUTE_MODEL_ALLOWLIST` gains `fable`. |
| `lib/classify/route-suggest.sh` | `tier_of`: added the `fable*` arm alongside its siblings. |
| `tests/test-harness-adapter.sh` | new. 21 assertions covering A1-A9. |
| `tests/test-harness-dispatch.sh` | new. 18 assertions covering B1-B8, using mock vendor binaries that record argv + stdin. |

### Two structural choices worth naming

**The harness is re-read inside `_run_one_session`, not threaded in as a parameter.** `route_flags`
reaches that function through four call sites (serial `cmd_run`, the wave subshell, `_pane_spawn`,
`cmd_pane_exec`). Widening all four signatures for one string is a much larger diff than one grep of
the goal file, and every extra parameter is another place the wave path and the serial path can
drift apart.

**The vendor path is a separate function, not another arm of the existing if/elif chain.** The claude
path keeps exactly the shape 178 pre-existing assertions already pin, so `Harness:`-less behavior is
unchanged by construction rather than by careful reading.

**Vendor path is plain-only, by necessity.** The other two run-paths need `--output-format
stream-json --verbose`, a Claude-CLI spelling with no portable equivalent. Those are observability
features, not correctness ones, so this WARNs and degrades (house convention: advisory failures
WARN+continue). Blocking would let a globally-set `CAPTURE_TOKENS=1` wall off every non-claude
sub-goal. The WARN is what keeps it from being the silent accounting black hole ID-097 closed.

Vendor facts were read off the installed binaries' own `--help` on 2026-07-22, not from the prior
art's table:

| Vendor | Headless | Prompt | Model | Effort | Permission |
|---|---|---|---|---|---|
| claude | `-p` | stdin | `--model` | `--effort` | `--dangerously-skip-permissions` |
| codex | `exec` | stdin (`--help`: "if not provided as an argument ... read from stdin") | `--model` | `-c model_reasoning_effort="…"` | `-s workspace-write` |
| pi | `--print` | positional | `--model` | `--thinking` | none (always autonomous) |
| opencode | `run` | positional | `--model` | `--variant` | `--auto` |

**Permission-posture decision.** `CODEX_FLAGS` defaults to `-s workspace-write`, NOT the
`--dangerously-bypass-approvals-and-sandbox` the prior art uses. Each wave sub-goal already runs in
its own git worktree, so `workspace-write` confines the agent to exactly the tree it should edit and
still runs unattended. Taking the bypass flag would discard isolation already paid for.

## Confirmation run-table

| Check | Command | Result |
|---|---|---|
| Adapter suite | `bash tests/test-harness-adapter.sh` | **21 PASS, 0 FAIL**, rc=0 |
| Dispatch-wiring suite | `bash tests/test-harness-dispatch.sh` | **18 PASS, 0 FAIL**, rc=0 |
| Regression: orchestrate | `bash tests/test-orchestrate.sh` | 63 pass, 0 fail, rc=0 |
| Regression: wavefront | `bash tests/test-orchestrate-wavefront.sh` | 103 pass, 0 fail, rc=0 |
| Regression: hardening | `bash tests/test-orchestrate-hardening.sh` | 12 pass, 0 fail, rc=0 |
| shellcheck (`-S warning`) | `orchestrate.sh` + `harness.sh` + dispatch test | clean (0 findings) |
| **Live: claude leg (adapter)** | resolved argv, prompt on stdin | `claude -p --model haiku --dangerously-skip-permissions` -> **rc=0, output `ADAPTER_OK`** |
| **Live: codex leg (adapter)** | resolved argv, prompt on stdin | argv ACCEPTED, `Reading prompt from stdin...` confirms A1; **rc=1 at HTTP 401** (codex not authenticated on this host) |
| **Live: full orchestrator, real claude** | `orchestrate.sh run <megadir>` on a 1-sub-goal mega-goal | dispatched a REAL claude session -> agent flipped the box -> `SG-01 complete (box checked); advancing` -> `all sub-goals checked; done` |
| **Live: full orchestrator, vendor harness** | same, `Harness: codex` + a mock codex on PATH | `running SG-01 ... (harness: codex, model: gpt-5, effort: high)`, `prompt via stdin`, argv `exec --model gpt-5 -c model_reasoning_effort="high" -s workspace-write`, box flipped, grounded completion advanced |

### Live-run detail (the part a green unit test would have missed)

The claude leg is proven end to end: the adapter's argv ran a real agent and got the expected reply.

The codex leg is proven **as far as credentials allow, and no further**. Two real facts came out of
it, both invisible to the unit tests:

1. `codex exec` refuses to start outside a trusted git repo ("Not inside a trusted directory and
   `--skip-git-repo-check` was not specified"). The real dispatch path always runs inside a git
   worktree, so this is satisfied naturally, but it would have broken a naive scratch-dir run.
2. Re-run inside a git repo, codex accepted the argv, printed `Reading prompt from stdin...`
   (independently confirming the stdin delivery mode this adapter declares for it), and reached the
   OpenAI API before failing `401 Unauthorized`. **The blocker is a missing credential, not the
   adapter.** Do not read this row as "codex works end to end"; it does not, on this host, yet.

### The bug the live run caught

The first live run returned a **truncated argv**: `claude -p --model haiku` with the permission flag
missing. Cause: the flag defaults (`CLAUDE_HARNESS_FLAGS="${CLAUDE_HARNESS_FLAGS:-…}"`) only execute
at SOURCE time, so a caller sourcing with a temporary assignment prefix leaves the variable unset by
the time the function is CALLED; a bare `$VAR` read then aborted `harness_argv` mid-emit under the
consumer's `set -u`.

This is the dangerous shape, not a cosmetic one: a truncated argv does not fail loudly, it dispatches
an unattended session with no permission flag, which then **hangs on a permission wall**. Fixed by
reading every flags var as `${VAR:-}`, and pinned by A6 so it cannot regress.

A second false-green was caught in the same pass: the fable cases first called `_route_flags`, which
does not exist (the function is `_route`), and the negative control happily read
"command not found" as "the gate rejected it". An existence guard now runs before those cases and
hard-exits if `_route` is not sourceable.

## Reproduce

```bash
cd ~/workspace/tieubao/dwarves-kit
git switch feat/multi-vendor-dispatch
bash tests/test-harness-adapter.sh          # expect: all green
bash lib/queue/harness.sh argv codex gpt-5 high   # eyeball a resolved argv
bash lib/queue/harness.sh mode pi                 # -> argv
```

Live leg (needs a git repo as cwd; `<vendor>` authenticated):

```bash
printf 'Reply with exactly the single word ADAPTER_OK and nothing else.\n' > /tmp/p
source lib/queue/harness.sh
argv=(); while IFS= read -r t; do argv+=("$t"); done < <(harness_argv claude haiku)
"${argv[@]}" < /tmp/p
```

### What the mock-vendor run does and does not prove

The full-orchestrator vendor run used a mock `codex` on PATH that records its argv and stdin, then
flips the ROADMAP box the way a real agent would. That proves the ENTIRE wired pipeline: harness
resolution, allowlist scoping, argv construction, prompt delivery on the right channel, the dispatch
log, grounded completion, and advance.

It does **not** prove a real codex model can complete a real sub-goal. It cannot, on this host: no
OpenAI credential (see the 401 row). What is proven is that everything the kit controls is correct up
to the vendor's own front door.

## Known gaps

- **No live non-claude model run.** codex reached the API and got 401; pi and opencode were never run
  against a real model at all, only mocked. The first thing to do with a real credential is re-run
  the vendor e2e without the mock.
- **Vendor sub-goals get no token accounting**, by construction (no stream-json equivalent). A run
  that mixes claude and codex sub-goals will have a partial token ledger. WARNed, not silent.
- **Wave path untested with mixed vendors.** The wiring sits in `_run_one_session`, which both the
  serial and wave paths call, so it should hold; but no test dispatches a WAVE with two different
  harnesses concurrently.
- **No cross-vendor model tiering.** `Model:` passes through verbatim for non-claude vendors, and
  orchestrate.sh's tier allowlist stays claude-only. Deliberate: there is no honest mapping from
  `opus` to a competitor's model id.
