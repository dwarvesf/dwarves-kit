# Verification -- context-budget absolute token thresholds

The context-budget hook now warns at 200k tokens of live context and escalates at 250k, whatever the window. It no longer guesses a window from a bare model id, which had made a larger-window session read 148k as a 74% ceiling and stop early.

| Claim | Evidence |
|---|---|
| Below 200k is silent, 200k warns once, 250k escalates once | Cases A.1 to A.6, green run below |
| A drop under 200k clears state, and the next crossing warns again | Cases A.7 and A.8 |
| The old false ceilings (148k, 154k on bare `claude-opus-5-5`) no longer fire | Cases B.1 and B.2 |
| `KIT_CTX_WINDOW` alone and a statusline window file do not change absolute mode | Cases B.3 and B.4 |
| Both notices print tokens and the threshold, never a percentage | Cases C.1 to C.4 |
| `KIT_CTX_WARN_TOKENS` / `KIT_CTX_STRONG_TOKENS` override; bad, zero or equal values fail open; leading zeros read as base 10 | Cases D.1 to D.7 |
| Explicit `KIT_CTX_STRONG_PCT=70` with `KIT_CTX_WINDOW=200000` restores the old ceiling at 148k | Case E.1 |
| Either `_PCT` variable alone switches modes; percent thresholds round up exactly as master compared | Cases E.2 to E.4 |
| Each battery-found gap is now pinned | Mutant run below |
| The legacy percent-of-window behavior still holds when a `_PCT` variable is set | Cases 1 to 9, unchanged assertions, run under `KIT_CTX_WARN_PCT=65 KIT_CTX_STRONG_PCT=70` |
| The new cases are sensitive to the bug, not vacuously green | Negative control below |

## Green run

```text
Command: bash tests/test-context-budget.sh
Exit: 0
Output:
== Case A: absolute token thresholds by default (bare opus id, no window file) ==
  PASS A.1 199999 silent                                  silent
  PASS A.2 200000 warns once                              speak
  PASS A.3 210k again, same threshold                     silent
  PASS A.4 249999 still under strong                      silent
  PASS A.5 250000 strong once                             speak
  PASS A.6 300k again, same threshold                     silent
  PASS A.7 drop under 200k clears state                   silent
  PASS A.8 re-cross 200k warns again                      speak
== Case B: the old false ceilings no longer fire ==
  PASS B.1 148k (old 74% ceiling) silent                  silent
  PASS B.2 154k (old 77% ceiling) silent                  silent
  PASS B.3 KIT_CTX_WINDOW alone keeps absolute mode, 148k silent silent
  PASS B.4 1M window file ignored in absolute mode, 200k warns speak
== Case C: messages print tokens, not a percentage ==
  PASS C.1 warn message                                   tokens, no %
  PASS C.2 strong message                                 tokens, no %
  PASS C.3 warn names the 200k budget                     has 200k budget
  PASS C.4 strong names the 250k ceiling                  has 250k ceiling
== Case D: token thresholds come from env, bad values fail open ==
  PASS D.1 120k with warn=100k speaks                     speak
  PASS D.2 warn >= strong fails open                      silent
  PASS D.3 non-numeric warn fails open                    silent
  PASS D.4 zero warn fails open                           silent
  PASS D.5 warn = strong fails open                       silent
  PASS D.6 STRONG_TOKENS=150000 at 160k escalates         has 150k ceiling
  PASS D.7 leading zeros read as base 10 (90k)            has 90k budget
== Case E: negative control, explicit percentage vars restore the old behavior ==
  PASS E.1 148k is 74% of 200k: old CEILING returns       has CONTEXT CEILING
  PASS E.2 WARN_PCT alone switches to pct mode: 140k speaks speak
  PASS E.3 pct rounds up: 65000 < 65% of 100001, silent   silent
  PASS E.4 pct rounds up: 65001 >= 65% of 100001, speaks  speak
...
Results: 53 passed, 0 failed
```

