# Verification: how to write a proof

A proof is a file that shows a change works. Anyone can read it, run its commands and get the same result. This page has everything you need to write one.

## One file per PR

- Write `docs/verification/<slug>.md`. The slug is the branch name without the type, for example `fix-login-timeout`.
- One file per PR, so two PRs never conflict on a proof. Add to your own file. Do not edit another PR's file: proofs are dated evidence.
- A change to any file that is not documentation needs one. CI job `pr-shape` fails the PR without it. The rule is in [`AGENTS.md`](../../AGENTS.md#proof).
- This README is never a proof. Editing it does not count.
- A change with no behavior effect (a comment, a rename, formatting) puts one line in the PR body: `no-proof: <reason, 10+ characters>`. CI prints the reason and skips the proof check.

## The block shape

Every claim is one block. Run the command yourself and paste what it printed. The shape, with placeholders in angle brackets:

```
Command: <the exact command, from the repo root>
Output:
<the lines the command printed, trimmed to the ones that matter>
Exit: <the real exit code>
Verdict: PASS
```

- `Command:` the exact command, from the repo root.
- `Output:` real output on the lines right below the label. Trim to the lines that matter and say how many you cut. Never write "should work" or invent a line.
- `Exit:` the real exit code.
- `Verdict:` `PASS`, or `RED, as expected` for a negative control.

CI reads the file, not only its name. At least one proof file in the PR must hold:

1. an `Exit:` line;
2. an `Output:` line with a non-empty line right after it;
3. a line that starts `Verdict: RED`;
4. the words `NEGATIVE CONTROL` (any case).

A missing part fails `pr-shape`, and the message names it. Paste real output: a file that has the labels and no real run is not a proof, and a reader will see that.

## What goes in the file

1. A title, `# Verification: <what changed>`, and one paragraph on what the PR does.
2. A green run: one block for each test, build or check that covers the change. Include `bash scripts/check.sh` run on the branch. Trim the output inside the block; store no raw log file anywhere.
3. A negative control (next section).
4. "Not proven": a list of what you did not run or could not run.
5. "Rollback", only for a stateful change.

## The negative control

A green run alone proves little: a test that cannot fail proves nothing. Show that the test goes red when the change is broken.

1. Commit the work first. The restore step below only brings back committed text.
2. Break one thing the change adds: remove a check, flip a condition, drop a line.
3. Run the test that should catch it. Paste the block with the failing lines and `Verdict: RED, as expected`.
4. Restore the file: `git checkout -- <file>`.
5. Run the test again. Paste the green block.

The block for step 3 reads like this:

```
NEGATIVE CONTROL: <the one thing you broke>
Command: <the test command>
Output:
<the failing lines>
Exit: <non-zero>
Verdict: RED, as expected
```

Name the one thing you broke. If the test stays green, the test is too weak: fix the test, then repeat.

`scripts/negctl.sh` runs these steps for you and prints the block. Give it the test command and a command that breaks one thing:

```sh
bash scripts/negctl.sh "<the test command>" "<a command that breaks one thing>"
```

It refuses a tree with uncommitted changes to tracked files, wants green before and red under the break, refuses a red that is only a load or syntax error, restores the files the break changed, and wants green again. It exits 0 only for green, red, green. Paste the block it prints.

## Not proven

List what the proof does not show, in plain words. Examples: a device run when no device was at hand, a job on the CI runner that you only ran locally, an agent other than Claude Code, a path that needs a credential you do not have. A short honest list is better than a long claim.

## Rollback

For a stateful change (a deploy, data, a migration, a secret), add a "Rollback" section: the command that undoes it, what it leaves behind, and whether you ran it. A reversible change says how to revert. An irreversible one is a one-way door: see [`docs/TEAM-WORKFLOW.md`](../TEAM-WORKFLOW.md) rule 3.

## Limits of a proof

A proof is a reader's check, not a lock. A person who merges from the GitHub site passes everything, on a plan without branch protection, and a teammate trusts the folder once before the Claude Code hook loads. [`docs/TEAM-WORKFLOW.md`](../TEAM-WORKFLOW.md) lists both limits.
