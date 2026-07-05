# Verification: kit-modularity SG-07 reconcile (capstone)

Full narrative + table-first proof: `docs/proof/kitmod-reconcile.md`. This file carries the
gate's required green run + NEGATIVE CONTROL in the flat single-file shape
(`docs/verification/README.md`'s back-compat form).

## Green run

Command (from the dotfiles worktree, `docs/kitmod-07-reconcile`):
```
$ grep -rn 'ledger-observatory\|bash lib/\|lib-vs-tools' \
    home/dot_claude/skills/plan-for-goal/SKILL.md \
    home/dot_claude/skills/plan-for-mega-goal/private_SKILL.md \
    home/dot_claude/skills/plan-for-mega-goal/references/GUIDE.md
Exit: 1 (no matches, as expected)
```

Command (from this worktree, `docs/kitmod-07-reconcile`):
```
$ grep -noE 'lib/[a-zA-Z_-]+\.sh' commands/mega.md | sort -u
lib/classify/lane-classify.sh
lib/gate/dispatch-gate.sh
lib/gate/gate-ledger.sh
lib/gate/proof-ledger.sh
lib/goal/goal-drafts.sh
lib/goal/mega-merge.sh
lib/queue/orchestrate.sh
lib/spec/spec-next.sh
Exit: 0
```
Every hit is already a real subsystem path (`lib/<subsystem>/<file>.sh`); verified each
exists via `ls`, all 8 `OK`. No flat (non-subsystem) `lib/<x>.sh` remains anywhere in scope.

Command (mirror check, run from the dotfiles worktree with `commands/mega.md` copied
alongside, or equivalently diffed cross-repo):
```
$ sed -n '/<!-- BEGIN triage-ladder -->/,/<!-- END triage-ladder -->/p' \
    home/dot_claude/skills/plan-for-goal/SKILL.md | shasum
a42939f37e91e61eadfa0a7e4de7034a3309a22c  -

$ sed -n '/<!-- BEGIN triage-ladder -->/,/<!-- END triage-ladder -->/p' \
    commands/mega.md | shasum
a42939f37e91e61eadfa0a7e4de7034a3309a22c  -
```
Both shasums match the `SPEC-142-mega-mirror-sync.md` recorded contract value. Byte-identical.

Verdict: PASS

## NEGATIVE CONTROL

Confirmed the grep-audit actually detects a live stale reference, by grepping the PRIOR
commit (before this sub-goal's fix) and comparing to the current worktree, both really run:

```
$ git show HEAD~1:home/dot_claude/skills/plan-for-goal/SKILL.md | grep -n 'lib/gate-ledger.sh'
68:...record each via `lib/gate-ledger.sh` so the ship-gate is the `Done` check...
$ echo $?
0                                       # RED: match found, pre-fix commit

$ grep -n 'lib/gate-ledger.sh' home/dot_claude/skills/plan-for-goal/SKILL.md
$ echo $?
1                                       # GREEN: no match, current (fixed) worktree
```

Mirror-check negative control: really corrupted one word inside the `commands/mega.md`
fence (`python3` string-replace, uncommitted), re-hashed:

```
$ sed -n '/<!-- BEGIN triage-ladder -->/,/<!-- END triage-ladder -->/p' commands/mega.md | shasum
c41f3958548995e08ea85ab841fb7cd739ad021a  -            # MISMATCH vs a42939f37e9..., as expected
$ git checkout -- commands/mega.md                      # restore
$ sed -n '/<!-- BEGIN triage-ladder -->/,/<!-- END triage-ladder -->/p' commands/mega.md | shasum
a42939f37e91e61eadfa0a7e4de7034a3309a22c  -              # back to the recorded contract value
```

Proves the shasum comparison actually detects drift rather than trivially passing.

## Reproduce

```
cd dwarves-kit && git checkout docs/kitmod-07-reconcile
cd dotfiles && git checkout docs/kitmod-07-reconcile
bash lib/gate/gate-ledger.sh check   # (kit-adopted repo; run from dwarves-kit worktree)
```
