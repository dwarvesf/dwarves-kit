# Implementation notes: ship-gate-quoted-push

Normal lane by the operator's call (the run started on the full lane and was moved before any spec was written). This note is the design record in place of a spec.

## Problem

`lib/gate/push-refs.sh` split a command with `tr ';&|'` on every separator character, quoted or not, and read every word after the remote as a refspec. Four real commands were refused as unaccounted pushes:

| Command | Refusal |
|---|---|
| `git push -q -u origin <branch> 2>&1 \| tail -2` | `'2>' does not resolve to a commit` |
| `orca orchestration worker-start ... --spec "...; 2. git push ..."` | `git push runs under a wrapper ('2.')` |
| `git push origin --delete a b` | `git push --delete pushes refs the gate cannot list` |
| a for-loop running `git push origin --delete "$b"` | `a push segment uses a variable or command substitution` |

The same split had two fail-open bugs: `git push &>/dev/null origin master` was read as a push of the current branch (the default push passed in a repo with no spec), and `bash -c "cd /tmp; git push origin <x>"` was read as a plain push and allowed.

## What changed

```
command ──> split_segments (awk) ──> per segment: text, masked text, dequoted words
              │  split at UNQUOTED ; & | newline
              │  drop comments and redirections (2>&1, >f, &>f, >|f, N>&M)
              │  keep a redirect target holding $ ` (
              v
           classify each segment
              git push ........ refspecs, --delete names (@@REF / @@DELETE / @@DEFAULT-PUSH)
              git commit|tag .. push text only in -m/--message, no git global option: data
              echo|printf|cat|grep|rg  print-only: data unless something can run a string
              orca + --spec/--prompt/... quoted value: data unless something can run a string
              anything else with push text: refused (wrapper) or no answer
              v
           @@NONE when nothing ships and every push-text occurrence is data
              v
hooks/ship-gate.sh: @@NONE passes only when the quote-blanked engage view sees no unquoted
                    push or gh pr create and no view died; @@DELETE-only passes
```

"Can run a string" means: an unquoted EXEC word anywhere (shells, eval, xargs, sudo, env, ssh, interpreters, sed, awk, ...), a command word that is a path or holds `$`, a substitution anywhere, or an unquoted `( ) { }`. The EXEC list only adds refusals; the decision to call quoted text data comes from the allowlist (orca, named prompt options), so an unknown program fails closed.

A wrapped body (`bash -c "..."`) is parsed once more, nested, for the default-branch rule only. Without this, the quote-aware split would have moved `bash -c "cd x; git push origin main"` from the any-repo default refusal to the adopted-only wrapper refusal.

When the splitter cannot parse the command (an unclosed quote, a redirection with no target), the parser falls back to the old plain split with no quote facts: nothing is data, and `@@NONE` is never answered.

## Decision: `--delete` of plain names is allowed

`git push <remote> --delete <name>...` and `git push <remote> :<name>` now emit `@@DELETE <name> <remote>`, and a push that only deletes passes the hook. Why this cannot bypass the proof gate:

- The proof gate guards a commit reaching the remote. A delete sends no commit object; the remote ends with less of the branch, never new unproven code.
- The default-branch pass runs first over every delete target, both argument orders (`--delete feat/x master` and `--delete master`), and `refs/heads/` and `heads/` forms. A default branch is still `@@DEFAULT-PUSH`, refused in any repo.
- The parser accepts only a plain name (`^[A-Za-z0-9._][A-Za-z0-9._/-]*$`). It refuses `HEAD`, `@`, a glob, a `+`, a variable, and `src:dst`. git itself rejects some of these (`--delete only accepts plain target ref names`, sampled on a local bare origin), but the parser does not rely on that.
- `--delete` with no names is refused (git: `--delete doesn't make sense without any refs`).
- A delete plus a real push in one command still gates the real ref: `@@REF` is present, and the hook checks that branch as before.

Cost: nothing in the kit now refuses deleting a non-default remote branch. safety-gate has no push-delete rule. A deleted feature branch can be recovered from any clone that still holds it.

## Decision: the for-loop delete stays refused

`for b in a b; do git push origin --delete "$b"; done` needs the loop evaluated to know `$b`, and `$b` could be a default branch from a substitution. The literal form `git push origin --delete a b` is allowed and does the same job.

## Review fixes (second commit)

An automated review of the first commit found three fail-open paths, each now pinned by a row that was red on the first commit:

1. git subcommands such as log, show, grep, stash and merge counted as data, but `-c core.pager`, `grep -O` and `--ext-diff` can run a string. Data is now only a commit or tag message.
2. Any program's quoted `--long-option` counted as data unless an EXEC word appeared. This is now an allowlist, and `( ) { }` count as able to run a string.
3. The hook trusted `@@NONE` alone. It now also checks its own quote-blanked view.

## Known limits

- A program that can run a string but is not on the EXEC list, combined with an allowlisted orca prompt in the same command, would let the prompt count as data. The prompt still has to be an orca option value. Example: `orca ... --spec "git push x" ; unlisted-runner`.
- `gh pr create` text inside `gh issue create --body "..."` still gets "no answer" (conservative, unchanged).
- Pre-existing and untouched: `test-boundary-lint` and `test-no-personal-paths` fail on origin/master (`commands/ui-design.md:27`).