## Negative control: the new suite against master's hook

The master hook was copied into `hooks/` (it sources `../lib/config/data-path.sh` relatively) and the suite pointed at it; both temp copies were removed after the run.

```text
Command: HOOK_OVERRIDE=$PWD/hooks/.cb-master.sh bash tests/.tcb-nc.sh
Exit: 1
Output:
  FAIL A.1 199999 silent                                  expected=silent actual=speak
  FAIL A.2 200000 warns once                              expected=speak actual=silent
  FAIL A.5 250000 strong once                             expected=speak actual=silent
  FAIL A.7 drop under 200k clears state                   expected=silent actual=speak
  FAIL A.8 re-cross 200k warns again                      expected=speak actual=silent
  FAIL B.1 148k (old 74% ceiling) silent                  expected=silent actual=speak
  FAIL B.3 KIT_CTX_WINDOW alone keeps absolute mode, 148k silent expected=silent actual=speak
  FAIL B.4 1M window file ignored in absolute mode, 200k warns expected=speak actual=silent
  FAIL C.1 warn message                                   want tokens and no %
  FAIL C.2 strong message                                 want tokens and no %
  FAIL C.3 warn names the 200k budget                     missing 200k budget
  FAIL C.4 strong names the 250k ceiling                  missing 250k ceiling
  FAIL D.1 120k with warn=100k speaks                     expected=speak actual=silent
Results: 33 passed, 13 failed
```

B.1 is the field bug: master speaks at 148k on a bare `claude-opus-5-5` id. The legacy cases 1 to 9 and E.1 pass on master too, which shows the percentage mode kept its old behavior.

The negative control above ran at the first commit (46 cases). The 7 cases added after the battery are mode-agnostic or legacy cases; the mutant run below proves they bite.

## Mutant run: the battery's gaps

The battery's reviewer and probe found 6 hook mutants that passed the first 46 cases. Each one now fails the suite.

```text
Command: bash mutants.sh <worktree>   (scratch script: copies each mutant into hooks/, removes it after)
Exit: 0
Output:
strong-ignores-env:  FAIL D.5 ...; FAIL D.6 STRONG_TOKENS=150000 at 160k escalates missing 150k ceiling;Results: 51 passed, 2 failed;
mode-strong-only:  FAIL E.2 WARN_PCT alone switches to pct mode: 140k speaks expected=speak actual=silent; FAIL E.4 ...;Results: 51 passed, 2 failed;
round-down:  FAIL E.3 pct rounds up: 65000 < 65% of 100001, silent expected=silent actual=speak; FAIL E.4 ...;Results: 51 passed, 2 failed;
no-base10:  FAIL D.7 leading zeros read as base 10 (90k) missing 90k budget;Results: 52 passed, 1 failed;
zero-allowed:  FAIL D.4 zero warn fails open expected=silent actual=speak;Results: 52 passed, 1 failed;
equal-allowed:  FAIL D.5 warn = strong fails open expected=silent actual=speak;Results: 52 passed, 1 failed;
```

## Dotfiles sibling

No dotfiles change is owed. The personal hook left dotfiles when the kit took it over (`tieubao/dotfiles` commit `cd7a2e1`, PR #428); `home/dot_claude/modify_settings.json` keeps only a strip-only marker, and no live settings file or dotfiles source sets any `KIT_CTX_*` variable. One comment there (`modify_settings.json`, the `del(."KIT_CTX_WARN")` block) still says the hook runs at "65/70 percent defaults"; it is stale but changes no behavior.

## Known trade

A model whose real window is 200k can never reach 200k tokens of live context, so in default mode it gets no notice. That follows the operator's cost rule (retire a chat past about 250k). Set `KIT_CTX_WARN_PCT` / `KIT_CTX_STRONG_PCT` to keep percent-of-window notices on such a model.
