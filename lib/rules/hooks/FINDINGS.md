# Hooks and autonomy: rules, proofs, bridges, findings

Every hook in `hooks/` except the ship-gate decision chain (in `lib/rules/gates/`), the autonomy dial with its four
hard stops, and the bounded-loop resume (`lib/loop/ql-verdict.sh`), written as native gdp-wired rules.

- Each rule follows what the bash does; the file and line are cited in the rule's header.
- Its laws are the ones the docs promise.
- Every kept broken variant is refused.
- A bridge runs the real hook on generated Claude Code hook JSON in a sandbox (temp HOME, repos and ledger; network
  and external tools stubbed) and compares the hook's exit code, output and stored state with the rule.

Run `cd lib/rules && npm ci && node hooks/prove.ts` (about 50 s on a 2-CPU box), or add `--no-bridges` for the proofs
alone (about 5 s). Any state a hook reloads from disk or from the host is proven `{from: 'any'}` with no `assumes`.

## Rules

| Rule | Source | Laws | Variants refused | Promise refuted (kept) | Bridge |
|---|---|---|---|---|---|
| safety-gate | hooks/safety-gate.sh :253-343 | 12 | pre-fix, lease-is-force, no-allowlist, reads-autonomy | - | 528 / 0 (151 corpus + 150 seeded x 3 configs); 7 documented holes, 1 fail-safe over-block |
| secrets-guard | hooks/secrets-guard.sh | 6 | lexical-allow, resolved-only | Grep of a secret path | 29 / 0; 5 coverage notes |
| commit-format | hooks/commit-format.sh | 8 | pre-fix, no-length-cap, gate-ignored | - | 198 / 0 |
| anti-rationalization | hooks/anti-rationalization.sh + host stop loop | 8 (any state) | pre-fix, no-loop-guard, guess-anytime | an excuse never ends a turn | 193 / 0 |
| hard-stops | autonomy.md + gates-and-proof.md | 3 | max-waives | every stop halts at every position; anti-rationalization halts while the gate is on | none (prose only) |
| spec-drift-guard | hooks/spec-drift-guard.sh | 5 | blocks-on-drift, warns-on-config | - | 288 / 0 |
| context-readiness | hooks/context-readiness.sh SUGGEST | 6 | ship-unreviewed, ambiguity-guesses | every state suggests a next step | 70 / 0 |
| post-compact-reinject | hooks/post-compact-reinject.sh | 3 | pre-fix, names-ambiguous | - | 24 / 0 |
| money-gate | hooks/money-gate.sh | 6 | asks-unarmed, denies | - | 121 / 0 |
| tool-policy-guard | hooks/tool-policy-guard.sh | 5 | ask-blocks, fail-closed | - | 90 / 0 |
| permission-auto-approve | hooks/permission-auto-approve.sh | 7 | git-before-worktree, denies-unknown, flags-unchecked | - | 153 / 0; no writing command approved |
| board-row-gate | hooks/board-row-gate.sh | 6 | kill-switch-ignored, marker-ignored, blocks-status-flips | - | 52 / 0 |
| output-offload | hooks/output-offload.sh | 3 | counts-input, blocks-large | - | 60 / 0 |
| citation-guard | hooks/citation-guard.sh | 3 | blocks-unarmed, blocks-on-any-citation | a continuing Stop is never blocked | 51 / 0 |
| anchor-root | hooks/anchor-root.sh + lib/config/hook-module.sh | 4 | spine-toggleable, swallows-exit | - | 80 / 0 |
| codex-hook-adapter | hooks/codex-hook-adapter.sh | 5 | fails-open-without-jq, unsupported-runs | - | 60 / 0 |
| advisory-hooks | 20 advisory hooks, hostile input | 1 | pre-fix | - | 160 / 0 |
| batch-debt-warn | hooks/batch-debt-warn.sh | 4 (any state) | warns-every-merge, warns-first-merge | - | 120 / 0 |
| context-budget | hooks/context-budget.sh | 6 + 2 band (any state) | no-clear, fires-every-prompt | - | 128 / 0 |
| context-hints | hooks/context-hints.sh temporal | 5 (any state) | restarts-clock, line-on-first | - | 98 / 0 |
| kit-update-notice | hooks/kit-update-notice.sh | 5 (any state) | fetch-every-start, notify-equal | - | 72 / 0 (curl, date stubbed) |
| slop-cleaner | hooks/slop-cleaner.sh | 5 (any state) | pre-fix, no-memory | - | 60 / 0 |
| harvest-throttle | lib/reflect/hook-util.sh hu_throttled | 5 (any state) | stamps-when-skipped, ignores-stamp | - | 60 / 0 |
| harvest-stop-trigger | hooks/harvest.sh --stop-trigger | 5 (any state) | off-by-one, no-reset | - | 56 / 0 |
| ql-verdict | lib/loop/ql-verdict.sh resume | 5 (any state) | pre-fix, streak-survives-dirty | - | 80 / 0 |

