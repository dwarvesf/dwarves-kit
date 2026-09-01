# SPEC-064: Hook precision: parse argv, not prose + the spec-number guard

Status: SHIPPED
Date: 2026-06-10
Lane: normal (classified: normal)
Type: spec-feature / behavioral
Board: ID-051 + ID-052 (the 2026-06-10 quality wave)

## Problem

The enforcement layer string-matched the WHOLE Bash command text, so DATA tripped rules
meant for ARGV. Seven false positives logged on 2026-06-10 alone:

1. `git merge -X ours -m "...squash of #38..." <sha>` blocked because the -m prose
   contained a protected-branch word (twice, during the stack merge).
2. `git push -q && gh pr edit 41 --base master` blocked: gh's --base argument read as a
   push ref.
3. A python heredoc whose FIXTURE TEXT contained a destructive-delete literal blocked.
4. The gate fired on a BACKLOG row's prose that merely DESCRIBED bug #3, while enqueuing
   the fix for it.
5. commit-format fired on a test-fixture string inside a command (same class, separate
   hook, logged for its own follow-up).
6. ship-gate engaged on "git push" inside generated prose and resolved the SESSION repo's
   spec for a `cd other-repo && git push` (the cross-repo misfire from FEEDBACK).
7. The operator's personal settings.json delete-hook fired on the same fixture text while
   THIS spec's tests were being added (outside the kit; evidence only).

False positives are alarm fatigue: each one teaches the operator (and the agent) to route
around the gate, which is worse than no gate. Separately, SPEC numbers collided twice in
one week (SPEC-047, SPEC-041) because "max of docs/specs/" goes stale while a numbered
spec ages inside an unmerged branch.

## Decision

1. **safety-gate.sh rewritten parse-aware.** Normalize first: strip heredoc BODIES (data,
   never code), split compounds (`&&`, `||`, `;`, `|`, subshell punctuation) into
   segments, strip quoted spans from the token scan. Every rule keys on the segment's
   actual argv: rm rules fire only on rm segments (flag scan + the regenerable-dir
   allowlist preserved); push rules read only a git-push segment's ref tokens
   (`main|master|*:main|*:master`, `--force`, `+refspec`); reset/kubectl/DROP-TABLE
   likewise. Quotes are UNWRAPPED, not deleted, so a quoted ref ("main") still reaches
   the scan while prose stays harmless via rule scoping (review F1/F2). Shell wrappers
   (`bash -c`, `eval`, `xargs`) are descended into (review F3).

   **Known limits (accepted, fail-open):** (a) a ref hidden in a variable
   (`B=main; git push origin $B`) is not resolved; remote branch protection is the
   backstop. (b) a heredoc body piped INTO a shell (`bash -s <<EOF`) executes but is
   treated as data; the gate targets accidental generated destruction, not adversarial
   smuggling, and the old hook covered this only by the same accident that produced the
   false positives.
2. **ship-gate.sh**: the engage check runs on heredoc-stripped CODE, and a leading
   `cd <path> &&` prefix resolves the gated repo (the cross-repo misfire fix). Fail-open
   posture unchanged.
3. **`lib/spec/spec-next.sh`** (ID-052): `next` prints max+1 over docs/specs/ filenames, ALL
   branch names (local + remote), and the last 200 commit subjects; `check <NNN>` exits 1
   when taken. `commands/spec.md` now instructs picking NNN through it. This spec's own
   number came from the tool (dogfood: `next` printed 064).

## Acceptance criteria

- AC1: all five command-level false positives from the problem list pass the gate (pins).
- AC2: every previously-blocked destructive shape still blocks: push-to-main incl.
  `HEAD:master`, bare/refspec force push, real rm of source incl. compound, reset --hard,
  kubectl delete, DROP TABLE via a db binary; the regenerable-dir allowlist still allows.
- AC3: ship-gate ignores prose pushes and gates the cd-target repo.
- AC4: spec-next flags a taken number (exit 1) and prints a numeric next; spec.md wires it.
- AC5: the full pre-existing hook suite passes unchanged (precision must not cost recall).

## Test plan

15 precision pins (5 false-positive allows + 4 still-blocks + 6 review-driven: quoted-ref
block, quoted-allowlist allow, bash -c / eval / xargs smuggles, ship-gate cd-target probe)
+ 3 spec-next tests, on top of the untouched pre-existing safety-gate block assertions.
Negative control: the heredoc-stripper removed -> FP3 pin goes RED (run live during build,
after the FP3 fixture was strengthened to a bare command; the first fixture hid behind a
comment marker and could not flip).

## Verification

- `tests/test-hooks.sh`: 282/282 (262 + 20; incl. the resurrected assert_true assertions,
  review F5: two pre-existing test calls referenced an undefined helper and silently never
  ran).
- `tests/test-meta.sh`: 421/421.
- Live allow/block matrix (17 cases) re-run post-fixes; recorded in the PR body.

## Review

Date: 2026-06-10. Adversarial security pass (asymmetric risk framing: a false negative
outranks a false positive; bypasses probed live). Verdict: **FIX-FIRST 5/10**, 2 HIGH +
2 MEDIUM + 2 LOW, all addressed in-branch:

1. HIGH, quote-DELETION opened a quoted-ref bypass (`git push origin "main"` passed). Root
   fix: unwrap quotes instead of deleting spans; prose stays harmless via rule scoping.
2. HIGH, the same deletion broke quoted allowlist targets (`rm -rf "node_modules"`
   blocked). Same root fix.
3. MEDIUM, `bash -c` / `eval` / `xargs` smuggling: wrappers now descended into.
4. MEDIUM, the cd-prefix extraction was dead code on BSD sed (the claimed cross-repo fix
   never fired). Rewritten portably + a DWARVES_KIT_PRINT_CDDIR probe affordance + pin.
5. LOW, `assert_true` was called but never defined: two pre-existing assertions silently
   never executed. Helper added; both now run and pass.
6. LOW, the heredoc-pipe-to-bash hole documented in Known limits as accepted.

Post-fix verdict: SHIP. hooks 282/282, meta 421/421, 17-case matrix green.
