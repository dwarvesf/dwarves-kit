# Verification: kit-modularity SG-03 subsystem-commands

Full narrative + table-first proof: `docs/proof/kitmod-subsystem-commands.md`. This file
carries the gate's required green run + NEGATIVE CONTROL in the flat single-file shape
(`docs/verification/README.md`'s back-compat form).

## Green run

Command: `bash lib/classify/classify.sh lane classify "fix a typo in README"`
Exit: 0
Output: `tiny`

Command: `bash lib/gate/gate.sh proof classes`
Exit: 0
Output:
```
stateful
behavioral
inert
```

Command: `bash lib/spec/spec.sh index | head -1`
Exit: 0
Output: `central docs/specs`

Command: `GOAL_DRAFTS_DIR=$(mktemp -d) bash lib/goal/goal.sh draft list`
Exit: 0
Output: `(no goal drafts)`

Command: `bash lib/session/session.sh observe --help`
Exit: 0
Output: `usage: cc-observe [-h] ...` (forwards to the real `cc-observe` usage)

Verdict: PASS

## NEGATIVE CONTROL

Reverted the change by removing the new entry file, re-ran the same command, restored it:

```
$ bash lib/classify/classify.sh lane classify "fix a typo in README"
tiny
Exit: 0

$ mv lib/classify/classify.sh /tmp/classify.sh.bak   # revert
$ bash lib/classify/classify.sh lane classify "fix a typo in README"
bash: lib/classify/classify.sh: No such file or directory
Exit: 127                                             # RED, as expected

$ mv /tmp/classify.sh.bak lib/classify/classify.sh    # restore
$ bash lib/classify/classify.sh lane classify "fix a typo in README"
tiny
Exit: 0                                               # GREEN again
```

Verdict: PASS (negative control confirms the entry is load-bearing, not a no-op).

## Call-sites resolve (additive, no regression)

Command: repo-wide scan of every `$LIB_ROOT/<path>` reference across `.sh`/`.py` files,
checked against the real `lib/` tree.
Exit: 0
Output: `14 unique refs, 0 missing`
Verdict: PASS

## Suite identical-or-better

Command: `bash tests/test-meta.sh` / `bash tests/test-hooks.sh`
Exit: 0 / 0
Output: `679/679` / `452/452`
Verdict: PASS

The one pre-existing `tests/test-board.sh` failure (36/45) reproduces byte-identically with
this branch's 5 new files `git stash`ed out (an install-staleness issue on this box unrelated
to this change, detailed in `docs/proof/kitmod-subsystem-commands.md` §4).
