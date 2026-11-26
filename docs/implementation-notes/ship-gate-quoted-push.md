# Implementation notes: ship-gate-quoted-push

Normal lane by the operator's call (the run started on the full lane and was moved before any spec was written). This note is the design record in place of a spec.

## Problem

`lib/gate/push-refs.sh` split a command with `tr ';&|'` on every separator character, quoted or not, and read every word after the remote as a refspec. Real commands were refused as unaccounted pushes:

| Command | Refusal on master |
|---|---|
| `git push -q -u origin <branch> 2>&1 \| tail -2` | `'2>' does not resolve to a commit` |
| `git push origin --delete a b` | `git push --delete pushes refs the gate cannot list` |
| `orca ... --spec "...; 2. git push ..."` | `git push runs under a wrapper ('2.')` |
| a for-loop running `git push origin --delete "$b"` | `a push segment uses a variable or command substitution` |

The same split had fail-open bugs. `git push &>/dev/null origin master` was read as a push of the current branch. `bash -c "cd /tmp; git push origin <x>"` was read as a plain push.

## The rule that shipped: one command

Five automated review rounds each found another step that changes what a push does: quoted push text run by a shell, a `GIT_EDITOR`, a git config `receivepack`, `--receive-pack`, `~/.gitconfig`, XDG config, `GIT_CONFIG_*` env, `HOME`, `GIT_DIR`, cd. Per-writer marks could not keep up. The lead replaced them with one structural rule:

```
the Bash call ──> split at UNQUOTED ; & | newline (per segment: words, file-redirect flag, separator)
                    v
                 the push or PR segment must be segment 0, with no VAR=value prefix, no file redirect,
                 and no $ ` ( ) anywhere in it, quoted or not (no $(...), backtick, <(...) or >(...))
                 allowed beside it:  fd redirects that write no file  (2>&1, >&2, >/dev/null, 2>/dev/null)
                                     one trailing `|` into the bare word tail, head, cat or grep (not a path), literal arguments
                 anything else (another step, export, cd, a group, a subshell, a file redirect) -> refused
                    v
                 default-branch pass first (any repo), then the one-command check, then @@REF / @@DELETE / @@FORCE
```

| Shape | Result |
|---|---|
| `git push ... 2>&1 \| tail -2`, `>/dev/null 2>&1`, `\| grep -v x` | answered |
| `git push <remote> --delete <plain names>`, `<remote> :<name>` | answered, `@@DELETE` |
| `git add && git commit && git push`, `cd x && git push`, `git push && gh pr create` | refused: run each as its own call |
| `git push >/tmp/log`, `\| tee`, `\| sed`, `\| ../bin/cat`, two pipes | refused |
| `gh pr create --title "$(...)"`, a backtick, `<(...)` in the push or PR step | refused (review round 6) |
| `GIT_*=... git push`, `export ...; git push` | refused |
| quoted `git push` text in an orca `--spec`, a commit message, an echo | refused, as on master; pass long text through a file |
| for-loop `--delete "$b"` | refused, as on master |

On the push itself the parser still refuses options that run a program or move the remote: `-c` other than `push.default`, `--exec-path`, `--receive-pack`, `--exec`, `--repo`, a `::` remote (`ext::`, `fd::`), and `--recurse-submodules` other than `check`/`no`. `-o`/`--push-option` stays allowed: it is data the server reads.

A command with push text but no push segment the parser reads gives no answer, exactly as on master, and the hook refuses it ("no answer"). There is no "nothing ships" answer. `sed` and `awk` are no longer on the print-only list, because both can run a command.

A wrapped body (`bash -c "..."`) is parsed once more, nested, for the default-branch rule only, so a wrapped push to a default branch is refused in every repo.

When the splitter cannot parse the command (an unclosed quote, a redirection with no target), no push is answered.

The hook refuses an answer that names no branch and no delete. A delete-only answer passes, because it sends no commit.

## Decision: `--delete` of plain names is allowed

- The proof gate guards a commit reaching the remote. A delete sends no commit object.
- The default-branch pass runs first over every delete target, in both argument orders and in the `refs/heads/` and `heads/` forms. A default branch is still `@@DEFAULT-PUSH`, refused in any repo.
- Only a plain name passes (`^[A-Za-z0-9._][A-Za-z0-9._/-]*$`). `HEAD`, `@`, a glob, `+`, a variable and `src:dst` are refused, and `--delete` with no names is refused.
- Under the one-command rule nothing can ride along with a delete.

Cost: nothing in the kit refuses deleting a non-default remote branch. safety-gate has no push-delete rule.

## Tightening against master

- Every push, and every `gh pr create`, must be its own Bash call in an adopted repo.
- `tests/test-lanes-data.sh` `ship-fail-closed-refs` flips two rows from allowed to refused:
  - `git log -1 --format="%s about git push" && git push -u origin feat/x`
  - `git push -u origin feat/x && gh pr create --fill`
- `tests/test-ship-gate-impl-notes.sh` row 14 (`cd <repo> && git push`) is now refused in the target repo by the one-command rule. It used to reach the notes check.

## Out of scope

- Config, hooks or environment left by an EARLIER Bash call: a `~/.gitconfig`, a `.git/config` key or a hook written in one call changes what a lone `git push` in the next call does. Only a native git pre-push hook, which receives the exact refs, can close that.
- F4: `cat <<EOT | bash` with a push in the body. The heredoc-to-shell path refuses only where `_fc_applies`, and it exits before the default-branch check.
- F5: `X=push; git $X origin feat/other:master`. The engage regex never sees `git ... push`, so the parser is never asked.

## Incident during review

The operator's real `~/.gitconfig` was overwritten during review round 5. At 09:50 it held only `[remote "origin"] push = refs/heads/feat/other:refs/heads/master`, which matches the S2 payload. It is chezmoi-managed (`dot_gitconfig.tmpl`). The suite runs in this note used `GIT_CONFIG_GLOBAL=/dev/null` so the stray refspec could not change fixture pushes.

## Known limits

- `gh pr create` text inside `gh issue create --body "..."` refuses ("no answer"), unchanged.
- Pre-existing and untouched: `test-boundary-lint` and `test-no-personal-paths` fail on origin/master (`commands/ui-design.md:27`).
