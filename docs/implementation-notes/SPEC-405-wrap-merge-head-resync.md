# Implementation notes: SPEC-405 wrap merge head resync

This file records only where the build differs from the spec. Anything not listed here matches the spec.

## Deviations

| Spec says | Build does | Why |
|---|---|---|
| One helper. The trap is armed at step 3 and the caller's handlers are restored on every return. | `_pr_head_resync` is a wrapper: it saves INT, TERM, HUP and PIPE, arms the trap, runs `_pr_head_resync_body`, and restores the handlers once. The body uses plain returns. | Architecture review: one restore point instead of one at every exit. It also closes the gap where a set flag was dropped at the trap clear. |
| Arm the trap at step 3. The handler always reads `state` once. | The trap is armed at helper entry. `_RS_CLOSING` is set just before the last pre-close check. A signal before that point prints `INTERRUPTED inside the resync of #N before the close; nothing changed on GitHub` and makes no network call. | Round 3 MUST 1 needs a signal window a test can reach (the step 1 read). Before the close there is nothing to undo. |
| The flag is checked before the close. | Three checks come before the close: after the step 1 read, after the step 2 read, and right after `_RS_CLOSING=1`. AC-24's control removes all three. | Architecture review: no `ls-remote` call and no false "closing and reopening" line after a Ctrl-C in step 1. |
| (not in spec) | After any interrupt with the close under way and no reopen on record, the wrapper reads state once more and reopens only on exactly `CLOSED`. | Security review, medium: a signal can land after the last check and before `gh pr close` starts. The handler then reads OPEN, the close still runs, and the PR would stay closed. Case `#117` covers it, and AC-25 is its control. |
| The handler has one outcome line for a failed reopen and no retry. | `could not reopen #N after the interrupt; reopen it: gh pr reopen N --repo <url>`. The wrapper's late read gives a second reopen try on `CLOSED` (case `#113` sees 2 reopens). | The command sits on the outcome line itself, so it survives any reordering. |
| Step 1 checks `state`, `isDraft`, `autoMergeRequest` and `headRefOid`. | It also requires `isCrossRepository` to be exactly `false` (`no resync for #N: a fork PR or unreadable`). | Security review, low: `land` and `carry` already refuse fork PRs, and `_open_own_prs` does not. |
| The comment is posted at step 7, after the trap clear. | The body stores the comment text. The wrapper posts it after restoring the handlers, and only when no interrupt was seen. The two-reopens FAILED line prints inside the body, while the trap still stands. | Security review, low: no late signal can drop the recovery command. |
| Printed `--repo <url>` | `_url_public` strips userinfo, greedy up to the last `@` before the first `/`. | Round 3 MUST 6. Security review, low: a raw `@` inside a password must not survive. |
| `no resync for #N: state <s>` | A missing or unknown state prints `state unreadable`. Only `CLOSED` and `MERGED` are echoed as they are. `headRefOid` must be 40 lowercase hex before it is echoed. | Round 3 note R1. |
| The failure comment names `<branch>`. | The comment has no branch name. The re-push hint is on the stderr FAILED line only. | Round 3 MUST 6. |
| TASK-A2: `GH_STUB_CLOSE_DELAY`, a background run, a marker wait | The stub sends TERM itself: `GH_STUB_CLOSE_KILL=1` and `GH_STUB_VIEW_KILL_<n>_<k>=1`, aimed at `GH_STUB_KILL_PIDFILE`. The spec's AC-18 and AC-22 rows still name the delay form. | The test is deterministic, with no sleep and no race. bash defers the handler until the stub returns, which matches the timing the spec describes. |
| AC rows | Added cases: `#110` interrupt in the step 1 read (AC-24); `#111`, `#112`, `#113` handler OPEN, unreadable, and failed reopen (AC-28); `#114` failed comment (AC-32); `#115` interrupt in a failed close's state read; `#116` the `--pr` form; `#117` late recheck (AC-25); `#118` moved head (AC-27); `#119` failed step 1 read; `#121` fork (AC-26); `#122` origin lost the ref. A unit block covers trap restore (AC-31), the flag reset (AC-30) and `_url_public` (AC-29). Refusal cases now assert their exit code, and stderr is kept separate from stdout. | Round 3 MUST 1, plus the test-coverage review. |

## Round 3 warnings

MUST, all built:

1. Flag check before `gh pr close`: built, plus the two earlier checks above. It is covered by `#110` and controlled by AC-24.
2. AC-22's control asserts the read count. `#109` asserts that `rs_reads 109` is 6, and the mutant makes a 7th read.
3. Fixtures:
   - Every `_5` fixture is `rs_json`, the full old-tip answer, with exactly one jq edit.
   - `#95` and `#103` each carry a `_REOPENED` answer.
   - Dependent `#99` is based on `feat/union`, so it is neither eligible nor CONFLICTING.
