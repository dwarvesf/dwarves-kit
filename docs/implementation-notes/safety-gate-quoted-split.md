# Implementation notes: SPEC-332 safety-gate quoted split

The delta from `docs/specs/SPEC-332-safety-gate-quoted-split.md`. Decisions already in the spec are not repeated here.

## Deltas

| Area | Delta | Why |
|---|---|---|
| Token strip | `strip_quotes()` became an inline `${SEG//[\'\"\\]/}` expansion in the loop | the function forked a subshell per segment; a 28 KB command took 17 s on master |
| Probe fixtures | branch-guard (the operator's global hook) reads any executed script for the push words and blocks it; probe scripts ran with `# branch-guard: allow:` on the command line | the probes feed strings to the hook via jq and never run git |
| Negative controls | run in a throwaway `git clone` of the worktree, not the worktree | the validator and the break-it agent were probing the worktree hook at the same time |
| Heredoc misreads | one replay backstop instead of the break-it pass's prefix match on the delimiter; an arithmetic frame joined in revision 3 (superseding the rev-2 'no frames' call), `${}` still has none | the replay covers every misread whose false delimiter never appears; only arithmetic showed a master-blocks, branch-allows ordering |
| `-E` operand | `sudo -E` takes no operand, so `-E` stays out of the operand list | round 2 of the scratch probes: `-E` in the list ate `git` in `sudo -E git push` |
| Redirect before basename | redirection and `NAME=value` checks read the raw word before the basename case | the basename of `>/dev/null` is `null`, which broke the redirect skip in a scratch build |

## Validation rounds

| Round | Source | Verdict | Folded in |
|---|---|---|---|
| 1 | fresh Opus validator | NEEDS REVISION | heredoc misreads, comment desync, keyword and redirect segment starts, push tokens (all rc 0 on master too) |
| 1b | Opus break-it pass | 3 regressions + bypasses | a `<<` in a comment or a here-string queued a second delimiter and hid lines master read; `(` inside `$(`; backslash-newline joined with a space; `sudo -u`, `bash -lc`, `/usr/bin/git`, brace refs, `rm -Rf`, `kubectl -n`, psql heredoc |
| 2 | fresh Opus validator | NEEDS REVISION (static read, probes confirmed by the lead) | `coproc NAME`, `function NAME`, `caffeinate -u` eating the command, and one master-blocks, branch-allows ordering (`cat <<A; echo $((1<<B))` with a later `B`); also zsh `noglob`, `repeat`, `always` |
| 3 | fresh Opus validator, every critical probe-confirmed | NEEDS REVISION | `#` after an escaped blank or operator read as a comment (hid `&` and `$(`); rev-3 arithmetic frame skipped `$(` inside it and closed on a lone `)`; `((` ordering; `xargs -d` |
| 4 | fresh Opus validator, every critical probe-confirmed | NEEDS REVISION | `((` after `if`/`for`/`!`/`{` queued a delimiter (regression vs master); `#` right after `$( )` or a backtick; the rev-4 escape marker never reset; text before a lone `)` never re-walked |
| 5 | fresh Opus validator, likelihood-rated | NEEDS REVISION, all contrived | `if((` with no blank, `#` after a `((` command's `))`, a delimiter queued twice by the re-walk (three regressions vs master); exponential re-walk on deep false nests (depth 20 took 2 s; now 0.06 s) |
| 6 | fresh Opus validator, likelihood-rated, plus a 48-command benign sweep | NEEDS REVISION | a `$( )` before the subcommand split the outer argv (`git -C "$(git rev-parse --show-toplevel)" push origin main`, plausible, open on master too); `coproc ((` (contrived regression); wrappers `op run`, `direnv exec`, `mise exec`; tag-glob false positive |

The round-2 validator found its criticals by reading the code; its probe pass was cut short. The lead confirmed each against branch and master before fixing (`probe-r3.sh` in the job scratch dir): R1, R3, R4 were bypasses on both; R5 was the one regression.

## Open questions

- None. `--all` stays blocked (decided in the spec's Decision Log): it pushes every local branch, main included. Reversible if an operator wants the shortcut back.
