# Verification -- ui-acceptance-verifier

The proof of done for the UI acceptance verifier: the runner `lib/ui-verify/run.mjs`, the agent `agents/ui-acceptance-verifier.md` and the suite `tests/test-ui-acceptance-verifier.sh` (spec: `docs/specs/SPEC-292-ui-acceptance-verifier.md`).

| Check | Result |
|---|---|
| The suite, run once at the end with the real install (`bash tests/test-ui-acceptance-verifier.sh`) | test-ui-acceptance-verifier: 469 passed, 0 failed, 0 skipped, exit 0 |
| Negative controls recorded in the implementation notes (hand mutations of a temp copy of the runner) | 45 mutations: 44 turned a case red, 1 stayed green by design (see the table) |
| Live dispatch (a): three criteria and one negative, all passing | PASS, runner exit 0 |
| Live dispatch (b): the planted-bug page | FAIL:fixable naming `Error 500`, runner exit 1 |
| Live dispatch (c): one criterion left out of the scenario | FAIL:escalate with an agent-added NO-CHECK row, runner exit 0 |
| Agent tools seen in the three streams | Read, Grep, Bash for the runner; no Write, no Edit, no npx |
| Reruns | none; each dispatch ran once |

## Green run

The suite on the real install (Playwright 1.65.1 and its Chromium in the install root, the headless browser cases all run, none skipped):

```
Command: bash tests/test-ui-acceptance-verifier.sh
Exit: 0
Output:
  test-ui-acceptance-verifier: 469 passed, 0 failed, 0 skipped
Verdict: PASS
```

## Negative controls

Each mutation below ran on a temp copy of the runner (next to a copy of `package.json`) outside any git work tree, selected with `UI_VERIFY_RUNNER`, with the one case run alone. The red lines are copied as the implementation notes recorded them (`docs/implementation-notes/ui-acceptance-verifier.md`: build logs A1 and A2, fix round F1) and, for round F4, as recorded in the shell during that round. Fix round F2 recorded no per-mutation table, so none of its controls is copied here. The controls that run inside the suite (a resolver copy without the entry, agent file and battery copies, MANUAL and README copies, a fixture copy without `wall.html`, a PATH without node, the synthetic live records) need no copy of the runner and are asserted by the suite itself.

