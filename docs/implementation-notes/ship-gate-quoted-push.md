# Implementation notes: ship-gate-quoted-push

Normal lane by the operator's call (the run started on the full lane and was moved before any spec was written). This note is the design record in place of a spec.

## Problem

`lib/gate/push-refs.sh` split a command with `tr ';&|'` on every separator character, quoted or not, and read every word after the remote as a refspec. Real commands were refused as unaccounted pushes:

| Command | Refusal on master |
|---|---|
| `git push -q -u origin <branch> 2>&1 \| tail -2` | `'2>' does not resolve to a commit` |
| `git push origin --delete a b` | `git push --delete pushes refs the gate cannot list` |
| `orca orchestration worker-start ... --spec "...; 2. git push ..."` | `git push runs under a wrapper ('2.')` |
| a for-loop running `git push origin --delete "$b"` | `a push segment uses a variable or command substitution` |

The same split had fail-open bugs. `git push &>/dev/null origin master` was read as a push of the current branch, so the default push passed in a repo with no spec. `bash -c "cd /tmp; git push origin <x>"` was read as a plain push and allowed.

## Scope after two security reviews

The first version treated quoted push text as data (an orca prompt, a commit message, an echo), answering `@@NONE`. Two automated reviews proved it fail-open. Six commands moved a bare origin's master: a delete followed by push text piped into bash or run as a script, an alias or post-commit hook written by printf or echo, `GIT_EDITOR` carrying the push, and git options held in a variable. The lead's decision: drop that feature entirely, and keep only the redirect fix and the plain-name delete, both failing closed.

| Shape | Result |
|---|---|
| redirection in a real push segment (`2>&1`, `>f`, `&>f`, `>\|f`) | read correctly (was: a refspec) |
| `git push <remote> --delete <plain names>`, `<remote> :<name>` | allowed, `@@DELETE` |
| quoted `git push` text in an orca `--spec`, a commit message, an echo | refused, as on master; pass long text through a file |
| for-loop `--delete "$b"` | refused, as on master |

## What the parser does now

```
command ──> split_segments (awk): split at UNQUOTED ; & | newline; drop comments and
            redirections (a target holding $ ` ( stays visible); per segment: text, masked
            text (quoted chars blanked), dequoted words
              v
           each segment
              git push ......... refspecs, --delete names
              anything else .... push text in it, or a risky git step -> suspect=1
              other command with push words -> wrapper refusal (as master)
              v
           default-branch pass (any repo) -> @@DEFAULT-PUSH
           suspect=1 -> refuse every push answer (ref, delete, force)
           delete answer also needs runner=0
              v
hooks/ship-gate.sh: @@DELETE-only passes; an answer naming no branch and no delete refuses
```

`suspect` is set by:
- push text anywhere outside a push segment;
- a `VAR=value` prefix, or an unquoted `$` word, in a git or gh step;
- a git step that can run a string: a `-c` other than `push.default`, a subcommand outside the known list (an alias could be anything), `rebase --exec/-x/-i`, or `-e/--edit` on commit, merge, tag, revert, cherry-pick, pull or notes.

`runner` is set by an EXEC word anywhere (shells, eval, xargs, sudo, env, ssh, interpreters, sed, awk, make, ...), a command word that is a path or holds `$`, a substitution anywhere, or an unquoted `( ) { }`. It only adds refusals.

Push options that run a program are refused: `--receive-pack` and `--exec` (git runs the named program for the remote side, through sh locally for a path or file:// remote; review round 3 proved a delete carrying one moved master), `--repo` (it replaces the remote the gate reads), a `::` remote (`ext::<command>`, a transport helper), and `--recurse-submodules` other than `check`/`no` (it pushes submodule refs). `git --exec-path` marks the command suspect. `-o`/`--push-option` stays allowed: it is data the server reads.

A wrapped body (`bash -c "..."`) is parsed once more, nested, for the default-branch rule only. A wrapped push to a default branch is refused in every repo, adopted or not.

When the splitter cannot parse the command (an unclosed quote, a redirection with no target), the parser falls back to master's plain split.

## Decision: `--delete` of plain names is allowed

Why this cannot bypass the proof gate:

- The proof gate guards a commit reaching the remote. A delete sends no commit object; the remote ends with less of the branch, never new unproven code.
- The default-branch pass runs first over every delete target, in both argument orders, and in the `refs/heads/` and `heads/` forms. A default branch is still `@@DEFAULT-PUSH`, refused in any repo.
- Only a plain name passes (`^[A-Za-z0-9._][A-Za-z0-9._/-]*$`). `HEAD`, `@`, a glob, `+`, a variable and `src:dst` are refused. git rejects some of these too (`--delete only accepts plain target ref names`, sampled on a local bare origin), but the parser does not rely on that. `--delete` with no names is refused.
- A delete is answered only when `suspect=0` and `runner=0`: the command holds nothing but plain git and gh steps. This closes reviewer bypass F1 (a delete followed by `echo '<push>' | bash`) and F1c (followed by the push written to a script and run from PATH).
- A delete plus a real push still gates the real ref (`@@REF` present).

Cost: nothing in the kit refuses deleting a non-default remote branch. safety-gate has no push-delete rule.

## Tightening against master

`tests/test-lanes-data.sh` row `ship-fail-closed-refs` pinned `git log -1 --format="%s about git push" && git push -u origin feat/x` as allowed. It now refuses: push text beside a push is never read as data. The same goes for a push in one command with `GIT_EDITOR=true git merge ...`, `git -c <key>=<value> <step>`, or an alias. Split such a command in two.

## Out of this diff (holes that exist on master too)

- F4: `cat <<EOT | bash` with a push in the body. The parser reports the default push, yet the gate exits 0 in the review harness's repo. The heredoc-to-shell path refuses only where `_fc_applies`, and it runs before the default-branch check.
- F5: `X=push; git $X origin feat/other:master`. The engage regex never sees `git ... push`, so the parser is never asked.
- A `git push` run from a script file the command does not name, as in master.

## Known limits

- The known git subcommand list and the EXEC list are fixed lists. An unlisted git subcommand fails closed (suspect). An unlisted runner only loses the extra delete check: push text anywhere still sets suspect.
- `gh pr create` text inside `gh issue create --body "..."` refuses ("no answer"), unchanged.
- Pre-existing and untouched: `test-boundary-lint` and `test-no-personal-paths` fail on origin/master (`commands/ui-design.md:27`).
