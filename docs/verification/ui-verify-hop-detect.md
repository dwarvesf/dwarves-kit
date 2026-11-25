# Verification -- ui-verify-hop-detect

Two security findings in the ui-verify runner (`lib/ui-verify/run.mjs`), fixed and proven against the real browser (Playwright 1.65.1, headless Chromium, macOS). Suite: `tests/test-ui-acceptance-verifier.sh`; spec: `docs/specs/SPEC-292-ui-acceptance-verifier.md`.

1. A redirect hop from an allowed origin to another port of the same allowed host was not seen by the runner (the route handler is not called for a hop), so a page's POST and body could be delivered there with nothing in `result.json`. The runner now listens with `context.on('request', ...)` and checks every request whose `redirectedFrom()` is set with the same host and port rule as the guards. A hop that fails it is counted in `blocked_requests` as `<host>:<port>` and makes the row of the scenario that was running NO-CHECK `redirected off an allowed host`. Honest limit: this is detection, not prevention. The hop request is still sent once before the runner can react; only the verdict is held.
2. The install-root trust check covered the root, its ancestors and `node_modules/playwright`, but the runner imports `playwright-core` and the rest of the package trees. The check now walks everything under `<root>/node_modules` and `<root>/browsers` recursively and runs again immediately before the `import()`, through one shared function that `--doctor` uses too. A review then found five gaps, fixed here: a hop after the last asserting step still ended PASS; an entry that could not be inspected was skipped; a FIFO, socket or device was accepted; `browsers` was not walked; and the path in the trust reason was only cleaned of line breaks.

| Check | Result |
|---|---|
| The `request` event fires for the hop of a sub-resource `fetch` POST, with `redirectedFrom()` set | yes; the hop keeps the method POST |
| The `request` event fires for a top-level navigation hop, with `redirectedFrom()` set | yes |
| 307 POST hop to the other port of the allowed host (`observed-residuals`) | exit 2, row NO-CHECK `redirected off an allowed host`, `blocked_requests` holds `127.0.0.1:<port>`, verdict not PASS; the listener still received one POST with its body |
| Scenario after the hop scenario, in its own context | PASS (attribution is the attempt: one scenario at one viewport in a fresh context) |
| Hop row beside a plain FAIL row | exit 1, verdict FAIL, hop row stays NO-CHECK |
| Top-level hop to another port (`offsite-request-aborted`, `/redirect-port`) | row NO-CHECK, `blocked_requests` holds `127.0.0.1:<port>` |
| Group-writable `node_modules`, `node_modules/playwright-core`, one file deep in `node_modules/playwright-core/lib` | refused by the runner and by `--doctor` with `install root not trusted: <relative path> is writable by group or others` |
| Link inside `node_modules` that points outside the root, a dangling link, a link to a file under the root but outside `node_modules` | refused with `is a link that leaves node_modules` or `is a link that cannot be resolved` |
| Link inside `node_modules` that resolves inside `node_modules` | not refused |
| Hop that arrives after the last asserting step (steps `expect_text`, `screenshot`; the 307 answer delayed 800 ms) | row NO-CHECK `redirected off an allowed host`, `blocked_requests` holds `127.0.0.1:<port>` |
| FIFO under `node_modules`; directory the user cannot read (mode 000); group-writable file under `browsers` | refused: `is not a file, a directory or a link`, `cannot be read`, `is writable by group or others`; by `--doctor` (exit 20) and by a run (exit 2) |
| File name with a backtick and a pipe under `node_modules` | the reason and the doctor state line show an apostrophe and a slash, neither character |
| SharedWorker POST to a path answering 307 to the other port | observed only: the listener received an OPTIONS request, `blocked_requests` empty, row PASS (not detected) |
| Early check cut out of a runner copy | the check before the import still refuses (`doctor-and-skip`) |
| Real install root, `node lib/ui-verify/run.mjs --doctor` | `state:         READY` |
| Cost of the walk on the real install root, both trees | about 930 entries (about 220 under `node_modules`, the rest under `browsers`), about 15 ms warm and about 140 ms cold, so both trees are walked in full (the 500 ms ceiling for a narrower rule was not reached) |

## Green run

The whole suite once on the final tree, with the real install and `UI_VERIFY_REQUIRE=1` (a skip would count as a failure):

```
Command: UI_VERIFY_REQUIRE=1 bash tests/test-ui-acceptance-verifier.sh
Exit: 0
Output:
  test-ui-acceptance-verifier: 500 passed, 0 failed, 0 skipped
Verdict: PASS
```

## Negative control

Each control is a hand-edited copy of the runner next to a copy of `package.json`, outside any git work tree, passed to the suite as `UI_VERIFY_RUNNER` with `UI_VERIFY_HOME` set to the real install. The listed lines are the `FAIL` lines the suite printed, shortened where marked.

The hop listener removed (the condition of the `request` handler replaced by `false`):

```
Command: UI_VERIFY_HOME=<install root> UI_VERIFY_RUNNER=<copy>/run.mjs bash tests/test-ui-acceptance-verifier.sh observed-residuals offsite-request-aborted
Exit: 1
Output:
  FAIL  blocked_requests names the allowed host with the other port for the top-level redirect hop
  FAIL  a page that POSTs to a path answering 307 to another port of the allowed host exits 2 (exit 0)
  FAIL  its row is NO-CHECK 'redirected off an allowed host', blocked_requests holds 127.0.0.1:<port> and the verdict is not PASS
  FAIL  with a FAIL row beside the hop row the exit is 1 and the verdict FAIL, the hop row staying NO-CHECK (exit 1)
  FAIL  control: the hop listener is no longer in the runner
  test-ui-acceptance-verifier: 27 passed, 5 failed, 0 skipped
Result: RED as expected
```