| Round | Mutation | Case | Red line |
|---|---|---|---|
| A1 | delete the `target.url` host check | `guard-refusals` | `FAIL refused: a URL host missing from allow_hosts (exit 2, 0 stderr lines: )` |
| A1 | delete the own-path self-check call | `guard-refusals` | `FAIL refused: a runner copy inside the scratch git repo that is the current directory (exit 2)` |
| A1 | run `main` without the wrapper and handlers | `internal-error` | `FAIL the injected fault exits 4 (exit 1)` |
| A1 | delete the pin compare | `doctor-and-skip` | `FAIL doctor with another installed version exits 21 (exit 0)` |
| A1 | make a pin older than 120 days change the doctor exit | `doctor-and-skip` | `FAIL a pin 121 days old prints the bump note and still exits 0 (exit 5)` |
| A1 | count NO-CHECK rows as PASS in the verdict | `doctor-and-skip` | `FAIL the verdict is NO-CHECK, never PASS` (and four more) |
| A2 | browser status forced to PASS | `rows-and-planted-bug` | `FAIL the planted bug (/?bug=1) exits 1 (exit 0)` |
| A2 | empty row set no longer NO-CHECK | `no-ac` | `FAIL an empty scenarios array exits 2 (exit 0)` |
| A2 | expect-step rule removed | `no-ac` | `FAIL a goto-and-screenshot scenario exits 2 (exit 0)` |
| A2 | `observed` stored raw | `hostile-text-fenced` | `FAIL observed holds no line break, U+2028, U+202E, pipe or backtick and is 1 to 200 characters` |
| A2 | screenshots written to the cwd | `git-status-clean` | `FAIL git status --porcelain is empty after the run` |
| A2 | request route always continues and no resolver pin | `offsite-request-aborted` | `FAIL the second listener saw no plain hit and no WebSocket upgrade ({"hits":2,"upgrades":0})` |
| A2 | WebSocket check always connects and no resolver pin | `offsite-request-aborted` | `FAIL the second listener saw no plain hit and no WebSocket upgrade ({"hits":0,"upgrades":2})` |
| A2 | resolver pin removed (route kept) | `offsite-request-aborted` | `FAIL the second listener saw no hit through the redirect ({"hits":1,"upgrades":0})` and the launch-argument check |
| A2 | request route always continues (pin kept) | `offsite-request-aborted` | green, 13 passed: the pin alone keeps the listener at 0 hits |
| A2 | `chromiumSandbox: false` | `browser-sandbox` | `FAIL a normal run exits 0 (exit 2)` |
| A2 | an empty scan treated as sandbox-ok | `browser-sandbox` | `FAIL a scan that finds no process carrying the run id (a ps stub that lists nothing) exits 2 (exit 0)` |
| A2 | browser not closed | `hang-bounded` | `FAIL browser.leftover_pids is empty` (Playwright's exit hook still ends the process, so the pgrep poll stays green) |
| A2 | run budget not enforced | `hang-bounded` | `FAIL the last row is NO-CHECK 'run budget spent'` |
| A2 | scenario clock does not cap a step | `hang-bounded` | `FAIL the scenario clock caps a step in flight: the row is NO-CHECK 'scenario timeout'` |
| A2 | `mismatch` read as `unverified` | `identity-and-readiness` | `FAIL a different 40-hex value -> mismatch (exit 0, got: unverified/ffffffffffff/PASS/)` |
| A2 | a UUID read as a build id | `identity-and-readiness` | `FAIL a UUID -> unverified (exit 2, got: mismatch/123e4567-e89/NO-CHECK/preview is not the head)` |
| F1 | port compare returns true | `offsite-request-aborted` | `FAIL the listener on another port of the SAME allowed name saw no GET, no JSON POST and no WebSocket ({"hits":4,"upgrades":2})` |
| F1 | `blocked_requests` cap removed | `offsite-request-aborted` | `FAIL blocked_requests holds at most 50 entries and blocked_requests_truncated is true` |
| F1 | host cut to 100 removed | `offsite-request-aborted` | `FAIL a 152 character host is cut to 100 characters` |
| F1 | flag clause of the per-step NO-CHECK removed | `offsite-request-aborted` | `FAIL the redirect row is NO-CHECK 'redirected off an allowed host'` |
| F1 | `expect_no_text` passes without a read | `rows-and-planted-bug` | `FAIL expect_no_text on a page with no body to read is NO-CHECK 'page did not settle', never PASS` |
| F1 | step timeout floor removed | `guard-refusals` | `FAIL refused: a step timeout under 500 ms, which would leave expect_no_text no window (exit 2)` |
| F1 | `Object.hasOwn` check back to the plain lookup | `guard-refusals` | `FAIL refused: a step verb named like an object property (constructor) (exit 4, ... shape.required is not iterable)` |
| F1 | IPv6 transition ranges removed | `guard-refusals` | `FAIL refused: an allowed IPv6 transition or site-local address [64:ff9b::808:808] (exit 2, 0 stderr lines: )` |
| F1 | untrusted root check removed | `doctor-and-skip` | `FAIL doctor: an install root inside a git work tree is not used ... (exit 0)` |
| F1 | double quotes in the doctor command | `doctor-and-skip` | `FAIL doctor: an install root with a space, a quote and a command substitution is quoted, nothing runs from it` |
| F1 | browser gets the whole environment | `browser-sandbox` | `FAIL the browser started with the sandbox on, --no-proxy-server and only HOME and PATH in its environment` |
| F1 | `--no-proxy-server` removed | `browser-sandbox` | same line |
| F1 | stray-process kill removed | `leftover-browser-killed` | `FAIL the runner killed the stray process that carried its run id` |
| F1 | run id line removed | `sigterm-closes-browser` | `FAIL the run id is printed on stderr before the browser work starts (none)` |
| F1 | signal handlers removed | `sigterm-closes-browser` | `FAIL the runner reports that it closed the browser before it exited` |
| F1 | `uncaughtException` listener removed | `internal-error` | `FAIL the injected fault exits 4 (exit 1)` |
| F4 | step verb check back to the plain lookup (an array holding a known verb) | `guard-refusals` | `FAIL refused: a step verb that is an array holding a known verb (want exit 3 and 'scenarios[0].steps[0].do is not a known step verb'; got exit 2, 1 stderr lines: ui-verify: run <id>)` |
| F4 | ancestor walk of the install-root check disabled | `doctor-and-skip` | `FAIL doctor: an install root whose parent directory is group-writable and not sticky is not used, state 'NOT READY: install root not trusted: a parent directory is writable by group or others and is not sticky' (exit 0)`, and the matching `run:` line |
| F4 | kill and scan match the run id alone, not the browser path | `leftover-browser-killed` | `FAIL a bystander whose command line holds only the run id (no browser path) is still alive after the run (pid <pid>)`, and `FAIL the bystander is not among the run's recorded pids` |
| F4 | `2001::/32` and `64:ff9b:1::/48` removed from the private list | `guard-refusals` | `FAIL refused: an allowed private-range address [2001::] (want exit 3 and '...'; got exit 2, 1 stderr lines: ui-verify: run <id>)`, the same for `[64:ff9b:1::]` and the two upper edges (4 FAIL lines) |
| F4 | `100::/64` removed from the private list | `guard-refusals` | `FAIL refused: an allowed private-range address [100::] (want exit 3 and '...'; got exit 2 ...)`, and the same for `[100::ffff:ffff:ffff:ffff]` |
| F4 | SIGHUP handler removed | `signal-during-launch` | `FAIL SIGHUP is handled like SIGTERM: the runner reports it and ends with exit 129 (exit 129)` (the default kill also gives 129, so the check reads the report line too), and `FAIL the browser's temporary home is removed after SIGHUP too` |
| F4 | removal of the temporary home on a signal exit disabled | `signal-during-launch` | `FAIL the browser's temporary home is removed after a signal exit`, and the same after SIGHUP |

The one green row is the control that proves the pin is the layer that blocks an off-list name: with the pin kept, removing the request route alone leaves the listener at 0 hits.

## Live dispatch

The real agent definition, with its real tool grant, driven by a real model, three times. Setup, the same for all three:

- Working directory: a fresh `mktemp -d` under `/tmp`, outside any git work tree: `/tmp/ui-verify-live.eum5PO`. The agent file was copied to `.claude/agents/ui-acceptance-verifier.md` inside it. The scenario files, the briefs, the out directories and the stream logs all live there. None of it is copied into the repo.
- Fixture: `tests/fixtures/ui-verify/serve.mjs` from the kit checkout, started in the background, stopped by PID afterwards. The preview URL was its loopback port (`http://127.0.0.1:64823/`).
- The runner is the kit checkout copy, called from the working directory (a checkout copy refuses to run from inside its own work tree). `<kit checkout>` below stands for its absolute path.
- Session command, one dispatch at a time, each bounded by `gtimeout 600`:

```
cd /tmp/ui-verify-live.eum5PO && claude -p "<lead prompt>" --model sonnet --output-format stream-json --verbose --permission-mode dontAsk --allowedTools "Agent" "Read" "Grep" "Glob" "Bash(node */lib/ui-verify/run.mjs*)" --max-budget-usd 3
```

- Claude Code 2.1.332 has no `--max-turns` flag, so `--max-budget-usd 3` and the shell timeout are the bounds. `--permission-mode dontAsk` denies anything not on the allow list, and no mode that skips permission checks was used. The allow list is the agent's own grant plus `Agent` so the session can dispatch it.
- Model: `sonnet` (the stream's init event names `claude-sonnet-5-5`), for the lead session and for the subagent (`model: sonnet` in its frontmatter).
- Lead prompt: `Dispatch the subagent ui-acceptance-verifier once with exactly this brief, then print its final reply verbatim and nothing else.` followed by the brief.
- Scenario: the shape of the suite's `rows-and-planted-bug` file. AC-1 has a criterion and a named negative (an expired link), AC-2 is the Save button, AC-3 is the heading, URL and `within` check. `viewports` `[1280]`, `allow_loopback` true, `head_sha` the kit HEAD at the time (masked below). A first run of the runner on scenario (a) from the same directory, before any dispatch, exited 0 with four PASS rows.
- The verdict block is read from the subagent's reply as the stream's `Agent` tool result carries it. The lead session's own last message did not reproduce it verbatim (a user-level instruction file loaded in the session changed that message), so the stream's tool result is the source, and the `.jsonl` files stay in the working directory.

### (a) Three criteria, all passing

Brief (the head SHA is masked here and was full length in the real brief):

```
## Target
- Path: /tmp/ui-verify-live.eum5PO (scratch working directory, no repository)
- Branch: fixture-live-a

Head SHA: 74953992…99062a62
Preview URL: http://127.0.0.1:64823/
Scenario file: /tmp/ui-verify-live.eum5PO/a.json
Scenario hash (first 16 hex of SHA-256): cf92577f3d6ed8c2
Out dir: /tmp/ui-verify-live.eum5PO/out-a
Runner path: <kit checkout>/lib/ui-verify/run.mjs
Baseline: none recorded (live dispatch proof)

Acceptance criteria (source: this brief):
AC-1. Given the fixture app home page, when a user types a display name and clicks Save, then the page shows "Saved". Negative case: given an expired link (/?link=expired), then the page shows "This link has expired" and does not show "Saved".
AC-2. Given the page /, when a user clicks Save, then the page shows "Saved".
AC-3. Given the home page at /, then the heading "Kit fixture app" is shown and the path is /.
```

Subagent tool calls, from the stream: `Read` (the scenario), `Grep` and `Read` (the README), `Bash`, `Read` (`result.json`). The `Bash` command:

```
node <kit checkout>/lib/ui-verify/run.mjs scenario --scenario /tmp/ui-verify-live.eum5PO/a.json --out /tmp/ui-verify-live.eum5PO/out-a
```

Runner exit: 0. The agent's reply, verbatim apart from the dropped user-level sign-off line:

```
### UI acceptance: fixture-live-a
Head: 74953992…99062a62   Preview: http://127.0.0.1:64823/   Preview identity: unverified   Playwright: 1.65.1
Runner result: PASS   Counts: 4 PASS, 0 FAIL, 0 NO-CHECK
Agent-added rows: 0 NO-CHECK

VERDICT: PASS
Acceptance criteria met: 3/3
Verification record:
- Command: `node <kit checkout>/lib/ui-verify/run.mjs scenario --scenario /tmp/ui-verify-live.eum5PO/a.json --out /tmp/ui-verify-live.eum5PO/out-a`
- Exit: 0
- Output (excerpt): the counts line and row lines; the runner printed no `observed` lines.

ui-verify: counts PASS 4 FAIL 0 NO-CHECK 0 runner-verdict PASS
row AC-1 | PASS |  | ac-1-1280-after-save.png
row AC-1 neg | PASS |  | ac-1-neg-1280-refused.png
row AC-2 | PASS |  | ac-2-1280-saved.png
row AC-3 | PASS |  | ac-3-1280-home.png

Notes:
- Preview identity: it is `unverified`, so the runner could not tell which build the preview serves. A stale preview can still pass.
- Coverage: I found no gaps. AC-1, AC-2 and AC-3 each have a criterion entry, and the one named negative case (AC-1, expired link) has a negative entry. Each `expect` matches its criterion's wording.
- Brief against file: the head SHA, preview URL and scenario hash `cf92577f3d6ed8c2` agree with `result.json`.
- Limits of the proof: only the 1280 width ran. AC-1 and AC-2 do not check that "Saved" is absent before the click. The AC-1 negative case checks the expired page as loaded and does not click Save, which its wording does not require.
- Run health: no row is flaky, `blocked_requests` is empty and `blocked_requests_truncated` is false.
- Artifacts: I wrote no files myself. The runner's out dir is `/tmp/ui-verify-live.eum5PO/out-a`, holding `result.json` and the four screenshots named above, which I did not open.
- Read next: `/tmp/ui-verify-live.eum5PO/out-a/result.json:18-24` (verdict and counts).
```

The three replies are re-laid-out here: the agent's inner code fence is dropped (its excerpt lines show inline) and the bold markers are removed. Every other word, row line and number is the agent's text.

### (b) The planted-bug page

Brief: the same as (a) with `Branch: fixture-live-b`, scenario `b.json`, hash `199b0d34e25da72a`, out dir `out-b`, and AC-2 stated for the page `/?bug=1`. The scenario differs from (a) only in the AC-2 `goto` path, `/?bug=1`.

```
AC-2. Given the page /?bug=1, when a user clicks Save, then the page shows "Saved".
```

Subagent tool calls: `Read`, `Grep`, `Grep`, `Bash`, `Read`. The `Bash` command:

```
node <kit checkout>/lib/ui-verify/run.mjs scenario --scenario /tmp/ui-verify-live.eum5PO/b.json --out /tmp/ui-verify-live.eum5PO/out-b
```

Runner exit: 1. The agent's reply:

```
### UI acceptance: fixture-live-b
Head: 74953992…99062a62   Preview: http://127.0.0.1:64823/   Preview identity: unverified   Playwright: 1.65.1
Runner result: FAIL   Counts: 3 PASS, 1 FAIL, 0 NO-CHECK
Agent-added rows: 0 NO-CHECK

VERDICT: FAIL:fixable
Acceptance criteria met: 2/3
Verification record:
- Command: `node <kit checkout>/lib/ui-verify/run.mjs scenario --scenario /tmp/ui-verify-live.eum5PO/b.json --out /tmp/ui-verify-live.eum5PO/out-b`
- Exit: 1
- Output (excerpt):

ui-verify: counts PASS 3 FAIL 1 NO-CHECK 0 runner-verdict FAIL
row AC-1 | PASS |  | ac-1-1280-after-save.png
row AC-1 neg | PASS |  | ac-1-neg-1280-refused.png
row AC-2 | FAIL |  |
row AC-3 | PASS |  | ac-3-1280-home.png
observed AC-2: Error 500

Notes:
- Finding, AC-2 (FAIL): on `/?bug=1`, after the Save click, the runner observed `Error 500`. The criterion requires the page to show "Saved". The row has `flaky: false` and no evidence file.
- Preview identity is `unverified`: the runner could not tell which build the preview serves, so a stale preview could pass.
- Coverage: no gaps or weak assertions found. AC-1 (criterion and negative case), AC-2 and AC-3 each have a matching entry.
- Brief match: head SHA, URL and scenario hash (`199b0d34e25da72a`) agree across the brief, the scenario file and `result.json`.
- Scope: only the 1280 viewport was run. Tokens, layout, pixels and accessibility were not checked.
- Network: `blocked_requests` is empty and `blocked_requests_truncated` is false.
- Runner path: it is the kit checkout copy listed in the README, outside the Target path.
- Artifacts: I wrote no files myself. The runner's out dir is `/tmp/ui-verify-live.eum5PO/out-b`, holding `result.json` and the three screenshots named above (not read).
- Read next: `/tmp/ui-verify-live.eum5PO/out-b/result.json:62` (AC-2 row) and `/tmp/ui-verify-live.eum5PO/b.json:1` (scenario).
```

The finding names the row, the observed value (`Error 500`) and the criterion it contradicts, and guesses no code fix.

### (c) One criterion left out of the scenario

Brief: the same as (a) with `Branch: fixture-live-c`, scenario `c.json` (the scenario of (a) with both AC-3 entries removed), hash `da97ddf693d47f4b`, out dir `out-c`. The acceptance criteria text still lists AC-1, AC-2 and AC-3.

Subagent tool calls: `Read`, `Read`, `Bash`, `Read`. The `Bash` command:

```
node <kit checkout>/lib/ui-verify/run.mjs scenario --scenario /tmp/ui-verify-live.eum5PO/c.json --out /tmp/ui-verify-live.eum5PO/out-c
```

Runner exit: 0. The agent's reply:

```
### UI acceptance: fixture-live-c
Head: 74953992…99062a62   Preview: http://127.0.0.1:64823/   Preview identity: unverified   Playwright: 1.65.1
Runner result: PASS   Counts: 3 PASS, 0 FAIL, 0 NO-CHECK
Agent-added rows: 1 NO-CHECK

VERDICT: FAIL:escalate
Acceptance criteria met: 2/3
Verification record:
- Command: `node <kit checkout>/lib/ui-verify/run.mjs scenario --scenario /tmp/ui-verify-live.eum5PO/c.json --out /tmp/ui-verify-live.eum5PO/out-c`
- Exit: 0
- Output (excerpt):

ui-verify: counts PASS 3 FAIL 0 NO-CHECK 0 runner-verdict PASS
row AC-1 | PASS |  | ac-1-1280-after-save.png
row AC-1 neg | PASS |  | ac-1-neg-1280-refused.png
row AC-2 | PASS |  | ac-2-1280-saved.png
(no observed lines printed)

Notes:
- Agent-added row: `NO-CHECK: scenario does not cover AC-3`. The scenario file has no `criterion` or `skip` entry for AC-3, so nothing asserted that the heading "Kit fixture app" is shown or that the path is `/`. The file's `ready.text` is "Kit fixture app", but that is not an AC-3 row and does not count as coverage.
- Next step for the lead: add an AC-3 entry that asserts both the heading text and `expect_url` `/`, recompute the scenario hash, and re-dispatch with a fresh out dir.
- Preview identity is `unverified`: the runner could not tell which build the preview serves, so a stale preview can still pass.
- The brief matches the file and `result.json` on head SHA, preview URL and scenario hash (`da97ddf693d47f4b`).
- Observation, no row added: the AC-1 and AC-2 entries do not assert that "Saved" is absent before the click. The criteria do not require it.
- No flaky rows. `blocked_requests` is empty and `blocked_requests_truncated` is false. The scenario ran at width 1280 only.
- Artifacts: I wrote no files myself. The runner wrote `result.json` and the screenshots (not opened) to `/tmp/ui-verify-live.eum5PO/out-c`.
- Read next: `/tmp/ui-verify-live.eum5PO/c.json:1` (scenario entries), `/tmp/ui-verify-live.eum5PO/out-c/result.json:25` (runner rows).
```

The runner passed every row it had, and the agent still refused a PASS because AC-3 had no entry. The runner's own rows were not changed.

## Lines the live-record case checks

The suite case `live-record` greps this file for these lines. Each is true for the runs above. The Tools line is the agent frontmatter grant; the calls actually seen in the three streams were `Read`, `Grep` and the one runner `Bash` command per dispatch, and none of them was `Write`, `Edit` or `npx`. The runtime's own summary line for (a) and (b) also listed `advisor`, a tool the harness adds to subagents. It is not in the agent's grant and has no file or shell access.

```
Working directory: /tmp/ui-verify-live.eum5PO
Tools: Read, Grep, Glob, Bash(node */lib/ui-verify/run.mjs*)
Playwright: 1.65.1
Runner exit codes: a 0, b 1, c 0. Suite run: 0 skipped.
VERDICT: PASS
VERDICT: FAIL:fixable the AC-2 row observed Error 500
VERDICT: FAIL:escalate NO-CHECK: scenario does not cover AC-3
No evidence was uploaded or committed. Screenshots, result.json files and stream logs stayed in the working directory.
```

## Reproduce

A skeptic with this checkout:

```bash
node lib/ui-verify/run.mjs --doctor
# not ready: run the one install command it prints (about 3 minutes, about 600 MB), then run --doctor again
UI_VERIFY_REQUIRE=1 bash tests/test-ui-acceptance-verifier.sh
```

The second command turns every SKIP into a FAIL, so a clean exit means no case was skipped.

To redo one live dispatch:

1. `W=$(mktemp -d /tmp/ui-verify-live.XXXXXX)` and copy `agents/ui-acceptance-verifier.md` to `$W/.claude/agents/`.
2. Start `node tests/fixtures/ui-verify/serve.mjs` in the background and read its `port` line.
3. Write a scenario file into `$W` per `## Writing a scenario` in `lib/ui-verify/README.md` (the spec's `scenario.json` rules), with `allow_loopback` true, `viewports` `[1280]` and the fixture's port in `target.url`.
4. Compute the hash: `shasum -a 256 $W/a.json | cut -c1-16`. Run the runner once yourself from `$W` to see the scenario accepted: `node <kit checkout>/lib/ui-verify/run.mjs scenario --scenario $W/a.json --out $W/out-probe`.
5. Build the brief as `## Input` in the agent file lists it and run the session command shown under `## Live dispatch`, from `$W`, with the brief after the lead prompt.
6. Read the `Agent` tool result in the stream JSON. Stop the fixture by its PID.

## Observations

Two things the guards do not cover, measured in the real browser by case `observed-residuals` (Playwright 1.65.1, headless Chromium on macOS). The case asserts only that each page settled; the counts print as NOTE lines.

- Worker WebSocket: a dedicated worker, started by `worker.html`, opened a WebSocket to the other port of the allowed host. The second listener counted 2 upgrades for the run's 2 page loads (the preflight and the scenario step), `blocked_requests` was empty, so the WebSocket guard did not see it. Playwright adds its WebSocket route to each page as an init script, which a worker does not run, and offers no context-level hook for workers, so it is not closed. It is a residual in the README, the spec and the agent notes.
- 307 hop: `post-hop.html` POSTed `{"hop":1}` to `/redirect-307` on the allowed target, which answered 307 to the other port of the same allowed host. The second listener counted 2 hits for the 2 page loads, each a POST with the body `{"hop":1}` (0 GET), and `blocked_requests` was empty, so the route handler did not see the hop. A 307 or 308 keeps the method and the body.

## Limits

- The consumer is the kit's own fixture on loopback, not a real preview. No real pull request, no CDN preview and no app behind a login was checked. `Preview identity` was `unverified` in all three dispatches, because the fixture sent no build id.
- One model ran each side: `sonnet` for the lead session and for the subagent, once per scenario. Three runs do not show the agent is stable. The other rows of the agent's seven-row mapping table (exit 2 with no FAIL, exit 3, exit 4, a FAIL beside a NO-CHECK row) were not run live. The agent file is checked for structure by the suite only.
- The lead session's own last message did not repeat the agent's reply verbatim. The verdicts come from the stream's `Agent` tool result. The agent's replies also ended with a user-level sign-off line that is not part of the contract and is dropped above.
- The runtime listed `advisor` among the tools a subagent used in (a) and (b). It is a harness tool outside the grant. The stream carries no call to it as a `tool_use` block, so only its name is recorded.
- The session allow list is a prefix filter, as the agent file's grant residual says. This proof shows the agent used the one command form, not that the grant could not be abused.
- DNS rebinding is proven by the recorded launch arguments only (`--host-resolver-rules`), because the suite has no controllable DNS.
- A hostile page that detects an automated browser can show it other content. A PASS proves what the page showed the runner.
- Linux was not run. The browser's minimal environment and `--no-proxy-server` were checked on macOS only.
- Fix round F4 controls were run by hand on temp copies of the runner and are copied from the shell, not from a notes table.
- Fix round F2 controls were each seen red by hand, and the notes recorded no per-mutation table for them.
- No dispatch needed a rerun, so there is no rerun to disclose.

## Test plan coverage

| Test plan rows | Where each ran |
|---|---|
| Every row marked `mechanical`, except row 47 | The suite case the row names in the spec's Test plan table. Every case ran in the green run (0 skipped). |
| 44, 45, 46 (`behavioral`) | The three live dispatches (a), (b) and (c) above. |
| 47 | The suite case `live-record`, which reads this file. |

No row is skipped. Rows that state a hand mutation as their control ran that mutation once on a copy of the runner outside any git work tree; the red lines are in the negative controls table.

## Outcome

The verdict lines in the live dispatch section are the agent's own output under test; two of them are FAIL by design (the planted bug and the uncovered criterion). The outcome of this proof is the suite run on the final tree, after the last fix pass and the merge with master:

```
Command: bash tests/test-ui-acceptance-verifier.sh
Exit: 0
Output:
  test-ui-acceptance-verifier: 469 passed, 0 failed, 0 skipped
Verdict: PASS
```