4. The flag is reset at helper entry. The unit block and AC-30 cover it.
5. The handler ignores PIPE, and the wrapper restores the caller's PIPE handler.
6. The comment carries no string derived from the PR. Userinfo is stripped from every printed URL, covered by the unit block and AC-29.

NOTE ONLY, with what I did about each:

- **One confirming read after a failed close reads OPEN.** Not adopted. OPEN is GitHub's answer after the close call returned. A late landing would need a delayed second state change, which the spec does not model.
- **A final state read before the two-reopens FAILED line.** Not adopted. The line asks for a reopen, and `gh pr reopen` on an open PR fails harmlessly.
- **rc 1 wording and line ownership.** Matches the code. `cmd_merge` prints `dependents open` and the still-stale SKIP. The helper prints everything else.
- **Soften the `land` reuse claim.** The code makes no such claim. The FAILED lines say `FAILED merge`.
- **Validate oids and state before echoing.** Adopted.
- **No timeout on the handler's `gh` calls.** Not adopted. wrap wraps no `gh` call in a timeout, and `_mvp_trap`'s `ls-remote` has the same shape. While the handler runs, only SIGKILL stops a hung `gh`.
- **Capture D3 mutant output to files.** Adopted. The negctl log is in the proof.
- **Worst case about 135s, above 120s.** Adopted. The `commands/wrap.md` sentence names it.

## Code review (security, architecture, test-coverage lenses)

| Finding | Lens, severity | Disposition |
|---|---|---|
| A signal after the last check and before the close spawns can leave the PR closed | security, medium | Fixed: wrapper late read, `#117`, AC-25 |
| A set flag dropped at the trap clear | security low, architecture medium | Fixed by the wrapper and body split |
| Restore enforced by convention at many exits | architecture, medium | Fixed by the wrapper and body split |
| FAILED line printed after the restore | security, low | Fixed: it prints in the body, under the trap |
| Fork PR not excluded | security, low | Fixed: `isCrossRepository`, `#121`, AC-26 |
| Userinfo strip stops at the first `@` | security, low | Fixed: greedy strip, unit block |
| A human's close in the read-to-close gap gets reopened | security, low | Accepted. This is spec Edge 3. GitHub gives no way to tell the two closes apart in that window. |
| Handler `gh` calls can hang | security, low | Accepted (see the NOTE ONLY list above) |
| Close fires workflows and notifications | security, low | Documented in `commands/wrap.md` and `docs/CHANGELOG.md` |
| An interrupt in steps 1 to 2 still calls `ls-remote` | architecture, low | Fixed: flag checks after steps 1 and 2 |
| The dependents `awk` is now in four places | architecture, low | Not done. Extracting `_has_dependents` would refactor three existing call sites outside this change. It is left as a follow-up. |
| Name `lines` | architecture, low | Fixed: renamed to `tips` |
| No test for the handler's non-CLOSED outcomes | test-coverage, high | Fixed: `#111`, `#112`, `#113`, AC-28 |
| No test for userinfo stripping | test-coverage, high | Fixed: unit block, AC-29. An end-to-end case is impossible because `git remote get-url` expands `insteadOf`. |
| No test for the moved-head guard | test-coverage, high | Fixed: `#118`, `#119`, AC-27 |
| No test for the comment-failure line | test-coverage, medium | Fixed: `#114`, AC-32 |
| Flag reset, trap restore and loop interrupts have no test | test-coverage, medium | Fixed: unit block (AC-30, AC-31) and `#115` |
| No test for the `--pr` form | test-coverage, medium | Fixed: `#116` |
| No assertion on which stream a line goes to | test-coverage, medium | Fixed: stderr is captured apart; `#101` and `#104` assert it |
| Weak AC-13 pins | test-coverage, low | Accepted as defense in depth. `#118` now pins the moved-head refusal directly. |
| Refusal cases do not check the exit code | test-coverage, low | Fixed: `rs_untouched` asserts it |
| The spec table names the delay form | test-coverage, low | Recorded in the Deviations table above |

## Other

- `docs/FEATURES.md` was regenerated with `feature-registry.sh check --fix`, because the new spec moved its counts.
- The spec id was dropped from the helper comment, because `test-no-scattered-ids` forbids ids in `lib/`.
- `docs/CHANGELOG.md` has an `Added` entry under Unreleased.