The hop row is PASS on that copy (exit 0), which is the bug. The last FAIL line is the suite noticing that its own copy no longer holds the listener text it edits.

The recursive walk removed (the last line of the trust function replaced by `return ''`):

```
Command: UI_VERIFY_HOME=<install root> UI_VERIFY_RUNNER=<copy>/run.mjs bash tests/test-ui-acceptance-verifier.sh doctor-and-skip
Exit: 1
Output:
  FAIL  doctor: an install root whose node_modules/playwright is group-writable is not used ...
  FAIL  doctor: an install root whose node_modules is group-writable is not used ...
  FAIL  doctor: an install root whose node_modules/playwright-core is group-writable is not used ...
  FAIL  doctor: an install root with one group-writable file deep inside node_modules/playwright-core/lib is not used ...
  FAIL  doctor: an install root with a link inside node_modules that points outside the root is not used ...
  FAIL  run: the same installs are not refused by a scenario run (one line each, shortened)
  FAIL  run: with the early check cut out, the check before the import still refuses a group-writable playwright-core
  test-ui-acceptance-verifier: 47 passed, 15 failed, 0 skipped
Result: RED as expected
```

A dangling link no longer refused (the unresolved-link fault replaced by an empty reason), and the link target compared with the root's parent instead of `node_modules`:

```
Command: UI_VERIFY_HOME=<install root> UI_VERIFY_RUNNER=<copy>/run.mjs bash tests/test-ui-acceptance-verifier.sh doctor-and-skip
Exit: 1
Output:
  dangling copy:  FAIL doctor and FAIL run for 'an install root with a dangling link inside node_modules'
                  test-ui-acceptance-verifier: 60 passed, 2 failed, 0 skipped
  outside-node_modules copy:  FAIL doctor and FAIL run for 'a link inside node_modules to a file under the root but outside node_modules'
                  test-ui-acceptance-verifier: 60 passed, 2 failed, 0 skipped
Result: RED as expected
```

Each fix from the review, one runner copy per defect, run against `doctor-and-skip` (or `observed-residuals` for the first):

```
Command: UI_VERIFY_HOME=<install root> UI_VERIFY_RUNNER=<copy>/run.mjs bash tests/test-ui-acceptance-verifier.sh <case>
Exit: 1
Output:
  final check after the last step removed (observed-residuals):
    FAIL  a hop that arrives after the last asserting step (steps expect_text, screenshot; the 307 answer is delayed 800 ms) still ends the row NO-CHECK 'redirected off an allowed host' (exit 0)
    test-ui-acceptance-verifier: 6 passed, 2 failed, 0 skipped
  unreadable entry treated as empty (doctor-and-skip):
    FAIL  doctor and FAIL run for 'an install root with a directory inside node_modules that the user cannot read'
    test-ui-acceptance-verifier: 69 passed, 2 failed, 0 skipped
  special-entry fault removed (doctor-and-skip):
    FAIL  doctor and FAIL run for 'an install root with a FIFO inside node_modules'
    test-ui-acceptance-verifier: 69 passed, 2 failed, 0 skipped
  browsers not walked (doctor-and-skip):
    FAIL  doctor and FAIL run for 'an install root with a group-writable file inside browsers'
    test-ui-acceptance-verifier: 69 passed, 2 failed, 0 skipped
  path passed through the line cleaner only (doctor-and-skip):
    FAIL  doctor and FAIL run for the file whose name holds a backtick and a pipe, and FAIL 'the doctor state line for that file name holds no backtick and no pipe'
    test-ui-acceptance-verifier: 68 passed, 3 failed, 0 skipped
Result: RED as expected
```

The `lstat` failure fault (`cannot be inspected`) is a race between listing a directory and reading its entry. No file mode reaches it in a test: a directory the user cannot read fails at the listing (`cannot be read`), so that fault has no red line of its own.

## Reproduce

```
bash tests/test-ui-acceptance-verifier.sh observed-residuals offsite-request-aborted doctor-and-skip
node lib/ui-verify/run.mjs --doctor        # state: READY on a trusted install
```

To see a control red, copy `lib/ui-verify/run.mjs` and `package.json` to a directory outside the checkout, edit the copy as described above and run the suite with `UI_VERIFY_RUNNER` pointing at it.

## Limits

- The hop request is still sent once, with its method and body, before the runner can react. Only the verdict is held.
- The `request` event was observed for the two hop types above (a sub-resource POST hop and a top-level hop). A hop type that Chromium does not report through this event would not be seen.
- A hop is held to the scenario attempt in which it was seen. The end of an attempt waits (at most 1 s, inside the scenario and run clocks) for the requests the context already knows about, then checks again, so a slow redirect still in flight when the last step ends is held. A request that has not started when the attempt ends (a timer that has not fired) is not known: a hop that begins after the scenario's last step ends is outside the row.
- A hop made by a SharedWorker is not seen by the context `request` listener. Observed: the shared worker POSTed to a path answering 307 to the other port of the allowed host, the listener there received an OPTIONS request (no POST with a body), `blocked_requests` stayed empty and the row was PASS. This is a residual, recorded as a NOTE by `observed-residuals`.
- The trust walk covers `node_modules` and `browsers`; it does not read the root's other files.
- The trust walk does not hash anything: a file replaced by its owner is not noticed. Linux was not run.

Verdict: PASS
