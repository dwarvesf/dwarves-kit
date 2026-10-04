# Implementation notes -- pitch-test-tmp-out

Delta from `docs/specs/SPEC-324-pitch-test-tmp-out.md` only.

- No deviation from the contract: AC1's render moved from `$PROOF_DIR/sample-pitch.md` to
  `$(mktemp -d)/sample-pitch.md`, the three reads that used to hit the tracked path (lines 75,
  76, 79) now read the temp path, and the `PROOF_DIR`/`mkdir -p "$PROOF_DIR"` lines were
  dropped since nothing writes there anymore.
- Added the self-check assertion (T3) beyond a literal repoint: a sentinel comment
  (`AC1-SELF-CHECK-BOUNDARY`) bounds the `sed -n` extraction of the AC1 block from the running
  script itself (`"$0"`), so the check's own source line (which necessarily contains the
  tracked path string to search for) sits outside the extracted range and never counts as a
  hit against itself -- the same self-referential-scanner trap AC5 already guards against a
  few lines below, applied here to a self-check that reads its own source rather than another
  file.
- `docs/implementation-notes/kit-pitch.md` (T4) got a new dated entry, not an edit to the
  existing 2026-07-04 15:20 entry: that entry's "kept it live" decision was real and reasoned
  at the time (SPEC-140), so it stays as the historical record; the revision is logged as a
  new entry that supersedes it, naming the explicit refresh command.
- Negative control: the mutation targets the section-count read (`SECTIONS=...`) rather than
  the render's `--out` target, on purpose. Mutating `--out` back to the tracked path makes the
  test itself write the tracked file during the RED run, and `negctl.sh`'s restore set is
  captured right after the mutate command runs (before the RED test executes), so it never
  restores files the test-cmd itself dirties mid-run -- the negctl run comes back
  `Verdict: FAIL: tree differs from the pre-run snapshot after restore`, a real negctl
  limitation (not a bug in this fix) confirmed by inspecting `lib/gate/negctl.sh` lines
  113-121. Mutating a read instead of the write reproduces the same regression class (a
  literal tracked-path reference reappearing in the AC1 block) without the test run itself
  writing anything, so negctl restores cleanly to `Verdict: PASS`.
- `docs/FEATURES.md` was stale before this change (pre-existing `test-meta` failure, unrelated
  to this fix); regenerated last via `bash lib/registry/feature-registry.sh generate` per the
  dispatch brief, in its own commit.
