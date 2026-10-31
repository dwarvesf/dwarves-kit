# archive-held-worktrees: implementation notes

Spec: `docs/specs/SPEC-415-archive-held-worktrees.md`. Validation round 1 warnings not folded into the spec, for the builder. Each line is a warning to handle during the build or log as a delta here.

## Reviewer 1
- Skip-worktree and assume-unchanged edits are invisible to `git status` and lost on removal: SKIP a worktree where `ls-files -v` shows an `S` or a lowercase tag.
- Sanitize every printed path with `tr '[:cntrl:]' '?'` before it reaches a report line.
- Validate the knob with `^[1-9][0-9]*$` and a length cap: `08` breaks bash arithmetic as octal.
- Cap the snapshot by path count or bytes before the push.
- Put `[skip ci]` in the snapshot and staged commit messages so an archive push starts no CI run.
- Regenerable ignored dirs may hold hand-placed files; this is an accepted risk, so log it in the delta.

## Reviewer 2
- Ambiguous push outcome: when the ref exists and equals HEAD on a clean worktree, count it as success; for a dirty worktree, name the wedge in the report.
- Add a push timeout and a size cap, and a Failure modes row for origin down.
- An empty mtime read counts as fresh; a deleted path uses its parent directory's mtime.
- Add a Failure modes row for two concurrent `apply` runs on the same repo.
- Re-run the ignored-blockers check after the push, before the removal.
- Check the exit code of the temp-index `add -A`.
- Order the cheap guards before the status walk, and short-circuit the idle-age read once one mtime is fresh.

## Reviewer 3
- A pid-less lock: override only lock reasons the Agent tool writes; keep any other locked worktree.
- Squash-merged detached worktrees: run `_absorbed` with the detached commit so they reach the merge-proof path.
- With reflogs off, `logs/HEAD` is absent; note the staleness fallback (admin `HEAD` and `commondir` only).
- `status --porcelain=v1 -z` rename records carry two NUL-separated paths; the parsers must consume both.

## Reviewer 4
- Touches misses `CHANGELOG.md`, `bin/**` and `docs/reference/**`.
- Untasked doc mentions to update: `bin/wrap:9`, `docs/reference/wrap.md:39`, `docs/reference/consumer-contract.md:88`, `lib/wrap/README.md:8`, `commands/wrap.md:160`.
- TASK-H is large; split it if it does not fit one session.
- The closed write set in the `wrap.sh` header must also name `config --remove-section` and the staged commit.
- Untested report lines: index.lock held, snapshot failed, origin holds X, checked out elsewhere, survived the removal, unresolvable.
- AC-16's control deletes two guards at once, so the read-back compare has no test of its own; add one.
- AC-26's control will not go red as written; grep a phrase from the new header paragraph instead of the flag name.
- Add a `status --porcelain=v1 -z` sample with a rename to `## Grounding`.
- The staged commit may be gold-plating; keep it only if the AC-5 fixture shows a real loss without it.
- The regenerable list misses `.next`, `build`, `coverage` and `lib/*/bin/*-rs`.
- AC numbering is out of order in the table (AC-29 to AC-33 follow AC-25); renumber at build time if the tests name rows by number.

## Reviewer 5
- Consider one shared `_archive_push` helper for both archive sweeps instead of duplicated push and read-back logic.
- Derive the regenerable list from land's `_LAND_IGNORED_BUILTIN` minus its local-config and secret entries, so the two lists cannot drift.

## Validation round 2

### Reviewer 1
- The secret guard's two tree halves (staged and snapshot `diff-tree`) have no isolated case; add one per half.
- Widen `_ARCHIVE_SECRET_GUARD` with `*key*`, `*.tfvars`, `*.tfstate`, `kubeconfig*`, `.pypirc`, `.htpasswd`, `*.ovpn`, `*.gpg`, `service-account*.json`, and match the path components `secrets/ .ssh/ .aws/ .gnupg/ .kube/ .docker/`.
- Print the first N sanitized uncommitted paths in the dry-run `WOULD` block.

### Reviewers 2, 3, 5
- Secret-name false positives (`tokenizer.py`, a modified tracked `token.go`) make worktrees pile up; restrict the name guard to added, renamed and untracked paths (`--diff-filter=AR` on the tree halves), and consider an allow knob later.
- Add a Failure modes row for the secret SKIP (detection: the SKIP line; recovery: move or commit the file, re-run).
- The status and tree secret checks overlap; state one rule for which runs in the dry run and which under `--apply`.
- Assert the dry-run verdict equals the `--apply` verdict for the embedded and secret fixtures.

