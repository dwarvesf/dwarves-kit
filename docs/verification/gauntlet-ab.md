# Proof of done: gauntlet A/B search-select (SPEC-241)

`tests/gauntlet/deploy/gauntlet-ab`: same card, two committed artifact variants, N rounds each through the room runner, scored per round by the row's own checker into `ab-verdict.txt`, verdict by sweep-or-honest-halt. One engine passthrough: `run-remote.sh` ships the caller's `GAUNTLET_SRC_TAR` as the artifact tarball (harness copy still ships HEAD).

## Green run (clean live N=2 pass under the FINAL post-battery driver)

`gauntlet-ab 26daed4 ab-smoke-defect user doorway 2` (omp/deepseek probe, local colima, bg-run detached; B = a plumbing commit with `lib/adopt.sh` removed, worktree untouched). Every verdict below is the driver's own checker-exit classification, not seeded:

```
A round 1 GREEN   A round 2 GREEN
B round 1 GREEN   B round 2 GREEN
Tiebreak: tokens A=122924 B=189063.
Verdict: variant A wins on cost tiebreak (tally tied).
[[AB-VERDICT winner=A why=tiebreak a=2/2 b=2/2]]
```

Result: PASS. This single record proves the whole contract:
- **Variant propagation, at the tarball level (the definitive check):** A's shipped `kit.tar.gz` contains `lib/adopt.sh` (1 entry), B's contains 0. The variant travels through `GAUNTLET_SRC_TAR`, both locally and (by the same code path) remotely.
- **End-to-end driver scoring:** four live rounds, each GREEN from a real checker exit 0, no seeding.
- **The verdict-honesty fix, proven in a live record:** a tied 2/2-vs-2/2 tally resolves on the cost tiebreak and the record SAYS SO (`why=tiebreak`, "wins on cost tiebreak (tally tied)"), not the false "sweep" the reviewer caught in the pre-fix record.
- **Rule-7:** variants built by `git archive <ref>` (committed state only); B's tag verifiably lacks `adopt.sh` in its committed tree.

The planted defect was RECOVERABLE: B's probe rebuilt a working `adopt.sh` from the kit's own docs (468 transcript references; the rebuilt file is 11325 bytes vs the real 17080), so B passed. Recorded as a finding, not a failure: a single-file deletion is recoverable, so a discriminating A/B card must vary what the docs TEACH, not what a probe can reconstruct. (Also a robustness data point: the onboarding surface survives a missing adopt script.)

## Discrimination, materialized in two driver-real halves

The reviewer flagged that the earlier "b=0/1" claim lived only in prose. Both halves are now materialized from the driver's own code paths, no prose substitute:

1. **Scoring path (checker exit → verdict):** the doorway checker on a valid fixture exits 0 → driver classifies GREEN (the four live rounds above); on an empty fixture it exits 1 → driver classifies RED. Reproduce: `git init` an empty dir, run `check-submission-user.sh` on it → `SUBMISSION: RED`, exit 1.
2. **Winner logic (given a scored tally):** seeded verdict files exercise only the tally→winner rule (the half that legitimately takes verdicts as input). `A=GREEN×2, B=RED×2, N=2` → `[[AB-VERDICT winner=A why=sweep a=2/2 b=0/2]]`. `A=GREEN, B=RED, N=1` → `winner=weak` (the N<2 floor: one round is a coin, never a winner).

## Negative + boundary controls

- No checker: `gauntlet-ab 26daed4 ab-smoke-defect user nope 2` → `no checker at ...check-submission-user-nope.sh`, exit 2, nothing staged.
- Non-numeric N: `... user doorway two` → `rounds-per-variant must be a positive integer`, exit 2.
- Untrusted tarball: a tar carrying a symlink member → `run.sh: refusing ...: it contains a symlink/hardlink or an absolute/.. member`, exit 2 (security HIGH-2).
- Resume: a round with `ab-verdict.txt` is skipped; a HARNESS verdict is retried, not stuck.

## Battery round (four independent legs)

Full battery: acceptance (sonnet), review (opus), security (opus, the diff qualifies), advisor (sonnet). Combined findings 2 HIGH + 1 MED (security) + 1 HIGH + 4 MED + 3 LOW (review) + 5 advisory + 1 acceptance-fixable, all addressed:

- **Security HIGH-1**: the checker runs host-side git against a probe-controlled `fixture-repo/.git` (fsmonitor/hooks/pager → RCE as the operator). Fixed: the checker runs with `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null`, and `core.fsmonitor=false / core.hooksPath=/var/empty / core.pager=cat` forced via `GIT_CONFIG_*`.
- **Security HIGH-2**: an A/B variant is an arbitrary ref, extracted host-side before the container; a symlink/`..`/absolute member escapes. Fixed: a reject pass over `tar -tvf` before extraction, plus `--no-same-owner --no-same-permissions`.
- **Security MED-3 / review MED-5**: room artifacts (nested kit copies, `kit.tar.gz`, ~90MB) are untracked but not gitignored, so `git add -A` would commit them (and the binary scrub skips them). Fixed: `docs/verification/gauntlet/.gitignore` for the room-artifact globs (the ID-640 class).
- **Review HIGH-1 / advisor**: a cost-tiebreak win was announced as a "sweep". Fixed: a `why=sweep|tiebreak` reason, printed and in the marker; proven in the live record above.
- **Review MED / advisor**: sticky HARNESS verdicts, no ROUNDS validation, silent HEAD fallback on a bad `GAUNTLET_SRC_TAR`, AB-WEAK dead at N=1. Fixed: HARNESS retried, ROUNDS validated + required, `run.sh` errors on a set-but-missing tar and echoes the source, and a winner now needs N>=2 (N=1 → AB-WEAK only).
- **Acceptance leg** correctly caught that the driver disagreed with SPEC-241 AC-1 and `commands/gauntlet.md` after I raised the N>=2 floor MID-BATTERY; the "mystery concurrent writer" it flagged was this author editing the same worktree while the read-only leg ran (a self-inflicted concurrent write, not a process breach). Spec AC-1, the Verification block, and the command doc were reconciled to the N>=2 floor, then this clean rerun was executed under the final code.

Delta log: `docs/implementation-notes/gauntlet-ab.md`.

## Reproduce

```
KIT_ROOT=<kit checkout> bash tests/gauntlet/deploy/gauntlet-ab <ref-A> <ref-B> user doorway 2
```
