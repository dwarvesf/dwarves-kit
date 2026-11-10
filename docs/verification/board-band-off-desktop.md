# Verification -- board-band-off-desktop

The board-pane band returns `next(e)` on the desktop surface, so it no longer draws above the prompt there and a row from a mod beneath still renders. Terminal, vscode and mobile keep the band.

## Green run
```
Command: claude plugin test integrations/claude-code/board-pane
Exit: 0
Output:
(pass) a survey takes the row, so the band steps aside [21.01ms]
(pass) on the desktop surface the band steps aside and a row from a mod beneath still renders [20.55ms]
(pass) the PR lookup is cached for five minutes across turns [32.72ms]
 57 pass
 0 fail
Ran 57 tests across 3 files. [0.81s]
Verdict: PASS
```

## Negative control
```
Command: claude plugin test integrations/claude-code/board-pane   (with `|| e.surface === 'desktop'` removed from hooks/register.tsx)
Exit: 1
Output:
(fail) on the desktop surface the band steps aside and a row from a mod beneath still renders [22.93ms]
 56 pass
 1 fail
Ran 57 tests across 3 files. [0.78s]
Verdict: PASS (the new test fails without the guard)
```
The guard was reverted, the new test went red, and `git checkout -- integrations/claude-code/board-pane/hooks/register.tsx` restored it; the green run above is after the restore.

## Not proven
- The real Claude desktop app was not driven; the test mounts the component on `surface: 'desktop'`.
- vscode and mobile are covered only by the guard comparing against `'desktop'` alone.
