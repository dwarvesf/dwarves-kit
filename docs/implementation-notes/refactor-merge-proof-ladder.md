# Merge-proof ladder: one function, callers branch on the code

Delta from the brief. The "is this branch merged" ladder existed three times (scan, `_merge_proof`, the inline copy in `_apply_branches`). It is now `_merge_ladder` in `lib/wrap/wrap-common.sh`. `_merge_proof` is deleted, not wrapped.

## Decisions

- Grammar: one line, `<SAFE|LEAVE> <reason> <detail>`. `SAFE ancestor|absorbed|squash <phrase>`; `LEAVE tip <pr head sha>`, `LEAVE base <branch>`, `LEAVE none <phrase>`.
- I added a fourth LEAVE reason, `nogh <gh note>`. The brief named three. Apply prints a different line when gh is down (`SKIP b: (gh unavailable), no squash proof available`), and the caller cannot tell that from `none` without re-reading the gh state. A reason code costs less than a second source of truth.
- `_squash_verdict` speaks the same grammar and is the gh rung inside the ladder. Its old `OK / TIP / BASE / NONE` words are gone. Carry calls the rung alone, because it judges the tip on origin, not a local branch, and the ancestor and absorbed rungs would widen what carry treats as "already merged".
- The function always exits 0. The word is the only channel; an exit status would be a second one to drift.
- The tip is an optional fifth argument. `_apply_branches` passes the sha it already compared with the scan snapshot, so the proof judges that commit. Other callers let the ladder read `refs/heads/<branch>` once. Before, the three rungs each read the ref on their own.
- `LEAVE tip` and `LEAVE base` carry data (a sha, a branch name). Every other detail is a phrase a caller may print and never match on.
- Land keeps only `SAFE absorbed` and `SAFE squash`. The old guard dropped any proof starting with `ancestor`; the new one is an allow list of the two codes.
- `_absorbed` stays in `wrap-apply.sh`. The ladder in `wrap-common.sh` calls it; every file is sourced by `wrap.sh`, so the order does not matter. Moving it would be a 40-line diff with no behavior change.

## Output

Byte-identical. Scan keeps its own labels per code. Apply prints the ladder's phrase for ancestor and absorbed (same text as before) and keeps its own squash wording in the branch sweep (`squash-merged into <def>, tip matches the PR head`) next to the worktree sweep's `squash-merged per gh`. Unifying them would change a pinned line in two suites for no gain.

Scan still flattens tip, base, none and nogh to `[NOT merged / unknown: LEAVE]`. It now chooses to, by code, and the comment says so.

## fetch_ok

The two variables held opposite values under one name. Both are renamed with their values unchanged:

| File | Old | New | Holds |
|---|---|---|---|
| `wrap-apply.sh` | `fetch_ok` (1 = fetched) | `fetch_succeeded` | 1 when the fetch worked |
| `wrap-land.sh` | `fetch_ok` (0 = fetched) | `fetch_failed` | 1 when the fetch failed |

## Tests

- `tests/test-wrap-ladder.sh` (new): every code, then scan, apply, land and carry run against a kit copy whose phrases are reworded (`reword_ladder` in `tests/lib/wrap-stub.sh`, same technique as `reword_wrap`).
- `tests/test-wrap-land.sh` TA2 stubs `_merge_ladder` instead of `_merge_proof`.

## Open

None.
