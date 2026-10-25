# Verification -- ship-gate-command-words

The ship gate engages on the command words of a ship step, not on prose. `gh pr new` (an alias of `gh pr create`) now engages. The words `gh pr create` or `gh pr new` inside the quotes of an inert command (`echo`, `printf`, `git commit`) no longer engage.

## Change

- Root cause: `ENGAGE_RE` matched `gh pr create` anywhere in the command code, with no notion of quoting, and did not list the alias.
- Fix: `hooks/ship-gate.sh` splits the regex into `GIT_RE` and `GH_RE` (`create|new`). The gh words are also read from `CMD_GH`, the code with inert quoted spans blanked by `_blank_inert_quotes`. The `git push` match still reads the unblanked code, so its behavior is unchanged.
- A span is blanked only when its segment's command word is `echo`, `printf` or `git commit`, and (for double quotes) the span holds no `$(` or backtick.
- Every ambiguity leaves the text as is, so the gate engages: an unbalanced quote, a `$'..'` quote, a `#` comment, and any pipe into a shell or runner (`sh`, `bash`, `xargs`, `eval`, `source`, `exec`, `sudo`, `command`, `node`, `python`, `perl`, `ruby`). Segments split on `;` `&` `|` and newline. Any other command word (`bash -c`, `eval`, `FOO=1 cmd`) is not inert.

## Red on master

Same test, kit tree at the parent commit (`git archive 67edf0a3`):

```
Command: bash tests/test-ship-gate-command-words.sh   (parent-commit hook)
Exit: 1
PASS=24 FAIL=12
```

| Gap | Cases red on master |
|---|---|
| `gh pr new` does not engage | alias, env-prefixed alias, after a commit, after `\|\|`, inside a `then` branch, `eval`, backtick, `xargs` |
| quoted `gh pr create` engages | `printf '...'`, `echo "..."`, a commit message, `echo '...' && git status` |

## Green run

```
Command: bash tests/test-ship-gate-command-words.sh
Exit: 0
Output:
ok - gh pr create -> engaged
ok - gh pr new (alias) -> engaged
ok - cd x && gh pr create -> engaged
ok - git -C dir push -> engaged
ok - env-prefixed gh pr create -> engaged
ok - env-prefixed gh pr new -> engaged
ok - git commit -m then gh pr new -> engaged
ok - printf then a real gh pr create -> engaged
ok - quoted title on a real command -> engaged
ok - after an echo with a ; -> engaged
ok - after an echo with || -> engaged
ok - after an echo with a single & -> engaged
ok - after a harmless pipe -> engaged
ok - after a redirect -> engaged
ok - apostrophe inside double quotes -> engaged
ok - escaped quote inside double quotes -> engaged
ok - joined single-quote escape -> engaged
ok - inside a then branch -> engaged
ok - after a git commit -> engaged
ok - printf single-quoted -> not engaged
ok - echo double-quoted -> not engaged
ok - echo mentions the alias -> not engaged
ok - git commit message -> not engaged
ok - multi-line commit message -> not engaged
ok - echo then an unrelated command -> not engaged
ok - echo piped into a shell -> engaged
ok - printf piped into xargs -> engaged
ok - command substitution in echo -> engaged
ok - backtick substitution in echo -> engaged
ok - bash -c -> engaged
ok - eval -> engaged
ok - unbalanced quote -> engaged
ok - ANSI-C quote then a real command -> engaged
ok - escaped quote then a real command -> engaged
ok - comment apostrophe hides nothing -> engaged
ok - nested double quotes -> engaged
---
PASS=36 FAIL=0
Verdict: PASS
```

Adjacent suites, all exit 0: `test-ship-gate-coverage-map.sh`, `-default-push.sh` (37), `-fail-closed.sh` (12), `-identities.sh`, `-impl-notes.sh` (19), `-profiles.sh`, `-refs-block.sh` (11), `-review-verdict.sh`, `test-ship-pr-body-verified.sh`. `feature-registry.sh check docs/FEATURES.md` reports fresh.

## Negative control

Each mutation of the committed hook turns the test red; the restore returns it green (`negctl`, run after the commit).

| Mutation | Red cases |
|---|---|
| `CMD_GH` never blanks (`CMD_GH="$CMD_CODE"`) | quoted-prose cases |
| `(create\|new)` back to `(create)` | alias cases, `eval`, backtick |
| pipe-to-shell guard regex neutered | `echo ... \| bash`, `xargs` |
| `#` comment guard deleted | comment apostrophe hides a real command |
| `$'..'` guard deleted | ANSI-C quote then a real command |
| `$(` and backtick exemption deleted | substitution cases |

```
Command: bash lib/gate/proof-ledger.sh negctl "$PWD" "bash tests/test-ship-gate-command-words.sh" "<mutation>"
Exit: 1 (under mutation, RED expected), for all six mutations
Restore: git checkout HEAD -- hooks/ship-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Reproduce

```bash
bash tests/test-ship-gate-command-words.sh
bash tests/test-ship-gate-default-push.sh
```

## Not proven

- Quote parsing is a best-effort reader, not a shell. It is built so that a misread engages the gate rather than hides a command.
- `git push` inside quoted prose still engages. This change is scoped to the `gh` words.
- Forms with options between `gh` and `pr` (`gh -R owner/repo pr create`) still do not engage. Not changed.