### Reviewer 4
- receive-pack's refusal of a ref created after its advertisement (the DEC-K reason for AC-11) has no live sample in `## Grounding`; add one.
- AC-31's dry trace asserts an unsampled behavior (`add -A` keeping an ignored, already-staged `.env`), and its mutation is stacked; sample it and isolate the control if possible.

### Reviewer 6
- The recovery recipe needs `git fetch` first, and should say that uncommitted state returns as one or two commits, the branch returns under the archive name, and regenerable ignored paths do not return.

## Validation round 3

### Reviewer 1
- Add `*.env *.p8 *.ppk *.asc .s3cfg .boto .dockercfg` to `_ARCHIVE_SECRET_GUARD`.
- Snapshot and staged commit messages must not embed the absolute worktree path; use the slug.
- Reword the invariant "Gitignored files are never pushed" to "the sweep never adds an ignored path not already in the index".
- The clean or dirty decision must use the same explicit `--untracked-files=all` status read as the guards.

### Reviewer 2
- The "live worker missed" Failure modes row's detection is the `archived worktree ... (<sha7>)` report line, read after the fact.

### Reviewer 3
- Guard the canonical `repo` path too: a linked worktree can arrive as `repo` through `--under`.
- Phase 1 tasks A, A2, B and C close with Phase 2, and B needs A.
- Approach 3's rejection reason is stale after #1076 (step 5 now defaults to `--own`); restate it on the contract change.
- TASK-H must also fix `commands/wrap.md:396` and the `:163` busy bullet.
- Detached review checkouts whose tip is on any `refs/remotes/origin/*` should short-circuit as already on origin, or the archive namespace fills with duplicates; log it if not done.

### Reviewer 4
- Add rows for the new knob to `lib/config/module-registry.md` (Root-only keys table and module table), and add `lib/config/**` to Touches.
- TASK-H runs after G1.
- The `wrap-apply.sh:662` usage line belongs in TASK-D.
- TASK-A2's widening changes land's hint: add a land case, or keep land's hint on the narrow list.
- Pick one test section name and use it everywhere.
- E2 does not need C.

### Reviewer 5
- Approach 3's tradeoff is stale (same as Reviewer 3).
- One combined `status --porcelain=v1 -z --untracked-files=all --ignored=matching` read can feed the idle-age, embedded, secret and ignored guards; fix the "one git status" sentence to match.
- The dry-run `<k> uncommitted paths` count comes from the status read, never from `_wt_snapshot`.
- The create-only lease Terms entry should match the form AC-11 greps.

### Reviewer 6
- Reword the Diagram's "no write happens before every guard" to "no write to the worktree, its branch or origin".
- Compare `wtb = cur` only when both are non-empty.
- Add the branch-elsewhere recheck to the Picture's post-push box, and name the repo-level `_write_guard` SKIP line.

## Validation round 4

### Worth doing during the build
- R1: run `_secret_shaped` under `set -f`, with a case whose cwd holds `a.pem` that still flags `b.pem`; one table-driven case looping a sample per secret pattern; `_wt_ignored_blockers` never reads land's allow-list or `wrap.land_ignored_allow`; sanitize the `FAILED ... <first push error line>` text.
- R2: `trap` in `_wt_snapshot` removes its temp index on interrupt; the `ls-remote` pre-read passes the full `refs/heads/<ref>` (a tail match false-positives on `refs/heads/foo/archive/x`).
- R3: the AC-8 fixture also ages the admin `locked` file; the branch-elsewhere line reads `kept <b>`; say that the operator names the flag knowing origin receives all uncommitted, non-ignored bytes.
- R5: name the shared constant for its meaning, `_SECRET_SHAPED_NAMES`, not for the archive sweep.

### Everything else
- R1: the `--no-optional-locks` rationale is wrong (idle age does not read the admin index); the real harm is rewriting a held worktree's index.
- R1: the dry run should warn that a public origin receives the uncommitted bytes.
- R2: add a Failure modes row for an interrupted `worktree remove` (partial directory, same-day wedge, data safe in the first ref).
- R2: `_wt_lock_live` cannot tell EPERM from ESRCH; `ps -p` would.
- R2: the same-day wedge after a transient read-back failure recovers the next day.
- R3: long-lived branches (`develop`, `staging`, `release/*`) are not in the protected set.
- R3: an Agent-tool lock pid can keep a subagent worktree from ever archiving (Failure modes row, safe side).
- R4: TASK-B is the heaviest task; TASK-H touches about 10 files; E1 and E2 acceptance names cases G tasks write.
- R5: Approach 2's "about 200 lines" understates the size.
- R6: Picture drift, handled in the spec fold.
