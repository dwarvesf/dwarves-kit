# Implementation notes: SPEC-332 safety-gate quoted split

The delta from `docs/specs/SPEC-332-safety-gate-quoted-split.md`. Decisions already in the spec are not repeated here.

## Deltas

| Area | Delta | Why |
|---|---|---|
| Token strip | `strip_quotes()` became an inline `${SEG//[\'\"\\]/}` expansion in the loop | the function forked a subshell per segment; a 28 KB command took 17 s on master |
| Probe fixtures | branch-guard (the operator's global hook) reads any executed script for the push words and blocks it; probe scripts ran with `# branch-guard: allow:` on the command line | the probes feed strings to the hook via jq and never run git |
| Negative controls | run in a throwaway `git clone` of the worktree, not the worktree | the validator and the break-it agent were probing the worktree hook at the same time |
| Heredoc misreads | one replay backstop instead of arithmetic and `${}` frames in the walk | the break-it pass proposed frames and a prefix match on the delimiter; the replay covers every misread whose false delimiter never appears, in five lines |
| `-E` operand | `sudo -E` takes no operand, so `-E` stays out of the operand list | round 2 of the scratch probes: `-E` in the list ate `git` in `sudo -E git push` |
| Redirect before basename | redirection and `NAME=value` checks read the raw word before the basename case | the basename of `>/dev/null` is `null`, which broke the redirect skip in a scratch build |

## Validation rounds

| Round | Source | Verdict | Folded in |
|---|---|---|---|
| 1 | fresh Opus validator | NEEDS REVISION | heredoc misreads, comment desync, keyword and redirect segment starts, push tokens (all rc 0 on master too) |
| 1b | Opus break-it pass | 3 regressions + bypasses | a `<<` in a comment or a here-string queued a second delimiter and hid lines master read; `(` inside `$(`; backslash-newline joined with a space; `sudo -u`, `bash -lc`, `/usr/bin/git`, brace refs, `rm -Rf`, `kubectl -n`, psql heredoc |

| 2 | fresh Opus validator | NEEDS REVISION (static read, probes confirmed by the lead) | `coproc NAME`, `function NAME`, `caffeinate -u` eating the command, and one master-blocks, branch-allows ordering (`cat <<A; echo $((1<<B))` with a later `B`); also zsh `noglob`, `repeat`, `always` |

The round-2 validator found its criticals by reading the code; its probe pass was cut short. The lead confirmed each against branch and master before fixing (`probe-r3.sh` in the job scratch dir): R1, R3, R4 were bypasses on both; R5 was the one regression.

## Open questions

- `--all` now blocks as `push-all`. A repo whose only branches are feature branches loses that shortcut. Confirm this trade is wanted.