## Fixes

Each fix keeps the old behaviour as a `pre-fix` variant, and `prove.ts` asserts that variant is refuted. "Before"
bridge numbers come from running the bridge against a copy of the pre-fix file.

### F1. safety-gate let 17 destructive commands through

Laws: the `docs/reference/hard-rules.tsv` `safety-gate.*` rows. Each of these exited 0 before the fix:

- `FOO="a b" rm -rf src`, `env MSG='hello world' rm -rf src`: quotes were deleted before word splitting, so the second
  half of the value was read as the binary. `GIT_SSH_COMMAND="ssh -i k" git push -f …` and
  `git -c user.name="A B" push --force …`: same cause.
- `find src -exec /opt/homebrew/bin/rm -f {} +`: only `rm`, `/bin/rm` and `/usr/bin/rm` were recognised.
- `git push origin refs/tags/v1.0:refs/heads/main`: the tag allowance matched before the main check.
- `git push --branches` (git 2.46+ name for `--all`), and `--mirr`, `--al`, `--m`, `--b` (git accepts any unique prefix).
- `git reset --har`, `--ha`, `--h`: all hard resets.
- `kubectl -v 6 delete`, `kubectl --request-timeout 5s delete`.

Reproduce: `jq -n --arg c 'git reset --har HEAD~1' '{tool_input:{command:$c}}' | bash hooks/safety-gate.sh; echo $?`
gives 0 before the fix and 2 after.

Diff: join the blanks inside a quoted `=value` per segment (parameter expansion only); accept `rm|*/rm`; move the
main/master case above `refs/tags/*`; list `--branches` and the accepted prefixes; match `--h|--ha|--har|--hard`; have
kubectl skip `-v --v --as --as-group --request-timeout --token`. Messages are unchanged.
Bridge 468/60 → 528/0. Tests: `tests/test-hooks.sh` G1–G10.

### F2. anti-rationalization never fired under Claude Code

Law: an excuse phrase is refused on a fresh Stop while the gate is on, whichever field carries the message.
Claude Code's Stop payload carries `last_assistant_message`; the hook read only `.assistant_response`, so it exited 0
before any guard ran. Reproduce: `echo '{"stop_hook_active":false,"last_assistant_message":"in a follow-up PR"}' |
KIT_CONFIG_OPERATOR=tests/fixtures/gates-on bash hooks/anti-rationalization.sh; echo $?` (0 before, 2 after).
Diff: `jq -r '.assistant_response // .last_assistant_message // empty'`. Bridge 162/30 → 193/0. Two tests added.

### F3. commit-format refused every heredoc message

Law: a Conventional subject of at most 72 characters with no marker is allowed, however the message is passed.
`git commit -m "$(cat <<'EOF' … EOF)"` was blocked because the subject read was the `$(cat` line. Diff: a `case` that
takes the line after `$(cat <<` as the subject. Bridge 185/13 → 198/0. Two tests added.

### F4. slop-cleaner could block the Stop

Law: an advisory hook never blocks. A recent source file with mode 000 made awk exit 2 under `set -e`. Diff: skip
files that are not readable. Bridge 53/7 → 60/0; the advisory bridge agrees on all 160 runs. One test added.

### F5. post-compact-reinject re-injected nothing without python3

