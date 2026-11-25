# Gates area: rules, laws, findings

The implicit state machines and decisions of `lib/gate/` and of the decision chain in `hooks/ship-gate.sh`, written
as native gdp-wired rules (`rule()` / `fun()`), each modelled from what the bash does (file:function cited in each
`.ts`) and held to the real bash by a bridge. `index.ts` exports `RULES` for a top-level prover; `prove.ts` proves
every rule (rules with `{from: 'any'}`, requiring `proven && checked && !assumes`), asserts every kept broken variant
is refused, asserts every recorded finding below is still refuted, and runs the bridges.

## Rules

Proofs: `node gates/prove.ts --no-bridges` (supercomputer job `proofs`, exit 0; 151 laws over 26 rules). Bridges:
supercomputer batches `gates-run1` and `gates-run2` (jobs in `supercomputer-jobs.json`). "Cases" are sequences or
scenarios, compared step by step where the rule has steps.

| Rule | Source | Laws proven | Kept broken variants (all refused) | Findings | Bridge (real bash) |
|---|---|---|---|---|---|
| lane-gate-check | `gate-ledger.sh:record,override,check,progress` | 10, from any state | any-row, marker-counts, no-reason-guard, progress-latest | - | 160 sequences agree (per-step accept/refuse, per-phase `check`, `progress` marks) |
| lane-effective | `lane-data.sh:lane_effective` + `gate-ledger.sh:start` | 9, from any state | override-forges, arrow-reason (the code before the fix), amend-unguarded | F1, F2 (fixed) | 154 agree after the fix; HEAD diverges on sequence 0 |
| record-batch | `gate-ledger.sh:record_batch` | 5 | lowers, partial-write | - | 150 calls agree (refused = exit 64/65 and the ledger byte-identical) |
| inherit | `gate-ledger.sh:inherit` | 7 | any-ran, mix-parents, rewrites | - | 150 agree |
| validate-round | `gate-ledger.sh:_vr_open,_vr_close,_vr_incomplete` | 7, from any state | drift-closes, unbounded-voids, double-open | - | 60 sequences agree (exit code per step, last ROUND, validate row) |
| spec-verdict | `ship-rules.sh:_sr_review_last_verdict` | 4, from any state | no-fence, first-wins, any-section | - | 608 agree, one bridge for the three review rules (400 spec bodies, 80 ledger sequences, 128 gate combinations) |
| ledger-verdict | `gate-ledger.sh:review_verdict` | 3, from any state | any-text-clears, any-state | - | (spec-verdict's bridge) |
| review-gate | `ship-rules.sh:ship_rule_review_verdict` | 8 | spec-only, ship-softens | - | (spec-verdict's bridge, every fact combination) |
| gate-policy | `gate-policy.sh:enabled` | 7 | dirty-false-applies, true-gated, unknown-off | - | 768/768 combinations agree |
| fixture-email | `ship-rules.sh:_sr_fixture_email` | 5 | local-allowed | - | 102 agree (22 spellings + 80 commit sequences) |
| fixture-identities | `ship-rules.sh:ship_rule_identities` (fold) | 3, from any state | author-only | - | (fixture-email's bridge) |
| fixture-identities-block | `ship-rules.sh:ship_rule_identities` (decision) | 3 | - | - | (fixture-email's bridge) |
| large-spec | `ship-rules.sh:ship_rule_large_spec` | 4 | any-validate-row | - | 168 agree (40 large-spec + all 128 floor combinations) |
| floor | `ship-rules.sh:ship_rule_floor` | 4 | head-switch | - | (large-spec's bridge) |
| ship-gate | `hooks/ship-gate.sh` (the chain) | 9 | default-needs-adoption, review-after-lane, floor-only-with-spec | F8 | 153 scenarios agree after the fix (the real hook on temp repos) |
| impl-notes | `hooks/ship-gate.sh` (full-lane notes rule) | 2, from any state | substring-grep (the code before the fix) | F3 (fixed), F9 | (ship-gate's bridge; HEAD diverges on pinned scenario 0) |
| proof-check | `proof-ledger.sh:check` | 8 | override-first, override-excuses-source, verdict-ignored | F5, F6 | 279 agree |
| proof-classify | `proof-ledger.sh:classify` | 7 | subject-first, board-counts-dirty | F7 | 206 agree (with proof-override-scope) |
| proof-override-scope | `proof-ledger.sh:is_overridden` | 4 | - | - | (proof-classify's bridge: two repos, a worktree, a legacy line, a forged reason) |
| negctl | `negctl.sh` (mutate mode) | 9, from any state | last-failure-wins, vacuous-passes, load-red-counts | - | 192/192 fact combinations agree |
| known-failures | `known-failures.sh:cmd_classify` | 10 | crash-masked, count-unchecked, absent-exit-passes | - | 300 agree |
| recheck-sample | `recheck-sample.sh:decide` | 6 | octal (the code before the fix) | F4 (fixed) | 200 agree after the fix; HEAD diverges at N=09 |
| redteam-round | `redteam-gate.sh:cmd_round` | 5 | cost-optional, capped-uncaught | F10 | 48 agree (exit code and the three ledger lines) |
| quiz-tap | `quiz-gate.sh:cmd_tap` | 4 | nudge-on-log, any-pr | - | 25 agree (with quiz-respond; the significance classifier is stubbed) |
| quiz-respond | `quiz-gate.sh:cmd_respond` | 3 | - | - | (quiz-tap's bridge) |
| premerge | `premerge.sh:cmd_check` | 5 | conflict-swallowed, merge-on-default | - | 7/7 agree, and no case rewrites history |

## Findings

Promised laws come from `lib/gate/README.md`, script headers and comments, and `docs/verification/README.md`;
reviewer laws are the questions a reviewer would ask. A promised law refuted and reproduced against the bash was
fixed in the bash (F1 to F4); the rest are recorded with their counterexample and left as the code ships, with why.

### F1 (fixed). The `override` verb could sanction a lane lowering, so a run shed its spec header's gates

- Law (promised, README "Amending a run's lane", lane_effective's header): *the check lane is never lighter than a
  ranked spec header unless the last amend was a sanctioned `start --amend --lower --reason`*.
- Counterexample (search on the pre-fix rule `override-forges`): header `Lane: normal`; `override <rid> lane-lower
  "x -> tiny: y"`, then `start --amend <rid> tiny ...`. With no START the amend is no lowering and is accepted; the
  reader saw a `lane-lower` row naming `tiny` right before it and marked it lowered: check lane `tiny`. The override
  verb writes `| via=hand`; only `start --amend --lower` writes `| via=lane-lower`, and the reader ignored the tag.
- Bash (HEAD): `start r normal; override r lane-lower "normal -> normal: just because"; start --amend r normal;
  lane r --spec <Lane: full>` gives check lane `normal` (law: `full`).
- Fix (`lib/gate/lane-data.sh:lane_effective`, one awk condition): a lane-lower row sanctions an amend only when it
  ends in `via=lane-lower`, or carries no tag (a ledger from before the tags, when only the verb wrote that row).
- Bridge: the HEAD archive diverges on sequence 0 (bash `chk tiny`, rule `normal`); after the fix 154 sequences
  agree. Test: `tests/test-lane-effective.sh` "a lane-lower row the override verb wrote (via=hand) does not
  sanction the amend" (fails on HEAD, passes now; suite 66/66).

### F2 (fixed). A sanctioned `--lower` whose reason held " -> " was ignored

- Law (promised, same section): *an amend written through `start --amend --lower --reason` is the check lane*.
- Counterexample (search, `arrow-reason`): header `normal`; `start r normal`; `start --amend --lower --reason
  "scope a -> b shrank" r tiny`. The row reads `normal -> tiny: scope a -> b shrank`; the reader took the LAST
  ` -> ` piece, so the target was `b` and the lowering was not honoured (fail-closed: a lawful lowering refused).
- Bash (HEAD): `start a1 full; start --amend --lower --reason "scope a -> b shrank" a1 normal; lane a1 --spec
  <Lane: full>` gives `full` (law: `normal`).
- Fix (`lane-data.sh:lane_effective`): the target is the piece right after the FIRST ` -> `. Test:
  `tests/test-lane-effective.sh` "a sanctioned --lower whose reason holds ' -> ' still resolves to its own lane".

### F3 (fixed). An ACTION line cleared the full-lane implementation-notes rule

- Law (promised, README "The load-bearing invariant"): *an additive marker can never fake, satisfy, or mask a
  gate*; the notes rule is cleared by "a logged `override <slug> impl-notes`".
- Counterexample (rule `impl-notes`, variant `substring-grep` = HEAD): rows `[forged]` with forged =
  `gate-ledger.sh action <slug> "| GATE | impl-notes | override | x"`. The hook grepped the whole ledger for
  `| GATE | impl-notes | override |`, which the ACTION line contains.
- Bash (HEAD): adopted repo, `Lane: full` spec, every full gate recorded, no notes: the push blocks with
  MISSING-NOTES; after that one `action` call the same push exits 0.
- Fix (`hooks/ship-gate.sh`, the notes rule): the override is read by field (`$2=="GATE" && $3=="impl-notes" &&
  $4=="override"`), like check(). The codex trust pin for ship-gate.sh in `hooks/codex-hooks.json` already carries
  the new hash in this working tree (`test-codex-hooks` needs no further repin for this edit).
- Bridge: HEAD diverges on pinned scenario 0 (rule: block; hook: exit 0); after the fix 153 scenarios agree. Test:
  `tests/test-ship-gate-impl-notes.sh` case 12b (fails on HEAD, passes now; suite 20/20).

### F4 (fixed). recheck-sample read a leading-zero N as octal

- Laws (promised, the script's header): *N>1 is sampled when the rid's cksum is divisible by N*; *it always exits 0
  on a decision*, and records it.
- Counterexample: `decide <rid> 08` (or 09) hit `$((sum % 08))`, an arithmetic error: no decision printed, nothing
  recorded, exit 1. `decide <rid> 010` decided by `sum % 8`. A root config `execute.recheck_sample = 010` too.
- Fix (`lib/gate/recheck-sample.sh:decide`): the digits are read as `$((10#$n))`. Test:
  `tests/test-whole-spec-dispatch.sh` "a leading-zero N is decimal" (two asserts; fail on HEAD, pass now).
- Bridge: HEAD diverges at case 6 (`N=09`, exit 1, "value too great for base"); after the fix 200 cases agree.

### F5 (not fixed: the gate is stricter than its docs). `[UNAVAILABLE: reason]` alone never passes a stateful proof

- Law (promised: docs/verification/README.md "stateful passes with a rollback note or `[UNAVAILABLE: reason]`";
  proof-ledger.sh: "`[UNAVAILABLE: reason]` says no run was possible, so it owes no output").
- Counterexample: a stateful diff whose fresh proof holds a rollback note and `[UNAVAILABLE: no staging database]`
  but no `Command:`/`Exit:` line: check() still demands `Command:|Exit:` and blocks (bash: exit 1; bridge agrees).
- Left as is: making it pass loosens a blocking gate. Whether a no-run proof should still name its command is the
  maintainer's call; fix either the doc or the code.

### F6 (reviewer law, not fixed). A stateful change ships on a failing recorded run

- Law: *a stateful change never ships on a run whose last Verdict is FAIL* (behavioral has this veto).
- Counterexample: `Command:`, `Exit: 1`, `Output:` lines, a rollback note, a final `Verdict: FAIL`: check() exits 0
  (bash confirmed). The docs ask for "a recorded run + a rollback", so code and docs agree; the asymmetry with the
  behavioral arm is worth a decision.

### F7 (reviewer law, not fixed). A doc's file name makes a code change stateful

- Law: *a doc file's name never changes the class of a code change*. Counterexample: `src/app.sh` +
  `docs/deploy-notes.md` classify `stateful` (the stateful-word scan reads every changed path); without the doc,
  `behavioral`. Fail-safe direction (owes more proof).

### F8 (reviewer law, documented fail-open, not fixed). Two exits skip the hard-path floor

- Law: *every push the hook lets through has passed the hard-path floor* (bar a human-allowed default push).
- Counterexample (decision witness: `shellHd`, not `_fc_applies`, `floorBlocks`): a push fed to a shell by heredoc
  (`bash <<'EOF'` / `git push -u origin feat/x` / `EOF`) in a repo that is not adopted but has `lane_gates = true`
  (an operator overlay turns it on for every repo) exits 0 before the floor runs, while the same push typed plainly
  is blocked by the floor (bridge pinned scenarios 1 and 2 confirm both on the real hook). A `@@BLOCK`, no-answer or
  several-branch push in a non-adopted repo likewise goes on checking only the CURRENT branch. The hook's header
  documents the fail-open outside adopted repos; the floor itself does not depend on adoption, so the two disagree.
  `--force` pushes also exit 0 here (left to safety-gate.sh, which blocks them).

### F9 (reviewer law, not fixed). The notes rule reads any override row, not the latest

- Law: *a later impl-notes row in another state undoes the override, as check() reads the latest row*. Run:
  `[forged, override, override, other]` stays cleared. Matches the README ("a logged override clears it").

### F10 (reviewer law, not fixed, unreachable today). A capped redteam round records `redteam ran`

- `redteam-gate.sh round <rid> capped cost=...` writes `GATE | redteam | ran` (the verdict rides in the reason), so
  a lane requiring `redteam` would count the fail-closed stop as a pass. No lane names `redteam`, and a project
  override naming it is ignored as an unknown phase.

### Observations (no law broken)

- The spec reader takes `### Verdict: **SHIP**` and `SHIP-clean` as SHIP; the ledger reader takes neither (it strips
  leading `*` but `**SHIP**` then reads as SHIP followed by `*`). A bold `**DO NOT SHIP**` recorded in the ledger is
  invisible to the cross-check. The review commands write plain verdicts, so this is latent.
- `echo git push` in an adopted repo is BLOCKED ("the command parser gave no answer"): fail-closed by design.
- `gh pr create --head main` exits 0 before every lane and proof check (`@@DEFAULT` is handled like `@@FORCE`).
- `runid()` folds distinct slugs onto one ledger file (`a/b`, `a-b`, `a b`; `a+b` and `ab`), and `feat/x` and
  `fix/x` share rid `x` by design: gates recorded for one count for the other.
- gate-policy.sh's kit-root layer is `kit_config_root` (`$HOME/.claude/dwarves-kit/kit.toml`), not the copy the
  script lives in (lane-data.sh pins its own); with no such file it falls to the code defaults.

## Bridge corrections (modelling errors in the bridges, not bash bugs)

- floor: a branch commit editing `.kit.toml` is itself a hard-path hit (kit config); the hit fact now includes it.
- review-verdict ledger part: `**SHIP** all good` is not a verdict (see observations).
- proof-classify: with nothing committed on the branch there is no subject; the subject fact now needs a commit.
- inherit: a phase drawn with last state `none` must have no row; the generator had written an earlier one.

## Implicit machines found but not modelled

- `check`'s verdict cache (`gate-ledger.sh:_check_cache_get/_put`, `ledger-key.sh`): keyed on lane, rid, the
  kit-lanes flag, the ledger's size/mtime/inode/ctime and a fingerprint of the lane data, written only for a ledger
  whose ctime is 2 s old. Its correctness rests on file-system timestamps and the clock, not a decision a rule can
  carry, and every bridge works on fresh ledgers (the uncached path). The law to state: a cached verdict equals a
  fresh check.
- `plan-record` (the same dry-run substrate as record-batch, which is modelled), `descent` and `progress` ordering
  marks (advisory; progress's disposal is in lane-gate-check), `history`, `report`.
- validate-round's crash resume (`_vr_check_resume`): the model has no crash between `closing` and the terminal line.
- push-refs.sh's parser and the hook's `_strip_heredocs`, `_blank_inert_quotes`, `_blank_quoted`, `_cd_var_target`:
  lexers over shell text (quote stacks, heredoc states). Only their outputs (the ref markers) enter the ship-gate
  rule; proving them needs a string-level model.
- proof-ledger.sh's `_captured_output` Output-slot machine and `_green_marks` (facts here), the set-wise group pass,
  the opt-in visual image rule (R3), `_negctl_required` (a fact).
- negctl.sh's `--parallel`, `--at`, `--base-ref` modes and `NEGCTL_RED_ATTEMPTS` retries (one attempt modelled).
- `lane_hard_path_exempt` (the `[[gate.hard_path_exempt]]` validator) and the floor verb itself
  (`lib/classify/lane-classify.sh`, outside this area); `spec.sh depth size` (a fact in large-spec).
- `_sr_relay` (the floor's notice relay, counters capped at 20; advisory text).
- In `lib/gate/` but not in this area's list: dispatch-gate.sh (a blocker per the README), mutation-smoke.sh,
  coverage-delta.sh, check-edit.sh, branch-merged.sh, boundary-lint.sh, battery-gate.sh, default-branch-warn.sh,
  front-door-advisory.sh, verbatim-rows.sh, verify-counts.sh, doc-projection-check.sh.

## Reproducing

```bash
cd lib/rules
node gates/prove.ts --no-bridges                     # every proof, variant and finding (about 30 s)
node gates/prove.ts --bridges-only --only negctl     # one bridge locally
supercomputer run --jobs lib/rules/gates/supercomputer-jobs.json --out runs/gates   # all bridges + the suites
supercomputer batch fetch runs/gates                 # results: runs/gates/<job>.files/gates-<name>.json
BRIDGE_KIT=<a `git archive HEAD lib hooks kit.toml` copy> node gates/lane-effective.bridge.ts   # the pre-fix bash
```

Suites run on the boxes (batch `gates-run1`): test-lane-effective 66/66, test-gate-ledger-amend 39/39,
test-ship-gate-impl-notes 20/20, test-ship-gate-review-verdict 60/60, test-ship-gate-fail-closed 12/12,
test-ship-gate-refs-block 11/11, test-gate-opt-in and test-gate-opt-out pass, test-gate-outcome 25/25,
test-gate-ledger-override-via 20/20, test-ledger-substrate 12/12, test-quiz-gate 37/37, test-ceremony-fits-diff
passes. test-whole-spec-dispatch 36/37: the one failure is T1 (commands/execute.md over 30000 bytes, a file this
area did not touch); both new recheck asserts pass. test-ledger-durability 53/54 on the box only (T3 runs
`proof-ledger.sh override` from the tree, which the box ships without `.git`); 54/54 locally.