Law: compaction always re-injects the push-to-main and `rm -rf` rules. With no python3 on PATH the JSON build exited
127 under `set -e`. Diff: the output JSON is built with `jq -n --arg ctx`. Bridge 12/12 → 24/0 on a PATH without python3.

### F6. ql-verdict counted a round that still had findings as clean

Law: no round in the clean streak carried findings. `[[QL-VERDICT round=1 clean=true findings=3]]` was accepted and
extended the streak. Diff: that marker is now the existing malformed error (exit 65); `clean=false findings=0` stays
legal (`done-modes.md` Trace 3). Bridge 72/8 → 80/0. Two tests added to `tests/test-ql-verdict.sh`.

### Codex pins

`hooks/codex-hooks.json` was repinned with `lib/codex/repin.sh` after these edits (it also repinned ship-gate, whose
pin was already stale from the gates area's edit). Re-run the repin if a hook changes again.

## Kept findings (promises the code does not keep; design or doc decisions, not fixed here)

- **N1, anti-rationalization:** the hard stop is one-shot per turn. Stop 1 with an excuse is refused (exit 2); Stop 2
  carries `stop_hook_active: true` and passes (exit 0). This refutes "the four hard stops are never waived"
  (`gates-and-proof.md`, `autonomy.md`). It is also off unless `[gate] understanding_gate = true`, which adopt does not seed.
- **N2, citation-guard strict:** it never reads `stop_hook_active`, so it blocks every Stop while a bad ref remains.
- **N3, secrets-guard:** a Grep of `.env` is unguarded (exit 0); plugin installs ship no deny list.
- **N4, context-readiness:** `spec:NONE` gets no `next:`; a task ticked `- [X]` never counts as done.

## Observations

- safety-gate documented holes: a ref in a variable; a script from a file or a pipe; `ssh` / `docker exec`;
  `timeout -s`; a heredoc run by `bash -s`. An implicit push of main is left to ship-gate. Not covered and not promised:
  `rm -r` without `-f`, `git clean -fdx`, `checkout -- .`, `restore .`, `DROP DATABASE`, `TRUNCATE`.
- secrets-guard coverage: not in the glob list: `.env.staging`, `.env.test`, `.envrc`. Through Bash, `cat .env` and
  `grep … ~/.aws/credentials` pass. The Codex adapter blocks `less .env`; the Claude Code path allows it. It is the one
  hook hooks.json runs by its exec bit, not through anchor-root's explicit `bash`.
- Host contract (from the Claude Code docs, not run live): context-readiness, slop-cleaner, spec-drift-guard and
  output-offload print a top-level `additionalContext`; the documented field is `hookSpecificOutput.additionalContext`.
- context-readiness builds its JSON by interpolation, so a branch named `feat/a"b` produces invalid JSON.
- tool-policy-guard decides in python3, against the "no Python in hooks" rule.
- Harvest throttle: a stamp dated in the future holds the throttle shut until now passes mtime + interval.

## Prose-only machines (no code enforces them)

- The autonomy dial and "decisions taken alone get recorded" (`hard-stops.ts` proves the stops are independent of
  position, as a model).
- The AGENTS.md pause rules.
- The `/kit:debug` 3-fix architecture wall: nothing counts `## Fix attempts`.
- Debug confirm-fix and gate-record ordering.
- Quiescence loops: the round cap of 3, strictly-decreasing findings, the stop decision (`ql-verdict.sh` only resumes).
- `/kit:docs` "after 2 rounds: stop".
- `/kit:execute` routing: now enforced by `bin/verify-loop` (`lib/rules/verify-loop.ts`).

## Not modelled

- safety-gate's awk parser: a string transducer, held to the rule only through the corpus bridge.
- Text scanners (money-gate keywords, context-hints word boundaries, citation-guard ref extraction, board-row-gate's
  command parse): each is modelled as the fact it produces and pinned by its parity tests.
- Harvest sweep, backlog-stage dedup, intake sources: LLM and Python work; only the shared throttle is modelled.
- pre-compact-backup numbering, auto-format, codebase-index, notification, prose-rag: only the advisory
  "never blocks" law applies.
